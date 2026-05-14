class AppConstants {
  static const String appName = 'بصوتك';
  static const String appNameEn = 'Bisawtak';

  // API base URL — overridable via --dart-define=API_URL=...
  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://voice.neojeen.com/api/v1',
  );

  // Free plan limit (in seconds) for free users
  static const int freeMaxSeconds = 30;

  // Google Sign-In — the WEB OAuth client ID. Passed to GoogleSignIn as
  // `serverClientId` so the returned idToken's `aud` claim matches what the
  // backend verifies against (GOOGLE_CLIENT_ID env var). NOT the iOS/Android
  // client IDs — those are matched automatically by bundle id / package+SHA.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '189277247383-hl6a00rppttpbrbk7v1mmm7e8tqfpa1g.apps.googleusercontent.com',
  );

  // Upload limits / allowed file types
  static const int maxUploadBytes = 200 * 1024 * 1024; // 200 MB
  static const Set<String> allowedAudioExtensions = {
    'm4a', 'mp3', 'wav', 'ogg', 'opus', 'aac', 'flac', 'webm', 'mp4',
  };

  // AdMob IDs — Google's TEST IDs.
  // TODO(release): replace with real ad-unit IDs before production release.
  // For now, can be overridden via --dart-define=ADMOB_BANNER_ANDROID=...
  static const String adBannerAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const String adBannerIos = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );
  static const String adInterstitialAndroid = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const String adInterstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/4411468910',
  );
}
