import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/stt/stt_orchestrator.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/features/plans/plans_screen.dart' show currentSubscriptionProvider;
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/file_validation.dart';
import 'package:bisawtak/shared/utils/sandbox_paths.dart';

/// Floating result sheet shown when a voice note is shared into the app.
///
/// On Android (and the iOS "فتح في بصوتك" hand-off) the app launches with a
/// translucent theme so this renders as a quick bottom sheet floating over the
/// previous app — the user gets the transcript without the full app chrome.
/// It mirrors the native iOS Share Extension sheet: accuracy/duration + word
/// count chips, the text, copy, and an action row with the language (right)
/// and "فتح في بصوتك" (left), plus the server request id.
class ShareHandlerScreen extends ConsumerStatefulWidget {
  final String filePath;
  final String? sourceApp;
  final VoidCallback? onDone;
  // Called when the user taps "فتح في بصوتك". The overlay can't navigate
  // itself (it's outside the GoRouter), so it hands the target route up to
  // main.dart which drives the router app.
  final void Function(String route)? onOpenRoute;

  const ShareHandlerScreen({
    super.key,
    required this.filePath,
    this.sourceApp,
    this.onDone,
    this.onOpenRoute,
  });

  @override
  ConsumerState<ShareHandlerScreen> createState() => _ShareHandlerScreenState();
}

class _ShareHandlerScreenState extends ConsumerState<ShareHandlerScreen> {
  Transcription? _result;
  String? _error;
  bool _processing = true;
  // True while the "higher quality" server re-transcription is in flight.
  bool _upgrading = false;

  @override
  void initState() {
    super.initState();
    _process();
  }

  @override
  void didUpdateWidget(covariant ShareHandlerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      setState(() {
        _result = null;
        _error = null;
        _processing = true;
      });
      _process();
    }
  }

  Future<void> _process() async {
    try {
      // Defense-in-depth: re-validate the shared file lives inside the sandbox
      // and is a supported audio format/size before sending it anywhere.
      final insideSandbox = await isPathInsideSandbox(widget.filePath);
      if (!insideSandbox) {
        throw const TranscriptionUploadException(
          'لا يمكن قراءة الملف من هذا المسار.',
          code: 'outside_sandbox',
        );
      }
      validateAudioFileForUpload(widget.filePath);

      // Route through the orchestrator so the on-device path is attempted first
      // on iOS; it falls back to the server automatically when needed.
      final uiLocale = Localizations.localeOf(context).languageCode;
      final result = await ref.read(sttOrchestratorProvider).transcribeFile(
            widget.filePath,
            source: 'share',
            sourceApp: widget.sourceApp,
            uiLocale: uiLocale,
          );
      if (!mounted) return;
      // Bust the cached subscription so the plans screen reflects the new
      // daily-used counter the next time it's opened.
      ref.invalidate(currentSubscriptionProvider);
      setState(() {
        _result = result;
        _processing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _processing = false;
      });
    }
  }

  Future<void> _copy() async {
    if (_result == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: _result!.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نسخ النص!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Re-runs the shared audio through the server for a higher-quality result
  /// when the user isn't happy with the free on-device transcript. This is a
  /// deliberate premium action — the backend bills it at 2× the daily quota.
  Future<void> _upgradeQuality() async {
    if (_result == null || _upgrading) return;
    setState(() => _upgrading = true);
    try {
      final result =
          await ref.read(sttOrchestratorProvider).retranscribeOnServer(
                widget.filePath,
                source: 'share',
                sourceApp: widget.sourceApp,
              );
      if (!mounted) return;
      // Refresh the cached subscription so the daily-used counter reflects the
      // 2 units this re-do just consumed.
      ref.invalidate(currentSubscriptionProvider);
      setState(() {
        _result = result;
        _upgrading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _upgrading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Opens the full result screen inside the app. Uses the local row id when we
  /// have it (so the user lands on the rich detail screen with save/share);
  /// otherwise falls back to the transcriptions list.
  void _openInApp() {
    final id = _result?.id;
    final route = id != null ? '/transcription/$id' : '/transcriptions';
    if (widget.onOpenRoute != null) {
      widget.onOpenRoute!(route);
    } else {
      widget.onDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Transparent scaffold so the sheet floats over whatever is behind it
    // (the translucent launch theme on Android / the app on iOS).
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.35),
      body: GestureDetector(
        // Tap the dimmed backdrop to dismiss.
        onTap: () => widget.onDone?.call(),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // swallow taps on the sheet itself
            child: _SheetBody(
              processing: _processing,
              error: _error,
              result: _result,
              upgrading: _upgrading,
              onClose: () => widget.onDone?.call(),
              onCopy: _copy,
              onUpgrade: _upgradeQuality,
              onOpenInApp: _openInApp,
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  final bool processing;
  final String? error;
  final Transcription? result;
  final bool upgrading;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onUpgrade;
  final VoidCallback onOpenInApp;

  const _SheetBody({
    required this.processing,
    required this.error,
    required this.result,
    required this.upgrading,
    required this.onClose,
    required this.onCopy,
    required this.onUpgrade,
    required this.onOpenInApp,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grabber.
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // Header.
              Row(
                children: [
                  Text(
                    'بصوتك',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (processing)
                _buildProcessing(context)
              else if (error != null)
                _buildError(context)
              else if (result != null)
                _buildResult(context, result!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessing(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('جاري تحويل الصوت...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 56, color: scheme.error),
          const SizedBox(height: 12),
          Text('فشل التحويل', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: onClose, child: const Text('إغلاق')),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, Transcription t) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1) Accuracy / duration + word count chips.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _Chip(icon: Icons.timer, label: _formatDuration(t.duration)),
            _Chip(icon: Icons.text_fields, label: '${t.wordCount} كلمة'),
            _Chip(
              icon: t.isClientSide ? Icons.phone_iphone : Icons.cloud,
              label: t.isClientSide ? 'داخل الجهاز' : 'عبر الخادم',
              color: t.isClientSide ? Colors.green : scheme.primary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // 3) The transcript text itself, scrollable + selectable.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                t.text.trim().isEmpty ? '—' : t.text,
                style: const TextStyle(fontSize: 17, height: 1.7),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // 2) Copy (full width).
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
        ),
        // "Higher quality" upgrade — only offered for a free on-device result.
        // A server result is already the high-quality path, so we hide it then.
        if (t.isClientSide) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: upgrading ? null : onUpgrade,
              icon: upgrading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                upgrading ? 'جاري التحويل عبر الخادم…' : 'الحصول على جودة أعلى',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'يحوّل الصوت عبر الخادم — يستهلك ٢× من رصيدك اليومي',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        // Action row: "فتح في بصوتك" on the leading (left) side, language on
        // the trailing (right) side, per the product spec.
        Row(
          children: [
            TextButton.icon(
              onPressed: onOpenInApp,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('فتح في بصوتك'),
            ),
            const Spacer(),
            Icon(Icons.language, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              t.languageName,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        // Server request id.
        const SizedBox(height: AppSpacing.xs),
        Text(
          t.serverRequestId != null
              ? 'معرّف الطلب: #${t.serverRequestId}'
              : 'سيظهر معرّف الطلب بعد المزامنة',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  String _formatDuration(double seconds) {
    if (seconds <= 0) return '—';
    if (seconds < 60) return '${seconds.toStringAsFixed(0)} ثانية';
    final m = seconds ~/ 60;
    final s = (seconds % 60).round();
    return '$m:${s.toString().padLeft(2, '0')} دقيقة';
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Chip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
