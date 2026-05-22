import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/analytics/analytics_service.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/features/auth/widgets/social_auth_buttons.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

/// SharedPreferences flag set by routes.dart when an auth invalidation
/// fires. The login screen reads + clears it on first build so the user
/// understands why they were bounced back here.
const kExpiredSessionFlag = 'expired_session_pending';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // If the user landed here because the session expired, surface that
    // reason once. The flag is set by routes.dart on auth invalidation.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeExpiredFlag());
  }

  Future<void> _consumeExpiredFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(kExpiredSessionFlag) ?? false)) return;
    await prefs.remove(kExpiredSessionFlag);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('انتهت جلستك. الرجاء تسجيل الدخول من جديد.'),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _loading = true);
    // Errors are surfaced through `ref.listen(authProvider, ...)` in build()
    // — do not also catch here, that yields a double snackbar.
    await ref.read(authProvider.notifier).login(email, password);
    if (ref.read(authProvider).status == AuthStatus.authenticated) {
      await ref.read(analyticsProvider).login('password');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isBusy = _loading || auth.status == AuthStatus.loading;

    final scheme = Theme.of(context).colorScheme;

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state.status == AuthStatus.authenticated) {
        // Brand-new accounts (including first-time Google/Apple sign-ups
        // that came in via THIS screen) haven't filled the onboarding
        // survey yet — route them through it so we capture their reason
        // for using the app. Returning users with a saved response (even
        // an empty "skipped" marker) go straight to /home.
        final destination = (state.user?.surveyResponse == null) ? '/survey' : '/home';
        context.go(destination);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxxl + AppSpacing.md),
                Icon(Icons.mic, size: 64, color: scheme.primary),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'بصوتك',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'تسجيل الدخول',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxxl),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  autofillHints: const [AutofillHints.email],
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'كلمة السر',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      tooltip: _obscurePassword ? 'إظهار كلمة السر' : 'إخفاء كلمة السر',
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _login(),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    child: const Text('نسيت كلمة السر؟'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ElevatedButton(
                  onPressed: isBusy ? null : _login,
                  child: isBusy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('تسجيل الدخول'),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SocialAuthButtons(),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('ليس لديك حساب؟'),
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text('إنشاء حساب'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
