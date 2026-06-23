"""Text translation via Gemini.

Translation reuses the Gemini API we already configure for transcription — no
new provider/key. We deliberately use an LLM (not a phrase-based MT API) because
the content is conversational voice-note text where context, idiom, and dialect
matter, and LLM output reads far more naturally in Arabic.

Resilience: Gemini's primary flash model occasionally returns 503 ("model
overloaded"). Translation is cheap text-only work, so we try the configured
model first and transparently fall back to a lighter model on failure rather
than surfacing an error to the user.
"""
import logging

import httpx

from app.core.config import (
    GEMINI_API_KEY,
    GEMINI_BASE_URL,
    GEMINI_MODEL,
    GEMINI_TRANSLATION_FALLBACK_MODEL,
)

logger = logging.getLogger(__name__)


class TranslationError(RuntimeError):
    pass


def is_configured() -> bool:
    return bool(GEMINI_API_KEY)


def _headers() -> dict:
    if not GEMINI_API_KEY:
        raise TranslationError("GEMINI_API_KEY is not configured")
    return {"X-goog-api-key": GEMINI_API_KEY, "Content-Type": "application/json"}


def _build_prompt(text: str, source_lang: str | None) -> str:
    src = f" from {source_lang}" if source_lang and source_lang != "unknown" else ""
    return (
        f"You are a professional translator. Translate the following text{src} "
        "into natural, fluent Arabic. Preserve the meaning, tone, and any line "
        "breaks. Do NOT add commentary, notes, quotes, or transliteration. "
        "Output ONLY the Arabic translation. If the text is already Arabic, "
        "return it unchanged.\n\n"
        "Text to translate:\n"
        f"{text}"
    )


async def _call_model(client: httpx.AsyncClient, model: str, prompt: str) -> str:
    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.2,
            "responseMimeType": "text/plain",
            # Headroom for long transcripts: the input is capped at 50k chars, and
            # an Arabic translation of that can run to tens of thousands of tokens.
            # The flash models support up to 65536 output tokens, so size for the
            # worst case rather than truncating (which would drop the tail).
            "maxOutputTokens": 65536,
        },
    }
    # Timeouts come from the client-level httpx.Timeout (connect 30s, read 120s) —
    # don't override them per-call.
    resp = await client.post(
        f"{GEMINI_BASE_URL}/models/{model}:generateContent",
        headers=_headers(),
        json=body,
    )
    if resp.status_code != 200:
        raise TranslationError(
            f"translate failed [{resp.status_code}] on {model}: {resp.text[:300]}"
        )
    data = resp.json()
    try:
        candidate = data["candidates"][0]
        parts = candidate["content"]["parts"]
        out = "".join(p.get("text", "") for p in parts).strip()
    except (KeyError, IndexError, TypeError) as e:
        raise TranslationError(f"unexpected Gemini response: {data}") from e
    if candidate.get("finishReason") == "MAX_TOKENS":
        raise TranslationError("translation truncated (MAX_TOKENS)")
    if not out:
        raise TranslationError("empty translation")
    return out


async def translate_to_arabic(text: str, source_lang: str | None = None) -> str:
    """Translate ``text`` into Arabic. Tries the primary model then a lighter
    fallback (covers the primary's transient 503 overloads)."""
    text = (text or "").strip()
    if not text:
        raise TranslationError("nothing to translate")

    prompt = _build_prompt(text, source_lang)
    # Primary first, then the fallback model — de-duplicated in case they match.
    models: list[str] = []
    for m in (GEMINI_MODEL, GEMINI_TRANSLATION_FALLBACK_MODEL):
        if m and m not in models:
            models.append(m)

    last_error: Exception | None = None
    async with httpx.AsyncClient(timeout=httpx.Timeout(30.0, read=120.0)) as client:
        for model in models:
            try:
                return await _call_model(client, model, prompt)
            except Exception as e:  # noqa: BLE001 — try every model before failing
                last_error = e
                logger.warning("translation model '%s' failed: %s", model, e)
                continue
    raise last_error or TranslationError("all translation models failed")
