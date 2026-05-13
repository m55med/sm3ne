import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/features/auth/widgets/social_auth_buttons.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordConfirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_]{3,30}$');
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    // Guard against double submission. `auth.status == loading` is also
    // checked at the button level so the UX is consistent.
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final username = _usernameCtrl.text.trim().toLowerCase();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final fullName = _nameCtrl.text.trim();

    setState(() => _loading = true);
    // Errors are surfaced through `ref.listen(authProvider, ...)` in build()
    // — duplicating in a try/catch produces two snackbars.
    await ref.read(authProvider.notifier).register(
          username,
          email,
          password,
          fullName.isNotEmpty ? fullName : null,
        );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isBusy = _loading || auth.status == AuthStatus.loading;

    final scheme = Theme.of(context).colorScheme;
    ref.listen<AuthState>(authProvider, (_, state) {
      if (state.status == AuthStatus.authenticated) {
        context.go('/survey');
      }
      final err = state.error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(err)),
            backgroundColor: scheme.error,
          ),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xxxl - AppSpacing.sm),
                  Text(
                    'إنشاء حساب',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'أنشئ حسابك وابدأ تحويل الصوت إلى نص',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'الاسم الكامل', prefixIcon: Icon(Icons.badge_outlined)),
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم *',
                      prefixIcon: Icon(Icons.person_outline),
                      helperText: 'حروف إنجليزية وأرقام و _ فقط (3-30 حرف)',
                    ),
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    autofillHints: const [AutofillHints.newUsername],
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'اسم المستخدم مطلوب';
                      if (!_usernameRegex.hasMatch(value)) {
                        return 'اسم المستخدم يجب أن يحتوي على حروف وأرقام فقط';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return null; // email is optional
                      if (!_emailRegex.hasMatch(value)) return 'بريد إلكتروني غير صحيح';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'كلمة السر *',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscure ? 'إظهار كلمة السر' : 'إخفاء كلمة السر',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      helperText: '10 أحرف على الأقل',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final value = v ?? '';
                      if (value.isEmpty) return 'كلمة السر مطلوبة';
                      if (value.length < 10) return 'كلمة السر يجب أن تكون 10 أحرف على الأقل';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordConfirmCtrl,
                    obscureText: _obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة السر *',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscureConfirm ? 'إظهار كلمة السر' : 'إخفاء كلمة السر',
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _register(),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'يرجى تأكيد كلمة السر';
                      if (v != _passwordCtrl.text) return 'كلمتا السر غير متطابقتين';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(
                    onPressed: isBusy ? null : _register,
                    child: isBusy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('إنشاء حساب'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SocialAuthButtons(),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('لديك حساب بالفعل؟'),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('تسجيل الدخول'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
