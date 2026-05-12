"""AssemblyAI integration.

Flow: upload audio to /v2/upload → POST /v2/transcript with the upload URL →
poll /v2/transcript/{id} until status is 'completed'.
"""
import asyncio

import httpx

from app.core.config import (
    ASSEMBLYAI_API_KEY,
    ASSEMBLYAI_BASE_URL,
    ASSEMBLYAI_LANGUAGE,
    ASSEMBLYAI_MODEL,
    ASSEMBLYAI_POLL_INTERVAL,
    ASSEMBLYAI_TIMEOUT_SECONDS,
)


AVAILABLE_MODELS = [
    {
        "id": "universal",
        "label": "Universal (متعدد اللغات، توصية افتراضية)",
        "description": "يدعم العربية وأكثر من 99 لغة. جودة عالية.",
    },
    {
        "id": "best",
        "label": "Best (أفضل جودة للإنجليزية)",
        "description": "أعلى جودة لكنه إنجليزي بالأساس. للعربية استخدم Universal.",
    },
    {
        "id": "nano",
        "label": "Nano (أسرع وأرخص)",
        "description": "نموذج أصغر، أسرع، وأرخص — جودته أقل قليلاً من Universal.",
    },
]


class AssemblyAIError(RuntimeError):
    pass


def is_configured() -> bool:
    return bool(ASSEMBLYAI_API_KEY)


def default_model() -> str:
    return ASSEMBLYAI_MODEL or AVAILABLE_MODELS[0]["id"]


def _headers() -> dict:
    if not ASSEMBLYAI_API_KEY:
        raise AssemblyAIError("ASSEMBLYAI_API_KEY is not configured")
    return {"Authorization": ASSEMBLYAI_API_KEY}


async def _upload(client: httpx.AsyncClient, path: str) -> str:
    with open(path, "rb") as f:
        resp = await client.post(
            f"{ASSEMBLYAI_BASE_URL}/upload",
            headers={**_headers(), "Content-Type": "application/octet-stream"},
            content=f.read(),
            timeout=300.0,
        )
    if resp.status_code != 200:
        raise AssemblyAIError(f"upload failed [{resp.status_code}]: {resp.text[:300]}")
    upload_url = resp.json().get("upload_url")
    if not upload_url:
        raise AssemblyAIError(f"upload returned no URL: {resp.text[:200]}")
    return upload_url


async def _create_job(
    client: httpx.AsyncClient, audio_url: str, model: str, language: str | None
) -> str:
    body = {
        "audio_url": audio_url,
        "speech_model": model,
    }
    # Universal model auto-detects language; supply it as a hint only for other models.
    if language and model != "universal":
        body["language_code"] = language
    elif language:
        body["language_detection"] = True

    resp = await client.post(
        f"{ASSEMBLYAI_BASE_URL}/transcript",
        headers={**_headers(), "Content-Type": "application/json"},
        json=body,
        timeout=60.0,
    )
    if resp.status_code != 200:
        raise AssemblyAIError(f"create job failed [{resp.status_code}]: {resp.text[:300]}")
    return resp.json()["id"]


async def _wait(client: httpx.AsyncClient, job_id: str) -> dict:
    deadline = asyncio.get_event_loop().time() + ASSEMBLYAI_TIMEOUT_SECONDS
    while True:
        if asyncio.get_event_loop().time() > deadline:
            raise AssemblyAIError(f"job {job_id} timed out")
        resp = await client.get(
            f"{ASSEMBLYAI_BASE_URL}/transcript/{job_id}",
            headers=_headers(),
            timeout=30.0,
        )
        if resp.status_code != 200:
            raise AssemblyAIError(f"poll failed [{resp.status_code}]: {resp.text[:300]}")
        data = resp.json()
        status = data.get("status")
        if status == "completed":
            return data
        if status == "error":
            raise AssemblyAIError(f"transcription error: {data.get('error')}")
        await asyncio.sleep(ASSEMBLYAI_POLL_INTERVAL)


def _to_whisper_dict(payload: dict) -> dict:
    """Map AssemblyAI's transcript shape into our Whisper-compatible dict.
    Words come in payload.words; we group them into pseudo-segments by sentence-
    ending punctuation, mirroring how we treat Speechmatics output.
    """
    text = (payload.get("text") or "").strip()
    language = (payload.get("language_code") or "unknown").lower()
    if "_" in language:
        language = language.split("_")[0]

    words_in = payload.get("words") or []
    segments = []
    cur_words: list[dict] = []
    cur_start: float | None = None
    cur_end = 0.0
    seg_id = 0

    def flush():
        nonlocal seg_id, cur_words, cur_start, cur_end
        if not cur_words:
            return
        seg_text = " ".join(w["word"] for w in cur_words).strip()
        segments.append({
            "id": seg_id,
            "start": cur_start or 0.0,
            "end": cur_end,
            "text": seg_text,
            "words": cur_words,
        })
        seg_id += 1
        cur_words = []
        cur_start = None
        cur_end = 0.0

    sentence_end = {".", "?", "!", "؟"}

    for w in words_in:
        # AssemblyAI gives times in milliseconds.
        start = float(w.get("start", 0)) / 1000.0
        end = float(w.get("end", start * 1000)) / 1000.0
        word = w.get("text") or ""
        if cur_start is None:
            cur_start = start
        cur_end = max(cur_end, end)
        cur_words.append({
            "word": word,
            "start": start,
            "end": end,
            "probability": float(w.get("confidence", 0.0)),
        })
        if word and word[-1] in sentence_end:
            flush()
    flush()

    # If they didn't supply word-level timings (rare), fall back to a single big segment.
    if not segments and text:
        duration = (payload.get("audio_duration") or 0.0)
        segments = [{
            "id": 0,
            "start": 0.0,
            "end": float(duration),
            "text": text,
            "words": [],
        }]

    return {"text": text, "language": language, "segments": segments}


async def transcribe_from_path(
    path: str, model: str | None = None, language: str | None = None
) -> dict:
    chosen_model = model or default_model()
    lang = language or ASSEMBLYAI_LANGUAGE

    async with httpx.AsyncClient() as client:
        audio_url = await _upload(client, path)
        job_id = await _create_job(client, audio_url, chosen_model, lang)
        result = await _wait(client, job_id)
    return _to_whisper_dict(result)
