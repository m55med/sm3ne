from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, Field, field_validator


def _ensure_expires_in_future(v: Optional[datetime]) -> Optional[datetime]:
    """F16: reject expires_at in the past — an already-expired key is a footgun
    (it'd be created then immediately reject every request)."""
    if v is None:
        return v
    # Normalize to aware UTC for comparison; pydantic passes naive datetimes
    # through unchanged for older client payloads.
    cmp = v if v.tzinfo is not None else v.replace(tzinfo=timezone.utc)
    if cmp <= datetime.now(timezone.utc):
        raise ValueError("expires_at must be in the future")
    return v


class ApiKeyCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    expires_at: Optional[datetime] = None
    # Admin-only fields — silently ignored when caller is not an admin
    requests_per_minute: Optional[int] = None
    requests_per_day: Optional[int] = None

    @field_validator("expires_at")
    @classmethod
    def _validate_expires_at(cls, v: Optional[datetime]) -> Optional[datetime]:
        return _ensure_expires_in_future(v)


class ApiKeyCreateResponse(BaseModel):
    id: int
    name: str
    key: str  # full plaintext — returned exactly ONCE, never stored in this form
    key_prefix: str
    expires_at: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True


class ApiKeyResponse(BaseModel):
    id: int
    name: str
    key_prefix: str
    last_used_at: Optional[datetime]
    expires_at: Optional[datetime]
    is_active: bool
    created_at: datetime
    requests_per_minute: Optional[int]
    requests_per_day: Optional[int]
    usage_today: int
    daily_limit: int

    class Config:
        from_attributes = True


class ApiKeyUpdateRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    is_active: Optional[bool] = None
    expires_at: Optional[datetime] = None
    # Admin-only — rejected with 403 for non-admins in the user route
    requests_per_minute: Optional[int] = None
    requests_per_day: Optional[int] = None

    @field_validator("expires_at")
    @classmethod
    def _validate_expires_at(cls, v: Optional[datetime]) -> Optional[datetime]:
        return _ensure_expires_in_future(v)


class AdminApiKeyCreateRequest(ApiKeyCreateRequest):
    user_id: int


class AdminApiKeyListItem(ApiKeyResponse):
    user_id: int
    user_email: Optional[str] = None
    user_full_name: Optional[str] = None


class AdminApiKeyListResponse(BaseModel):
    keys: list[AdminApiKeyListItem]
    total: int
    page: int
    per_page: int


class ApiKeyUsageItem(BaseModel):
    request_id: int
    filename: Optional[str]
    duration_seconds: float
    processed_seconds: float
    language: Optional[str]
    word_count: int
    was_trimmed: bool
    created_at: datetime


class ApiKeyUsageResponse(BaseModel):
    key_id: Optional[int]  # None when listing usage across all keys
    key_name: Optional[str]
    usage_today: int
    daily_limit: int
    items: list[ApiKeyUsageItem]
    total: int
    page: int
    per_page: int
