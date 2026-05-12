"""Google Gemini integration for audio transcription.

Gemini is multimodal — it can transcribe audio inline as part of a
`generateContent` call. Compared to dedicated ASR providers:
  - Pricing is per-token (very cheap for short clips, generous free tier).
  - It returns plain text by default, NOT word-level timestamps.

For audio ≤ INLINE_MAX_BYTES the file is sent base64-inline. Larger files use
the Files API (upload → reference by URI in the generate call).
"""
import asyncio
import base64
import os
import mimetypes

import httpx

from app.core.config import (
    GEMINI_API_KEY,
    GEMINI_BASE_URL,
    GEMINI_INLINE_MAX_BYTES,
    GEMINI_LANGUAGE_HINT,
    GEMINI_MODEL,
)


class GeminiError(RuntimeError):
    pass


AVAILABLE_MODELS = [
    {
        "id": "gemini-flash-latest",
        "label": "Gemini 2.5 Flash (سريع، الافتراضي)",
        "description": "أسرع نسخة، أرخص، جودة جيدة جداً للتفريغ.",
    },
    {
        "id": "gemini-flash-lite-latest",
        "label": "Gemini Flash Lite (الأرخص)",
        "description": "أصغر وأرخص نموذج، مناسب للمهام البسيطة.",
    },
    {
        "id": "gemini-pro-latest",
        "label": "Gemini 2.5 Pro (أعلى جودة، أبطأ)",
        "description": "أعلى جودة وفهم سياقي، أبطأ وأغلى.",
    },
]


def default_model() -> str:
    return GEMINI_MODEL or AVAILABLE_MODELS[0]["id"]


_AUDIO_MIME_FALLBACK = {
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".m4a": "audio/mp4",
    ".mp4": "audio/mp4",
    ".aac": "audio/aac",
    ".ogg": "audio/ogg",
    ".flac": "audio/flac",
    ".webm": "audio/webm",
    ".wma": "audio/x-ms-wma",
}


def is_configured() -> bool:
    return bool(GEMINI_API_KEY)


def _headers() -> dict:
    if not GEMINI_API_KEY:
        raise GeminiError("GEMINI_API_KEY is not configured")
    return {"X-goog-api-key": GEMINI_API_KEY, "Content-Type": "application/json"}


