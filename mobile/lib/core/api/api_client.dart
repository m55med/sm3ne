import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/config/constants.dart';
import 'package:bisawtak/core/auth/token_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref));

class ApiClient {
  late final Dio dio;
  final Ref _ref;

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
        if (error.response?.statusCode == 401) {
          await _ref.read(tokenStorageProvider).clearToken();
        }
        handler.next(error);
      },
    ));
  }
}
