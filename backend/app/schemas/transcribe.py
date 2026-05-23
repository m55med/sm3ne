"""Pydantic schemas for the transcription routes."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


ClientEngine = Literal["apple_speech", "android_speech"]
ClientSource = Literal["recording", "upload", "share"]


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
