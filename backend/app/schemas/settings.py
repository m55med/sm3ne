from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel


ProviderName = Literal["whisper", "speechmatics", "gemini", "groq", "assemblyai"]


class ModelOption(BaseModel):
    id: str
    label: str
    description: str | None = None


class ProviderInfo(BaseModel):
    name: ProviderName
    label: str
    description: str
    available: bool  # is it actually configured/usable right now?
    models: list[ModelOption] = []
    selected_model: str | None = None
    default_model: str | None = None


class TranscriptionProviderResponse(BaseModel):
    """Returned by GET /admin/settings/transcription-provider."""
    current: ProviderName
    effective: ProviderName  # what would actually run (after availability fallback)
    updated_at: datetime | None = None
    updated_by_user_id: int | None = None
    providers: list[ProviderInfo]
    # Auto-failover priority: when the active provider fails mid-request
    # (credit exhausted, 429, 5xx...), the dispatcher walks this list.
    provider_order: list[ProviderName] = []


class TranscriptionProviderUpdateRequest(BaseModel):
    provider: ProviderName


class ProviderOrderUpdateRequest(BaseModel):
    """New failover priority order — full list, highest priority first."""
    order: list[ProviderName]


class ProviderUsageLocal(BaseModel):
    requests_today: int
    requests_month: int
    requests_total: int
    seconds_today: float
    seconds_month: float
    seconds_total: float


class ProviderUsageRemote(BaseModel):
    period: str
    total_hours_month: float
    raw: dict[str, Any] | None = None


class ProviderUsage(BaseModel):
    provider: ProviderName
    free_tier_label: str | None = None
    free_tier_limit_text: str | None = None
    billing_unit: str | None = None
    local: ProviderUsageLocal
    remote: ProviderUsageRemote | None = None


class TranscriptionProviderUsageResponse(BaseModel):
    providers: list[ProviderUsage]


class ProviderModelUpdateRequest(BaseModel):
    provider: ProviderName
    model: str


class ProviderTestResponse(BaseModel):
    provider: ProviderName
    model: str | None
    duration_ms: int
    audio_seconds: float
    text: str
    language: str | None = None
    word_count: int
    segment_count: int
