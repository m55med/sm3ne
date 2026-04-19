from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ApiKeyCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    expires_at: Optional[datetime] = None
    # Admin-only fields — silently ignored when caller is not an admin
    requests_per_minute: Optional[int] = None
    requests_per_day: Optional[int] = None


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


class AdminApiKeyCreateRequest(ApiKeyCreateRequest):
    user_id: int


class AdminApiKeyListItem(ApiKeyResponse):
    user_id: int
    username: str


class AdminApiKeyListResponse(BaseModel):
    keys: list[AdminApiKeyListItem]
    total: int
    page: int
    per_page: int
