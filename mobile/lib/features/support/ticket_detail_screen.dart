import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bisawtak/core/api/api_client.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  final String publicId;
  const TicketDetailScreen({super.key, required this.publicId});

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  Map<String, dynamic>? _ticket;
  bool _loading = true;
  String? _error;
  final _replyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ref.read(apiClientProvider).dio.get('/support/tickets/${widget.publicId}');
      setState(() {
        _ticket = Map<String, dynamic>.from(resp.data);
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ?? 'تعذر التحميل';
        _loading = false;
      });
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).dio.post(
        '/support/tickets/${widget.publicId}/replies',
        data: {'message': text},
      );
      _replyCtrl.clear();
      await _load();
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data?['detail']?.toString() ?? 'فشل الإرسال')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الرسالة'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    final t = _ticket!;
    final replies = List<Map<String, dynamic>>.from(t['replies'] ?? []);
    final status = t['status'] as String? ?? 'open';
    final isClosed = status == 'closed';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(ticket: t),
              const SizedBox(height: 16),
              _MessageBubble(
                authorName: t['username']?.toString() ?? 'أنت',
                message: t['message']?.toString() ?? '',
                isAdmin: false,
                createdAt: t['created_at']?.toString(),
              ),
              const SizedBox(height: 12),
              if (replies.isNotEmpty) ...[
                Divider(color: Colors.grey.shade200),
                const SizedBox(height: 8),
              ],
              ...replies.map((r) => _MessageBubble(
                    authorName: r['author_name']?.toString() ?? (r['is_admin'] == true ? 'فريق الدعم' : 'أنت'),
                    message: r['message']?.toString() ?? '',
                    isAdmin: r['is_admin'] == true,
                    createdAt: r['created_at']?.toString(),
                  )),
            ],
          ),
        ),
        if (!isClosed)
          SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'اكتب ردك...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendReply,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Center(
              child: Text('الرسالة مغلقة', style: TextStyle(color: Colors.grey.shade700)),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final Map<String, dynamic> ticket;
  const _Header({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final status = ticket['status'] as String? ?? 'open';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ticket['subject']?.toString() ?? '',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _TypeChip(type: ticket['ticket_type']?.toString() ?? 'contact'),
                const SizedBox(width: 8),
                _StatusChip(status: status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String authorName;
  final String message;
  final bool isAdmin;
  final String? createdAt;

  const _MessageBubble({
    required this.authorName,
    required this.message,
    required this.isAdmin,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isAdmin ? cs.primaryContainer : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isAdmin ? Icons.support_agent : Icons.person,
                  size: 14,
                  color: isAdmin ? cs.primary : Colors.grey.shade700,
                ),
                const SizedBox(width: 4),
                Text(
                  authorName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isAdmin ? cs.primary : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(height: 1.5)),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(_fmt(createdAt!), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return DateFormat('yyyy/MM/dd HH:mm').format(d);
    } catch (_) {
      return iso;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'open' => ('جديدة', Colors.blue),
      'in_progress' => ('جاري العمل', Colors.orange),
      'resolved' => ('تم الحل', Colors.green),
      'closed' => ('مغلقة', Colors.grey),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'suggestion' => 'اقتراح',
      'bug' => 'بلاغ خطأ',
      'other' => 'أخرى',
      _ => 'استفسار',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
