import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/widgets/empty_state.dart';
import 'package:bisawtak/shared/widgets/error_view.dart';
import 'package:bisawtak/shared/widgets/skeletons.dart';

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
    // Pull-to-refresh also re-syncs the server-side request history so the
    // user can manually recover their event history (e.g. right after a
    // reinstall) without waiting for the post-login background sync.
    await ref.read(transcriptionRepoProvider).syncHistoryFromServer();
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

    // When a background history-sync inserts new rows it pulses this signal;
    // invalidate our cached list so the restored history shows immediately.
    ref.listen<int>(historySyncSignalProvider, (_, __) {
      ref.invalidate(transcriptionsProvider);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيلاتي')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'البحث في التسجيلات...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
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
            return const TranscriptionListSkeleton();
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
      loading: () => const TranscriptionListSkeleton(),
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
                title: _searchCtrl.text.trim().isNotEmpty
                    ? 'لا توجد نتائج مطابقة'
                    : 'لا توجد تسجيلات بعد',
                message: _searchCtrl.text.trim().isNotEmpty
                    ? 'جرّب كلمة بحث مختلفة.'
                    : 'سجّل أول صوت لك أو ارفع ملفاً صوتياً للبدء.',
                actionLabel: _searchCtrl.text.trim().isNotEmpty ? null : 'ابدأ التسجيل',
                onAction: _searchCtrl.text.trim().isNotEmpty
                    ? null
                    : () => context.go('/home'),
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final t = list[i];
        return _TranscriptionTile(transcription: t);
      },
    );
  }
}

class _TranscriptionTile extends StatelessWidget {
  final Transcription transcription;
  const _TranscriptionTile({required this.transcription});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = transcription;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text(
            t.language.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        title: Hero(
          tag: 'transcription-text-${t.id ?? 0}',
          flightShuttleBuilder: _flightShuttle,
          child: Material(
            color: Colors.transparent,
            // Restored rows carry no transcript text (the server never stored
            // it). Show a muted, italic placeholder describing the event
            // instead of a blank line so the history still reads clearly.
            child: t.isRestored && t.text.trim().isEmpty
                ? Text(
                    '${_sourceLabel(t.source)} • ${t.wordCount} كلمة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: scheme.onSurfaceVariant,
                        ),
                  )
                : Text(
                    t.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(
            children: [
              Icon(Icons.timer, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${t.duration.toStringAsFixed(1)}ث',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(_sourceIcon(t.source), size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _sourceLabel(t.source),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Provenance + server request id, so admins (and curious users)
              // can verify on-device transcriptions made it to the backend.
              // On-device rows get a green phone icon; server-backed rows get
              // a cloud icon in the primary tint.
              Icon(
                t.isClientSide ? Icons.phone_iphone : Icons.cloud,
                size: 14,
                color: t.isClientSide ? Colors.green : scheme.primary,
              ),
              const SizedBox(width: 2),
              Text(
                t.serverRequestId != null
                    ? '#${t.serverRequestId}'
                    : (t.isClientSide ? 'محلي' : 'خادم'),
                style: TextStyle(
                  color: t.isClientSide ? Colors.green : scheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                _formatRelative(t.createdAt),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
        trailing: t.wasTrimmed
            ? Tooltip(
                message: 'تم قص الصوت',
                child: Icon(Icons.content_cut, size: 16, color: Theme.of(context).extension<BrandColors>()?.warningAmber ?? scheme.tertiary),
              )
            : null,
        onTap: () {
          if (t.id != null) context.push('/transcription/${t.id}');
        },
      ),
    );
  }

  IconData _sourceIcon(String source) {
    switch (source) {
      case 'recorded':
        return Icons.mic;
      case 'shared':
        return Icons.share;
      default:
        return Icons.upload_file;
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'recorded':
        return 'تسجيل';
      case 'shared':
        return 'مشاركة';
      default:
        return 'رفع';
    }
  }

  /// Renders a short relative timestamp. Input is expected in UTC ISO-8601
  /// (`DateTime.now().toUtc().toIso8601String()`) — we convert back to the
  /// device's local time before formatting so the user sees the wall clock
  /// they remember.
  String _formatRelative(String iso) {
    if (iso.isEmpty) return '';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    return DateFormat('yyyy-MM-dd').format(local);
  }

  Widget _flightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // Use the destination's widget during the flight so the text style
    // morphs smoothly.
    return DefaultTextStyle(
      style: DefaultTextStyle.of(toHeroContext).style,
      child: toHeroContext.widget,
    );
  }
}
