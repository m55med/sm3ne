import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:bisawtak/shared/utils/remote_logger.dart';

/// Outcome of a live on-device STT session.
///
/// `success` carries the recognized text. Anything else carries `reason` so
/// the orchestrator can decide whether to fall back to the server (it always
/// does on failure) and so analytics knows *why* the cheap path didn't work.
class OnDeviceSttResult {
  final bool success;
  final String text;
  final double confidence;
  final String engineName; // 'apple_speech' | 'android_speech'
  final String? failureReason;

  const OnDeviceSttResult._({
    required this.success,
    required this.text,
    required this.confidence,
    required this.engineName,
    this.failureReason,
  });

  factory OnDeviceSttResult.ok({
    required String text,
    required double confidence,
    required String engineName,
  }) {
    return OnDeviceSttResult._(
      success: true,
      text: text,
      confidence: confidence,
      engineName: engineName,
    );
  }

  factory OnDeviceSttResult.fail(String reason, {String engineName = ''}) {
    return OnDeviceSttResult._(
      success: false,
      text: '',
      confidence: 0,
      engineName: engineName,
      failureReason: reason,
    );
  }
}

/// Maps an app UI locale to a BCP-47 speech recognizer locale.
///
/// We default to ar-EG / en-US since those are the only two languages the
/// UI ships with. The recognizer plugin matches by prefix, so even if the
/// system only has e.g. ar-SA installed it still resolves correctly.
String resolveSpeechLocale(String? uiLocale) {
  final code = (uiLocale ?? 'ar').toLowerCase();
  if (code.startsWith('en')) return 'en-US';
  return 'ar-EG';
}

abstract class OnDeviceStt {
  /// Initializes the underlying recognizer. Safe to call repeatedly.
  /// Returns false if the device has no recognizer or the user denied speech
  /// permission — in which case the orchestrator should stop trying for the
  /// rest of the session.
  Future<bool> initialize();

  /// Starts listening to the mic. Buffers partial results internally.
  Future<void> startLive({required String localeId});

  /// Stops listening and returns the accumulated result.
  Future<OnDeviceSttResult> stopLive();

  /// Recognizes an audio FILE on-device. Currently iOS-only — Android has
  /// no native file-based recognizer, so this returns a `not_supported`
  /// failure there and the orchestrator falls back to the server.
  Future<OnDeviceSttResult> recognizeFile({
    required String filePath,
    required String localeId,
  });

  /// True once [initialize] succeeded.
  bool get isAvailable;

  /// Best-effort engine name for the current platform.
  String get engineName;
}

final onDeviceSttProvider = Provider<OnDeviceStt>((ref) {
  return SpeechToTextOnDeviceStt();
});

/// Concrete implementation backed by the `speech_to_text` pub.dev plugin —
/// which wraps `SFSpeechRecognizer` on iOS and `SpeechRecognizer` on Android.
///
/// Only handles **live mic** input. File-based recognition would need a
/// platform channel (iOS has `SFSpeechURLRecognitionRequest`; Android has
/// no first-party file API). v1 leaves uploaded/shared files on the server
/// path — see `transcription_repository.transcribeFile`.
class SpeechToTextOnDeviceStt implements OnDeviceStt {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _initialized = false;
  String _lastWords = '';
  double _lastConfidence = 0;
  String? _lastErrorCode;

  @override
  bool get isAvailable => _available;

  @override
  String get engineName => Platform.isIOS ? 'apple_speech' : 'android_speech';

