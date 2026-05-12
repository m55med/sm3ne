import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

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
  bool _obscure = true;

  // Resend cooldown state.
  static const _resendCooldown = 30;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPasswordCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendCooldown);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).dio.post('/auth/forgot-password', data: {'email': email});
      if (!mounted) return;
      setState(() => _otpSent = true);
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isResend ? 'تم إرسال رمز جديد' : 'تم إرسال رمز التحقق')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final otp = _otpCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;
    if (otp.isEmpty || newPassword.length < 10 || _loading) {
      if (newPassword.length < 10 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('كلمة السر يجب أن تكون 10 أحرف على الأقل'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).dio.post('/auth/reset-password', data: {
        'email': _emailCtrl.text.trim(),
        'otp': otp,
        'new_password': newPassword,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة السر بنجاح')));
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة السر')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.lock_reset, size: 64, color: Colors.grey),
            const SizedBox(height: 24),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.email],
              enabled: !_otpSent,
            ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otpCtrl,
                decoration: const InputDecoration(
                  labelText: 'رمز التحقق',
                  prefixIcon: Icon(Icons.pin),
                  counterText: '',
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newPasswordCtrl,
                decoration: InputDecoration(
                  labelText: 'كلمة السر الجديدة',
                  prefixIcon: const Icon(Icons.lock_outline),
                  helperText: '10 أحرف على الأقل',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: (_resendIn > 0 || _loading) ? null : () => _sendOtp(isResend: true),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    _resendIn > 0 ? 'إعادة الإرسال خلال $_resendIn ث' : 'إعادة إرسال الرمز',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
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
