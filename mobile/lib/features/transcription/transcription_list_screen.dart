import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/widgets/empty_state.dart';
import 'package:bisawtak/shared/widgets/error_view.dart';

final transcriptionsProvider = FutureProvider<List<Transcription>>((ref) {
  return ref.read(transcriptionRepoProvider).getLocalTranscriptions();
});

class TranscriptionListScreen extends ConsumerStatefulWidget {
  const TranscriptionListScreen({super.key});

  @override
  ConsumerState<TranscriptionListScreen> createState() => _TranscriptionListScreenState();
}

class _TranscriptionListScreenState extends ConsumerState<TranscriptionListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  Future<List<Transcription>>? _searchFuture;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        if (value.trim().isEmpty) {
          _searchFuture = null;
        } else {
          _searchFuture = ref.read(transcriptionRepoProvider).search(value.trim());
        }
      });
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(transcriptionsProvider);
    if (_searchCtrl.text.trim().isNotEmpty) {
      setState(() {
        _searchFuture = ref.read(transcriptionRepoProvider).search(_searchCtrl.text.trim());
      });
    }
    await ref.read(transcriptionsProvider.future);
  }

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
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'البحث في التسجيلات...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _buildList(transcriptions),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(AsyncValue<List<Transcription>> all) {
    // If user is searching, prefer the (debounced) dao.search future.
    if (_searchFuture != null) {
      return FutureBuilder<List<Transcription>>(
        future: _searchFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorView(
              message: friendlyErrorMessage(snap.error ?? 'unknown'),
              onRetry: _refresh,
            );
          }
          return _renderList(snap.data ?? const []);
        },
      );
    }
    return all.when(
      data: _renderList,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: friendlyErrorMessage(e),
        onRetry: _refresh,
      ),
    );
  }

  Widget _renderList(List<Transcription> list) {
    if (list.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // Wrap in a scrollable so RefreshIndicator stays usable on empty.
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: EmptyState(
                icon: Icons.mic_none,
                title: 'لا توجد تسجيلات بعد',
                message: 'سجّل أول صوت لك أو ارفع ملفاً صوتياً.',
                actionLabel: 'ابدأ التسجيل',
                onAction: () => context.go('/home'),
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final t = list[i];
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
