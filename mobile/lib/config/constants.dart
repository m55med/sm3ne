import 'dart:io';

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
  // backend verifies against. The Android SDK rejects sign-in with
  // ApiException:10 (DEVELOPER_ERROR) unless the Android OAuth client AND
  // the Web client used here live in the SAME Google Cloud project — so
  // each platform has its own web client.
  //
  //   • Android Android OAuth client → project `bisawtak-41e56`
  //   • Android Web client (here)    → project `bisawtak-41e56`
  //   • iOS    iOS OAuth client      → project `bisawtak`
  //   • iOS    Web client (here)     → project `bisawtak`
  //
  // The backend's GOOGLE_CLIENT_IDS_EXTRA accepts both so tokens from
  // either platform verify cleanly.
  static const String _androidGoogleServerClientId =
      '257623929369-ntkn3lb1ospp3hh4a0kchoqf4mb34hn2.apps.googleusercontent.com';
  static const String _iosGoogleServerClientId =
      '189277247383-hl6a00rppttpbrbk7v1mmm7e8tqfpa1g.apps.googleusercontent.com';

  static String get googleServerClientId {
    // --dart-define overrides everything (useful for local testing against a
    // staging client). An empty value (the default) falls through to the
    // platform-specific picks below.
    const override = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    if (override.isNotEmpty) return override;
    return Platform.isAndroid
        ? _androidGoogleServerClientId
        : _iosGoogleServerClientId;
  }

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
