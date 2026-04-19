from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class PlanResponse(BaseModel):
    id: int
    name: str
    price: float
    original_price: float
    max_audio_seconds: int
    daily_request_limit: int
    rpm_default: int
    api_keys_allowed: int

    class Config:
        from_attributes = True


class SubscriptionResponse(BaseModel):
    id: int
    plan: PlanResponse
    starts_at: datetime
    expires_at: Optional[datetime]
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class SubscribeRequest(BaseModel):
    plan_id: int
    coupon_code: Optional[str] = None


class CouponApplyRequest(BaseModel):
    code: str
