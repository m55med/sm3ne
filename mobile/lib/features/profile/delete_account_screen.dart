import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:bisawtak/config/constants.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/haptics.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _passwordCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _ackPermanent = false;
  bool _ackData = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDelete() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    if (!_ackPermanent || !_ackData) {
      setState(() => _error = 'يجب الموافقة على البندين قبل المتابعة.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      // This dialog represents the point of no return — block taps outside
      // so the user can't accidentally dismiss it.
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد نهائي'),
        content: const Text(
          'هذا الإجراء نهائي ولا يمكن التراجع عنه.\n'
          'ستفقد جميع تسجيلاتك واشتراكاتك ورسائلك.\n'
          'هل أنت متأكد؟',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('احذف الحساب'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        if (_reasonCtrl.text.trim().isNotEmpty) 'reason': _reasonCtrl.text.trim(),
      };

      switch (user.authProvider) {
        case 'google':
          final token = await _freshGoogleToken();
          if (token == null) {
            setState(() {
              _error = 'تأكيد الهوية عبر Google مطلوب لإتمام الحذف.';
              _busy = false;
            });
            return;
          }
          body['google_token'] = token;
          break;
        case 'apple':
          final token = await _freshAppleToken();
          if (token == null) {
            setState(() {
              _error = 'تأكيد الهوية عبر Apple مطلوب لإتمام الحذف.';
              _busy = false;
            });
            return;
          }
          body['apple_token'] = token;
          break;
        default:
          if (_passwordCtrl.text.isEmpty) {
            setState(() {
              _error = 'كلمة السر مطلوبة.';
              _busy = false;
            });
            return;
          }
          body['password'] = _passwordCtrl.text;
      }

      await ref.read(apiClientProvider).dio.delete('/profile', data: body);

      // Locally clear everything WITHOUT calling /auth/logout — the account
      // no longer exists, so /auth/logout would 401 and trip the global
      // auth-invalidation listener, which would then surface a misleading
      // "session expired" toast on the next login.
      await ref.read(authProvider.notifier).logoutLocalOnly();
      // Also clear any pending expired-session flag set by an earlier 401
      // racing with the delete request.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('expired_session_pending');
      } catch (_) {/* best effort */}
      Haptics.heavy();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الحساب نهائياً.')),
      );
      context.go('/login');
    } on DioException catch (e) {
      Haptics.error();
      setState(() {
        _error = friendlyErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      Haptics.error();
      setState(() {
        _error = friendlyErrorMessage(e);
        _busy = false;
      });
    }
  }

  Future<String?> _freshGoogleToken() async {
    try {
      final account = await GoogleSignIn(
        scopes: const ['email'],
        serverClientId: AppConstants.googleServerClientId,
      ).signIn();
      if (account == null) return null;
      final auth = await account.authentication;
      return auth.idToken;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _freshAppleToken() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
      );
      return credential.identityToken;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final provider = user?.authProvider ?? 'local';
    final scheme = Theme.of(context).colorScheme;
    final errorColor = scheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text('حذف الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: errorColor.withValues(alpha: 0.08),
              border: Border.all(color: errorColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: errorColor, size: 28),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تحذير',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: errorColor,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs + 2),
                      Text(
                        'حذف الحساب إجراء نهائي. ستُحذف جميع تسجيلاتك ورسائلك واشتراكاتك وبياناتك من خوادمنا، ولن يمكن استرجاعها لاحقاً.',
                        style: TextStyle(
                          color: scheme.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'تأكيد الهوية',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'لحمايتك نحتاج التأكد من أنك صاحب الحساب فعلاً.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (provider == 'local') ...[
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'كلمة السر الحالية',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md + 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              ),
              child: Row(
                children: [
                  Icon(
                    provider == 'google' ? Icons.account_circle : Icons.apple,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      provider == 'google'
                          ? 'عند الضغط على "احذف" سيُطلب منك تسجيل الدخول بـ Google مجدداً للتأكيد.'
                          : 'عند الضغط على "احذف" سيُطلب منك تسجيل الدخول بـ Apple مجدداً للتأكيد.',
                      style: TextStyle(color: scheme.onSurface, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'سبب الحذف (اختياري)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            value: _ackPermanent,
            onChanged: (v) => setState(() => _ackPermanent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('أُقرّ بأن الحذف نهائي ولا يمكن التراجع عنه.'),
          ),
          CheckboxListTile(
            value: _ackData,
            onChanged: (v) => setState(() => _ackData = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('أُقرّ بأن جميع بياناتي ستُحذف من الخوادم.'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.08),
                border: Border.all(color: errorColor.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(_error!, style: TextStyle(color: errorColor)),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: _busy ? null : _confirmAndDelete,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.delete_forever),
            label: Text(_busy ? 'جارٍ الحذف...' : 'احذف الحساب نهائياً'),
            style: FilledButton.styleFrom(
              backgroundColor: errorColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : () => context.pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
