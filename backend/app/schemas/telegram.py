"""Pydantic schemas for the Telegram-linking and admin Telegram endpoints."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


# -- User-facing -------------------------------------------------------------

class TelegramLinkStartResponse(BaseModel):
    """Returned from POST /telegram/link/start.

    ``code`` is shown to the user in the mobile app. ``deep_link`` opens
    Telegram directly with the bot + code as the /start payload — preferred
    UX over manual copy/paste.
    """
    code: str
    expires_at: datetime
    bot_username: Optional[str] = None
    deep_link: Optional[str] = None


class TelegramStatusResponse(BaseModel):
    enabled: bool
    linked: bool
    telegram_id: Optional[int] = None
    telegram_username: Optional[str] = None
    telegram_first_name: Optional[str] = None
    linked_at: Optional[datetime] = None
    bot_username: Optional[str] = None


class TelegramUnlinkResponse(BaseModel):
    unlinked: bool
    telegram_id: Optional[int] = None


# -- Admin -------------------------------------------------------------------

class AdminTelegramUserItem(BaseModel):
    id: int
    telegram_id: int
    first_name: Optional[str]
    last_name: Optional[str]
    username: Optional[str]
    language_code: Optional[str]
    is_premium: bool
    is_blocked: bool
    bio: Optional[str]
    photo_url: Optional[str] = None
    linked_user_id: Optional[int]
    linked_user_username: Optional[str] = None
    linked_user_public_id: Optional[str] = None
    linked_at: Optional[datetime]
    last_interaction_at: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True


class AdminTelegramUserListResponse(BaseModel):
    items: list[AdminTelegramUserItem]
    total: int
    page: int
    per_page: int


class AdminTelegramMessageRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4096)


class AdminTelegramBroadcastRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4096)
    # Either an explicit list of telegram_users.id rows, or null = everyone
    # who's not blocked. Allowed values for ``audience``: ``all`` |
    # ``linked_only`` | ``unlinked_only`` | ``selected``.
    audience: str = Field(default="all")
    telegram_user_ids: list[int] = Field(default_factory=list, max_length=5000)


class AdminTelegramBroadcastResponse(BaseModel):
    queued: int


class AdminTelegramSendResponse(BaseModel):
    sent: bool
    error: Optional[str] = None


class AdminTelegramBotMessageItem(BaseModel):
    key: str
    description: Optional[str]
    text_ar: str
    default_text: str
    is_default: bool
    updated_at: Optional[datetime]
    updated_by_user_id: Optional[int]


class AdminTelegramBotMessagesResponse(BaseModel):
    items: list[AdminTelegramBotMessageItem]


class AdminTelegramBotMessageUpdateRequest(BaseModel):
    # Allow empty string to reset to default.
    text_ar: str = Field(..., max_length=4096)


class AdminTelegramWebhookInfo(BaseModel):
    configured: bool
    url: Optional[str] = None
    pending_update_count: Optional[int] = None
    last_error_date: Optional[datetime] = None
    last_error_message: Optional[str] = None
    bot_username: Optional[str] = None


class AdminTelegramSetWebhookRequest(BaseModel):
    # Optional override; default uses TELEGRAM_PUBLIC_BASE_URL from config.
    public_base_url: Optional[str] = Field(default=None, max_length=200)