  @override
  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      // On iOS the plugin requests speech-recognition permission as part of
      // initialize(). We don't pre-request: that would pop two dialogs in a
      // row (mic + speech) when the user has only seen the mic prompt before.
      _available = await _speech.initialize(
        onError: (SpeechRecognitionError err) {
          _lastErrorCode = err.errorMsg;
          if (kDebugMode) {
            debugPrint('on-device STT error: ${err.errorMsg} '
                'permanent=${err.permanent}');
          }
        },
        onStatus: (status) {
          if (kDebugMode) debugPrint('on-device STT status: $status');
        },
        debugLogging: kDebugMode,
      );
    } catch (e) {
      _available = false;
      if (kDebugMode) debugPrint('on-device STT initialize failed: $e');
    }
    return _available;
  }

  @override
  Future<void> startLive({required String localeId}) async {
    _lastWords = '';
    _lastConfidence = 0;
    _lastErrorCode = null;
    if (!_available) return;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        _lastWords = r.recognizedWords;
        // Android often returns -1 for confidence; iOS returns 0..1.
        if (r.confidence > 0) _lastConfidence = r.confidence;
      },
      listenOptions: stt.SpeechListenOptions(
        // Force the OS to keep recognition on-device. On a device that
        // doesn't support it for this locale, the engine returns an
        // unavailable error and we fall back to the server path.
        onDevice: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        autoPunctuation: true,
        localeId: localeId,
        // The user's mic session is already capped at 10 minutes by the
        // UI. We mirror that ceiling here as a safety net — without an
        // upper bound `speech_to_text` defaults to ~30s on Android.
        listenFor: const Duration(minutes: 10),
        // Tolerate long pauses inside a single recording (e.g. someone
        // thinking mid-sentence). Without this Android cuts off after ~3s
        // of silence and we'd get a truncated transcript.
        pauseFor: const Duration(seconds: 30),
      ),
    );
  }

  /// Tunable confidence threshold for iOS. SFSpeech sometimes reports 0 for
  /// short utterances even when the text is correct — so we accept text with
  /// confidence == 0 (treat as "unscored") and only reject below an explicit
  /// low-confidence threshold. Empirically this catches the WhatsApp voice
  /// message case where Apple returns good text but doesn't score it.
  static const double _minIosConfidence = 0.30;

  bool _meetsQualityBar(String text, double confidence, double recordedSec) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (Platform.isIOS) {
      // Accept unscored results (confidence == 0): SFSpeech doesn't always
      // emit a meaningful score, particularly for short Arabic utterances.
      // Only reject when Apple did give us a score and it's below the floor.
      if (confidence == 0) return true;
      return confidence >= _minIosConfidence;
    }
    // Android: confidence is unreliable. Use a sanity gate — at least 8
    // characters AND roughly 1.5 chars/sec of recording. Below that the
    // result is almost always partial or "I didn't catch that".
    if (trimmed.length < 8) return false;
    if (recordedSec > 0 && trimmed.length < recordedSec * 1.5) return false;
    return true;
  }

  @override
  Future<OnDeviceSttResult> stopLive() async {
    if (!_available) {
      return OnDeviceSttResult.fail('not_initialized', engineName: engineName);
    }
    try {
      await _speech.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('on-device STT stop error: $e');
    }
    if (_lastErrorCode != null) {
      return OnDeviceSttResult.fail(
        'recognizer_error:$_lastErrorCode',
        engineName: engineName,
      );
    }
    // We don't know the exact recorded duration here — the caller passes
    // it in via the orchestrator. We use a coarse heuristic of "any text"
    // and let the orchestrator do the final quality gate when it knows
    // the actual seconds elapsed.
    if (_lastWords.trim().isEmpty) {
      return OnDeviceSttResult.fail('empty_result', engineName: engineName);
    }
    return OnDeviceSttResult.ok(
      text: _lastWords,
      confidence: _lastConfidence,
      engineName: engineName,
    );
  }

  /// Public helper so the orchestrator can apply the duration-aware quality
  /// bar after recording is finalized.
  bool meetsQualityBar(String text, double confidence, double recordedSec) {
    return _meetsQualityBar(text, confidence, recordedSec);
  }

  /// File recognition — iOS only via the native channel
  /// `com.bisawtak/stt_file`. Android returns a `not_supported` failure
  /// without making a channel call (no native handler is registered).
  static const _fileChannel = MethodChannel('com.bisawtak/stt_file');

  /// Triggers Apple's `SFSpeechRecognizer.requestAuthorization` so the system
  /// permission dialog appears (if the user hasn't decided yet). Returns the
  /// resulting status as a short string: `authorized`, `denied`, `restricted`,
  /// `notDetermined`, or `not_applicable` on non-iOS.
  ///
  /// Safe to call repeatedly — Apple only shows the dialog the first time.
  static Future<String> requestPermission() async {
    if (!Platform.isIOS) return 'not_applicable';
    try {
      final r = await _fileChannel.invokeMethod<String>('requestPermission');
      return r ?? 'unknown';
    } catch (e) {
      // Log to /diag/log so we can see when the native channel isn't
      // wired up properly on real devices (e.g. MissingPluginException).
      // Without this, the setting silently shows "unknown" forever.
      RemoteLogger.log('stt_channel', 'requestPermission failed: $e');
      if (kDebugMode) debugPrint('requestPermission failed: $e');
      return 'unknown';
    }
  }

  /// Reports current speech-recognizer capability for [localeId] WITHOUT
  /// triggering a permission dialog. Returns a map with three booleans:
  /// `auth_status` (string), `recognizer_available` (bool — does this device
  /// have a recognizer for the locale at all), `supports_on_device` (bool —
  /// is the offline language pack installed).
  ///
  /// The settings screen uses this to display a precise diagnostic when the
  /// user enables the toggle — so they know whether to grant permission, or
  /// install the language under iOS Settings → General → Keyboards → Dictation.
  static Future<Map<String, dynamic>> probeAvailability({
    String localeId = 'ar-EG',
  }) async {
    if (!Platform.isIOS) {
      return const {
        'auth_status': 'not_applicable',
        'recognizer_available': false,
        'supports_on_device': false,
      };
    }
    try {
      final raw = await _fileChannel
          .invokeMethod<dynamic>('isAvailable', {'localeId': localeId});
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      return const {'auth_status': 'unknown', 'recognizer_available': false, 'supports_on_device': false};
    } catch (e) {
      // Most common cause: MissingPluginException because the native channel
      // handler isn't registered. Surface to /diag/log so production failures
      // are visible without a re-build.
      RemoteLogger.log('stt_channel', 'probeAvailability failed: $e');
      if (kDebugMode) debugPrint('probeAvailability failed: $e');
      return const {'auth_status': 'unknown', 'recognizer_available': false, 'supports_on_device': false};
    }
  }

  @override
  Future<OnDeviceSttResult> recognizeFile({
    required String filePath,
    required String localeId,
  }) async {
    if (!Platform.isIOS) {
      return OnDeviceSttResult.fail('not_supported', engineName: engineName);
    }
    try {
      final raw = await _fileChannel.invokeMethod<dynamic>('recognize', {
        'filePath': filePath,
        'localeId': localeId,
      });
      if (raw is! Map) {
        return OnDeviceSttResult.fail('bad_native_response', engineName: engineName);
      }
      final map = Map<String, dynamic>.from(raw);
      final success = map['success'] == true;
      if (!success) {
        final reason = (map['reason'] as String?) ?? 'unknown';
        return OnDeviceSttResult.fail(reason, engineName: engineName);
      }
      final text = (map['text'] as String?) ?? '';
      // SFSpeech returns confidence in 0..1; we forward as-is and let the
      // orchestrator apply its quality gate.
      final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.0;
      return OnDeviceSttResult.ok(
        text: text,
        confidence: confidence,
        engineName: engineName,
      );
    } on PlatformException catch (e) {
      return OnDeviceSttResult.fail(
        'platform_error:${e.code}',
        engineName: engineName,
      );
    } catch (e) {
      return OnDeviceSttResult.fail('unknown:$e', engineName: engineName);
    }
  }
}

/// Best-effort permission check. The plugin will also request internally,
/// but we ask up front to know whether to even attempt on-device for this
/// session. Returns true only if both mic AND speech are granted.
Future<bool> checkSpeechPermissions() async {
  final mic = await Permission.microphone.status;
  if (!mic.isGranted) return false;
  if (Platform.isIOS) {
    final speech = await Permission.speech.status;
    if (speech.isDenied || speech.isPermanentlyDenied) return false;
  }
  return true;
}
