import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/core/services/app_group_bridge.dart';
import 'package:bisawtak/data/local/transcription_dao.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/file_validation.dart';
import 'package:bisawtak/shared/utils/remote_logger.dart';

final transcriptionRepoProvider = Provider<TranscriptionRepository>((ref) {
  return TranscriptionRepository(ref.read(apiClientProvider));
});

/// Monotonic counter pulsed whenever a background history-sync inserts new
/// rows. The transcription list screen watches it and invalidates its own
/// FutureProvider so freshly restored history appears without a manual pull.
final historySyncSignalProvider = StateProvider<int>((ref) => 0);

class TranscriptionRepository {
  final ApiClient _api;
  final TranscriptionDao _dao;

  TranscriptionRepository(this._api, {TranscriptionDao? dao})
      : _dao = dao ?? TranscriptionDao();

  /// Uploads [filePath] to the transcription endpoint.
  ///
  /// Throws [TranscriptionUploadException] if local validation fails. On
  /// server / network errors, throws [TranscriptionUploadException] with a
  /// friendly Arabic message derived from [friendlyErrorMessage].
  Future<Transcription> transcribeFile(
    String filePath, {
    String source = 'uploaded',
    String? sourceApp,
    bool isLiveRecording = false,
    // When true the backend runs a premium "higher quality" pass and bills it
    // at 2× the daily quota (see backend routes/transcribe.py). Used by the
    // share sheet's "الحصول على جودة أعلى" button to re-do a free on-device
    // result through the server.
    bool highQuality = false,
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    // Local validation first — throws TranscriptionUploadException.
    final file = validateAudioFileForUpload(filePath);

    final backendSource = isLiveRecording ? 'recording' : 'upload';
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: p.basename(file.path),
      ),
      'source': backendSource,
      'is_live_recording': isLiveRecording.toString(),
      if (highQuality) 'high_quality': 'true',
    });

    try {
      final resp = await _api.dio.post(
        '/transcribe',
        data: formData,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      final transcription = Transcription.fromApiResponse(
        resp.data,
        source: source,
        sourceApp: sourceApp,
      );
      final localId = await _dao.insert(transcription);
      return transcription.withId(localId);
    } on TranscriptionUploadException {
      rethrow;
    } catch (e) {
      throw TranscriptionUploadException(friendlyErrorMessage(e));
    }
  }

  /// Logs an on-device transcription to the server (metadata only — no audio
  /// is uploaded). The server stores a `provider_used='client_side'` row so
  /// history is preserved without the cost of running Whisper/Gemini.
  ///
  /// Falls back gracefully: if the network or the endpoint is unreachable the
  /// returned [Transcription] still gets cached locally with `serverRequestId`
  /// = null. The caller treats failure as non-fatal because the user already
  /// has their text — we just lose cloud history for that one row.
  Future<Transcription> logClientTranscription({
    required String text,
    required String lang,
    String? langName,
    required double durationSeconds,
    required String source, // 'recording' | 'upload' | 'share'
    required bool isLiveRecording,
    required String clientEngine, // 'apple_speech' | 'android_speech'
    String? sourceApp,
  }) async {
    final localSource = isLiveRecording ? 'recorded' : source;
    Transcription? transcription;
    try {
      final resp = await _api.dio.post(
        '/transcriptions/log',
        data: {
          'text': text,
          'lang': lang,
          if (langName != null) 'lang_name': langName,
          'duration_seconds': durationSeconds,
          'source': source,
          'is_live_recording': isLiveRecording,
          'client_engine': clientEngine,
        },
      );
      transcription = Transcription.fromApiResponse(
        resp.data,
        source: localSource,
        sourceApp: sourceApp,
      );
    } catch (e) {
      // Surface the failure to /diag/log so admin can see WHY the log call
      // dropped — previously we silently fabricated a fake local row, which
      // hid bugs like the `source: 'shared'` vs `'share'` enum mismatch that
      // caused every share-intent on-device transcription to never reach the
      // server. The user's text still survives via the local DAO insert
      // below, but we no longer pretend it's tracked centrally.
      int? status;
      String? respBody;
      if (e is DioException) {
        status = e.response?.statusCode;
        respBody = e.response?.data?.toString();
      }
      RemoteLogger.log(
        'client_log',
        'POST /transcriptions/log FAILED status=$status err=$e '
            'body=${respBody == null ? "null" : respBody.substring(0, respBody.length.clamp(0, 200))}',
      );
      final words = text.trim().isEmpty
          ? 0
          : text.trim().split(RegExp(r'\s+')).length;
      transcription = Transcription(
        serverRequestId: null,
        text: text,
        language: lang,
        languageName: langName ?? lang,
        duration: durationSeconds,
        wordCount: words,
        charCount: text.length,
        wasTrimmed: false,
        source: localSource,
        sourceApp: sourceApp,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        providerUsed: 'client_side',
      );
    }
    // Force provider_used = client_side regardless of what the server
    // echoes back, since this method only runs after on-device success.
    if (transcription.providerUsed != 'client_side') {
      transcription = Transcription(
        id: transcription.id,
        serverRequestId: transcription.serverRequestId,
        text: transcription.text,
        language: transcription.language,
        languageName: transcription.languageName,
        duration: transcription.duration,
        wordCount: transcription.wordCount,
        charCount: transcription.charCount,
        wasTrimmed: transcription.wasTrimmed,
        segmentsJson: transcription.segmentsJson,
        source: transcription.source,
        sourceApp: transcription.sourceApp,
        originalFilename: transcription.originalFilename,
        createdAt: transcription.createdAt,
        providerUsed: 'client_side',
      );
    }
    final localId = await _dao.insert(transcription);
    return transcription.withId(localId);
  }

  Future<List<Transcription>> getLocalTranscriptions() => _dao.getAll();
  Future<List<Transcription>> search(String query) => _dao.search(query);
  Future<void> deleteLocal(int id) => _dao.delete(id);
  Future<void> deleteAllLocal() => _dao.deleteAll();

  /// Flushes on-device transcriptions the iOS Share Extension queued while the
  /// app was closed. Each queued entry is sent to `/transcriptions/log` (so the
  /// server history + admin dashboards stay complete and the row gets a real
  /// server request id) and cached locally. Best-effort: a failed entry is
  /// dropped (the user already saw the text in the share sheet) rather than
  /// retried forever. Returns how many were successfully logged.
  Future<int> flushPendingShareLogs() async {
    final pending = await AppGroupBridge.drainPendingClientLogs();
    if (pending.isEmpty) return 0;
    var logged = 0;
    for (final entry in pending) {
      try {
        final text = (entry['text'] ?? '').toString();
        if (text.trim().isEmpty) continue;
        await logClientTranscription(
          text: text,
          lang: (entry['lang'] ?? 'ar').toString(),
          durationSeconds: (entry['duration_seconds'] ?? 0).toDouble(),
          source: (entry['source'] ?? 'share').toString(),
          isLiveRecording: entry['is_live_recording'] == true,
          clientEngine: (entry['client_engine'] ?? 'apple_speech').toString(),
          sourceApp: entry['source_app']?.toString(),
        );
        logged++;
      } catch (e) {
        RemoteLogger.log('share_flush', 'entry failed: $e');
      }
    }
    return logged;
  }

  /// Pulls the user's request history from the server and merges any rows the
  /// device is missing into the local DB. This is what rebuilds "تسجيلاتي"
  /// after the user deletes and reinstalls the app: the server keeps the
  /// request/event metadata (date, duration, language, word count, source,
  /// request id) — though never the transcript text — so the history reappears
  /// even on a fresh install.
  ///
  /// Idempotent and best-effort: existing rows are skipped (dedup by
  /// `server_request_id`), and any network/auth error is swallowed so a flaky
  /// connection never blocks login or the list screen. Returns how many rows
  /// were newly inserted (0 on failure or when already up to date).
  ///
  /// Paginates defensively up to [maxPages] * 200 = 20k rows so a huge history
  /// can't spin forever; we log a truncation if the cap is hit.
  Future<int> syncHistoryFromServer({int maxPages = 100}) async {
    var totalInserted = 0;
    try {
      const perPage = 200; // server cap
      for (var page = 1; page <= maxPages; page++) {
        final resp = await _api.dio.get(
          '/profile/transcriptions',
          queryParameters: {'page': page, 'per_page': perPage},
        );
        final data = resp.data;
        final items = (data is Map ? data['items'] : null);
        if (items is! List || items.isEmpty) break;

        final rows = items
            .whereType<Map>()
            .map((m) => Transcription.fromHistoryJson(
                  Map<String, dynamic>.from(m),
                ))
            .toList();
        totalInserted += await _dao.mergeHistory(rows);

        if (items.length < perPage) break; // last page
        if (page == maxPages) {
          RemoteLogger.log(
            'history_sync',
            'truncated at maxPages=$maxPages (history larger than ${maxPages * perPage} rows)',
          );
        }
      }
    } catch (e) {
      // Non-fatal: the user keeps whatever is already cached locally.
      RemoteLogger.log('history_sync', 'failed: $e');
    }
    return totalInserted;
  }
}
