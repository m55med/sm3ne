"""Speechmatics Batch ASR integration.

Submits an audio file to Speechmatics, polls for completion, fetches the
json-v2 transcript, and maps it into the same shape `text_analyzer.build_response`
expects (the Whisper-style dict with `text`, `language`, and `segments`).
"""
import asyncio
import json
import os
from typing import Any

import httpx

from app.core.config import (
    SPEECHMATICS_API_KEY,
    SPEECHMATICS_BASE_URL,
    SPEECHMATICS_LANGUAGE,
    SPEECHMATICS_OPERATING_POINT,
    SPEECHMATICS_POLL_INTERVAL,
    SPEECHMATICS_TIMEOUT_SECONDS,
)


class SpeechmaticsError(RuntimeError):
    pass


# Punctuation marks that should close the current segment.
_SENTENCE_END = {".", "?", "!", "؟", "…"}


def _auth_headers() -> dict:
    if not SPEECHMATICS_API_KEY:
        raise SpeechmaticsError("SP API key is not configured")
    return {"Authorization": f"Bearer {SPEECHMATICS_API_KEY}"}


def _job_config(language: str | None) -> dict:
    return {
        "type": "transcription",
        "transcription_config": {
            "language": (language or SPEECHMATICS_LANGUAGE),
            "operating_point": SPEECHMATICS_OPERATING_POINT,
            "diarization": "none",
            "enable_entities": True,
        },
    }


async def _submit_job(client: httpx.AsyncClient, path: str, language: str | None) -> str:
    filename = os.path.basename(path)
    with open(path, "rb") as f:
        files = {
            "config": (None, json.dumps(_job_config(language)), "application/json"),
            "data_file": (filename, f, "application/octet-stream"),
        }
        resp = await client.post(
            f"{SPEECHMATICS_BASE_URL}/jobs",
            headers=_auth_headers(),
            files=files,
            timeout=120.0,
        )
    if resp.status_code != 201:
        raise SpeechmaticsError(f"submit failed [{resp.status_code}]: {resp.text[:300]}")
    data = resp.json()
    job_id = data.get("id")
    if not job_id:
        raise SpeechmaticsError(f"no job id in response: {data}")
    return job_id


async def _wait_for_job(client: httpx.AsyncClient, job_id: str) -> dict:
    deadline = asyncio.get_event_loop().time() + SPEECHMATICS_TIMEOUT_SECONDS
    while True:
        if asyncio.get_event_loop().time() > deadline:
            raise SpeechmaticsError(f"job {job_id} timed out after {SPEECHMATICS_TIMEOUT_SECONDS}s")
        resp = await client.get(
            f"{SPEECHMATICS_BASE_URL}/jobs/{job_id}",
            headers=_auth_headers(),
            timeout=30.0,
        )
        if resp.status_code != 200:
            raise SpeechmaticsError(f"status failed [{resp.status_code}]: {resp.text[:300]}")
        job = resp.json().get("job", {})
        status = job.get("status")
        if status == "done":
            return job
        if status in ("rejected", "deleted", "expired"):
            errors = job.get("errors") or job.get("error") or "unknown reason"
            raise SpeechmaticsError(f"job {job_id} ended as {status}: {errors}")
        await asyncio.sleep(SPEECHMATICS_POLL_INTERVAL)


async def _fetch_transcript(client: httpx.AsyncClient, job_id: str) -> dict:
    resp = await client.get(
        f"{SPEECHMATICS_BASE_URL}/jobs/{job_id}/transcript",
        headers=_auth_headers(),
        params={"format": "json-v2"},
        timeout=60.0,
    )
    if resp.status_code != 200:
        raise SpeechmaticsError(f"transcript fetch failed [{resp.status_code}]: {resp.text[:300]}")
    return resp.json()


def _to_whisper_dict(transcript: dict) -> dict:
    """Map Speechmatics json-v2 → the dict shape `build_response` expects.

    Segments are split on sentence-ending punctuation or on a >2s silence gap,
    so the downstream consumer sees natural-looking segments with word timings.
    """
    metadata = transcript.get("metadata", {}) or {}
    tc = metadata.get("transcription_config", {}) or {}
    language = tc.get("language", "unknown")

    results: list[dict[str, Any]] = transcript.get("results") or []

    segments: list[dict] = []
    cur_words: list[dict] = []
    cur_text_parts: list[str] = []
    cur_start: float | None = None
    cur_end: float = 0.0
    last_word_end: float | None = None
    seg_id = 0

    def flush():
        nonlocal seg_id, cur_words, cur_text_parts, cur_start, cur_end
        if not cur_words and not cur_text_parts:
            return
        segments.append({
            "id": seg_id,
            "start": cur_start or 0.0,
            "end": cur_end,
            "text": "".join(cur_text_parts).strip(),
            "words": cur_words,
        })
        seg_id += 1
        cur_words = []
        cur_text_parts = []
        cur_start = None
        cur_end = 0.0

    for item in results:
        alts = item.get("alternatives") or []
        if not alts:
            continue
        alt = alts[0]
        content = alt.get("content", "")
        confidence = alt.get("confidence", 0.0)
        start_time = float(item.get("start_time", 0.0))
        end_time = float(item.get("end_time", start_time))
        itype = item.get("type", "word")

        # Silence-gap break (only between words, not on attached punctuation)
        if (
            itype == "word"
            and last_word_end is not None
            and start_time - last_word_end > 2.0
            and (cur_words or cur_text_parts)
        ):
            flush()

        if itype == "word":
            if cur_start is None:
                cur_start = start_time
            # Add a leading space between words (skip before the very first word in a segment).
            if cur_text_parts and not cur_text_parts[-1].endswith(" "):
                cur_text_parts.append(" ")
            cur_text_parts.append(content)
            cur_words.append({
                "word": content,
                "start": start_time,
                "end": end_time,
                "probability": confidence,
            })
            cur_end = max(cur_end, end_time)
            last_word_end = end_time
        else:
            # Punctuation: attach to the previous token without a leading space.
            if cur_text_parts:
                # Drop trailing space before the punctuation if any (defensive).
                if cur_text_parts[-1] == " ":
                    cur_text_parts.pop()
                cur_text_parts.append(content)
            else:
                cur_text_parts.append(content)
            cur_end = max(cur_end, end_time)
            if content in _SENTENCE_END:
                flush()

    flush()

    text = " ".join(s["text"] for s in segments if s["text"]).strip()

    return {
        "text": text,
        "language": language,
        "segments": segments,
    }


async def transcribe_from_path(path: str, language: str | None = None) -> dict:
    """Public entry point — submits, polls, fetches, and returns a Whisper-shaped dict."""
    async with httpx.AsyncClient() as client:
        job_id = await _submit_job(client, path, language)
        await _wait_for_job(client, job_id)
        transcript = await _fetch_transcript(client, job_id)
    return _to_whisper_dict(transcript)


def is_configured() -> bool:
    return bool(SPEECHMATICS_API_KEY)
