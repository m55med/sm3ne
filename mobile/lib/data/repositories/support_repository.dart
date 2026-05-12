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
}
