import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/data/local/transcription_dao.dart';
import 'package:bisawtak/data/models/transcription.dart';
import 'package:bisawtak/shared/utils/error_messages.dart';
import 'package:bisawtak/shared/utils/file_validation.dart';

final transcriptionRepoProvider = Provider<TranscriptionRepository>((ref) {
  return TranscriptionRepository(ref.read(apiClientProvider));
});

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
      await _dao.insert(transcription);
      return transcription;
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
    } catch (_) {
      // Server-side history sync is best-effort. The user already got their
      // text on-device; losing the cloud row is preferable to bubbling an
      // error up and making them think the transcription failed.
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
    await _dao.insert(transcription);
    return transcription;
  }

  Future<List<Transcription>> getLocalTranscriptions() => _dao.getAll();
  Future<List<Transcription>> search(String query) => _dao.search(query);
  Future<void> deleteLocal(int id) => _dao.delete(id);
  Future<void> deleteAllLocal() => _dao.deleteAll();
}
