import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bisawtak/core/api/api_client.dart';
import 'package:bisawtak/data/local/transcription_dao.dart';
import 'package:bisawtak/data/models/transcription.dart';

final transcriptionRepoProvider = Provider<TranscriptionRepository>((ref) {
  return TranscriptionRepository(ref.read(apiClientProvider));
});

class TranscriptionRepository {
  final ApiClient _api;
  final TranscriptionDao _dao = TranscriptionDao();

  TranscriptionRepository(this._api);

  Future<Transcription> transcribeFile(
    String filePath, {
    String source = 'uploaded',
    String? sourceApp,
    bool isLiveRecording = false,
  }) async {
    final backendSource = isLiveRecording ? 'recording' : 'upload';
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      'source': backendSource,
      'is_live_recording': isLiveRecording.toString(),
    });

    final resp = await _api.dio.post('/transcribe', data: formData);
    final transcription = Transcription.fromApiResponse(
      resp.data,
      source: source,
      sourceApp: sourceApp,
    );

    // Save locally
    await _dao.insert(transcription);
    return transcription;
  }

  Future<List<Transcription>> getLocalTranscriptions() => _dao.getAll();
  Future<List<Transcription>> search(String query) => _dao.search(query);
  Future<void> deleteLocal(int id) => _dao.delete(id);
}
