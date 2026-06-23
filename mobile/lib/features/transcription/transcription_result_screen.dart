import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' as share;
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/data/local/transcription_dao.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/haptics.dart';
import 'package:bisawtak/shared/widgets/confirm_dialog.dart';

class TranscriptionResultScreen extends ConsumerStatefulWidget {
  final int transcriptionId;

  const TranscriptionResultScreen({super.key, required this.transcriptionId});

  @override
  ConsumerState<TranscriptionResultScreen> createState() =>
      _TranscriptionResultScreenState();
}

class _TranscriptionResultScreenState
    extends ConsumerState<TranscriptionResultScreen> {
  Transcription? _t;
  bool _loading = true;
  // Cached Arabic translation (from the local row, or fetched on demand).
  String? _translation;
  bool _translating = false;
  bool _showTranslation = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await TranscriptionDao().getById(widget.transcriptionId);
    if (!mounted) return;
    setState(() {
      _t = t;
      _translation = t?.translation;
      _loading = false;
    });
  }

  /// Arabic transcripts have nothing to translate to Arabic — hide the button.
  bool get _isArabic => _t?.language.toLowerCase().startsWith('ar') ?? false;

  bool get _canTranslate {
    final t = _t;
    return t != null && t.text.trim().isNotEmpty && !_isArabic;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = _t;
    if (t == null) {
      // The row may have been deleted from another screen while the user
      // navigated here (e.g. swipe-to-delete in the list).
      return Scaffold(
        appBar: AppBar(title: const Text('النتيجة')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Text('تعذّر العثور على هذا التسجيل.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('النتيجة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'حذف التسجيل',
            onPressed: () => _confirmDelete(context, t),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _StatChip(icon: Icons.language, label: t.languageName),
                _StatChip(icon: Icons.timer, label: '${t.duration.toStringAsFixed(1)}ث'),
                _StatChip(icon: Icons.text_fields, label: '${t.wordCount} كلمة'),
                _StatChip(icon: Icons.abc, label: '${t.charCount} حرف'),
                _ProviderChip(transcription: t),
              ],
            ),
            if (t.wasTrimmed)
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.lg),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.brand.warningAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.content_cut, color: context.brand.warningAmber, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(child: Text('تم قص الصوت إلى 30 ثانية (باقة مجانية)')),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'النص:',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Restored history rows have no transcript text — the server only
            // kept the request metadata, never the audio or the words. Show an
            // explanatory card and hide copy/share/translate.
            if (t.isRestored && t.text.trim().isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history, color: scheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'هذا السجل مُستعاد من خادمنا. لا نحتفظ بنص التفريغ '
                        'أو الصوت على الخادم حفاظاً على خصوصيتك، لذلك يظهر '
                        'الطلب هنا بتفاصيله دون النص.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.6,
                            ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Hero(
                tag: 'transcription-text-${t.id ?? widget.transcriptionId}',
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: SelectableText(
                      t.text,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontSize: 18, height: 1.8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _buildActions(context, t, scheme),
              if (_translation != null && _showTranslation) ...[
                const SizedBox(height: AppSpacing.lg),
                _TranslationCard(
                  text: _translation!,
                  onCopy: () => _copy(context, _translation!, label: 'تم نسخ الترجمة!'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, Transcription t, ColorScheme scheme) {
    // Primary row: نسخ + (ترجمة beside it, as requested). When the text is
    // already Arabic the translate button is replaced by مشاركة so the row
    // never shows a pointless Arabic→Arabic action.
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _copy(context, t.text),
                icon: const Icon(Icons.copy),
                label: const Text('نسخ'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _canTranslate
                  ? _translateButton(context)
                  : OutlinedButton.icon(
                      onPressed: () => _share(t.text),
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة'),
                    ),
            ),
          ],
        ),
        // When translate took the second slot, keep مشاركة available full-width.
        if (_canTranslate) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _share(t.text),
              icon: const Icon(Icons.share),
              label: const Text('مشاركة'),
            ),
          ),
          if (_translation == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'الترجمة إلى العربية تخصم 1 من رصيدك اليومي.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _translateButton(BuildContext context) {
    if (_translating) {
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
    final translated = _translation != null;
    return ElevatedButton.icon(
      onPressed: translated
          ? () => setState(() => _showTranslation = !_showTranslation)
          : _translate,
      icon: Icon(translated
          ? (_showTranslation ? Icons.visibility_off : Icons.visibility)
          : Icons.translate),
      label: Text(translated
          ? (_showTranslation ? 'إخفاء الترجمة' : 'إظهار الترجمة')
          : 'ترجمة'),
    );
  }

  Future<void> _translate() async {
    final t = _t;
    if (t == null) return;
    Haptics.tap();
    setState(() => _translating = true);
    try {
      final updated = await ref.read(transcriptionRepoProvider).translate(t);
      if (!mounted) return;
      setState(() {
        _t = updated;
        _translation = updated.translation;
        _showTranslation = true;
        _translating = false;
      });
      Haptics.success();
    } catch (e) {
      if (!mounted) return;
      setState(() => _translating = false);
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is TranslationException ? e.message : friendlyErrorMessage(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _copy(BuildContext context, String text, {String label = 'تم نسخ النص!'}) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      Haptics.success();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
      }
    } catch (e) {
      Haptics.error();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _share(String text) async {
    Haptics.tap();
    await share.Share.share(text);
  }

  Future<void> _confirmDelete(BuildContext context, Transcription t) async {
    final ok = await showConfirmDialog(
      context,
      title: 'حذف التسجيل',
      message: 'هل تريد حذف هذا التسجيل نهائياً؟ يمكنك التراجع خلال 4 ثوانٍ.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    final dao = TranscriptionDao();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      await dao.delete(t.id!);
      Haptics.tap();
    } catch (e) {
      Haptics.error();
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Show the Undo snackbar and only pop after it closes. If the user pressed
    // Undo we re-insert the row preserving its id and stay on the screen.
    bool undone = false;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('تم حذف التسجيل'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () async {
            undone = true;
            await dao.insertWithId(t);
            Haptics.success();
          },
        ),
      ),
    );

    await controller.closed;
    if (!undone) {
      if (router.canPop()) router.pop();
    }
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
      padding: const EdgeInsets.all(AppSpacing.lg),
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
              Icon(Icons.translate, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'الترجمة (العربية)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
          const SizedBox(height: AppSpacing.sm),
          Directionality(
            textDirection: TextDirection.rtl,
            child: SelectableText(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontSize: 18, height: 1.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ProviderChip extends StatelessWidget {
  final Transcription transcription;
  const _ProviderChip({required this.transcription});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOnDevice = transcription.isClientSide;
    final reqId = transcription.serverRequestId;
    final label = isOnDevice
        ? (reqId != null ? 'داخل الجهاز • #$reqId' : 'داخل الجهاز')
        : (reqId != null ? 'عبر الخادم • #$reqId' : 'عبر الخادم');
    final color = isOnDevice ? Colors.green : scheme.primary;
    return Chip(
      avatar: Icon(
        isOnDevice ? Icons.phone_iphone : Icons.cloud,
        size: 16,
        color: color,
      ),
      label: Text(
        label,
        style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
      ),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: color.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
    );
  }
}
