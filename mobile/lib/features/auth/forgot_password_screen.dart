import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/api/api_client.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;

  Future<void> _sendOtp() async {
    if (_emailCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).dio.post('/auth/forgot-password', data: {'email': _emailCtrl.text});
      setState(() => _otpSent = true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال رمز التحقق')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ'), backgroundColor: Colors.red));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_otpCtrl.text.isEmpty || _newPasswordCtrl.text.length < 6) return;
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).dio.post('/auth/reset-password', data: {
        'email': _emailCtrl.text,
        'otp': _otpCtrl.text,
        'new_password': _newPasswordCtrl.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة السر بنجاح')));
        context.go('/login');
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data?['detail'] ?? 'خطأ'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة السر')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.lock_reset, size: 64, color: Colors.grey),
            const SizedBox(height: 24),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
              keyboardType: TextInputType.emailAddress,
              enabled: !_otpSent,
            ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otpCtrl,
                decoration: const InputDecoration(labelText: 'رمز التحقق', prefixIcon: Icon(Icons.pin)),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newPasswordCtrl,
                decoration: const InputDecoration(labelText: 'كلمة السر الجديدة', prefixIcon: Icon(Icons.lock_outline)),
                obscureText: true,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : (_otpSent ? _resetPassword : _sendOtp),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_otpSent ? 'تغيير كلمة السر' : 'إرسال رمز التحقق'),
            ),
          ],
        ),
      ),
    );
  }
}
