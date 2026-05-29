import 'dart:io';

import 'package:flutter/services.dart';

import 'package:bisawtak/config/constants.dart';
import 'package:bisawtak/shared/utils/remote_logger.dart';

/// Mirrors a small, non-secret slice of app state into the iOS **App Group**
/// shared container so the Share Extension can transcribe a shared voice note
/// *without launching the full app*.
///
/// The Share Extension runs in its own process and cannot read the app's
/// keychain or Riverpod state. To let it fall back to the server pipeline
/// (`/transcribe`) when on-device Apple Speech can't handle a file, it needs:
///   - the access token (so the upload authenticates as the user), and
///   - the API base URL (so a flavour/staging build hits the right host).
///
/// We deliberately keep this iOS-only and best-effort: every method no-ops on
/// non-iOS and swallows channel errors. The access token is short-lived and
/// the App Group container is sandboxed to our own signed apps, which is the
/// standard pattern for handing an auth token to an extension. The token is
/// cleared on logout so a signed-out device leaves nothing behind.
class AppGroupBridge {
  static const _channel = MethodChannel('com.bisawtak/appgroup');

  static const _kAccessToken = 'access_token';
  static const _kApiBaseUrl = 'api_base_url';

  /// Pushes the current access token + API base URL into the App Group.
  /// Call after every token save/refresh.
  static Future<void> syncAuth(String? accessToken) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('setValues', {
        _kAccessToken: accessToken ?? '',
        _kApiBaseUrl: AppConstants.apiBaseUrl,
      });
    } catch (e) {
      RemoteLogger.log('appgroup', 'syncAuth failed: $e');
    }
  }

  /// Wipes the shared auth slice. Call on logout / account deletion so the
  /// Share Extension can no longer authenticate as the (now signed-out) user.
  static Future<void> clearAuth() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('clearValues');
    } catch (e) {
      RemoteLogger.log('appgroup', 'clearAuth failed: $e');
    }
  }

  /// Drains (returns + clears) the queue of on-device transcriptions the Share
  /// Extension produced while the app was closed. Each entry mirrors the
  /// `/transcriptions/log` payload. Returns an empty list on non-iOS or error.
  static Future<List<Map<String, dynamic>>> drainPendingClientLogs() async {
    if (!Platform.isIOS) return const [];
    try {
      final raw = await _channel.invokeMethod('drainPendingClientLogs');
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (e) {
      RemoteLogger.log('appgroup', 'drain failed: $e');
      return const [];
    }
  }
}
