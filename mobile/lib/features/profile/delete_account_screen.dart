import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';

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
      setState(() => _error = 'لازم توافق على الاتنين قبل التأكيد');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد نهائي'),
        content: const Text(
          'الإجراء ده نهائي ومش هينفع تتراجع عنه.\nهتفقد كل تسجيلاتك واشتراكاتك ورسايلك.\nمتأكد؟',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
              _error = 'تأكيد الهوية بـ Google مطلوب';
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
              _error = 'تأكيد الهوية بـ Apple مطلوب';
              _busy = false;
            });
            return;
          }
          body['apple_token'] = token;
          break;
        default:
          if (_passwordCtrl.text.isEmpty) {
            setState(() {
              _error = 'كلمة السر مطلوبة';
              _busy = false;
            });
            return;
          }
          body['password'] = _passwordCtrl.text;
      }

      await ref.read(apiClientProvider).dio.delete('/profile', data: body);

      // Locally clear everything and bounce to login
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الحساب نهائياً')),
      );
      context.go('/login');
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail']?.toString() ?? 'فشل الحذف';
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<String?> _freshGoogleToken() async {
    try {
      final account = await GoogleSignIn(scopes: const ['email']).signIn();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('حذف الحساب'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تحذير', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(
                        'حذف الحساب إجراء نهائي. كل تسجيلاتك، رسائلك، اشتراكاتك والبيانات بتاعتك هتتحذف نهائياً ومش هنقدر نسترجعها بعدها.',
                        style: TextStyle(color: Colors.red.shade900, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text('تأكيد الهوية', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'لحمايتك، لازم نتأكد إنك أنت صاحب الحساب فعلاً.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 16),

          if (provider == 'local') ...[
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة السر الحالية',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    provider == 'google' ? Icons.account_circle : Icons.apple,
                    color: Colors.grey.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      provider == 'google'
                          ? 'لما تضغط "احذف"، هنطلب منك تسجيل دخول بـ Google تاني للتأكيد'
                          : 'لما تضغط "احذف"، هنطلب منك تسجيل دخول بـ Apple تاني للتأكيد',
                      style: TextStyle(color: Colors.grey.shade800, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'سبب الحذف (اختياري)',
              alignLabelWithHint: true,
              prefixIcon: Padding(padding: EdgeInsets.only(bottom: 60), child: Icon(Icons.edit_note)),
            ),
          ),
          const SizedBox(height: 8),

          CheckboxListTile(
            value: _ackPermanent,
            onChanged: (v) => setState(() => _ackPermanent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('فاهم أن الحذف نهائي ومش بيتراجع عنه'),
          ),
          CheckboxListTile(
            value: _ackData,
            onChanged: (v) => setState(() => _ackData = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('فاهم أن كل بياناتي هتتحذف من السيرفر'),
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
            ),
          ],
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _busy ? null : _confirmAndDelete,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete_forever),
            label: Text(_busy ? 'جاري الحذف...' : 'احذف الحساب نهائياً'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => context.pop(),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
