import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bisawtak/config/constants.dart';
import 'package:bisawtak/core/auth/token_storage.dart';

/// Stream of auth-invalidation events. Anything that needs to react to a
/// global 401 (e.g. router redirect to /login) should `listen` here.
final authInvalidationProvider =
    StreamProvider<DateTime>((ref) => _authInvalidationController.stream);

/// Internal broadcast controller. Lives for the lifetime of the app.
final StreamController<DateTime> _authInvalidationController =
    StreamController<DateTime>.broadcast();

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref));

class ApiClient {
  late final Dio dio;
  final Ref _ref;

  /// Guards against multiple parallel refresh attempts.
  Completer<String?>? _refreshLock;

  ApiClient(this._ref) {
    dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _ref.read(tokenStorageProvider).getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // --- Network retry (max 1 retry on transient errors) ---
        final isTransient = error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout;
        final alreadyRetried =
            error.requestOptions.extra['__retried__'] == true;
        if (isTransient && !alreadyRetried) {
          try {
            error.requestOptions.extra['__retried__'] = true;
            final clone = await dio.fetch(error.requestOptions);
            return handler.resolve(clone);
          } catch (_) {
            // fall through with original error
          }
        }

        // --- 401 handling: attempt refresh, else logout signal ---
        if (error.response?.statusCode == 401) {
          final tokenStorage = _ref.read(tokenStorageProvider);
          final path = error.requestOptions.path;
          // 401s on auth endpoints (/auth/login, /auth/google, /auth/apple,
          // /auth/register) are CREDENTIAL errors — wrong password, bad
          // Google token, etc. — NOT expired sessions. Surfacing them as
          // "session expired" is misleading and was causing the stale flag
          // bug after a failed login attempt.
          final isAuthCall = path.startsWith('/auth/');
          // Avoid infinite recursion on the refresh endpoint itself.
          final isRefreshCall = path.contains('/auth/refresh');
          final refreshToken = await tokenStorage.getRefreshToken();

          if (!isAuthCall && refreshToken != null && !isRefreshCall) {
            final newToken = await _refreshAccessToken(refreshToken);
            if (newToken != null) {
              // Replay the original request with the new token.
              error.requestOptions.headers['Authorization'] =
                  'Bearer $newToken';
              try {
                final clone = await dio.fetch(error.requestOptions);
                return handler.resolve(clone);
              } catch (e) {
                // fall through to logout
              }
            }
          }

          if (!isAuthCall) {
            // Refresh failed (or no refresh token) on a protected request —
            // the existing session is dead. Clear and signal.
            await tokenStorage.clearAll();
            if (!_authInvalidationController.isClosed) {
              _authInvalidationController.add(DateTime.now());
            }
          }
        }
        handler.next(error);
      },
    ));
  }

  /// Performs a refresh-token exchange. Concurrent callers share the same
  /// in-flight refresh via [_refreshLock]. Returns the new access token, or
  /// null on failure.
  Future<String?> _refreshAccessToken(String refreshToken) async {
    if (_refreshLock != null) {
      return _refreshLock!.future;
    }
    final completer = Completer<String?>();
    _refreshLock = completer;
    try {
      // Use a bare Dio for the refresh call to avoid the auth interceptor
      // chasing its own tail.
      final bare = Dio(BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ));
      final resp = await bare.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final newAccess = resp.data is Map ? resp.data['access_token'] : null;
      final newRefresh = resp.data is Map ? resp.data['refresh_token'] : null;
      if (newAccess is String && newAccess.isNotEmpty) {
        final storage = _ref.read(tokenStorageProvider);
        await storage.saveToken(newAccess);
        if (newRefresh is String && newRefresh.isNotEmpty) {
          await storage.saveRefreshToken(newRefresh);
        }
        completer.complete(newAccess);
        return newAccess;
      }
      completer.complete(null);
      return null;
    } catch (_) {
      completer.complete(null);
      return null;
    } finally {
      _refreshLock = null;
    }
  }
}
