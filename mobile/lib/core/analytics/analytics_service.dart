import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin, typed wrapper around Firebase Analytics.
///
/// Every screen logs through this single service instead of touching
/// `FirebaseAnalytics.instance` directly — keeps event names consistent and
/// gives us one place to add/remove instrumentation.
///
/// The wrapped [FirebaseAnalytics] is nullable: when Firebase fails to
/// initialise (misbuilt flavour, offline first-run edge cases) the service
/// degrades to a silent no-op so a missing analytics backend can never break
/// a user flow. All methods are fire-and-forget and never throw.
class AnalyticsService {
  AnalyticsService(this._analytics);

  final FirebaseAnalytics? _analytics;

  bool get isEnabled => _analytics != null;

  /// Navigator observer — wire into GoRouter so screen views are tracked
  /// automatically. Returns null when analytics is disabled.
  FirebaseAnalyticsObserver? get observer => _analytics == null
      ? null
      : FirebaseAnalyticsObserver(analytics: _analytics);

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.logEvent(name: name, parameters: params);
    } catch (e) {
      if (kDebugMode) debugPrint('analytics: failed to log "$name": $e');
    }
  }

  /// Tie events to the signed-in user — we send the anonymised public id,
  /// never the email/phone.
  Future<void> setUser(String? publicId) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.setUserId(id: publicId);
    } catch (_) {/* never throw from analytics */}
  }

  // --- Domain events --------------------------------------------------------

  Future<void> appOpened() => _log('app_opened');

  Future<void> login(String method) =>
      _log('login', {'method': method}); // method: password | google | apple

  Future<void> signUp(String method) => _log('sign_up', {'method': method});

  Future<void> transcriptionStarted(String source) =>
      _log('transcription_started', {'source': source}); // upload | recording | share

  Future<void> transcriptionCompleted({
    required String source,
    required int durationSeconds,
    required int wordCount,
  }) =>
      _log('transcription_completed', {
        'source': source,
        'duration_seconds': durationSeconds,
        'word_count': wordCount,
      });

  Future<void> transcriptionFailed(String source) =>
      _log('transcription_failed', {'source': source});

  Future<void> couponRedeemed(String planName) =>
      _log('coupon_redeemed', {'plan': planName});

  Future<void> subscriptionCancelled() => _log('subscription_cancelled');

  Future<void> telegramLinked() => _log('telegram_linked');
}

/// App-wide analytics provider. `main.dart` overrides it with the real
/// instance when Firebase initialises; if Firebase init fails the default
/// below (a disabled no-op service) keeps every `ref.read(analyticsProvider)`
/// call safe.
final analyticsProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService(null);
});
