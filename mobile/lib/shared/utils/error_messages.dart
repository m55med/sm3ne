import 'package:dio/dio.dart';

/// Maps any error (typically a [DioException]) into a friendly Arabic message.
String friendlyErrorMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;

    // Backend convention: 4xx errors return either {"detail": "..."} or
    // {"detail": {"error": "<code>", ...}}. Inspect both shapes.
    final code = _extractErrorCode(detail);
    final mapped = _mapBackendCode(code);
    if (mapped != null) return mapped;

    switch (status) {
      case 400:
        if (detail is String) return detail;
        return 'بيانات غير صحيحة.';
      case 401:
        return 'انتهت الجلسة، سجّل دخولك مرة أخرى.';
      case 402:
        return 'هذه الباقة تتطلب كوبون للاشتراك.';
      case 403:
        return 'لا تملك صلاحية هذا الإجراء.';
      case 404:
        return 'العنصر المطلوب غير موجود.';
      case 409:
        return 'العملية تتعارض مع حالة الحساب الحالية.';
      case 413:
        return 'الملف كبير جداً.';
      case 422:
        return 'بيانات غير صحيحة.';
      case 429:
        return 'محاولات كثيرة. الرجاء المحاولة بعد قليل.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'تعذّر الاتصال بالخادم. حاول لاحقاً.';
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'الاتصال بطيء جداً. تحقّق من الشبكة وحاول مجدداً.';
      case DioExceptionType.connectionError:
        return 'لا يوجد اتصال بالإنترنت.';
      case DioExceptionType.cancel:
        return 'تم إلغاء الطلب.';
      case DioExceptionType.badCertificate:
        return 'تعذّر التحقّق من شهادة الخادم.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }
  }
  return 'حدث خطأ، حاول مجدداً.';
}

/// Extracts a backend `error` string from a variety of payload shapes.
String? _extractErrorCode(Object? detail) {
  if (detail is Map) {
    final code = detail['error'];
    if (code is String) return code;
  }
  return null;
}

/// Centralised translation table for backend error codes. Keeping the map
/// in one place avoids drifting wording across screens.
String? _mapBackendCode(String? code) {
  if (code == null) return null;
  switch (code) {
    case 'api_disabled_on_plan':
      return 'باقتك الحالية لا تدعم استخدام الـ API.';
    case 'daily_quota_exceeded':
      return 'لقد استنفدت حصتك اليومية. حاول مجدداً غداً.';
    case 'live_recording_quota_exceeded':
      return 'تجاوزت حصة التسجيل المباشر اليومية.';
    case 'coupon_invalid':
    case 'invalid_coupon':
      return 'الكوبون غير صالح.';
    case 'coupon_expired':
      return 'انتهت صلاحية هذا الكوبون.';
    case 'coupon_already_used':
    case 'coupon_used':
      return 'تم استخدام هذا الكوبون من قبل.';
    case 'coupon_not_applicable':
      return 'لا يمكن استخدام هذا الكوبون مع هذه الباقة.';
    case 'plan_not_found':
      return 'الباقة المطلوبة غير موجودة.';
    case 'subscription_active':
      return 'لديك اشتراك نشط بالفعل.';
    case 'account_exists_local':
      return 'يوجد حساب بنفس البريد الإلكتروني. سجّل دخولك بكلمة السر.';
    case 'invalid_credentials':
      return 'بيانات الدخول غير صحيحة.';
    case 'email_taken':
      return 'هذا البريد مستخدم بالفعل.';
    case 'weak_password':
      return 'كلمة السر ضعيفة. اختر كلمة أقوى.';
    case 'invalid_otp':
      return 'رمز التحقق غير صحيح.';
    case 'otp_expired':
      return 'انتهت صلاحية الرمز. اطلب رمزاً جديداً.';
    case 'too_many_otp_attempts':
      return 'محاولات كثيرة لإدخال الرمز. اطلب رمزاً جديداً.';
    case 'audio_too_long':
      return 'مدة الصوت أطول من الحد المسموح.';
    case 'unsupported_audio_format':
      return 'صيغة الصوت غير مدعومة.';
    default:
      return null;
  }
}

/// Returns a short Arabic explanation for a coupon-related error suitable
/// for an inline `errorText` field. Falls back to the generic mapper.
String couponErrorMessage(Object error) {
  if (error is DioException) {
    final detail = error.response?.data is Map
        ? (error.response!.data as Map)['detail']
        : null;
    final code = _extractErrorCode(detail);
    final mapped = _mapBackendCode(code);
    if (mapped != null) return mapped;
    // Older endpoints occasionally returned the message in `detail` directly.
    if (detail is String && detail.trim().isNotEmpty) return detail;
  }
  return friendlyErrorMessage(error);
}
