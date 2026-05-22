import 'dart:convert';
import 'dart:io';
import 'dart:math';
// TODO Mobile-1: ensure `crypto: ^3.0.0` is declared in pubspec.yaml dependencies
// (it's transitive today but used directly here for Apple Sign-In nonce hashing).
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:bisawtak/config/constants.dart';
import 'package:bisawtak/config/design_tokens.dart';
import 'package:bisawtak/core/analytics/analytics_service.dart';
import 'package:bisawtak/core/auth/auth_provider.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/remote_logger.dart';

class SocialAuthButtons extends ConsumerWidget {
  const SocialAuthButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'أو تابع عبر',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _googleSignIn(context, ref),
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ),
            if (Platform.isIOS) ...[
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _appleSignIn(context, ref),
                  icon: const Icon(Icons.apple, size: 24),
                  label: const Text('Apple'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
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
    // TEMP diagnostic — remove once Android Google Sign-In is confirmed working.
    // Logs every step of the sign-in flow to the backend /diag/log endpoint so
    // we can SEE on the server what's failing on real devices.
    final serverClientId = AppConstants.googleServerClientId;
    RemoteLogger.log(
      'google_signin',
      'start platform=${Platform.operatingSystem} serverClientId=${serverClientId.substring(0, 24)}...',
    );
    try {
      // serverClientId = the WEB OAuth client. It makes the returned idToken's
      // `aud` claim equal the backend's GOOGLE_CLIENT_ID so verification passes.
      final googleUser = await GoogleSignIn(
        scopes: const ['email'],
        serverClientId: serverClientId,
      ).signIn();
      if (googleUser == null) {
        RemoteLogger.log('google_signin', 'user_cancelled');
        // User dismissed the system sheet. Show a neutral confirmation
        // instead of staying silent — silence reads as "the app froze".
        if (context.mounted) _info(context, 'تم إلغاء تسجيل الدخول');
        return;
      }
      RemoteLogger.log(
        'google_signin',
        'user_obtained email=${_redactEmail(googleUser.email)}',
      );
      final auth = await googleUser.authentication;
      if (auth.idToken != null) {
        RemoteLogger.log(
          'google_signin',
          'idtoken_obtained len=${auth.idToken!.length}',
        );
        await ref.read(authProvider.notifier).googleSignIn(auth.idToken!);
        RemoteLogger.log('google_signin', 'backend_call_ok');
        if (ref.read(authProvider).status == AuthStatus.authenticated) {
          await ref.read(analyticsProvider).login('google');
        }
      } else {
        RemoteLogger.log('google_signin', 'idtoken_null');
        if (context.mounted) {
          _error(context, 'تعذر الحصول على بيانات الحساب من Google');
        }
      }
    } on PlatformException catch (e) {
      RemoteLogger.log(
        'google_signin',
        'PlatformException code=${e.code} msg=${e.message ?? "-"} details=${e.details ?? "-"}',
      );
      if (context.mounted) _error(context, friendlyErrorMessage(e));
    } catch (e, st) {
      RemoteLogger.log(
        'google_signin',
        'unknown_error type=${e.runtimeType} msg=${e.toString()} stack=${st.toString().substring(0, st.toString().length > 200 ? 200 : st.toString().length)}',
      );
      if (context.mounted) _error(context, friendlyErrorMessage(e));
    }
  }

  /// Keeps the email prefix's first 2 chars + domain so we can confirm an
  /// account was returned without dumping a full PII string into logs.
  String _redactEmail(String email) {
    final at = email.indexOf('@');
    if (at < 0) return '***';
    final prefix = email.substring(0, at);
    final domain = email.substring(at);
    final shown = prefix.length <= 2 ? prefix : prefix.substring(0, 2);
    return '$shown***$domain';
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
        if (context.mounted) _error(context, 'تعذر الحصول على بيانات الحساب من Apple');
        return;
      }

      // Forward the identity token AND the raw nonce. Backend recomputes
      // sha256(rawNonce) and compares with the `nonce` claim Apple put inside
      // the identity token — defeats replay attacks.
      //
      // Also forward Apple's one-time `authorizationCode` — the backend
      // exchanges it server-side for a refresh_token used at account-deletion
      // time to call /auth/revoke (so Apple forgets this user too).
      await ref.read(authProvider.notifier).appleSignIn(
            identityToken,
            nonce: rawNonce,
            authorizationCode: credential.authorizationCode,
          );
      if (ref.read(authProvider).status == AuthStatus.authenticated) {
        await ref.read(analyticsProvider).login('apple');
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      // The Apple SDK throws a typed exception on cancel/cancelled. Surface
      // a neutral message rather than the technical error.
      if (e.code == AuthorizationErrorCode.canceled) {
        if (context.mounted) _info(context, 'تم إلغاء تسجيل الدخول');
        return;
      }
      if (context.mounted) _error(context, friendlyErrorMessage(e));
    } catch (e) {
      if (context.mounted) _error(context, friendlyErrorMessage(e));
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

  void _error(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _info(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
