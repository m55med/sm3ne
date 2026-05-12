import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/features/auth/widgets/social_auth_buttons.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    final username = _usernameCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).login(username, password);
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
    final auth = ref.watch(authProvider);
    final isBusy = _loading || auth.status == AuthStatus.loading;

    ref.listen<AuthState>(authProvider, (_, state) {
      if (state.status == AuthStatus.authenticated) {
        context.go('/home');
      }
      final err = state.error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(err)),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                Icon(Icons.mic, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'بصوتك',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'تسجيل الدخول',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  autofillHints: const [AutofillHints.username],
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'كلمة السر',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
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
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: isBusy ? null : _login,
                  child: isBusy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('تسجيل الدخول'),
                ),
                const SizedBox(height: 24),
                const SocialAuthButtons(),
                const SizedBox(height: 24),
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
