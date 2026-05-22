"""Schemas for the push-notification device-registration flow.

Mobile clients call ``POST /devices/register`` whenever they get a fresh FCM
token (on first launch, on token-rotation, on login). The admin browses
``GET /admin/devices`` to see all registrations and ``POST /admin/notifications/send``
to fan a push out to a subset.
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, Field


class DeviceRegisterRequest(BaseModel):
    # FCM registration token. Long-ish (firebase tokens hover around 150-200
    # chars); cap at 512 to match the DB column.
    fcm_token: str = Field(min_length=10, max_length=512)
    platform: Literal["android", "ios"]
    device_model: Optional[str] = Field(default=None, max_length=128)
    device_marketing_name: Optional[str] = Field(default=None, max_length=128)
    device_os: Optional[str] = Field(default=None, max_length=32)
    device_os_version: Optional[str] = Field(default=None, max_length=64)
    device_locale: Optional[str] = Field(default=None, max_length=16)
    app_version: Optional[str] = Field(default=None, max_length=32)
    push_enabled: bool = True


class DeviceItem(BaseModel):
    public_id: str
    user_id: int
    user_email: Optional[str] = None
    user_full_name: Optional[str] = None
    platform: str
    device_model: Optional[str] = None
    device_marketing_name: Optional[str] = None
    device_os: Optional[str] = None
    device_os_version: Optional[str] = None
    device_locale: Optional[str] = None
    app_version: Optional[str] = None
    push_enabled: bool
    last_seen_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


class DeviceListResponse(BaseModel):
    devices: List[DeviceItem]
    total: int
    page: int
    per_page: int


class NotificationSendRequest(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(min_length=1, max_length=1000)
    # Targeting — exactly one MUST be set. Validated in the route handler so
    # we can give a precise error code instead of a vague 422.
    target: Literal["all", "users", "devices", "hearing_impaired"]
    user_ids: List[int] = Field(default_factory=list, max_length=500)
    device_public_ids: List[str] = Field(default_factory=list, max_length=500)
    # Optional deep-link route the client opens when the notification is
    # tapped (e.g. "/plans"). Free-form so we can extend without a schema
    # bump; client validates against its routing table.
    deep_link: Optional[str] = Field(default=None, max_length=200)


class NotificationSendResponse(BaseModel):
    sent: int
    failed: int
    skipped_no_token: int = 0
