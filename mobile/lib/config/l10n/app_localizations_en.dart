// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Bisawtak';

  @override
  String get login => 'Login';

  @override
  String get register => 'Create Account';

  @override
  String get email => 'Email';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get fullName => 'Full Name';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get enterOtp => 'Enter verification code';

  @override
  String get newPassword => 'New Password';

  @override
  String get orContinueWith => 'Or continue with';

  @override
  String get google => 'Google';

  @override
  String get apple => 'Apple';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get dontHaveAccount => 'Don\'t have an account?';

  @override
  String get home => 'Home';

  @override
  String get myTranscriptions => 'My Transcriptions';

  @override
  String get profile => 'Profile';

  @override
  String get settings => 'Settings';

  @override
  String get plans => 'Plans';

  @override
  String get recordAudio => 'Record Audio';

  @override
  String get uploadAudio => 'Upload Audio';

  @override
  String get processing => 'Processing...';

  @override
  String get transcriptionResult => 'Result';

  @override
  String get language => 'Language';

  @override
  String get duration => 'Duration';

  @override
  String get words => 'Words';

  @override
  String get characters => 'Characters';

  @override
  String get copyText => 'Copy Text';

  @override
  String get shareText => 'Share Text';

  @override
  String get textCopied => 'Text copied!';

  @override
  String get freePlan => 'Free';

  @override
  String get monthlyPlan => 'Monthly';

  @override
  String get annualPlan => 'Annual';

  @override
  String get subscribe => 'Subscribe';

  @override
  String get couponCode => 'Coupon Code';

  @override
  String get applyCoupon => 'Apply';

  @override
  String get perMonth => '/month';

  @override
  String get perYear => '/year';

  @override
  String maxSeconds(Object seconds) {
    return 'Max $seconds seconds';
  }

  @override
  String get unlimited => 'Unlimited';

  @override
  String get noAds => 'No Ads';

  @override
  String get currentPlan => 'Current Plan';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get languageSetting => 'Language';

  @override
  String get logout => 'Logout';

  @override
  String get survey => 'Tell us about yourself';

  @override
  String get surveyHearing => 'I have hearing difficulties';

  @override
  String get surveyMessages => 'I want to read voice messages';

  @override
  String get surveyLectures => 'I want to transcribe lectures';

  @override
  String get surveyMeetings => 'I want to transcribe meetings';

  @override
  String get surveyOther => 'Other';

  @override
  String get continueBtn => 'Continue';

  @override
  String get skip => 'Skip';

  @override
  String get noTranscriptions => 'No transcriptions yet';

  @override
  String trimmedNotice(Object seconds) {
    return 'Audio was trimmed to ${seconds}s (free plan)';
  }

  @override
  String get searchTranscriptions => 'Search transcriptions...';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get error => 'Error';

  @override
  String get retry => 'Retry';

  @override
  String get seconds => 's';

  @override
  String get onboardingTitle1 => 'Convert Voice to Text';

  @override
  String get onboardingDesc1 =>
      'Transcribe any audio file into text with high accuracy';

  @override
  String get onboardingTitle2 => 'Share from Anywhere';

  @override
  String get onboardingDesc2 =>
      'Share voice messages from WhatsApp, Telegram, or any app';

  @override
  String get onboardingTitle3 => 'Save & Search';

  @override
  String get onboardingDesc3 =>
      'All your transcriptions are saved locally for easy access';
}
