import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bisawtak/config/constants.dart';
import 'package:bisawtak/core/stt/on_device_stt.dart';
import 'package:bisawtak/core/stt/on_device_stt_pref.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/data/repositories/transcription_repository.dart';

/// Single entry point that picks between on-device STT and the server-side
/// `/transcribe` pipeline. Callers (home screen, share handler) used to
/// reach into `TranscriptionRepository.transcribeFile` directly — now they
/// go through here so the engine choice is one place.
///
/// The model:
/// - [LiveRecordingSession] wraps a parallel mic + recognizer session for
///   live recordings. The home screen starts/stops it.
/// - [transcribeFile] handles uploaded/shared files. v1 always routes these
///   to the server because Android lacks file STT entirely and iOS file
///   recognition needs a platform channel we haven't wired yet.
class SttOrchestrator {
  final OnDeviceStt _onDevice;
  final TranscriptionRepository _repo;

  SttOrchestrator(this._onDevice, this._repo);

  Future<bool> get _userEnabled async {
    if (!AppConstants.onDeviceSttEnabled) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(onDeviceSttPrefsKey) ?? true;
  }

  /// Files (uploaded or shared). On iOS we try on-device file recognition
  /// FIRST via SFSpeechURLRecognitionRequest — that turns a WhatsApp voice
  /// share into instant local text, free of server quota or upload latency.
  /// On Android there's no native file-STT API, so we go straight to the
  /// server (Whisper.cpp embedded would bloat the APK by 150+ MB).
  ///
  /// Fallbacks: any failure on the on-device path (no permission, no
  /// recognizer for the locale, low confidence, > 1 min audio, unsupported
  /// codec) routes to the existing `_repo.transcribeFile` so the user
  /// always gets a result.
  Future<Transcription> transcribeFile(
    String filePath, {
    required String source,
    String? sourceApp,
    bool isLiveRecording = false,
    String uiLocale = 'ar',
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    if (Platform.isIOS && await _userEnabled) {
      final localeId = resolveSpeechLocale(uiLocale);
      final result = await _onDevice.recognizeFile(
        filePath: filePath,
        localeId: localeId,
      );
      if (result.success && result.text.trim().isNotEmpty) {
        // Use the same length/confidence gate the live path uses. Duration
        // isn't precisely known here (we'd have to probe the file with
        // ffmpeg) — passing 0 makes the gate effectively confidence-only,
        // which is the right call for a transcribed result.
        final ok = (_onDevice as SpeechToTextOnDeviceStt)
            .meetsQualityBar(result.text, result.confidence, 0);
        if (ok) {
          // Estimate duration from the text length when not provided —
          // mostly used for plan-quota stats. 3 words ~= 1 second of
          // Arabic speech, give or take.
          final wordCount = result.text.trim().split(RegExp(r'\s+')).length;
          final estimatedSec = wordCount / 3.0;
          try {
            return await _repo.logClientTranscription(
              text: result.text,
              lang: _shortLocale(uiLocale),
              langName: _localeName(uiLocale),
              durationSeconds: estimatedSec,
              source: source,
              isLiveRecording: false,
              clientEngine: result.engineName,
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('client-side file log failed, falling back: $e');
            }
            // fall through to server upload
          }
        } else if (kDebugMode) {
          debugPrint(
            'on-device file STT below quality bar — falling back. '
            'len=${result.text.length} conf=${result.confidence}',
          );
        }
      } else if (kDebugMode) {
        debugPrint(
          'on-device file STT failed reason=${result.failureReason}',
        );
      }
    }
    // Android or any iOS failure → existing server pipeline.
    return _repo.transcribeFile(
      filePath,
      source: source,
      sourceApp: sourceApp,
      isLiveRecording: isLiveRecording,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  String _shortLocale(String uiLocale) {
    final c = uiLocale.toLowerCase();
    if (c.startsWith('en')) return 'en';
    return 'ar';
  }

  String _localeName(String uiLocale) {
    final c = uiLocale.toLowerCase();
    if (c.startsWith('en')) return 'English';
    return 'العربية';
  }

  /// Starts a live recording session. Both the WAV writer (caller-owned)
  /// and the on-device recognizer run in parallel. If on-device fails or
  /// is disabled, the WAV is uploaded.
  Future<LiveRecordingSession> startLive({required String uiLocale}) async {
    final enabled = await _userEnabled;
    final localeId = resolveSpeechLocale(uiLocale);
    bool attemptOnDevice = enabled;
    if (attemptOnDevice) {
      // initialize() is idempotent — calling it on every session is fine and
      // keeps the failure surface tight (e.g. user revokes speech permission
      // between recordings).
      final ready = await _onDevice.initialize();
      if (!ready) attemptOnDevice = false;
    }
    if (attemptOnDevice) {
      try {
        await _onDevice.startLive(localeId: localeId);
      } catch (e) {
        if (kDebugMode) debugPrint('startLive failed: $e');
        attemptOnDevice = false;
      }
    }
    return LiveRecordingSession._(
      orchestrator: this,
      onDeviceAttempted: attemptOnDevice,
    );
  }
}

/// Live session — kept open for the duration of the user holding/recording.
/// The home screen calls [finish] once the recorder has stopped, passing the
/// WAV path and the recorded duration. The session decides whether to log
/// the on-device result or upload the WAV.
class LiveRecordingSession {
  final SttOrchestrator _orch;
  final bool _onDeviceAttempted;

  LiveRecordingSession._({
    required SttOrchestrator orchestrator,
    required bool onDeviceAttempted,
  })  : _orch = orchestrator,
        _onDeviceAttempted = onDeviceAttempted;

  bool get onDeviceAttempted => _onDeviceAttempted;

  /// Cancels the on-device session without committing anything. Used when
  /// the user long-presses to discard a recording.
  Future<void> cancel() async {
    if (_onDeviceAttempted) {
      try {
        await _orch._onDevice.stopLive();
      } catch (_) {}
    }
  }

  /// Finalizes the session. On a successful on-device result, [wavPath] is
  /// deleted by the caller (we don't upload it). On fallback we hand the
  /// WAV to the server via the existing repository path.
  ///
  /// Returns a record carrying the [Transcription] and whether on-device
  /// served it — the UI uses the flag to show the "via server" chip.
  Future<LiveResult> finish({
    required String wavPath,
    required double durationSeconds,
    required String uiLocale,
    required void Function(int sent, int total)? onSendProgress,
  }) async {
    if (_onDeviceAttempted) {
      final result = await _orch._onDevice.stopLive();
      if (result.success && _passesQualityBar(result, durationSeconds)) {
        try {
          final transcription = await _orch._repo.logClientTranscription(
            text: result.text,
            lang: _langCodeFromLocale(uiLocale),
            langName: _langNameFromLocale(uiLocale),
            durationSeconds: durationSeconds,
            source: 'recording',
            isLiveRecording: true,
            clientEngine: result.engineName,
          );
          return LiveResult(
            transcription: transcription,
            servedByOnDevice: true,
            fallbackReason: null,
          );
        } catch (e) {
          // The on-device text was good but the log endpoint failed — still
          // a win because the user has their text. The repo method already
          // inserted the row locally; just return success.
          if (kDebugMode) debugPrint('client log endpoint failed: $e');
          // We won't fall through to server upload here — uploading the WAV
          // would silently double-bill the user. The text is already saved
          // via the catch block inside logClientTranscription.
          rethrow;
        }
      }
      if (kDebugMode) {
        debugPrint('on-device STT below quality bar, falling back. '
            'reason=${result.failureReason ?? "low_quality"} '
            'len=${result.text.length} conf=${result.confidence}');
      }
    }
    // Fallback: upload the WAV.
    final transcription = await _orch._repo.transcribeFile(
      wavPath,
      source: 'recorded',
      isLiveRecording: true,
      onSendProgress: onSendProgress,
    );
    return LiveResult(
      transcription: transcription,
      servedByOnDevice: false,
      fallbackReason: _onDeviceAttempted ? 'low_quality' : 'disabled',
    );
  }

  bool _passesQualityBar(OnDeviceSttResult r, double durSec) {
    // Defer to the concrete impl's gate — it knows iOS vs Android quirks.
    final impl = _orch._onDevice;
    if (impl is SpeechToTextOnDeviceStt) {
      return impl.meetsQualityBar(r.text, r.confidence, durSec);
    }
    // Generic fallback gate.
    final trimmed = r.text.trim();
    if (trimmed.isEmpty) return false;
    if (Platform.isIOS) return r.confidence >= 0.55;
    return trimmed.length >= 8;
  }
}

class LiveResult {
  final Transcription transcription;
  final bool servedByOnDevice;
  final String? fallbackReason;

  const LiveResult({
    required this.transcription,
    required this.servedByOnDevice,
    required this.fallbackReason,
  });
}

String _langCodeFromLocale(String? uiLocale) {
  final code = (uiLocale ?? 'ar').toLowerCase();
  if (code.startsWith('en')) return 'en';
  return 'ar';
}

String _langNameFromLocale(String? uiLocale) {
  return _langCodeFromLocale(uiLocale) == 'en' ? 'English' : 'Arabic';
}

final sttOrchestratorProvider = Provider<SttOrchestrator>((ref) {
  return SttOrchestrator(
    ref.read(onDeviceSttProvider),
    ref.read(transcriptionRepoProvider),
  );
});
