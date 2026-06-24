import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/stt/stt_orchestrator.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/features/plans/plans_screen.dart' show currentSubscriptionProvider;
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/file_validation.dart';
import 'package:bisawtak/shared/utils/sandbox_paths.dart';

/// Floating result sheet shown when a voice note is shared into the app via the
/// document-open path (the full app launches).
///
/// It renders as a `Positioned.fill` overlay inside `MaterialApp.router`'s
/// builder, so the sheet floats over the app's own home (dimmed by its 0.35
/// scrim) instead of a solid-black screen. It does NOT float over the host app
/// (WhatsApp) — that case is handled by the native iOS Share Extension. The
/// sheet mirrors that native sheet: duration + word-count chips, the text,
/// copy + translate, and an action row with the language (right) and
/// "فتح في بصوتك" (left), plus the server request id.
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
  // On-demand Arabic translation state (cached on the row once fetched).
  String? _translation;
  bool _translating = false;
  bool _showTranslation = true;

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
        _translation = result.translation;
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

  Future<void> _copy() => _copyText(_result?.text ?? '', 'تم نسخ النص!');

  Future<void> _copyTranslation() =>
      _copyText(_translation ?? '', 'تم نسخ الترجمة!');

  Future<void> _copyText(String text, String okLabel) async {
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(okLabel)),
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
        // The text changed — drop any stale translation of the old transcript.
        _translation = result.translation;
        _showTranslation = true;
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

  /// Translates the transcript into Arabic via the server (1 daily credit),
  /// caches it on the local row, and shows it under the original text.
  Future<void> _translate() async {
    final t = _result;
    if (t == null || _translating) return;
    setState(() => _translating = true);
    try {
      final updated = await ref.read(transcriptionRepoProvider).translate(t);
      if (!mounted) return;
      setState(() {
        _result = updated;
        _translation = updated.translation;
        _showTranslation = true;
        _translating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _translating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is TranslationException ? e.message : friendlyErrorMessage(e)),
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
              translation: _translation,
              translating: _translating,
              showTranslation: _showTranslation,
              onClose: () => widget.onDone?.call(),
              onCopy: _copy,
              onCopyTranslation: _copyTranslation,
              onUpgrade: _upgradeQuality,
              onOpenInApp: _openInApp,
              onTranslate: _translate,
              onToggleTranslation: () =>
                  setState(() => _showTranslation = !_showTranslation),
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
  final String? translation;
  final bool translating;
  final bool showTranslation;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onCopyTranslation;
  final VoidCallback onUpgrade;
  final VoidCallback onOpenInApp;
  final VoidCallback onTranslate;
  final VoidCallback onToggleTranslation;

  const _SheetBody({
    required this.processing,
    required this.error,
    required this.result,
    required this.upgrading,
    required this.translation,
    required this.translating,
    required this.showTranslation,
    required this.onClose,
    required this.onCopy,
    required this.onCopyTranslation,
    required this.onUpgrade,
    required this.onOpenInApp,
    required this.onTranslate,
    required this.onToggleTranslation,
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
    // Arabic transcripts have nothing to translate to Arabic — hide the button.
    final canTranslate = t.text.trim().isNotEmpty &&
        !t.language.toLowerCase().startsWith('ar');
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
        // 2) Copy + Translate (translate sits beside copy, hidden for Arabic).
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ'),
                ),
              ),
            ),
            if (canTranslate) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SizedBox(height: 48, child: _translateButton(context)),
              ),
            ],
          ],
        ),
        if (canTranslate && translation == null && !translating) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'الترجمة إلى العربية تخصم 1 من رصيدك اليومي',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
        // Arabic translation card (cached after the first translate).
        if (translation != null && showTranslation) ...[
          const SizedBox(height: AppSpacing.sm),
          _TranslationCard(text: translation!, onCopy: onCopyTranslation),
        ],
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

  Widget _translateButton(BuildContext context) {
    if (translating) {
      return ElevatedButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('يترجم…'),
      );
    }
    final translated = translation != null;
    return ElevatedButton.icon(
      onPressed: translated ? onToggleTranslation : onTranslate,
      icon: Icon(
        translated
            ? (showTranslation ? Icons.visibility_off : Icons.visibility)
            : Icons.translate,
        size: 18,
      ),
      label: Text(
        translated ? (showTranslation ? 'إخفاء' : 'إظهار') : 'ترجمة',
      ),
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

class _TranslationCard extends StatelessWidget {
  final String text;
  final VoidCallback onCopy;
  const _TranslationCard({required this.text, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.translate, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'الترجمة (العربية)',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'نسخ الترجمة',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: onCopy,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SelectableText(
                  text,
                  style: const TextStyle(fontSize: 16, height: 1.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
