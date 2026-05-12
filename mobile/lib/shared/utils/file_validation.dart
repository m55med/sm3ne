import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:bisawtak/config/constants.dart';

/// Typed exception thrown when an upload candidate fails validation.
class TranscriptionUploadException implements Exception {
  final String message;
  final String? code;
  const TranscriptionUploadException(this.message, {this.code});

  @override
  String toString() => 'TranscriptionUploadException($code): $message';
}

/// Validates the file at [path] for upload to the transcription API.
///
/// Throws [TranscriptionUploadException] with an Arabic message on any failure.
/// Returns the validated `File` if all checks pass.
File validateAudioFileForUpload(String path) {
  if (path.isEmpty) {
    throw const TranscriptionUploadException(
      'الملف غير صالح.',
      code: 'empty_path',
    );
  }

  final file = File(path);
  if (!file.existsSync()) {
    throw const TranscriptionUploadException(
      'تعذّر العثور على الملف.',
      code: 'file_not_found',
    );
  }

  final size = file.lengthSync();
  if (size <= 0) {
    throw const TranscriptionUploadException(
      'الملف فارغ.',
      code: 'empty_file',
    );
  }
  if (size > AppConstants.maxUploadBytes) {
    throw const TranscriptionUploadException(
      'الملف كبير جداً. الحد الأقصى المسموح به للرفع هو 200 ميغابايت.',
      code: 'file_too_large',
    );
  }

  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (!AppConstants.allowedAudioExtensions.contains(ext)) {
    throw const TranscriptionUploadException(
      'صيغة الملف غير مدعومة. الصيغ المسموحة: m4a, mp3, wav, ogg, opus, aac, flac, webm, mp4.',
      code: 'unsupported_extension',
    );
  }

  return file;
}
