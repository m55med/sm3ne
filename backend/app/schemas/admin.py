from pydantic import BaseModel, Field, field_validator
from typing import Literal, Optional, List
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
    public_id: Optional[str] = None
    username: str
    email: Optional[str]
    full_name: Optional[str]
    role: str
    is_active: bool
    auth_provider: str
    plan_name: Optional[str] = "free"
    active_sessions: int = 0
    last_session_at: Optional[datetime] = None
    created_at: datetime


class UserListResponse(BaseModel):
    users: List[UserListItem]
    total: int
    page: int
    per_page: int


class UserUpdateRequest(BaseModel):
    is_active: Optional[bool] = None
    # F11: constrain role to a closed set so an admin can't mass-assign an
    # arbitrary value (e.g. "superadmin") via the JSON body. Backend further
    # checks at the route layer that an admin can't demote themselves nor
    # disable another admin (F12).
    role: Optional[Literal["user", "admin"]] = None
    full_name: Optional[str] = Field(default=None, max_length=100)
    email: Optional[str] = None


class SessionItem(BaseModel):
    id: int
    event_type: str
    auth_provider: str
    success: bool
    error_message: Optional[str] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    device_platform: Optional[str] = None
    device_model: Optional[str] = None
    device_os_version: Optional[str] = None
    app_version: Optional[str] = None
    is_active: bool = False
    created_at: datetime

    class Config:
        from_attributes = True


class UserUsageInfo(BaseModel):
    requests_today: int = 0
    requests_this_month: int = 0
    requests_today_api: int = 0
    daily_limit: int = 0
    monthly_limit: Optional[int] = None
    api_daily_limit: int = -1
    max_audio_seconds: int = 30


class UserSubscriptionInfo(BaseModel):
    plan_name: str = "free"
    plan_source: str = "free"  # free | coupon | purchase
    starts_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    days_remaining: Optional[int] = None
    coupon_code: Optional[str] = None
    coupon_id: Optional[int] = None
    is_active: bool = False


class UserDetailResponse(BaseModel):
    id: int
    public_id: Optional[str] = None
    username: str
    email: Optional[str]
    full_name: Optional[str]
    role: str
    is_active: bool
    auth_provider: str
    survey_response: Optional[str] = None
    created_at: Optional[datetime]
    total_requests: int = 0
    subscription: UserSubscriptionInfo
    usage: UserUsageInfo
    active_sessions: int = 0


class AdminSubscribeRequest(BaseModel):
    plan_id: int
    duration_days: Optional[int] = None  # null = use plan-default (monthly=30, annual=365)
    coupon_code: Optional[str] = None


class SubscriptionLogItem(BaseModel):
    id: int
    user_id: int
    user_public_id: Optional[str] = None
    username: str
    plan_id: int
    plan_name: str
    plan_source: str  # free | coupon | purchase
    coupon_code: Optional[str] = None
    starts_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    is_active: bool
    created_at: Optional[datetime] = None


class SubscriptionLogResponse(BaseModel):
    subscriptions: list[SubscriptionLogItem]
    total: int
    page: int
    per_page: int


class PlanSubscriberItem(BaseModel):
    user_id: int
    user_public_id: Optional[str] = None
    username: str
    full_name: Optional[str] = None
    email: Optional[str] = None
    plan_source: str
    coupon_code: Optional[str] = None
    starts_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    days_remaining: Optional[int] = None


class RequestListItem(BaseModel):
    id: int
    user_public_id: Optional[str] = None
    username: str
    api_key_id: Optional[int] = None
    api_key_name: Optional[str] = None
    filename: Optional[str]
    duration_seconds: float
    processed_seconds: float
    language: Optional[str]
    word_count: int
    was_trimmed: bool
    status: str = "completed"
    error_message: Optional[str] = None
    plan_name: str = "free"
    plan_source: str = "free"
    daily_used: int = 0
    daily_limit: int = 0
    monthly_limit: Optional[int] = None
    # Origin of the request — answers "where did this come from?":
    #   upload | recording | share | api | telegram
    # The set is closed (FastAPI/Pydantic reject anything else with 422), and
    # `telegram` is stamped server-side, so an attacker can't forge the origin.
    source: str = "upload"
    is_live_recording: bool = False
    provider_used: Optional[str] = None
    model_used: Optional[str] = None
    latency_ms: Optional[int] = None
    created_at: datetime


