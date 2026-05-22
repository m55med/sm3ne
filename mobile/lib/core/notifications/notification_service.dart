import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/shared/utils/remote_logger.dart';

/// Permission + token lifecycle for push notifications, plus a local
/// fallback that displays foreground FCM messages as system notifications
/// (firebase_messaging by itself only auto-displays when the app is
/// backgrounded — foreground messages go silently to onMessage).
///
/// Two-stage flow:
///   1. [registerIfAuthenticated] (called from auth provider on every
///      successful auth) requests permission and registers the FCM token
///      with the backend.
///   2. The constructor wires the foreground handler so any FCM payload
///      arriving while the app is open shows as a banner / appears in the
///      notification tray.
class NotificationService {
  NotificationService(this._ref) {
    _wireForegroundHandler();
  }

  final Ref _ref;
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _localInitDone = false;

  /// Channel id MUST match the one declared in AndroidManifest.xml as
  /// `default_notification_channel_id` — otherwise Android 8+ silently
  /// drops the notification with no log line.
  static const _kChannelId = 'bisawtak_default';
  static const _kChannelName = 'Bisawtak notifications';

  /// Local cache key — saved so logout knows which token to deregister.
  static const _kLastTokenKey = 'last_fcm_token';

  void _wireForegroundHandler() {
    FirebaseMessaging.onMessage.listen((message) async {
      RemoteLogger.log(
        'fcm_fg',
        'received id=${message.messageId ?? "-"} hasNotif=${message.notification != null}',
      );
      // Foreground delivery: we need to call into the OS notification
      // service ourselves to show a banner.
      await _ensureLocalReady();
      final n = message.notification;
      if (n == null) return;
      await _local.show(
        message.hashCode,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannelId,
            _kChannelName,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data['deep_link'] as String?,
      );
    });
  }

  Future<void> _ensureLocalReady() async {
    if (_localInitDone) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    // Android 8+ requires the channel to exist before the first .show().
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _kChannelId,
            _kChannelName,
            description: 'إشعارات Bisawtak',
            importance: Importance.high,
          ),
        );
    _localInitDone = true;
  }

  /// Called from auth flow once we have a fresh access token. Safe to call
  /// repeatedly; subsequent calls just refresh `last_seen_at` server-side.
  Future<void> registerIfAuthenticated() async {
    RemoteLogger.log(
      'fcm_reg',
      'start platform=${Platform.operatingSystem}',
    );
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      RemoteLogger.log(
        'fcm_reg',
        'perm=${settings.authorizationStatus.name} granted=$granted',
      );

      if (Platform.isIOS) {
        // On iOS we need the APNS token to be ready before FCM hands us a
        // usable registration token. Polls every 500ms for up to 10s.
        String? apns;
        for (var i = 0; i < 20; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        RemoteLogger.log(
          'fcm_reg',
          'apns_token ${apns == null ? "NULL_after_10s" : "ok len=${apns.length}"}',
        );
        if (apns == null) {
          // No APNs token = FCM will return null too. Bail early with a
          // clear log line so we know why iOS never made it to /register.
          return;
        }
      }

      final token = await _messaging.getToken();
      RemoteLogger.log(
        'fcm_reg',
        'fcm_token ${token == null ? "NULL" : "ok len=${token.length}"}',
      );
      if (token == null) return;

      // Remember the latest token so logout can deregister it.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kLastTokenKey, token);
      } catch (_) {/* non-fatal */}

      await _postRegistration(token: token, pushEnabled: granted);

      // One-shot listener that re-registers on token rotation.
      _messaging.onTokenRefresh.listen((newToken) async {
        RemoteLogger.log('fcm_reg', 'token_rotated len=${newToken.length}');
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kLastTokenKey, newToken);
        } catch (_) {/* non-fatal */}
        await _postRegistration(token: newToken, pushEnabled: granted);
      });
    } catch (e, st) {
      // Snapshot enough of the stack to debug without spamming.
      final preview = st.toString();
      RemoteLogger.log(
        'fcm_reg',
        'unknown_error type=${e.runtimeType} msg=$e stack=${preview.substring(0, preview.length > 200 ? 200 : preview.length)}',
      );
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
      RemoteLogger.log('fcm_reg', 'post_register_ok');
    } on DioException catch (e) {
      RemoteLogger.log(
        'fcm_reg',
        'post_register_dio status=${e.response?.statusCode ?? "-"} msg=${e.message}',
      );
    } catch (e) {
      RemoteLogger.log('fcm_reg', 'post_register_err msg=$e');
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
