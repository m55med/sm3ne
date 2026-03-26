// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'بصوتك';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get register => 'إنشاء حساب';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get username => 'اسم المستخدم';

  @override
  String get password => 'كلمة السر';

  @override
  String get fullName => 'الاسم الكامل';

  @override
  String get forgotPassword => 'نسيت كلمة السر؟';

  @override
  String get resetPassword => 'استعادة كلمة السر';

  @override
  String get enterOtp => 'أدخل رمز التحقق';

  @override
  String get newPassword => 'كلمة السر الجديدة';

  @override
  String get orContinueWith => 'أو تابع عبر';

  @override
  String get google => 'جوجل';

  @override
  String get apple => 'آبل';

  @override
  String get alreadyHaveAccount => 'لديك حساب بالفعل؟';

  @override
  String get dontHaveAccount => 'ليس لديك حساب؟';

  @override
  String get home => 'الرئيسية';

  @override
  String get myTranscriptions => 'تسجيلاتي';

  @override
  String get profile => 'الملف الشخصي';

  @override
  String get settings => 'الإعدادات';

  @override
  String get plans => 'الباقات';

  @override
  String get recordAudio => 'تسجيل صوت';

  @override
  String get uploadAudio => 'رفع ملف صوتي';

  @override
  String get processing => 'جاري المعالجة...';

  @override
  String get transcriptionResult => 'النتيجة';

  @override
  String get language => 'اللغة';

  @override
  String get duration => 'المدة';

  @override
  String get words => 'كلمات';

  @override
  String get characters => 'أحرف';

  @override
  String get copyText => 'نسخ النص';

  @override
  String get shareText => 'مشاركة النص';

  @override
  String get textCopied => 'تم نسخ النص!';

  @override
  String get freePlan => 'مجانية';

  @override
  String get monthlyPlan => 'شهرية';

  @override
  String get annualPlan => 'سنوية';

  @override
  String get subscribe => 'اشترك';

  @override
  String get couponCode => 'رمز الكوبون';

  @override
  String get applyCoupon => 'تطبيق';

  @override
  String get perMonth => '/شهرياً';

  @override
  String get perYear => '/سنوياً';

  @override
  String maxSeconds(Object seconds) {
    return 'حد أقصى $seconds ثانية';
  }

  @override
  String get unlimited => 'بلا حدود';

  @override
  String get noAds => 'بدون إعلانات';

  @override
  String get currentPlan => 'الباقة الحالية';

  @override
  String get upgrade => 'ترقية';

  @override
  String get darkMode => 'الوضع المظلم';

  @override
  String get languageSetting => 'اللغة';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get survey => 'حدثنا عن نفسك';

  @override
  String get surveyHearing => 'أعاني من ضعف السمع';

  @override
  String get surveyMessages => 'أريد قراءة الرسائل الصوتية';

  @override
  String get surveyLectures => 'أريد نسخ المحاضرات';

  @override
  String get surveyMeetings => 'أريد نسخ الاجتماعات';

  @override
  String get surveyOther => 'أخرى';

  @override
  String get continueBtn => 'متابعة';

  @override
  String get skip => 'تخطي';

  @override
  String get noTranscriptions => 'لا توجد تسجيلات بعد';

  @override
  String trimmedNotice(Object seconds) {
    return 'تم قص الصوت إلى $seconds ثانية (باقة مجانية)';
  }

  @override
  String get searchTranscriptions => 'البحث في التسجيلات...';

  @override
  String get delete => 'حذف';

  @override
  String get save => 'حفظ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get error => 'خطأ';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get seconds => 'ث';

  @override
  String get onboardingTitle1 => 'حوّل الصوت إلى نص';

  @override
  String get onboardingDesc1 => 'حوّل أي ملف صوتي إلى نص مكتوب بدقة عالية';

  @override
  String get onboardingTitle2 => 'شارك من أي مكان';

  @override
  String get onboardingDesc2 =>
      'شارك الرسائل الصوتية من واتساب وتيليجرام أو أي تطبيق';

  @override
  String get onboardingTitle3 => 'احفظ وابحث';

  @override
  String get onboardingDesc3 => 'كل تسجيلاتك محفوظة محلياً للوصول السريع';
}
