"""Groq Whisper integration.

Groq runs Whisper on their custom LPU hardware — same OpenAI-compatible
`/audio/transcriptions` endpoint shape, but 10-30x faster than self-hosted
Whisper. Output is `verbose_json` which carries segments and durations.
"""
import os

import httpx

from app.core.config import (
    GROQ_API_KEY,
    GROQ_BASE_URL,
    GROQ_MODEL,
    GROQ_LANGUAGE,
)


# Models Groq currently exposes via the audio API. Keep this list maintained as
# Groq changes their lineup — the admin UI will read it to populate a dropdown.
AVAILABLE_MODELS = [
    {
        "id": "whisper-large-v3",
        "label": "Whisper Large v3 (أفضل جودة)",
        "description": "أعلى جودة، الأبطأ نسبياً — ممتاز للعربية والمهمات الصعبة.",
    },
    {
        "id": "whisper-large-v3-turbo",
        "label": "Whisper Large v3 Turbo (سريع)",
        "description": "أسرع بكتير من v3 العادي، جودة قريبة جداً منه. توصية افتراضية.",
    },
    {
        "id": "distil-whisper-large-v3-en",
        "label": "Distil Whisper v3 (إنجليزي فقط، الأسرع)",
        "description": "أسرع شيء، لكنه يدعم الإنجليزية فقط.",
    },
]


class GroqError(RuntimeError):
    pass


def is_configured() -> bool:
    return bool(GROQ_API_KEY)


def default_model() -> str:
    return GROQ_MODEL or AVAILABLE_MODELS[1]["id"]


def _headers() -> dict:
    if not GROQ_API_KEY:
        raise GroqError("GROQ_API_KEY is not configured")
    return {"Authorization": f"Bearer {GROQ_API_KEY}"}


def _to_whisper_dict(payload: dict) -> dict:
    """Groq returns a verbose_json response that's already Whisper-shaped —
    we just normalize the segment word timings into our expected schema."""
    segments_in = payload.get("segments") or []
    segments_out = []
    for seg in segments_in:
        words_out = []
        for w in seg.get("words") or []:
            words_out.append({
                "word": w.get("word", ""),
                "start": float(w.get("start", 0.0)),
                "end": float(w.get("end", 0.0)),
                "probability": float(w.get("probability", w.get("confidence", 0.0))),
            })
        segments_out.append({
            "id": seg.get("id", len(segments_out)),
            "start": float(seg.get("start", 0.0)),
            "end": float(seg.get("end", 0.0)),
            "text": seg.get("text", "").strip(),
            "words": words_out,
        })

    return {
        "text": (payload.get("text") or "").strip(),
        "language": payload.get("language", "unknown"),
        "segments": segments_out,
    }


async def transcribe_from_path(
    path: str, model: str | None = None, language: str | None = None
) -> dict:
    filename = os.path.basename(path)
    chosen_model = model or default_model()
    lang = language or GROQ_LANGUAGE

    data = {
        "model": chosen_model,
        "response_format": "verbose_json",
        "timestamp_granularities[]": "segment",
    }
    if lang:
        data["language"] = lang

    with open(path, "rb") as f:
        files = {"file": (filename, f, "application/octet-stream")}
        async with httpx.AsyncClient(timeout=300.0) as client:
            resp = await client.post(
                f"{GROQ_BASE_URL}/audio/transcriptions",
                headers=_headers(),
                data=data,
                files=files,
            )

    if resp.status_code != 200:
        raise GroqError(f"transcription failed [{resp.status_code}]: {resp.text[:400]}")
    return _to_whisper_dict(resp.json())
