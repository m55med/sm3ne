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

class CurrentSubscription {
  final String planName;
  final String? expiresAt;
  final bool active;

  const CurrentSubscription({
    required this.planName,
    this.expiresAt,
    required this.active,
  });

  factory CurrentSubscription.fromJson(Map<String, dynamic> json) {
    return CurrentSubscription(
      planName: (json['plan_name'] as String?) ??
          (json['name'] as String?) ??
          'free',
      expiresAt: json['expires_at'] as String?,
      active: (json['active'] as bool?) ?? false,
    );
  }
}

class CouponValidation {
  final bool valid;
  final double? discountPercent;
  final double? discountAmount;
  final String? message;

  const CouponValidation({
    required this.valid,
    this.discountPercent,
    this.discountAmount,
    this.message,
  });

  factory CouponValidation.fromJson(Map<String, dynamic> json) {
    return CouponValidation(
      valid: (json['valid'] as bool?) ?? false,
      discountPercent: (json['discount_percent'] as num?)?.toDouble(),
      discountAmount: (json['discount_amount'] as num?)?.toDouble(),
      message: json['message'] as String?,
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
      // If the user has no subscription, the backend may return 404.
      if (e.response?.statusCode == 404) return null;
      throw PlansException(friendlyErrorMessage(e),
          statusCode: e.response?.statusCode);
    } catch (e) {
      throw PlansException(friendlyErrorMessage(e));
    }
  }

  Future<void> subscribe({
    required int planId,
    String? couponCode,
  }) async {
    try {
      await _dio.post('/plans/subscribe', data: {
        'plan_id': planId,
        if (couponCode != null && couponCode.isNotEmpty) 'coupon': couponCode,
      });
    } catch (e) {
      throw PlansException(friendlyErrorMessage(e),
          statusCode: e is DioException ? e.response?.statusCode : null);
    }
  }

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
}
