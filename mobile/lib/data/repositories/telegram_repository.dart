import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

final telegramRepositoryProvider = Provider<TelegramRepository>((ref) {
  return TelegramRepository(ref.read(apiClientProvider));
});

class TelegramException implements Exception {
  final String message;
  final int? statusCode;
  // Stable codes from the backend (`telegram_disabled`, `link_error`, etc.).
  final String? code;
  const TelegramException(this.message, {this.statusCode, this.code});

  bool get isDisabled => statusCode == 503;

  @override
  String toString() => 'TelegramException($statusCode/$code): $message';
}

/// One-time code shown to the user. ``deepLink`` opens Telegram with the
/// bot + code as the /start payload — preferred over manual copy/paste.
class TelegramLinkStart {
  final String code;
  final DateTime expiresAt;
  final String? botUsername;
  final String? deepLink;

  const TelegramLinkStart({
    required this.code,
    required this.expiresAt,
    this.botUsername,
    this.deepLink,
  });

  factory TelegramLinkStart.fromJson(Map<String, dynamic> json) {
    return TelegramLinkStart(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      botUsername: json['bot_username'] as String?,
      deepLink: json['deep_link'] as String?,
    );
  }
}

class TelegramStatus {
  final bool enabled;
  final bool linked;
  final int? telegramId;
  final String? telegramUsername;
  final String? telegramFirstName;
  final DateTime? linkedAt;
  final String? botUsername;

  const TelegramStatus({
    required this.enabled,
    required this.linked,
    this.telegramId,
    this.telegramUsername,
    this.telegramFirstName,
    this.linkedAt,
    this.botUsername,
  });

  factory TelegramStatus.fromJson(Map<String, dynamic> json) {
    final linkedAtRaw = json['linked_at'] as String?;
    return TelegramStatus(
      enabled: (json['enabled'] as bool?) ?? false,
      linked: (json['linked'] as bool?) ?? false,
      telegramId: (json['telegram_id'] as num?)?.toInt(),
      telegramUsername: json['telegram_username'] as String?,
      telegramFirstName: json['telegram_first_name'] as String?,
      linkedAt: linkedAtRaw != null ? DateTime.parse(linkedAtRaw) : null,
      botUsername: json['bot_username'] as String?,
    );
  }
}

class TelegramRepository {
  final ApiClient _api;
  TelegramRepository(this._api);

  Dio get _dio => _api.dio;

  Future<TelegramStatus> status() async {
    try {
      final resp = await _dio.get('/telegram/status');
      return TelegramStatus.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw _wrap(e);
    }
  }

  Future<TelegramLinkStart> startLink() async {
    try {
      final resp = await _dio.post('/telegram/link/start');
      return TelegramLinkStart.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw _wrap(e);
    }
  }

  Future<bool> unlink() async {
    try {
      final resp = await _dio.post('/telegram/unlink');
      final data = Map<String, dynamic>.from(resp.data);
      return (data['unlinked'] as bool?) ?? false;
    } catch (e) {
      throw _wrap(e);
    }
  }

  TelegramException _wrap(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      String? code;
      String? message;
      if (body is Map) {
        final detail = body['detail'];
        if (detail is Map) {
          code = detail['error'] as String?;
          message = detail['message'] as String?;
        } else if (detail is String) {
          message = detail;
        }
      }
      return TelegramException(
        message ?? friendlyErrorMessage(e),
        statusCode: status,
        code: code,
      );
    }
    return TelegramException(friendlyErrorMessage(e));
  }
}
