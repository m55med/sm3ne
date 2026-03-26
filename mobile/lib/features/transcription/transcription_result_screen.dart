import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' as share;
import 'package:bisawtak/data/local/transcription_dao.dart';
import 'package:bisawtak/data/models/transcription.dart';

class TranscriptionResultScreen extends ConsumerWidget {
  final int transcriptionId;

  const TranscriptionResultScreen({super.key, required this.transcriptionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Transcription?>(
      future: TranscriptionDao().getById(transcriptionId),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final t = snap.data!;

        return Scaffold(
          appBar: AppBar(
            title: const Text('النتيجة'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await TranscriptionDao().delete(t.id!);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatChip(icon: Icons.language, label: t.languageName),
                    _StatChip(icon: Icons.timer, label: '${t.duration.toStringAsFixed(1)}ث'),
                    _StatChip(icon: Icons.text_fields, label: '${t.wordCount} كلمة'),
                    _StatChip(icon: Icons.abc, label: '${t.charCount} حرف'),
                  ],
                ),
                if (t.wasTrimmed)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.content_cut, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Expanded(child: Text('تم قص الصوت إلى 30 ثانية (باقة مجانية)')),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                const Text('النص:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    t.text,
                    style: const TextStyle(fontSize: 18, height: 1.8),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: t.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم نسخ النص!')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('نسخ'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => share.Share.share(t.text),
                        icon: const Icon(Icons.share),
                        label: const Text('مشاركة'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
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
