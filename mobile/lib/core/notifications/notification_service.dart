import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bisawtak/core/api/api_client.dart';

/// Permission + token lifecycle for push notifications.
///
/// Two-stage flow:
///   1. After login/register the auth provider calls [registerIfAuthenticated]
///      which prompts for notification permission and (on grant) registers
///      the device's FCM token with the backend.
///   2. On token rotation we re-register automatically via the
///      `onTokenRefresh` stream.
///
/// The class is intentionally idempotent + best-effort: failures are logged
/// but never thrown to the UI — notifications are an enhancement, not a
/// requirement to use the app.
class NotificationService {
  NotificationService(this._ref);

  final Ref _ref;
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// Local cache key — saved so logout knows which token to deregister.
  static const _kLastTokenKey = 'last_fcm_token';

  /// Called from auth flow once we have a fresh access token. Safe to call
  /// repeatedly; subsequent calls just refresh `last_seen_at` server-side.
  Future<void> registerIfAuthenticated() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;

      if (Platform.isIOS) {
        // On iOS we need the APNS token to be ready before FCM hands us a
        // usable registration token. Waiting briefly is cheap and avoids a
        // null on first launch.
        for (var i = 0; i < 5; i++) {
          final apns = await _messaging.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      final token = await _messaging.getToken();
      if (token == null) return;

      // Remember the latest token so logout can deregister it.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kLastTokenKey, token);
      } catch (_) {/* non-fatal */}

      await _postRegistration(token: token, pushEnabled: granted);

      // One-shot listener that re-registers on token rotation.
      _messaging.onTokenRefresh.listen((newToken) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kLastTokenKey, newToken);
        } catch (_) {/* non-fatal */}
        await _postRegistration(token: newToken, pushEnabled: granted);
      });
    } catch (_) {
      // Best-effort: don't disrupt sign-in UX on Firebase init errors.
    }
  }

  Future<void> _postRegistration({
    required String token,
    required bool pushEnabled,
  }) async {
    final info = await _collectDeviceInfo();
    try {
      await _ref.read(apiClientProvider).dio.post(
            '/devices/register',
            data: {
              'fcm_token': token,
              'platform': Platform.isIOS ? 'ios' : 'android',
              'push_enabled': pushEnabled,
              ...info,
            },
          );
    } on DioException {
      // Server may be down or token may be unauthenticated — both recover
      // on the next call.
    }
  }

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    final pkg = await PackageInfo.fromPlatform();
    final appVersion = '${pkg.version}+${pkg.buildNumber}';
    final out = <String, dynamic>{'app_version': appVersion};

    try {
      if (Platform.isIOS) {
        final ios = await plugin.iosInfo;
        out.addAll({
          'device_model': ios.utsname.machine,           // e.g. iPhone15,3
          'device_marketing_name': ios.name,             // "Mohamed's iPhone"
          'device_os': ios.systemName,                   // iOS
          'device_os_version': ios.systemVersion,        // 17.4.1
          'device_locale': Platform.localeName.replaceAll('_', '-'),
        });
      } else if (Platform.isAndroid) {
        final android = await plugin.androidInfo;
        out.addAll({
          'device_model': android.model,                 // SM-S928B
          'device_marketing_name': '${android.brand} ${android.model}',
          'device_os': 'Android',
          'device_os_version': android.version.release,  // 14
          'device_locale': Platform.localeName.replaceAll('_', '-'),
        });
      }
    } catch (_) {/* device-info best effort */}

    return out;
  }

  /// Called from logout. Deregisters the cached token server-side so it
  /// stops receiving pushes; tolerates 401 / no-token cases.
  Future<void> deregister() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kLastTokenKey);
      if (token == null) return;
      await _ref.read(apiClientProvider).dio.delete(
            '/devices/me',
            queryParameters: {'fcm_token': token},
          );
      await prefs.remove(_kLastTokenKey);
    } catch (_) {/* best effort */}
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref);
});
