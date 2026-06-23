"""Post-processing helpers that turn a raw Whisper-style transcription dict
into the public API response shape: language name resolution, punctuation
counts, segment normalization, and overall stats (char/word/segment counts).

Provider-specific code lives elsewhere (gemini_service, groq_service, ...);
this module is provider-agnostic and only consumes the normalized dict shape.
"""

import re
from collections import Counter


# Stopwords for top-word ranking — covers the highest-frequency function words
# in the two languages that dominate Bisawtak usage. Not exhaustive; intent is
# to keep "في", "من", "the", "and" etc. from drowning out content words.
_AR_STOPWORDS = {
    "في", "من", "الى", "إلى", "على", "عن", "هذا", "هذه", "ذلك", "تلك",
    "ان", "أن", "إن", "هو", "هي", "هم", "هن", "نحن", "انت", "أنت", "انا",
    "أنا", "ما", "لا", "لم", "لن", "كان", "كانت", "يكون", "تكون", "قد",
    "كل", "بعض", "لكن", "أو", "او", "ثم", "أيضا", "أيضًا", "حتى", "إذا",
    "اذا", "كما", "بين", "عند", "عنده", "كذلك", "هنا", "هناك", "بعد", "قبل",
    "مع", "غير", "بدون", "اي", "أي", "ال",
}
_EN_STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "if", "to", "of", "in", "on",
    "at", "for", "with", "by", "from", "is", "are", "was", "were", "be",
    "been", "being", "have", "has", "had", "do", "does", "did", "that",
    "this", "these", "those", "it", "its", "as", "i", "you", "he", "she",
    "we", "they", "his", "her", "their", "my", "your", "our", "not", "so",
    "no", "yes", "ok",
}
_STOPWORDS = _AR_STOPWORDS | _EN_STOPWORDS

# Word boundary that respects Arabic and Latin scripts but drops punctuation.
_WORD_RE = re.compile(r"[\w؀-ۿݐ-ݿ]+", re.UNICODE)
# Sentence boundary: Western or Arabic terminator, optionally followed by space.
_SENTENCE_SPLIT_RE = re.compile(r"[\.!\?؟۔]+\s*")

# Full Whisper language set (ISO 639-1 code → English name). Auto-detection can
# return ANY of these, so the map is comprehensive — both to display a proper
# name and to reverse full-name detections (e.g. Groq's "azerbaijani") back to a
# short code that fits the VARCHAR(10) `language` column.
LANG_NAMES = {
    "en": "English", "zh": "Chinese", "de": "German", "es": "Spanish",
    "ru": "Russian", "ko": "Korean", "fr": "French", "ja": "Japanese",
    "pt": "Portuguese", "tr": "Turkish", "pl": "Polish", "ca": "Catalan",
    "nl": "Dutch", "ar": "Arabic", "sv": "Swedish", "it": "Italian",
    "id": "Indonesian", "hi": "Hindi", "fi": "Finnish", "vi": "Vietnamese",
    "he": "Hebrew", "uk": "Ukrainian", "el": "Greek", "ms": "Malay",
    "cs": "Czech", "ro": "Romanian", "da": "Danish", "hu": "Hungarian",
    "ta": "Tamil", "no": "Norwegian", "th": "Thai", "ur": "Urdu",
    "hr": "Croatian", "bg": "Bulgarian", "lt": "Lithuanian", "la": "Latin",
    "mi": "Maori", "ml": "Malayalam", "cy": "Welsh", "sk": "Slovak",
    "te": "Telugu", "fa": "Persian", "lv": "Latvian", "bn": "Bengali",
    "sr": "Serbian", "az": "Azerbaijani", "sl": "Slovenian", "kn": "Kannada",
    "et": "Estonian", "mk": "Macedonian", "br": "Breton", "eu": "Basque",
    "is": "Icelandic", "hy": "Armenian", "ne": "Nepali", "mn": "Mongolian",
    "bs": "Bosnian", "kk": "Kazakh", "sq": "Albanian", "sw": "Swahili",
    "gl": "Galician", "mr": "Marathi", "pa": "Punjabi", "si": "Sinhala",
    "km": "Khmer", "sn": "Shona", "yo": "Yoruba", "so": "Somali",
    "af": "Afrikaans", "oc": "Occitan", "ka": "Georgian", "be": "Belarusian",
    "tg": "Tajik", "sd": "Sindhi", "gu": "Gujarati", "am": "Amharic",
    "yi": "Yiddish", "lo": "Lao", "uz": "Uzbek", "fo": "Faroese",
    "ht": "Haitian Creole", "ps": "Pashto", "tk": "Turkmen", "nn": "Nynorsk",
    "mt": "Maltese", "sa": "Sanskrit", "lb": "Luxembourgish", "my": "Myanmar",
    "bo": "Tibetan", "tl": "Tagalog", "mg": "Malagasy", "as": "Assamese",
    "tt": "Tatar", "haw": "Hawaiian", "ln": "Lingala", "ha": "Hausa",
    "ba": "Bashkir", "jw": "Javanese", "su": "Sundanese", "yue": "Cantonese",
}


