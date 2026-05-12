import 'dart:convert';
import 'dart:io';
import 'dart:math';
// TODO Mobile-1: ensure `crypto: ^3.0.0` is declared in pubspec.yaml dependencies
// (it's transitive today but used directly here for Apple Sign-In nonce hashing).
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

class SocialAuthButtons extends ConsumerWidget {
  const SocialAuthButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('أو تابع عبر', style: TextStyle(color: Colors.grey.shade600)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _googleSignIn(context, ref),
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (Platform.isIOS) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _appleSignIn(context, ref),
                  icon: const Icon(Icons.apple, size: 24),
                  label: const Text('Apple'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _googleSignIn(BuildContext context, WidgetRef ref) async {
    try {
      // TODO Mobile-2: serverClientId must come from AppConstants (e.g. AppConstants.googleServerClientId)
      // so the backend can verify the audience of the ID token.
      final googleUser = await GoogleSignIn(scopes: ['email']).signIn();
      if (googleUser == null) return; // user cancelled
      final auth = await googleUser.authentication;
      if (auth.idToken != null) {
        await ref.read(authProvider.notifier).googleSignIn(auth.idToken!);
      } else {
        if (context.mounted) {
          _toast(context, 'تعذر الحصول على بيانات الحساب من Google');
        }
      }
    } catch (e) {
      if (context.mounted) _toast(context, friendlyErrorMessage(e));
    }
  }

  Future<void> _appleSignIn(BuildContext context, WidgetRef ref) async {
    try {
      // Generate a cryptographically-secure nonce and pass its SHA-256 hash
      // to Apple. The backend will verify by recomputing the hash from the
      // raw nonce we send alongside the identity token.
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256Hex(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: hashedNonce,
      );

      final identityToken = credential.identityToken;
      if (identityToken == null) {
        if (context.mounted) _toast(context, 'تعذر الحصول على بيانات الحساب من Apple');
        return;
      }

      // Forward the identity token AND the raw nonce. Backend recomputes
      // sha256(rawNonce) and compares with the `nonce` claim Apple put inside
      // the identity token — defeats replay attacks.
      await ref
          .read(authProvider.notifier)
          .appleSignIn(identityToken, nonce: rawNonce);
    } catch (e) {
      if (context.mounted) _toast(context, friendlyErrorMessage(e));
    }
  }

  /// Generates a 32-character random nonce using a cryptographically-secure
  /// source.
  String _generateNonce([int length = 32]) {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256Hex(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
}
