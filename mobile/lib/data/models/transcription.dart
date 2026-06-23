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
  // Engine that produced the text. 'client_side' means on-device STT (no
  // audio uploaded). Anything else (whisper/gemini/null) means the server
  // ran the transcription. Drives the "via server" chip on the result sheet.
  final String? providerUsed;
  // True for rows rebuilt from the server's metadata-only history after a
  // reinstall. These carry no transcript text (the server never stored it),
  // so the UI shows a "السجل مستعاد — النص غير محفوظ على الخادم" hint instead
  // of an empty body.
  final bool isRestored;
  // Cached Arabic translation of [text], produced on demand by the server
  // translate endpoint. Cached locally so re-opening the result never re-charges
  // a daily credit. Null until the user taps "ترجمة" at least once.
  final String? translation;

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
    this.providerUsed,
    this.isRestored = false,
    this.translation,
  });

  bool get isClientSide => providerUsed == 'client_side';

  /// Returns a copy of this row carrying the local sqflite [id]. Used right
  /// after a DAO insert so callers (e.g. the share sheet's "فتح في بصوتك")
  /// can navigate to the freshly persisted detail screen by id.
  Transcription withId(int id) => Transcription(
        id: id,
        serverRequestId: serverRequestId,
        text: text,
        language: language,
        languageName: languageName,
        duration: duration,
        wordCount: wordCount,
        charCount: charCount,
        wasTrimmed: wasTrimmed,
        segmentsJson: segmentsJson,
        source: source,
        sourceApp: sourceApp,
        originalFilename: originalFilename,
        createdAt: createdAt,
        providerUsed: providerUsed,
        isRestored: isRestored,
        translation: translation,
      );

  /// Returns a copy carrying a cached Arabic [translation]. Used after the
  /// translate endpoint succeeds so the result screen can render and persist it.
  Transcription withTranslation(String translation) => Transcription(
        id: id,
        serverRequestId: serverRequestId,
        text: text,
        language: language,
        languageName: languageName,
        duration: duration,
        wordCount: wordCount,
        charCount: charCount,
        wasTrimmed: wasTrimmed,
        segmentsJson: segmentsJson,
        source: source,
        sourceApp: sourceApp,
        originalFilename: originalFilename,
        createdAt: createdAt,
        providerUsed: providerUsed,
        isRestored: isRestored,
        translation: translation,
      );

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
      providerUsed: json['provider_used'],
      // Always store timestamps in UTC. The UI converts back via
      // .toLocal() when rendering — that way the row keeps its meaning
      // even if the user switches timezones between creating and viewing.
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Rebuilds a [Transcription] from a server history row returned by
  /// `GET /profile/transcriptions`. The server never stores the transcript
  /// text, so [text] is left empty and [isRestored] is set — the UI renders a
  /// "history restored, text not kept on server" hint instead of a blank body.
  ///
  /// Maps the backend's canonical sources (`recording`/`upload`/`share`/`api`)
  /// onto the local labels the list screen already understands.
  factory Transcription.fromHistoryJson(Map<String, dynamic> json) {
    final lang = (json['language'] ?? '').toString();
    return Transcription(
      serverRequestId: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}'),
      text: '',
      language: lang,
      languageName: _languageNameFor(lang),
      duration: (json['duration_seconds'] ?? 0).toDouble(),
      wordCount: json['word_count'] ?? 0,
      // The server never stores the transcript text or its character count, so
      // restored rows have no char count. UI that surfaces charCount should
      // guard on isRestored rather than treating 0 as a real value.
      charCount: 0,
      wasTrimmed: json['was_trimmed'] == true,
      source: _localSourceFor(json['source']?.toString(), json['is_live_recording'] == true),
      createdAt: _normalizeCreatedAt(json['created_at']),
      providerUsed: json['provider_used']?.toString(),
      isRestored: true,
    );
  }

  /// Server timestamps arrive as ISO-8601 (with tz offset). Normalize to a
  /// UTC ISO string so it matches the convention used by locally created rows
  /// (`DateTime.now().toUtc().toIso8601String()`) and sorts/formats the same.
  static String _normalizeCreatedAt(dynamic raw) {
    if (raw == null) return DateTime.now().toUtc().toIso8601String();
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return DateTime.now().toUtc().toIso8601String();
    return parsed.toUtc().toIso8601String();
  }

  static String _localSourceFor(String? serverSource, bool isLive) {
    if (isLive) return 'recorded';
    switch (serverSource) {
      case 'recording':
        return 'recorded';
      case 'share':
        return 'shared';
      case 'api':
      case 'upload':
      default:
        return 'uploaded';
    }
  }

  static String _languageNameFor(String code) {
    final c = code.toLowerCase();
    if (c.startsWith('ar')) return 'العربية';
    if (c.startsWith('en')) return 'English';
    if (c.startsWith('fr')) return 'Français';
    if (c.startsWith('es')) return 'Español';
    if (c.startsWith('de')) return 'Deutsch';
    if (c.startsWith('tr')) return 'Türkçe';
    if (c.isEmpty) return '—';
    return code;
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
      'provider_used': providerUsed,
      'is_restored': isRestored ? 1 : 0,
      'translation': translation,
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
      providerUsed: map['provider_used'],
      isRestored: map['is_restored'] == 1,
      translation: map['translation'],
    );
  }
}
