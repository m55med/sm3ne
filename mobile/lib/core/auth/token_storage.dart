import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bisawtak/core/services/app_group_bridge.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

class TokenStorage {
  // Secure storage is used for access/refresh tokens.
  // Android: encryptedSharedPreferences avoids the broken keystore fallback.
  // iOS: first_unlock_this_device keeps tokens accessible after first unlock
  // and prevents them from being restored to a different device via iCloud.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  // First-launch flag lives in SharedPreferences (NOT keychain) so it is
  // wiped on app uninstall — required to re-show onboarding after reinstall
  // on iOS, where keychain persists across uninstalls.
  static const _firstLaunchKey = 'first_launch';

  // --- access token ---
  Future<void> saveToken(String token) async {
    await _storage.write(key: _accessTokenKey, value: token);
    // Mirror into the iOS App Group so the Share Extension can authenticate a
    // server fallback without launching the app. No-op on Android.
    await AppGroupBridge.syncAuth(token);
  }

  Future<String?> getToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  Future<void> clearToken() async {
    await _storage.delete(key: _accessTokenKey);
    await AppGroupBridge.clearAuth();
  }

  // --- refresh token ---
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> clearRefreshToken() async {
    await _storage.delete(key: _refreshTokenKey);
  }

  /// Convenience: wipe both tokens. Used on logout / hard 401.
  Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
    // Also wipe the App Group mirror so a signed-out device can't transcribe
    // from the Share Extension as the previous user.
    await AppGroupBridge.clearAuth();
  }

  // --- first-launch (SharedPreferences) ---
  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_firstLaunchKey) ?? false);
  }

  Future<void> setFirstLaunchDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstLaunchKey, true);
  }

  /// Alias kept for the spec's preferred name.
  Future<void> markFirstLaunchDone() => setFirstLaunchDone();
}
