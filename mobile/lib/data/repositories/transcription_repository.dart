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

  Future<List<Transcription>> getLocalTranscriptions() => _dao.getAll();
  Future<List<Transcription>> search(String query) => _dao.search(query);
  Future<void> deleteLocal(int id) => _dao.delete(id);
  Future<void> deleteAllLocal() => _dao.deleteAll();
}
