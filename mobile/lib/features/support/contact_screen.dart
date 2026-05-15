import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/data/repositories/support_repository.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/widgets/empty_state.dart';
import 'package:bisawtak/shared/widgets/error_view.dart';

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
    // Make sure intl's Arabic locale data is initialised once before any
    // DateFormat('...', 'ar') call.
    initializeDateFormatting('ar', null);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Stays on the raw API call here because the existing UI relies on
      // metadata (ticket_type, reply_count, ...) not yet exposed by
      // SupportRepository's typed model.
      final resp = await ref.read(apiClientProvider).dio.get('/support/tickets');
      final data = resp.data is Map<String, dynamic>
          ? List<Map<String, dynamic>>.from(resp.data['tickets'] ?? const [])
          : List<Map<String, dynamic>>.from(resp.data as List);
      setState(() {
        _tickets = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
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
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          ErrorView(message: _error!, onRetry: _load),
        ],
      );
    }
    if (_tickets.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          EmptyState(
            icon: Icons.forum_outlined,
            title: 'لا توجد رسائل بعد',
            message: 'اضغط "رسالة جديدة" لو عندك سؤال أو اقتراح',
          ),
        ],
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
        subtitle: Builder(
          builder: (context) {
            final muted = Theme.of(context).colorScheme.onSurfaceVariant;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _TypeBadge(type: type),
                  const SizedBox(width: 6),
                  _StatusBadge(status: status),
                  const Spacer(),
                  if (replyCount > 0) ...[
                    Icon(Icons.forum_outlined, size: 14, color: muted),
                    const SizedBox(width: 4),
                    Text('$replyCount', style: TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(width: 8),
                  ],
                  if (createdAt != null)
                    Text(
                      _formatDate(createdAt),
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                ],
              ),
            );
          },
        ),
        trailing: Icon(forwardChevron(context), size: 20),
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
    return DateFormat('yyyy/MM/dd HH:mm', 'ar').format(d);
  } catch (_) {
    return iso;
  }
}

// ---- New ticket bottom sheet ----

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

// Mirrors the server-side defaults. Server still re-validates — this only
// gives instant feedback so the user doesn't wait for an upload to fail.
const _kMaxAttachmentBytes = 5 * 1024 * 1024;
const _kMaxAttachments = 5;
const _kAllowedExts = ['jpg', 'jpeg', 'png', 'webp', 'heic'];

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _type = 'contact';
  bool _sending = false;
  String? _error;
  final List<File> _attachments = [];

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_sending) return;
    if (_attachments.length >= _kMaxAttachments) {
      setState(() => _error = 'الحد الأقصى $_kMaxAttachments صور');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _kAllowedExts,
        allowMultiple: true,
        withData: false,
      );
      if (result == null) return;
      final added = <File>[];
      for (final f in result.files) {
        if (f.path == null) continue;
        final file = File(f.path!);
        final size = await file.length();
        if (size > _kMaxAttachmentBytes) {
          setState(() => _error =
              'الصورة "${f.name}" أكبر من ${_kMaxAttachmentBytes ~/ (1024 * 1024)} ميجا');
          continue;
        }
        added.add(file);
        if (_attachments.length + added.length >= _kMaxAttachments) break;
      }
      if (added.isNotEmpty) {
        setState(() {
          _attachments.addAll(added);
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = friendlyErrorMessage(e));
    }
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final subject = _subjectCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    try {
      // Route through the typed repository when subject/body are sufficient.
      // For ticket type metadata not yet supported by the repo, fall back to
      // direct API call.
      String? publicId;
      if (_type == 'contact') {
        final ticket = await ref.read(supportRepositoryProvider).createTicket(
              subject: subject,
              body: message,
            );
        publicId = ticket.publicId;
      } else {
        final resp = await ref
            .read(apiClientProvider)
            .dio
            .post('/support/tickets', data: {
          'ticket_type': _type,
          'subject': subject,
          'message': message,
        });
        final data = resp.data;
        if (data is Map) {
          publicId = data['public_id']?.toString();
        }
      }

      // Upload attachments sequentially. We tolerate per-image failures so a
      // single bad image doesn't lose the ticket — but surface the count.
      int failed = 0;
      if (publicId != null && _attachments.isNotEmpty) {
        final repo = ref.read(supportRepositoryProvider);
        for (final f in _attachments) {
          try {
            await repo.uploadAttachment(publicId: publicId, filePath: f.path);
          } catch (_) {
            failed++;
          }
        }
      }
      if (mounted) {
        if (failed > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم إرسال التذكرة لكن فشل رفع $failed صورة')),
          );
        }
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
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
                    color: Theme.of(context).colorScheme.outlineVariant,
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
                onChanged: _sending ? null : (v) => setState(() => _type = v ?? 'contact'),
                decoration: const InputDecoration(labelText: 'النوع'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(labelText: 'العنوان'),
                enabled: !_sending,
                validator: (v) => (v == null || v.trim().length < 3) ? 'لازم العنوان 3 حروف على الأقل' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageCtrl,
                decoration: const InputDecoration(labelText: 'الرسالة', alignLabelWithHint: true),
                maxLines: 6,
                enabled: !_sending,
                validator: (v) => (v == null || v.trim().length < 5) ? 'الرسالة قصيرة جداً' : null,
              ),
              const SizedBox(height: 12),
              _AttachmentPicker(
                files: _attachments,
                disabled: _sending,
                onAdd: _pickImages,
                onRemove: (i) => setState(() => _attachments.removeAt(i)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

class _AttachmentPicker extends StatelessWidget {
  final List<File> files;
  final bool disabled;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  const _AttachmentPicker({
    required this.files,
    required this.disabled,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: disabled || files.length >= _kMaxAttachments ? null : onAdd,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('إرفاق صور'),
            ),
            const SizedBox(width: 8),
            Text(
              files.isEmpty
                  ? 'اختياري (سكرين شوت)'
                  : '${files.length}/$_kMaxAttachments',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: files.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _AttachmentThumb(
                file: files[i],
                onRemove: disabled ? null : () => onRemove(i),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  final File file;
  final VoidCallback? onRemove;

  const _AttachmentThumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
