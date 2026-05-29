import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/auth/token_storage.dart';
import 'package:bisawtak/core/notifications/notification_service.dart';
import 'package:bisawtak/data/local/transcription_dao.dart';
import 'package:bisawtak/data/models/user.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';

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
  final TranscriptionDao _transcriptionDao;
  // Used to reach the NotificationService for push-token registration on
  // login + deregistration on logout. Passed via the provider below.
  final Ref _ref;

  AuthNotifier(this._ref, this._api, this._tokenStorage, {TranscriptionDao? dao})
      : _transcriptionDao = dao ?? TranscriptionDao(),
        super(const AuthState());

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
      // Fire-and-forget: ask for push permission + register this device's
      // FCM token with the server. Idempotent, safe on every auth check.
      unawaited(_ref.read(notificationServiceProvider).registerIfAuthenticated());
      // Fire-and-forget: rebuild "تسجيلاتي" from the server's request history.
      // This is what brings back the user's request/event history after a
      // delete-and-reinstall (the audio/text are never on the server, but the
      // metadata is). Best-effort — never blocks the auth check. On success we
      // bump historySyncSignalProvider so an open list screen refreshes.
      unawaited(_syncHistory());
    } catch (_) {
      await _tokenStorage.clearAll();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  /// Best-effort history rebuild from the server. First flushes any on-device
  /// transcriptions the iOS Share Extension queued while the app was closed
  /// (so they get a real server request id), then pulls the full request
  /// history and inserts only rows the device is missing. On any insert it
  /// pulses [historySyncSignalProvider] so a mounted transcription list
  /// refreshes itself.
  Future<void> _syncHistory() async {
    try {
      final repo = _ref.read(transcriptionRepoProvider);
      // Flush first so freshly logged share-extension rows are part of the
      // history we then pull back down (and dedup against locally).
      final flushed = await repo.flushPendingShareLogs();
      final inserted = await repo.syncHistoryFromServer();
      if (flushed > 0 || inserted > 0) {
        _ref.read(historySyncSignalProvider.notifier).state++;
      }
    } catch (_) {
      // Both calls already swallow + log; defensive guard only.
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final resp = await _api.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      await _persistTokensFrom(resp.data);
      await checkAuth();
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.response?.data?['detail'] ?? 'Login failed',
      );
    }
  }

  Future<void> register(String email, String password, String? fullName) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final resp = await _api.dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        if (fullName != null) 'full_name': fullName,
      });
      await _persistTokensFrom(resp.data);
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
      await _persistTokensFrom(resp.data);
      await checkAuth();
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.response?.data?['detail'] ?? 'Google sign-in failed',
      );
    }
  }

  Future<void> appleSignIn(
    String identityToken, {
    String? nonce,
    String? authorizationCode,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final payload = <String, dynamic>{'token': identityToken};
      // Raw nonce that hashed to the value baked into the identity token.
      // Backend verifies sha256(nonce) == payload.nonce to defeat replay attacks.
      if (nonce != null) payload['nonce'] = nonce;
      // Apple's single-use authorization code, exchanged server-side for a
      // refresh_token (stored to enable /auth/revoke at delete time).
      if (authorizationCode != null && authorizationCode.isNotEmpty) {
        payload['authorization_code'] = authorizationCode;
      }
      final resp = await _api.dio.post('/auth/apple', data: payload);
      await _persistTokensFrom(resp.data);
      await checkAuth();
    } on DioException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.response?.data?['detail'] ?? 'Apple sign-in failed',
      );
    }
  }

  /// Logs out the current user.
  ///
  /// 1. Best-effort POST to `/auth/logout` (ignored on failure).
  /// 2. Wipes access + refresh tokens.
  /// 3. Clears the local cached transcriptions so the next user doesn't see them.
  /// 4. Marks state as unauthenticated.
  Future<void> logout() async {
    // Deregister the FCM token first while we're still authenticated —
    // running it after _clearLocalAuthState would have no token to attach.
    try {
      await _ref.read(notificationServiceProvider).deregister();
    } catch (_) {/* best effort */}
    try {
      await _api.dio.post('/auth/logout');
    } catch (_) {
      // Best-effort; logout proceeds even if the server call fails.
    }
    await _clearLocalAuthState();
  }

  /// Clears local auth state WITHOUT calling `/auth/logout`. Used by the
  /// account-deletion flow: after a successful DELETE /profile the account
  /// no longer exists, so calling /auth/logout would 401 — and that 401
  /// trips the api_client's auth-invalidation stream which mis-attributes
  /// the deletion as an "expired session" and shows the wrong message on
  /// the next login. Calling THIS method instead avoids that side-effect.
  Future<void> logoutLocalOnly() async {
    await _clearLocalAuthState();
  }

  Future<void> _clearLocalAuthState() async {
    await _tokenStorage.clearAll();
    try {
      await _transcriptionDao.deleteAll();
    } catch (_) {
      // Don't block teardown on DB failure.
    }
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _persistTokensFrom(dynamic data) async {
    if (data is! Map) return;
    final access = data['access_token'];
    if (access is String && access.isNotEmpty) {
      await _tokenStorage.saveToken(access);
    }
    final refresh = data['refresh_token'];
    if (refresh is String && refresh.isNotEmpty) {
      await _tokenStorage.saveRefreshToken(refresh);
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(
    ref,
    ref.read(apiClientProvider),
    ref.read(tokenStorageProvider),
  );

  // React to global 401 invalidation signals from the API client.
  ref.listen(authInvalidationProvider, (_, __) {
    notifier.logout();
  });

  return notifier;
});
