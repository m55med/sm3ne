import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/analytics/analytics_service.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/haptics.dart';
import 'package:bisawtak/shared/widgets/confirm_dialog.dart';
import 'package:bisawtak/shared/widgets/connectivity_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _maxDuration = Duration(minutes: 10);

  final AudioRecorder _recorder = AudioRecorder();
  late final AnimationController _pulseController;

  bool _isRecording = false;
  bool _isProcessing = false;
  bool _toggleBusy = false; // re-entrancy guard for _toggleRecording
  String? _currentRecordingPath;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  DateTime? _recordingStartedAt;

  // Upload progress (0..1). Null while not uploading.
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    // Prevent rapid double-tap from racing start/stop.
    if (_toggleBusy) return;
    _toggleBusy = true;
    try {
      if (_isRecording) {
        await _stopAndSend();
      } else {
        await _startRecording();
      }
    } finally {
      _toggleBusy = false;
    }
  }

  Future<bool> _ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      if (!mounted) return false;
      final open = await showConfirmDialog(
        context,
        title: 'إذن الميكروفون مطلوب',
        message: 'لتسجيل الصوت يرجى السماح بالوصول للميكروفون من إعدادات التطبيق.',
        confirmLabel: 'افتح الإعدادات',
        cancelLabel: 'إلغاء',
      );
      if (open) await openAppSettings();
      return false;
    }
    status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && mounted) {
      final open = await showConfirmDialog(
        context,
        title: 'إذن الميكروفون مطلوب',
        message: 'لتسجيل الصوت يرجى السماح بالوصول للميكروفون من إعدادات التطبيق.',
        confirmLabel: 'افتح الإعدادات',
        cancelLabel: 'إلغاء',
      );
      if (open) await openAppSettings();
      return false;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض إذن الميكروفون')),
      );
    }
    return false;
  }

  Future<void> _startRecording() async {
    try {
      // Snapshot the permission state BEFORE we ask, so we can tell whether
      // this call is the first-ever request (which will pop the iOS dialog)
      // vs. a subsequent record attempt with permission already in place.
      final wasUngrantedBefore = !(await Permission.microphone.status).isGranted;

      final granted = await _ensureMicPermission();
      if (!granted) return;

      // First-time grant UX: the iOS permission sheet is modal and the
      // recorder cannot start cleanly under it. If the user happens to tap
      // through the sheet while the recorder is mid-init, the first
      // recording captures nothing useful and Whisper hallucinates a
      // greeting onto the silence ("مرحبا بكم في الفيديو الجديد"). Forcing
      // a second explicit tap eliminates that race.
      if (wasUngrantedBefore && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم منح إذن الميكروفون. اضغط مرة أخرى للبدء بالتسجيل.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      // WAV (pcm16 with headers): guaranteed ffmpeg/Whisper compatibility.
      // 16kHz mono matches Whisper's expected input — keeps files small.
      final path = p.join(
        dir.path,
        'rec_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );

      _currentRecordingPath = path;
      _recordingStartedAt = DateTime.now();
      _elapsed = Duration.zero;
      setState(() => _isRecording = true);

      _ticker = Timer.periodic(const Duration(milliseconds: 200), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        final now = DateTime.now();
        final elapsed = now.difference(_recordingStartedAt ?? now);
        setState(() => _elapsed = elapsed);
        if (elapsed >= _maxDuration) {
          t.cancel();
          _ticker = null;
          _stopAndSend();
        }
      });

      Haptics.success();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل بدء التسجيل: ${friendlyErrorMessage(e)}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _stopAndSend() async {
    _ticker?.cancel();
    _ticker = null;
    String? recordedPath;
    try {
      recordedPath = await _recorder.stop();
    } catch (_) {}
    recordedPath ??= _currentRecordingPath;

    setState(() => _isRecording = false);
    Haptics.success();

    if (recordedPath == null) return;
    if (_elapsed.inMilliseconds < 800) {
      _safeDelete(recordedPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('التسجيل قصير جداً')),
        );
      }
      return;
    }

    await _processFile(recordedPath, source: 'recorded', isLiveRecording: true);
  }

  Future<void> _cancelRecording() async {
    _ticker?.cancel();
    _ticker = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    final path = _currentRecordingPath;
    if (path != null) _safeDelete(path);
    setState(() => _isRecording = false);
    Haptics.heavy();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      _processFile(result.files.single.path!, source: 'uploaded');
    }
  }

  Future<void> _processFile(
    String path, {
    String source = 'uploaded',
    bool isLiveRecording = false,
  }) async {
    final online = await hasInternetConnection();
    if (!online) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('لا يوجد اتصال بالإنترنت.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0;
    });
    final analytics = ref.read(analyticsProvider);
    await analytics.transcriptionStarted(source);
    try {
      final transcription = await ref.read(transcriptionRepoProvider).transcribeFile(
        path,
        source: source,
        isLiveRecording: isLiveRecording,
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => _uploadProgress = (sent / total).clamp(0.0, 1.0));
        },
      );
      await analytics.transcriptionCompleted(
        source: source,
        durationSeconds: transcription.duration.round(),
        wordCount: transcription.wordCount,
      );
      if (mounted) {
        Haptics.success();
        _showResult(transcription);
      }
    } catch (e) {
      await analytics.transcriptionFailed(source);
      Haptics.error();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      _safeDelete(path);
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _uploadProgress = null;
        });
      }
    }
  }

  void _safeDelete(String path) {
    try {
      final f = File(path);
      f.exists().then((exists) {
        if (exists) f.delete().catchError((_) => f);
      });
    } catch (_) {}
  }

  void _showResult(Transcription t) {
    final brand = context.brand;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ListView(
            controller: scrollCtrl,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  Chip(label: Text(t.languageName)),
                  Chip(label: Text('${t.duration.toStringAsFixed(1)}ث')),
                  Chip(label: Text('${t.wordCount} كلمة')),
                  if (t.source == 'recorded')
                    Chip(
                      avatar: const Icon(Icons.mic, size: 16, color: Colors.white),
                      label: const Text(
                        'تسجيل',
                        style: TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Theme.of(ctx).colorScheme.primary,
                    ),
                ],
              ),
              if (t.wasTrimmed)
                Container(
                  margin: const EdgeInsets.only(top: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: brand.warningAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: brand.warningAmber, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'تم قص الصوت (تجاوز الحد المسموح).',
                          style: TextStyle(color: brand.warningAmber),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              SelectableText(
                t.text,
                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                      height: 1.8,
                      fontSize: 18,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: t.text));
                        Haptics.success();
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('تم نسخ النص.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Haptics.tap();
                        Share.share(t.text);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = context.brand;
    return ConnectivityBanner(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بصوتك'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'الإعدادات',
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        body: AnimatedSwitcher(
          duration: AppDuration.base,
          child: _isProcessing
              ? _buildProcessingState(brand)
              : _buildIdleOrRecording(scheme, brand),
        ),
      ),
    );
  }

  Widget _buildProcessingState(BrandColors brand) {
    return Center(
      key: const ValueKey('processing'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(
              value: _uploadProgress,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _uploadProgress == null || _uploadProgress! >= 1.0
                ? 'جاري تحويل الصوت إلى نص...'
                : 'جاري الرفع... ${(_uploadProgress! * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleOrRecording(ColorScheme scheme, BrandColors brand) {
    return Padding(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final glow = _isRecording
                    ? (0.35 + 0.35 * _pulseController.value)
                    : 0.25;
                final ringColor = _isRecording ? brand.recordingRed : scheme.primary;
                return Semantics(
                  button: true,
                  label: _isRecording ? 'إيقاف التسجيل' : 'بدء التسجيل',
                  hint: _isRecording ? 'استمر بالضغط للإلغاء' : null,
                  child: GestureDetector(
                    onTap: _toggleRecording,
                    onLongPress: _isRecording ? _cancelRecording : null,
                    child: AnimatedContainer(
                      duration: AppDuration.slow,
                      curve: Curves.easeOut,
                      width: _isRecording ? 160 : 130,
                      height: _isRecording ? 160 : 130,
                      decoration: BoxDecoration(
                        color: ringColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: ringColor.withValues(alpha: glow),
                            blurRadius: _isRecording ? 40 : 20,
                            spreadRadius: _isRecording
                                ? (10 + 6 * _pulseController.value)
                                : 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AnimatedSwitcher(
            duration: AppDuration.base,
            child: _isRecording
                ? _buildRecordingHints(scheme, brand)
                : _buildIdleHints(scheme),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          OutlinedButton.icon(
            onPressed: _isRecording ? null : _pickFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('رفع ملف صوتي'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingHints(ColorScheme scheme, BrandColors brand) {
    return Column(
      key: const ValueKey('recording-hints'),
      children: [
        Text(
          _fmt(_elapsed),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: brand.recordingRed,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: LinearProgressIndicator(
            value: (_elapsed.inMilliseconds / _maxDuration.inMilliseconds)
                .clamp(0, 1),
            backgroundColor: brand.recordingRed.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation(brand.recordingRed),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'اضغط للإيقاف والتحويل · أقصى 10 دقائق',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'استمر بالضغط للإلغاء',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildIdleHints(ColorScheme scheme) {
    return Column(
      key: const ValueKey('idle-hints'),
      children: [
        Text(
          'اضغط للتسجيل',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'التسجيل مجاني ولا يُخصم من باقتك.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