# Reverse lookup: full English language name (lowercased) → ISO 639-1 code.
# Whisper/Groq verbose_json returns the DETECTED language as a full name
# ("english", "arabic", "french") rather than a code, so we normalize it back
# to a code for consistent storage, admin filtering, and lang_name display.
_NAME_TO_CODE = {name.lower(): code for code, name in LANG_NAMES.items()}


def to_iso_code(language: str | None) -> str:
    """Normalize any provider's language value to a lowercase ISO 639-1 code.

    Handles three shapes providers return:
      * already a code ("ar", "en")            → unchanged
      * a full English name ("arabic", "english") → mapped via _NAME_TO_CODE
      * a code with a region/script suffix ("en_us", "ar-EG") → base code

    Unknown values fall through lowercased so nothing is silently dropped.
    """
    if not language:
        return "unknown"
    v = language.strip().lower()
    if not v or v == "auto":
        return "unknown"
    if v in LANG_NAMES:  # already a known code
        return v
    if v in _NAME_TO_CODE:  # a full English name
        return _NAME_TO_CODE[v]
    # Strip a region/script suffix like en_us / ar-eg and retry.
    base = re.split(r"[-_]", v, maxsplit=1)[0]
    if base in LANG_NAMES:
        return base
    if base in _NAME_TO_CODE:
        return _NAME_TO_CODE[base]
    # Unknown value — clamp to the DB column width (VARCHAR(10)) so an exotic
    # provider string can never overflow `transcription_requests.language` and
    # 500 the request after a paid transcription already succeeded.
    return (base or "unknown")[:10]


def analyze_punctuation(text: str) -> dict:
    return {
        "comma": text.count(",") + text.count("\u060c"),
        "period": text.count("."),
        "question_mark": text.count("?") + text.count("\u061f"),
        "exclamation_mark": text.count("!"),
        "semicolon": text.count(";") + text.count("\u061b"),
        "colon": text.count(":"),
        "ellipsis": text.count("...") + text.count("\u2026"),
    }


def build_segments(raw_segments: list) -> list:
    segments = []
    for seg in raw_segments:
        segment_data = {
            "id": seg.get("id", 0),
            "start": round(seg.get("start", 0), 2),
            "end": round(seg.get("end", 0), 2),
            "text": seg.get("text", "").strip(),
        }
        if "words" in seg:
            segment_data["words"] = [
                {
                    "word": w.get("word", "").strip(),
                    "start": round(w.get("start", 0), 2),
                    "end": round(w.get("end", 0), 2),
                    "probability": round(w.get("probability", 0), 4),
                }
                for w in seg["words"]
            ]
        segments.append(segment_data)
    return segments


def extended_analysis(text: str, duration_seconds: float = 0.0, top_n: int = 15) -> dict:
    """Linguistic stats beyond the basic build_response output.

    Used by the admin "analyze audio" tool to surface everything we can
    cheaply derive from the transcript: sentence/paragraph structure, word
    length distribution, top content words, and speaking rate.
    """
    words = _WORD_RE.findall(text)
    word_count = len(words)
    word_lengths = [len(w) for w in words]
    avg_word_length = round(sum(word_lengths) / word_count, 2) if word_count else 0.0
    longest_word = max(words, key=len) if words else ""

    sentences = [s.strip() for s in _SENTENCE_SPLIT_RE.split(text) if s.strip()]
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    lines = [ln for ln in text.splitlines() if ln.strip()]

    lowered = [w.lower() for w in words]
    content = [w for w in lowered if len(w) >= 2 and w not in _STOPWORDS]
    top_words = [
        {"word": w, "count": c}
        for w, c in Counter(content).most_common(top_n)
    ]

    speaking_rate_wpm = (
        round(word_count / (duration_seconds / 60.0), 1)
        if duration_seconds and duration_seconds > 0
        else None
    )

    return {
        "word_count": word_count,
        "unique_word_count": len(set(lowered)),
        "avg_word_length": avg_word_length,
        "longest_word": longest_word,
        "sentence_count": len(sentences),
        "paragraph_count": len(paragraphs),
        "line_count": len(lines),
        "speaking_rate_wpm": speaking_rate_wpm,
        "top_words": top_words,
    }


def build_response(result: dict) -> dict:
    text = result.get("text", "").strip()
    # Providers report the detected language in different shapes (ISO code, full
    # name, or code+region). Normalize to a bare ISO 639-1 code so storage,
    # admin filters, and the name lookup below all stay consistent.
    language = to_iso_code(result.get("language"))
    segments = build_segments(result.get("segments", []))

    return {
        "lang": language,
        "lang_name": LANG_NAMES.get(language, language),
        "text": text,
        "char_count": len(text),
        "char_count_no_spaces": len(text.replace(" ", "")),
        "word_count": len(text.split()),
        "segment_count": len(segments),
        "segments": segments,
        "duration": round(segments[-1]["end"], 2) if segments else 0.0,
        "punctuation_count": analyze_punctuation(text),
    }
