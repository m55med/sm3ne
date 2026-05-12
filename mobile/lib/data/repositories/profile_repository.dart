import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/data/models/user.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.read(apiClientProvider));
});

class ProfileException implements Exception {
  final String message;
  final int? statusCode;
  const ProfileException(this.message, {this.statusCode});

  @override
  String toString() => 'ProfileException($statusCode): $message';
}

class ProfileRepository {
  final ApiClient _api;
  ProfileRepository(this._api);

  Dio get _dio => _api.dio;

  Future<User> me() async {
    try {
      final resp = await _dio.get('/profile');
      return User.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw ProfileException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<User> update({String? fullName, String? email}) async {
    try {
      final resp = await _dio.patch('/profile', data: {
        if (fullName != null) 'full_name': fullName,
        if (email != null) 'email': email,
      });
      return User.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw ProfileException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post('/profile/change-password', data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
    } catch (e) {
      throw ProfileException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<void> deleteAccount({String? confirmation}) async {
    try {
      await _dio.delete('/profile', data: {
        if (confirmation != null) 'confirmation': confirmation,
      });
    } catch (e) {
      throw ProfileException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<void> submitSurvey(String response) async {
    try {
      await _dio.post('/profile/survey', data: {'response': response});
    } catch (e) {
      throw ProfileException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }
}