def _guess_mime(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    return _AUDIO_MIME_FALLBACK.get(ext) or mimetypes.guess_type(path)[0] or "audio/mpeg"


def _build_prompt(language: str | None) -> str:
    lang = language or GEMINI_LANGUAGE_HINT
    return (
        f"Transcribe the following audio verbatim. The spoken language is '{lang}'. "
        "Return ONLY the transcribed text — no preamble, no explanation, no quotes, "
        "no formatting. If the audio is silent or unintelligible, return an empty string."
    )


async def _upload_via_files_api(client: httpx.AsyncClient, path: str, mime: str) -> str:
    """Upload audio via the resumable Files API and return its `file.uri`."""
    size = os.path.getsize(path)
    filename = os.path.basename(path)

    # 1) Start an upload session — server returns a resumable upload URL via header.
    start = await client.post(
        f"{GEMINI_BASE_URL}/files",
        headers={
            **_headers(),
            "X-Goog-Upload-Protocol": "resumable",
            "X-Goog-Upload-Command": "start",
            "X-Goog-Upload-Header-Content-Length": str(size),
            "X-Goog-Upload-Header-Content-Type": mime,
        },
        json={"file": {"display_name": filename}},
        timeout=60.0,
    )
    if start.status_code >= 400:
        raise GeminiError(f"Files API start failed [{start.status_code}]: {start.text[:300]}")
    upload_url = start.headers.get("x-goog-upload-url") or start.headers.get("X-Goog-Upload-URL")
    if not upload_url:
        raise GeminiError("Files API start did not return upload URL")

    # 2) Upload the bytes and finalize in one go.
    with open(path, "rb") as f:
        data = f.read()
    finalize = await client.post(
        upload_url,
        headers={
            "Content-Length": str(size),
            "X-Goog-Upload-Offset": "0",
            "X-Goog-Upload-Command": "upload, finalize",
        },
        content=data,
        timeout=300.0,
    )
    if finalize.status_code >= 400:
        raise GeminiError(f"Files API upload failed [{finalize.status_code}]: {finalize.text[:300]}")
    body = finalize.json()
    file_uri = body.get("file", {}).get("uri")
    if not file_uri:
        raise GeminiError(f"Files API upload returned no URI: {body}")

    # 3) Wait until the file is processed (state == ACTIVE).
    name = body["file"]["name"]
    for _ in range(60):
        s = await client.get(f"{GEMINI_BASE_URL}/{name}", headers=_headers(), timeout=15.0)
        state = s.json().get("file", {}).get("state") or s.json().get("state")
        if state == "ACTIVE":
            return file_uri
        if state in ("FAILED", "ERROR"):
            raise GeminiError(f"Files API processing failed: {s.text[:300]}")
        await asyncio.sleep(1.0)
    raise GeminiError("Files API processing timed out")


def _to_whisper_dict(text: str, language: str | None, duration: float) -> dict:
    """Wrap Gemini's plain-text output in the Whisper-shaped dict the rest of
    the pipeline expects. Word timings aren't available, so we emit a single
    catch-all segment spanning the audio.
    """
    text = (text or "").strip()
    lang = (language or GEMINI_LANGUAGE_HINT or "unknown").lower()
    segments = []
    if text:
        segments.append({
            "id": 0,
            "start": 0.0,
            "end": round(duration, 2),
            "text": text,
            "words": [],  # not provided by Gemini
        })
    return {"text": text, "language": lang, "segments": segments}


async def transcribe_from_path(
    path: str,
    model: str | None = None,
    language: str | None = None,
    duration: float = 0.0,
) -> dict:
    mime = _guess_mime(path)
    size = os.path.getsize(path)
    if size <= 0:
        raise GeminiError("Audio file is empty")
    prompt = _build_prompt(language)
    chosen_model = model or default_model()

    # The GEMINI_INLINE_MAX_BYTES env var draws the line between an inline
    # base64 payload (fast, single round-trip) and the resumable Files API
    # (which can handle gigabytes). We NEVER truncate — if a future code path
    # tried to it would be a regression, so the size check below is explicit.
    default_timeout = httpx.Timeout(30.0, read=60.0)
    async with httpx.AsyncClient(timeout=default_timeout) as client:
        if size <= GEMINI_INLINE_MAX_BYTES:
            with open(path, "rb") as f:
                audio_b64 = base64.b64encode(f.read()).decode("ascii")
            parts = [
                {"inline_data": {"mime_type": mime, "data": audio_b64}},
                {"text": prompt},
            ]
        else:
            file_uri = await _upload_via_files_api(client, path, mime)
            parts = [
                {"file_data": {"mime_type": mime, "file_uri": file_uri}},
                {"text": prompt},
            ]

        body = {
            "contents": [{"parts": parts}],
            "generationConfig": {"temperature": 0, "responseMimeType": "text/plain"},
        }
        resp = await client.post(
            f"{GEMINI_BASE_URL}/models/{chosen_model}:generateContent",
            headers=_headers(),
            json=body,
            timeout=300.0,
        )

    if resp.status_code != 200:
        raise GeminiError(f"generateContent failed [{resp.status_code}]: {resp.text[:400]}")

    data = resp.json()
    try:
        candidate = data["candidates"][0]
        parts_out = candidate["content"]["parts"]
        text = "".join(p.get("text", "") for p in parts_out)
    except (KeyError, IndexError, TypeError) as e:
        raise GeminiError(f"Unexpected Gemini response shape: {data}") from e

    return _to_whisper_dict(text, language, duration)
