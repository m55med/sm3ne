import 'package:dio/dio.dart';

/// Maps any error (typically a [DioException]) into a friendly Arabic message.
String friendlyErrorMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;

    switch (status) {
      case 400:
        if (detail is String) return detail;
        return 'بيانات غير صحيحة.';
      case 401:
        return 'انتهت الجلسة، سجّل دخولك مرة أخرى.';
      case 403:
        if (detail is Map && detail['error'] == 'api_disabled_on_plan') {
          return 'باقتك الحالية لا تدعم استخدام الـ API.';
        }
        return 'لا تملك صلاحية هذا الإجراء.';
      case 404:
        return 'العنصر المطلوب غير موجود.';
      case 413:
        return 'الملف كبير جداً.';
      case 422:
        return 'بيانات غير صحيحة.';
      case 429:
        if (detail is Map && detail['error'] == 'daily_quota_exceeded') {
          return 'لقد استنفدت حصتك اليومية. حاول مجدداً غداً.';
        }
        if (detail is Map && detail['error'] == 'live_recording_quota_exceeded') {
          return 'تجاوزت حصة التسجيل المباشر اليومية.';
        }
        return 'محاولات كثيرة. حاول لاحقاً.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'تعذّر الاتصال بالخادم. حاول لاحقاً.';
    }

    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
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
