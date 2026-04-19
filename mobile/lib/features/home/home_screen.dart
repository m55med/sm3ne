import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/data/models/transcription.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  static const Duration _maxDuration = Duration(minutes: 10);

  final AudioRecorder _recorder = AudioRecorder();
  late final AnimationController _pulseController;

  bool _isRecording = false;
  bool _isProcessing = false;
  String? _currentRecordingPath;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  DateTime? _recordingStartedAt;

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
    if (_isRecording) {
      await _stopAndSend();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('برجاء السماح بالوصول للميكروفون من إعدادات التطبيق')),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _currentRecordingPath = path;
      _recordingStartedAt = DateTime.now();
      _elapsed = Duration.zero;
      setState(() => _isRecording = true);

      _ticker = Timer.periodic(const Duration(milliseconds: 200), (t) {
        if (!mounted) return;
        final now = DateTime.now();
        final elapsed = now.difference(_recordingStartedAt ?? now);
        setState(() => _elapsed = elapsed);
        if (elapsed >= _maxDuration) {
          _stopAndSend();
        }
      });

      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل بدء التسجيل: $e')),
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
    HapticFeedback.mediumImpact();

    if (recordedPath == null) return;
    // If the recording is too short, just discard it.
    if (_elapsed.inMilliseconds < 800) {
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
    setState(() => _isRecording = false);
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

  Future<void> _processFile(String path, {String source = 'uploaded', bool isLiveRecording = false}) async {
    setState(() => _isProcessing = true);
    try {
      final transcription = await ref.read(transcriptionRepoProvider).transcribeFile(
        path,
        source: source,
        isLiveRecording: isLiveRecording,
      );
      if (mounted) {
        _showResult(transcription);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التحويل: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showResult(Transcription t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(t.languageName)),
                  Chip(label: Text('${t.duration.toStringAsFixed(1)}ث')),
                  Chip(label: Text('${t.wordCount} كلمة')),
                  if (t.source == 'recorded')
                    Chip(
                      avatar: const Icon(Icons.mic, size: 16, color: Colors.white),
                      label: const Text('تسجيل', style: TextStyle(color: Colors.white)),
                      backgroundColor: Theme.of(ctx).colorScheme.primary,
                    ),
                ],
              ),
              if (t.wasTrimmed)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(child: Text('تم قص الصوت (تجاوز الحد المسموح)', style: TextStyle(color: Colors.orange))),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              SelectableText(
                t.text,
                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(height: 1.8, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: t.text));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('تم نسخ النص')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Share.share(t.text),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('بصوتك'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 24),
                  Text('جاري تحويل الصوت إلى نص...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final glow = _isRecording ? (0.35 + 0.35 * _pulseController.value) : 0.25;
                      return GestureDetector(
                        onTap: _toggleRecording,
                        onLongPress: _isRecording ? _cancelRecording : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: _isRecording ? 160 : 130,
                          height: _isRecording ? 160 : 130,
                          decoration: BoxDecoration(
                            color: _isRecording ? Colors.red : cs.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isRecording ? Colors.red : cs.primary).withValues(alpha: glow),
                                blurRadius: _isRecording ? 40 : 20,
                                spreadRadius: _isRecording ? (10 + 6 * _pulseController.value) : 5,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isRecording ? Icons.stop : Icons.mic,
                            size: 64,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  if (_isRecording) ...[
                    Text(
                      _fmt(_elapsed),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: LinearProgressIndicator(
                        value: (_elapsed.inMilliseconds / _maxDuration.inMilliseconds).clamp(0, 1),
                        backgroundColor: Colors.red.shade100,
                        valueColor: const AlwaysStoppedAnimation(Colors.red),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'اضغط للإيقاف والتحويل · أقصى 10 دقائق',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'استمرار بالضغط للإلغاء',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                    ),
                  ] else ...[
                    Text(
                      'اضغط للتسجيل',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'التسجيل مجاني ولا يُخصم من باقتك',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 48),
                  OutlinedButton.icon(
                    onPressed: _isRecording ? null : _pickFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('رفع ملف صوتي'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