class RequestListResponse(BaseModel):
    requests: List[RequestListItem]
    total: int
    page: int
    per_page: int


class CouponCreate(BaseModel):
    # F13: tight pattern + auto-uppercase so lookups are case-insensitive.
    # The DB column is unique, so casing collisions on user input would
    # silently break — easier to canonicalize once at the schema boundary.
    code: str = Field(min_length=4, max_length=50, pattern=r"^[A-Z0-9_-]+$")
    plan_id: int
    # duration_days = how long the SUBSCRIPTION lasts once the coupon is redeemed.
    #   1..3650 → fixed duration in days
    #   -1      → PERMANENT subscription (never expires) — used for coupons
    #             issued to deaf users so premium stays free for life.
    duration_days: int = Field(default=30, ge=-1, le=3650)
    max_uses: int = Field(default=-1, ge=-1)
    expires_at: Optional[datetime] = None

    @field_validator("code", mode="before")
    @classmethod
    def _upper(cls, v):
        # Normalize BEFORE the pattern check so a lowercase "promo10" becomes
        # "PROMO10" and passes the [A-Z0-9_-] regex instead of being 422'd.
        if isinstance(v, str):
            return v.strip().upper()
        return v

    @field_validator("duration_days")
    @classmethod
    def _no_zero_duration(cls, v):
        # ge=-1 would also let 0 through; 0 days is a meaningless subscription.
        if v == 0:
            raise ValueError("duration_days must be -1 (permanent) or >= 1")
        return v


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


class PlanAdminItem(BaseModel):
    id: int
    name: str
    price: float
    original_price: float
    max_audio_seconds: int
    daily_request_limit: int
    monthly_request_limit: Optional[int] = None
    api_daily_request_limit: int = -1
    rpm_default: int
    api_keys_allowed: int
    description: Optional[str] = None
    is_active: bool
    subscriber_count: int = 0
    transcription_provider: Optional[str] = None
    transcription_model: Optional[str] = None

    class Config:
        from_attributes = True


class PlanCreate(BaseModel):
    name: str
    price: float = 0
    original_price: float = 0
    max_audio_seconds: int = 30
    daily_request_limit: int = 100
    monthly_request_limit: Optional[int] = None
    api_daily_request_limit: int = -1
    rpm_default: int = 10
    api_keys_allowed: int = 1
    description: Optional[str] = None
    is_active: bool = True
    transcription_provider: Optional[str] = None
    transcription_model: Optional[str] = None


class PlanUpdate(BaseModel):
    price: Optional[float] = None
    original_price: Optional[float] = None
    max_audio_seconds: Optional[int] = None
    daily_request_limit: Optional[int] = None
    monthly_request_limit: Optional[int] = None
    api_daily_request_limit: Optional[int] = None
    rpm_default: Optional[int] = None
    api_keys_allowed: Optional[int] = None
    description: Optional[str] = None
    is_active: Optional[bool] = None
    transcription_provider: Optional[str] = None
    transcription_model: Optional[str] = None


# --- Admin audio analyzer ---

class AnalyzeFileInfo(BaseModel):
    filename: str
    content_type: Optional[str] = None
    size_bytes: int


class AnalyzeWordCount(BaseModel):
    word: str
    count: int


class AnalyzeSegment(BaseModel):
    id: int
    start: float
    end: float
    text: str


class AnalyzeAudioResponse(BaseModel):
    file: AnalyzeFileInfo
    provider: str
    model: Optional[str] = None
    language: str
    language_name: str
    duration_seconds: float
    text: str
    char_count: int
    char_count_no_spaces: int
    word_count: int
    unique_word_count: int
    avg_word_length: float
    longest_word: str
    sentence_count: int
    paragraph_count: int
    line_count: int
    segment_count: int
    speaking_rate_wpm: Optional[float] = None
    punctuation: dict
    top_words: List[AnalyzeWordCount]
    segments: List[AnalyzeSegment]
