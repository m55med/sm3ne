import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/data/models/transcription.dart';

final transcriptionsProvider = FutureProvider<List<Transcription>>((ref) {
  return ref.read(transcriptionRepoProvider).getLocalTranscriptions();
});

class TranscriptionListScreen extends ConsumerStatefulWidget {
  const TranscriptionListScreen({super.key});

  @override
  ConsumerState<TranscriptionListScreen> createState() => _TranscriptionListScreenState();
}

class _TranscriptionListScreenState extends ConsumerState<TranscriptionListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final transcriptions = ref.watch(transcriptionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيلاتي'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'البحث في التسجيلات...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: transcriptions.when(
              data: (list) {
                final filtered = _search.isEmpty
                    ? list
                    : list.where((t) => t.text.contains(_search)).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text('لا توجد تسجيلات بعد', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final t = filtered[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(t.language.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(
                          t.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Row(
                          children: [
                            Icon(Icons.timer, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text('${t.duration.toStringAsFixed(1)}ث'),
                            const SizedBox(width: 12),
                            Icon(_sourceIcon(t.source), size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(_sourceLabel(t.source)),
                          ],
                        ),
                        trailing: t.wasTrimmed
                            ? const Icon(Icons.content_cut, size: 16, color: Colors.orange)
                            : null,
                        onTap: () {
                          if (t.id != null) context.push('/transcription/${t.id}');
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
            ),
          ),
        ],
      ),
    );
  }

  IconData _sourceIcon(String source) {
    switch (source) {
      case 'recorded': return Icons.mic;
      case 'shared': return Icons.share;
      default: return Icons.upload_file;
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'recorded': return 'تسجيل';
      case 'shared': return 'مشاركة';
      default: return 'رفع';
    }
  }
}
