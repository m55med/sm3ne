import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/auth/token_storage.dart';
import 'package:bisawtak/data/models/user.dart';

enum AuthStatus { initial, authenticated, unauthenticated, loading }

class AuthState {
  final AuthStatus status;
  final User? user;
  final String? error;

  const AuthState({this.status = AuthStatus.initial, this.user, this.error});

  AuthState copyWith({AuthStatus? status, User? user, String? error}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  final TokenStorage _tokenStorage;

  AuthNotifier(this._api, this._tokenStorage) : super(const AuthState());

  Future<void> checkAuth() async {
    final token = await _tokenStorage.getToken();
    if (token == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final resp = await _api.dio.get('/profile');
      final user = User.fromJson(resp.data);
      state = state.copyWith(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      await _tokenStorage.clearToken();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final resp = await _api.dio.post('/auth/login', data: {
        'username': username,
        'password': password,
      });
      await _tokenStorage.saveToken(resp.data['access_token']);
      await checkAuth();
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.response?.data?['detail'] ?? 'Login failed',
      );
    }
  }

  Future<void> register(String username, String email, String password, String? fullName) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final resp = await _api.dio.post('/auth/register', data: {
        'username': username,
        'email': email,
        'password': password,
        if (fullName != null) 'full_name': fullName,
      });
      await _tokenStorage.saveToken(resp.data['access_token']);
      await checkAuth();
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.response?.data?['detail'] ?? 'Registration failed',
      );
    }
  }

  Future<void> googleSignIn(String idToken) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final resp = await _api.dio.post('/auth/google', data: {'token': idToken});
      await _tokenStorage.saveToken(resp.data['access_token']);
      await checkAuth();
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.response?.data?['detail'] ?? 'Google sign-in failed',
      );
    }
  }

  Future<void> appleSignIn(String identityToken) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final resp = await _api.dio.post('/auth/apple', data: {'token': identityToken});
      await _tokenStorage.saveToken(resp.data['access_token']);
      await checkAuth();
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.response?.data?['detail'] ?? 'Apple sign-in failed',
      );
    }
  }

  Future<void> logout() async {
    await _tokenStorage.clearToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(apiClientProvider),
    ref.read(tokenStorageProvider),
  );
});
