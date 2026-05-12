from datetime import datetime
from typing import Literal

from pydantic import BaseModel


ProviderName = Literal["whisper", "speechmatics"]


class ProviderInfo(BaseModel):
    name: ProviderName
    label: str
    description: str
    available: bool  # is it actually configured/usable right now?


class TranscriptionProviderResponse(BaseModel):
    """Returned by GET /admin/settings/transcription-provider."""
    current: ProviderName
    effective: ProviderName  # what would actually run (after availability fallback)
    updated_at: datetime | None = None
    updated_by_user_id: int | None = None
    providers: list[ProviderInfo]


class TranscriptionProviderUpdateRequest(BaseModel):
    provider: ProviderName
