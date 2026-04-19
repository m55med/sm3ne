import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameCtrl = TextEditingController(text: user?.fullName ?? '');
    _emailCtrl = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(apiClientProvider).dio.put('/profile', data: {
        'full_name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      });
      await ref.read(authProvider.notifier).checkAuth();
      setState(() => _success = 'تم حفظ التعديلات');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التعديلات'), behavior: SnackBarBehavior.floating),
        );
      }
    } on DioException catch (e) {
      setState(() => _error = e.response?.data?['detail']?.toString() ?? 'تعذر الحفظ');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل البروفايل'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    (user?.fullName ?? user?.username ?? '?')[0].toUpperCase(),
                    style: TextStyle(fontSize: 34, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '@${user?.username ?? ''}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  return re.hasMatch(v.trim()) ? null : 'بريد إلكتروني غير صحيح';
                },
              ),
              const SizedBox(height: 12),
              _ReadOnlyRow(label: 'اسم المستخدم', value: user?.username ?? '-'),
              _ReadOnlyRow(label: 'تسجيل الدخول عبر', value: _providerLabel(user?.authProvider)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _Banner(text: _error!, color: Colors.red),
              ],
              if (_success != null) ...[
                const SizedBox(height: 12),
                _Banner(text: _success!, color: Colors.green),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_saving ? 'جاري الحفظ...' : 'حفظ التغييرات'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _providerLabel(String? p) {
    switch (p) {
      case 'google':
        return 'Google';
      case 'apple':
        return 'Apple';
      case 'local':
      default:
        return 'البريد الإلكتروني';
    }
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  const _Banner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}
