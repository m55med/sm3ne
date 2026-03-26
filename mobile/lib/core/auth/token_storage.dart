import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

class TokenStorage {
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'access_token';
  static const _firstLaunchKey = 'first_launch';

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> isFirstLaunch() async {
    final val = await _storage.read(key: _firstLaunchKey);
    return val == null;
  }

  Future<void> setFirstLaunchDone() async {
    await _storage.write(key: _firstLaunchKey, value: 'done');
  }
}
