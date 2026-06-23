"""Pydantic schemas for the transcription routes."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator


ClientEngine = Literal["apple_speech", "android_speech"]
ClientSource = Literal["recording", "upload", "share"]

# Mobile sometimes ships small naming drifts (e.g. an old build sent "shared"
# instead of "share", and "recorded" instead of "recording"). Rather than
# 422-ing those silently and dropping the on-device transcription on the
# floor, normalize to the canonical literal so the row still lands.
_SOURCE_ALIASES = {
    "shared": "share",
    "recorded": "recording",
    "uploaded": "upload",
}


class ClientLogIn(BaseModel):
    """Payload for ``POST /transcriptions/log``.

    Sent when the mobile app produced a transcription locally via the OS
    speech recognizer and only wants to persist the metadata server-side
    (no audio uploaded). The shape mirrors the ``/transcribe`` response so
    client code can stay uniform.
    """

    text: str = Field(min_length=1, max_length=50_000)
    lang: str = Field(min_length=2, max_length=10)
    lang_name: str | None = Field(default=None, max_length=64)
    duration_seconds: float = Field(ge=0, le=3600)
    source: ClientSource
    is_live_recording: bool
    client_engine: ClientEngine

    @field_validator("source", mode="before")
    @classmethod
    def _normalize_source(cls, v):
        if isinstance(v, str):
            return _SOURCE_ALIASES.get(v, v)
        return v


class TranslateIn(BaseModel):
    """Payload for ``POST /transcriptions/translate``.

    The server never persists transcript text (privacy), so the client sends
    the text to translate inline.
    """

    text: str = Field(min_length=1, max_length=50_000)
    source_lang: str | None = Field(default=None, max_length=10)


class TranslateOut(BaseModel):
    translated_text: str
    target_lang: str = "ar"
    quota_cost: int
