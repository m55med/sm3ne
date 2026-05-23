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

  /// Files (uploaded or shared) go straight to the server. See class
  /// docstring for the reasoning. Returns a [Transcription] just like the
  /// repository would.
  Future<Transcription> transcribeFile(
    String filePath, {
    required String source,
    String? sourceApp,
    bool isLiveRecording = false,
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
  }) {
    return _repo.transcribeFile(
      filePath,
      source: source,
      sourceApp: sourceApp,
      isLiveRecording: isLiveRecording,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
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
