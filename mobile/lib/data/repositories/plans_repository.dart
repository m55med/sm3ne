import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/data/models/plan.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';

final plansRepositoryProvider = Provider<PlansRepository>((ref) {
  return PlansRepository(ref.read(apiClientProvider));
});

class PlansException implements Exception {
  final String message;
  final int? statusCode;
  const PlansException(this.message, {this.statusCode});

  @override
  String toString() => 'PlansException($statusCode): $message';
}

/// Current subscription + plan + today's usage.
///
/// Parses the `/plans/my` (alias `/plans/current`) envelope:
///   { plan: {...}, subscription: {...}|null, usage: {...} }
class CurrentSubscription {
  final String planName;
  final int planId;
  /// True only when the user has an *active paid* subscription row.
  /// A free user has [hasActiveSubscription] == false.
  final bool hasActiveSubscription;
  /// ISO-8601 string. null = free plan OR a permanent (lifetime) subscription.
  final String? expiresAt;
  final DateTime? startsAt;
  /// True when there's a subscription with no expiry — a lifetime grant
  /// (the coupon-for-deaf-users case).
  final bool isPermanent;
  final int requestsToday;
  final int dailyLimit;
  final int maxAudioSeconds;

  const CurrentSubscription({
    required this.planName,
    required this.planId,
    required this.hasActiveSubscription,
    this.expiresAt,
    this.startsAt,
    required this.isPermanent,
    required this.requestsToday,
    required this.dailyLimit,
    required this.maxAudioSeconds,
  });

  bool get isFree => planName == 'free';

  factory CurrentSubscription.fromJson(Map<String, dynamic> json) {
    final plan = (json['plan'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sub = (json['subscription'] as Map?)?.cast<String, dynamic>();
    final usage = (json['usage'] as Map?)?.cast<String, dynamic>() ?? const {};

    final hasSub = sub != null && (sub['is_active'] as bool? ?? false);
    final expiresAt = sub?['expires_at'] as String?;

    return CurrentSubscription(
      planName: (plan['name'] as String?) ?? 'free',
      planId: (plan['id'] as int?) ?? 0,
      hasActiveSubscription: hasSub,
      expiresAt: expiresAt,
      startsAt: sub?['starts_at'] != null
          ? DateTime.tryParse(sub!['starts_at'] as String)
          : null,
      isPermanent: hasSub && expiresAt == null,
      requestsToday: (usage['requests_today'] as int?) ?? 0,
      dailyLimit: (usage['daily_limit'] as int?) ?? 0,
      maxAudioSeconds: (usage['max_audio_seconds'] as int?) ?? 0,
    );
  }
}

/// Read-only preview of what a coupon would grant — from `/plans/coupon/validate`.
class CouponValidation {
  final bool valid;
  final String code;
  final int planId;
  final String planName;
  final int durationDays; // -1 = permanent
  final bool isPermanent;
  final String message;

  const CouponValidation({
    required this.valid,
    required this.code,
    required this.planId,
    required this.planName,
    required this.durationDays,
    required this.isPermanent,
    required this.message,
  });

  factory CouponValidation.fromJson(Map<String, dynamic> json) {
    return CouponValidation(
      valid: (json['valid'] as bool?) ?? false,
      code: (json['code'] as String?) ?? '',
      planId: (json['plan_id'] as int?) ?? 0,
      planName: (json['plan_name'] as String?) ?? '',
      durationDays: (json['duration_days'] as int?) ?? 0,
      isPermanent: (json['is_permanent'] as bool?) ?? false,
      message: (json['message'] as String?) ?? '',
    );
  }
}

class PlansRepository {
  final ApiClient _api;
  PlansRepository(this._api);

  Dio get _dio => _api.dio;

  Future<List<Plan>> listPlans() async {
    try {
      final resp = await _dio.get('/plans');
      final list = (resp.data as List).cast<Map<String, dynamic>>();
      return list.map(Plan.fromJson).toList();
    } catch (e) {
      throw PlansException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  Future<CurrentSubscription?> currentSubscription() async {
    try {
      final resp = await _dio.get('/plans/current');
      if (resp.data == null) return null;
      return CurrentSubscription.fromJson(
        Map<String, dynamic>.from(resp.data),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw PlansException(friendlyErrorMessage(e),
          statusCode: e.response?.statusCode);
    } catch (e) {
      throw PlansException(friendlyErrorMessage(e));
    }
  }

  /// Redeem a coupon — this is the only way to get a paid plan in the app.
  Future<void> applyCoupon(String code) async {
    try {
      await _dio.post('/plans/coupon', data: {'code': code});
    } catch (e) {
      throw PlansException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  /// Read-only check of what a coupon would grant, before redeeming it.
  Future<CouponValidation> validateCoupon({
    required String code,
    int? planId,
  }) async {
    try {
      final resp = await _dio.post('/plans/coupon/validate', data: {
        'code': code,
        if (planId != null) 'plan_id': planId,
      });
      return CouponValidation.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (e) {
      throw PlansException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

  /// Cancel the current subscription — the user immediately drops to the free
  /// plan. A coupon-granted subscription can be cancelled too (the coupon is
  /// already consumed and is not refunded).
  Future<void> cancelSubscription() async {
    try {
      await _dio.post('/plans/cancel');
    } catch (e) {
      throw PlansException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }
}
