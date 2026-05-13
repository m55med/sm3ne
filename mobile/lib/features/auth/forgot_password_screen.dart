import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  bool _obscure = true;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

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

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'البريد الإلكتروني مطلوب';
    if (!_emailRegex.hasMatch(value)) return 'بريد إلكتروني غير صحيح';
    return null;
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    if (_loading) return;
    // Validate the email field through the Form so user sees inline errors.
    if (!isResend && !(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailCtrl.text.trim();
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
      if (!mounted) return;
      // Only start the cooldown AFTER a successful send — otherwise we lock
      // the resend button on a transient failure for no reason.
      setState(() => _otpSent = true);
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isResend ? 'تم إرسال رمز جديد' : 'تم إرسال رمز التحقق')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_loading) return;
    final otp = _otpCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;
    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رمز التحقق')),
      );
      return;
    }
    if (newPassword.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('كلمة السر يجب أن تكون 10 أحرف على الأقل'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير كلمة السر بنجاح')),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة السر')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          // ListView keeps content reachable when the keyboard is shown.
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              children: [
                const SizedBox(height: AppSpacing.lg),
                Icon(Icons.lock_reset, size: 64, color: scheme.primary),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _otpSent
                      ? 'أدخل الرمز المرسل إلى بريدك واختر كلمة سر جديدة.'
                      : 'أدخل بريدك الإلكتروني وسنرسل لك رمز تحقق.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  enabled: !_otpSent,
                  validator: _validateEmail,
                ),
                if (_otpSent) ...[
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _otpCtrl,
                    decoration: const InputDecoration(
                      labelText: 'رمز التحقق',
                      prefixIcon: Icon(Icons.pin),
                      counterText: '',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autofillHints: const [AutofillHints.oneTimeCode],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _newPasswordCtrl,
                    decoration: InputDecoration(
                      labelText: 'كلمة السر الجديدة',
                      prefixIcon: const Icon(Icons.lock_outline),
                      helperText: '10 أحرف على الأقل',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscure ? 'إظهار كلمة السر' : 'إخفاء كلمة السر',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  const SizedBox(height: AppSpacing.sm),
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
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: _loading ? null : (_otpSent ? _resetPassword : _sendOtp),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_otpSent ? 'تغيير كلمة السر' : 'إرسال رمز التحقق'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
