from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class AdminStatsResponse(BaseModel):
    total_users: int
    active_subscribers: int
    requests_today: int
    requests_week: int
    requests_month: int
    total_requests: int


class UserListItem(BaseModel):
    id: int
    username: str
    email: Optional[str]
    full_name: Optional[str]
    role: str
    is_active: bool
    auth_provider: str
    plan_name: Optional[str] = "free"
    created_at: datetime


class UserListResponse(BaseModel):
    users: List[UserListItem]
    total: int
    page: int
    per_page: int


class UserUpdateRequest(BaseModel):
    is_active: Optional[bool] = None
    role: Optional[str] = None


class RequestListItem(BaseModel):
    id: int
    username: str
    filename: Optional[str]
    duration_seconds: float
    processed_seconds: float
    language: Optional[str]
    word_count: int
    was_trimmed: bool
    created_at: datetime


class RequestListResponse(BaseModel):
    requests: List[RequestListItem]
    total: int
    page: int
    per_page: int


class CouponCreate(BaseModel):
    code: str
    plan_id: int
    duration_days: int = 30
    max_uses: int = -1
    expires_at: Optional[datetime] = None


class CouponResponse(BaseModel):
    id: int
    code: str
    plan_id: int
    duration_days: int
    max_uses: int
    times_used: int
    is_active: bool
    created_at: datetime
    expires_at: Optional[datetime]

    class Config:
        from_attributes = True


class CouponUpdate(BaseModel):
    is_active: Optional[bool] = None
    max_uses: Optional[int] = None
    expires_at: Optional[datetime] = None
