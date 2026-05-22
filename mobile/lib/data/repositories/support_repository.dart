import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.read(apiClientProvider));
});

class SupportException implements Exception {
  final String message;
  final int? statusCode;
  const SupportException(this.message, {this.statusCode});

  @override
  String toString() => 'SupportException($statusCode): $message';
}

class SupportTicket {
  final String publicId;
  final String subject;
  final String status;
  final String createdAt;
  final String? lastMessageAt;

  const SupportTicket({
    required this.publicId,
    required this.subject,
    required this.status,
    required this.createdAt,
    this.lastMessageAt,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      publicId: (json['public_id'] ?? json['id']).toString(),
      subject: (json['subject'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'open',
      createdAt: (json['created_at'] as String?) ?? '',
      lastMessageAt: json['last_message_at'] as String?,
    );
  }
}

class SupportReply {
  final int id;
  final String body;
  final String authorRole; // 'user' | 'admin'
  final String createdAt;

  const SupportReply({
    required this.id,
    required this.body,
    required this.authorRole,
    required this.createdAt,
  });

  factory SupportReply.fromJson(Map<String, dynamic> json) {
    return SupportReply(
      id: json['id'] as int,
      body: (json['body'] as String?) ?? '',
      authorRole: (json['author_role'] as String?) ?? 'user',
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}

class SupportRepository {
  final ApiClient _api;
  SupportRepository(this._api);

  Dio get _dio => _api.dio;

  Future<List<SupportTicket>> listTickets() async {
    try {
      final resp = await _dio.get('/support/tickets');
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      return list.map(SupportTicket.fromJson).toList();
    } catch (e) {
      throw SupportException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<SupportTicket> createTicket({
    required String subject,
    required String body,
  }) async {
    try {
      final resp = await _dio.post('/support/tickets', data: {
        'subject': subject,
        'body': body,
      });
      return SupportTicket.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw SupportException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<List<SupportReply>> listReplies(String publicId) async {
    try {
      final resp = await _dio.get('/support/tickets/$publicId/replies');
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      return list.map(SupportReply.fromJson).toList();
    } catch (e) {
      throw SupportException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<SupportReply> createReply({
    required String publicId,
    required String body,
  }) async {
    try {
      final resp = await _dio.post(
        '/support/tickets/$publicId/replies',
        data: {'body': body},
      );
      return SupportReply.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw SupportException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  /// Uploads an image attachment for the given ticket. The backend validates
  /// size, extension, and magic bytes — we forward the raw file bytes and
  /// rely on those checks rather than duplicating them here.
  Future<Map<String, dynamic>> uploadAttachment({
    required String publicId,
    required String filePath,
    String? replyPublicId,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });
      final resp = await _dio.post(
        '/support/tickets/$publicId/attachments',
        data: form,
        queryParameters: {
          if (replyPublicId != null) 'reply_public_id': replyPublicId,
        },
        options: Options(
          // Image uploads can take a moment on slow connections.
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      return Map<String, dynamic>.from(resp.data);
    } catch (e) {
      throw SupportException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  /// Fetches the raw bytes of an attachment. The endpoint requires Bearer
  /// auth, so a plain `<img src=...>`-style approach won't work — the caller
  /// builds an in-memory image from these bytes.
  Future<List<int>> fetchAttachmentBytes({
    required String ticketPublicId,
    required String attachmentPublicId,
  }) async {
    try {
      final resp = await _dio.get<List<int>>(
        '/support/tickets/$ticketPublicId/attachments/$attachmentPublicId',
        options: Options(responseType: ResponseType.bytes),
      );
      return resp.data ?? const [];
    } catch (e) {
      throw SupportException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }
}
