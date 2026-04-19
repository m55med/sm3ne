import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bisawtak/core/api/api_client.dart';

class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ref.read(apiClientProvider).dio.get('/support/tickets');
      final data = List<Map<String, dynamic>>.from(resp.data['tickets'] ?? []);
      setState(() {
        _tickets = data;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ?? 'تعذر تحميل الرسائل';
        _loading = false;
      });
    }
  }

  Future<void> _openNew() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _NewTicketSheet(),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اتصل بنا / اقتراحات'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('رسالة جديدة'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
    if (_tickets.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 120), _EmptyView()],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _tickets.length,
      itemBuilder: (_, i) => _TicketCard(
        data: _tickets[i],
        onTap: () => context.push('/contact/${_tickets[i]['public_id']}').then((_) => _load()),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _TicketCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'open';
    final type = data['ticket_type'] as String? ?? 'contact';
    final createdAt = data['created_at'] as String?;
    final replyCount = (data['reply_count'] as int?) ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          data['subject']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              _TypeBadge(type: type),
              const SizedBox(width: 6),
              _StatusBadge(status: status),
              const Spacer(),
              if (replyCount > 0) ...[
                Icon(Icons.forum_outlined, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text('$replyCount', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
              ],
              if (createdAt != null)
                Text(
                  _formatDate(createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_left, size: 20),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _meta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  (String, Color) _meta(String s) {
    switch (s) {
      case 'open':
        return ('جديدة', Colors.blue);
      case 'in_progress':
        return ('جاري العمل', Colors.orange);
      case 'resolved':
        return ('تم الحل', Colors.green);
      case 'closed':
        return ('مغلقة', Colors.grey);
      default:
        return (s, Colors.grey);
    }
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'suggestion' => 'اقتراح',
      'bug' => 'بلاغ خطأ',
      'other' => 'أخرى',
      _ => 'استفسار',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

String _formatDate(String iso) {
  try {
    final d = DateTime.parse(iso).toLocal();
    return DateFormat('yyyy/MM/dd HH:mm').format(d);
  } catch (_) {
    return iso;
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('لا توجد رسائل بعد', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(
            'اضغط "رسالة جديدة" لو عندك سؤال أو اقتراح',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}

// ---- New ticket bottom sheet ----

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _type = 'contact';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).dio.post('/support/tickets', data: {
        'ticket_type': _type,
        'subject': _subjectCtrl.text.trim(),
        'message': _messageCtrl.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ?? 'تعذر الإرسال';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('رسالة جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _type,
                items: const [
                  DropdownMenuItem(value: 'contact', child: Text('استفسار / تواصل')),
                  DropdownMenuItem(value: 'suggestion', child: Text('اقتراح')),
                  DropdownMenuItem(value: 'bug', child: Text('بلاغ عن خطأ')),
                  DropdownMenuItem(value: 'other', child: Text('أخرى')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'contact'),
                decoration: const InputDecoration(labelText: 'النوع'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(labelText: 'العنوان'),
                validator: (v) => (v == null || v.trim().length < 3) ? 'لازم العنوان 3 حروف على الأقل' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageCtrl,
                decoration: const InputDecoration(labelText: 'الرسالة', alignLabelWithHint: true),
                maxLines: 6,
                validator: (v) => (v == null || v.trim().length < 5) ? 'الرسالة قصيرة جداً' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(_sending ? 'جاري الإرسال...' : 'إرسال'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
