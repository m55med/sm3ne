class Transcription {
  final int? id;
  final int? serverRequestId;
  final String text;
  final String language;
  final String languageName;
  final double duration;
  final int wordCount;
  final int charCount;
  final bool wasTrimmed;
  final String? segmentsJson;
  final String source; // 'recorded', 'uploaded', 'shared'
  final String? sourceApp;
  final String? originalFilename;
  final String createdAt;

  Transcription({
    this.id,
    this.serverRequestId,
    required this.text,
    required this.language,
    required this.languageName,
    required this.duration,
    required this.wordCount,
    required this.charCount,
    required this.wasTrimmed,
    this.segmentsJson,
    required this.source,
    this.sourceApp,
    this.originalFilename,
    required this.createdAt,
  });

  factory Transcription.fromApiResponse(Map<String, dynamic> json, {String source = 'uploaded', String? sourceApp}) {
    return Transcription(
      serverRequestId: json['request_id'],
      text: json['text'] ?? '',
      language: json['lang'] ?? '',
      languageName: json['lang_name'] ?? '',
      duration: (json['duration'] ?? 0).toDouble(),
      wordCount: json['word_count'] ?? 0,
      charCount: json['char_count'] ?? 0,
      wasTrimmed: json['was_trimmed'] ?? false,
      segmentsJson: json['segments'] != null ? json['segments'].toString() : null,
      source: source,
      sourceApp: sourceApp,
      originalFilename: null,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'server_request_id': serverRequestId,
      'text': text,
      'language': language,
      'language_name': languageName,
      'duration': duration,
      'word_count': wordCount,
      'char_count': charCount,
      'was_trimmed': wasTrimmed ? 1 : 0,
      'segments_json': segmentsJson,
      'source': source,
      'source_app': sourceApp,
      'original_filename': originalFilename,
      'created_at': createdAt,
    };
  }

  factory Transcription.fromMap(Map<String, dynamic> map) {
    return Transcription(
      id: map['id'],
      serverRequestId: map['server_request_id'],
      text: map['text'] ?? '',
      language: map['language'] ?? '',
      languageName: map['language_name'] ?? '',
      duration: (map['duration'] ?? 0).toDouble(),
      wordCount: map['word_count'] ?? 0,
      charCount: map['char_count'] ?? 0,
      wasTrimmed: map['was_trimmed'] == 1,
      segmentsJson: map['segments_json'],
      source: map['source'] ?? 'uploaded',
      sourceApp: map['source_app'],
      originalFilename: map['original_filename'],
      createdAt: map['created_at'] ?? '',
    );
  }
}
