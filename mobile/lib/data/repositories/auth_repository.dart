import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/data/models/user.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(apiClientProvider));
});

/// Typed exception with an Arabic message for auth flow failures.
class AuthException implements Exception {
  final String message;
  final int? statusCode;
  const AuthException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthException($statusCode): $message';
}

class AuthTokens {
  final String accessToken;
  final String? refreshToken;
  const AuthTokens({required this.accessToken, this.refreshToken});

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
    );
  }
}

class AuthRepository {
  final ApiClient _api;

  AuthRepository(this._api);

  Dio get _dio => _api.dio;

  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    try {
      final resp = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      return AuthTokens.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw AuthException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<AuthTokens> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final resp = await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        if (fullName != null) 'full_name': fullName,
      });
      return AuthTokens.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw AuthException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<AuthTokens> google(String idToken) async {
    try {
      final resp = await _dio.post('/auth/google', data: {'token': idToken});
      return AuthTokens.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw AuthException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<AuthTokens> apple(String identityToken) async {
    try {
      final resp = await _dio.post('/auth/apple', data: {'token': identityToken});
      return AuthTokens.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw AuthException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await _dio.post('/auth/forgot-password', data: {'email': email});
    } catch (e) {
      throw AuthException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _dio.post('/auth/reset-password', data: {
        'token': token,
        'new_password': newPassword,
      });
    } catch (e) {
      throw AuthException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    try {
      final resp = await _dio.post('/auth/refresh', data: {
        'refresh_token': refreshToken,
      });
      return AuthTokens.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw AuthException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  /// Best-effort server logout. Caller should ignore failures.
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {
      // Intentionally swallowed — logout must always succeed locally.
    }
  }

  Future<User> me() async {
    try {
      final resp = await _dio.get('/profile');
      return User.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw AuthException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }
}
