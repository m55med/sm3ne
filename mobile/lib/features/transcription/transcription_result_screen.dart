import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' as share;
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/data/local/transcription_dao.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/haptics.dart';
import 'package:bisawtak/shared/widgets/confirm_dialog.dart';

class TranscriptionResultScreen extends ConsumerWidget {
  final int transcriptionId;

  const TranscriptionResultScreen({super.key, required this.transcriptionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Transcription?>(
      future: TranscriptionDao().getById(transcriptionId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final t = snap.data;
        if (t == null) {
          // The row may have been deleted from another screen while the
          // user navigated here (e.g. swipe-to-delete in the list).
          return Scaffold(
            appBar: AppBar(title: const Text('النتيجة')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'تعذّر العثور على هذا التسجيل.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

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
                        const Expanded(
                          child: Text('تم قص الصوت إلى 30 ثانية (باقة مجانية)'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'النص:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Hero(
                  tag: 'transcription-text-${t.id ?? transcriptionId}',
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontSize: 18,
                              height: 1.8,
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
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
                      child: OutlinedButton.icon(
                        onPressed: () => _share(t.text),
                        icon: const Icon(Icons.share),
                        label: const Text('مشاركة'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      Haptics.success();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نسخ النص!')),
        );
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

    // Show the Undo snackbar and only pop after it closes. If the user
    // pressed Undo we re-insert the row preserving its id and stay on
    // the screen so the FutureBuilder can re-resolve it.
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
      // Pop via GoRouter so the back stack stays consistent.
      if (router.canPop()) router.pop();
    }
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
