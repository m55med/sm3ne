LANG_NAMES = {
    "ar": "Arabic", "en": "English", "fr": "French", "de": "German",
    "es": "Spanish", "it": "Italian", "pt": "Portuguese", "ru": "Russian",
    "zh": "Chinese", "ja": "Japanese", "ko": "Korean", "tr": "Turkish",
    "nl": "Dutch", "pl": "Polish", "sv": "Swedish", "da": "Danish",
    "no": "Norwegian", "fi": "Finnish", "cs": "Czech", "ro": "Romanian",
    "hu": "Hungarian", "el": "Greek", "he": "Hebrew", "hi": "Hindi",
    "th": "Thai", "uk": "Ukrainian", "vi": "Vietnamese", "id": "Indonesian",
    "ms": "Malay", "fa": "Persian", "ur": "Urdu", "bn": "Bengali",
    "ta": "Tamil", "te": "Telugu", "ml": "Malayalam", "sw": "Swahili",
}


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


def build_response(result: dict) -> dict:
    text = result.get("text", "").strip()
    language = result.get("language", "unknown")
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
