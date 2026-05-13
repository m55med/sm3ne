"""User-facing Telegram linking endpoints.

These are called from the mobile app's "Link with Telegram" screen. The webhook
that consumes the generated code lives in :mod:`app.routes.telegram_webhook`.

All endpoints are JWT-only (no API-key access) since linking is a per-human
intent, not an automated one.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.auth.jwt import get_current_user
from app.core.config import RATE_LIMIT, TELEGRAM_BOT_USERNAME, TELEGRAM_ENABLED, limiter
from app.db.database import get_db
from app.db.models import User
from app.schemas.telegram import (
    TelegramLinkStartResponse,
    TelegramStatusResponse,
    TelegramUnlinkResponse,
)
from app.services import audit_service, telegram_link_service


router = APIRouter(prefix="/telegram", tags=["telegram"])
logger = logging.getLogger(__name__)


def _require_enabled() -> None:
    if not TELEGRAM_ENABLED:
        raise HTTPException(
            status_code=503,
            detail={"error": "telegram_disabled", "message": "Telegram integration is not configured on this server."},
        )


def _bot_username() -> str | None:
    return TELEGRAM_BOT_USERNAME or None


def _deep_link_for(code: str) -> str | None:
    username = _bot_username()
    if not username:
        return None
    return f"https://t.me/{username}?start={code}"


@router.post("/link/start", response_model=TelegramLinkStartResponse)
@limiter.limit("10/minute")
async def link_start(
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Generate a fresh single-use linking code for the calling user.

    Each call invalidates any previously-issued unused codes for the same
    user — so re-pressing "generate" in the app always shows a fresh code
    and an old screenshot is no longer redeemable.
    """
    _require_enabled()

    code, expires_at = telegram_link_service.generate_code(db, user)

    # Best-effort audit. Don't log the code itself — only the fact a code was
    # issued. The code is shown to the user once and never re-derived here.
    try:
        audit_service.record(
            db,
            action="telegram.link.code_issued",
            actor_user_id=user.id,
            target_type="user",
            target_id=user.id,
            ip_address=_client_ip(request),
        )
    except Exception:  # noqa: BLE001
        pass

    return TelegramLinkStartResponse(
        code=code,
        expires_at=expires_at,
        bot_username=_bot_username(),
        deep_link=_deep_link_for(code),
    )


@router.get("/status", response_model=TelegramStatusResponse)
@limiter.limit("30/minute")
async def link_status(
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return whether the calling user has a linked Telegram account."""
    if not TELEGRAM_ENABLED:
        return TelegramStatusResponse(enabled=False, linked=False)

    tg = telegram_link_service.get_linked_telegram_for_user(db, user.id)
    if tg is None:
        return TelegramStatusResponse(enabled=True, linked=False, bot_username=_bot_username())
    return TelegramStatusResponse(
        enabled=True,
        linked=True,
        telegram_id=tg.telegram_id,
        telegram_username=tg.username,
        telegram_first_name=tg.first_name,
        linked_at=tg.linked_at,
        bot_username=_bot_username(),
    )


@router.post("/unlink", response_model=TelegramUnlinkResponse)
@limiter.limit("10/minute")
async def unlink(
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Disconnect the calling user from their linked Telegram account.

    We also send a courtesy notification to the bot side so the user knows
    via Telegram that the link was severed — but the notification is
    best-effort; the unlink is committed regardless.
    """
    _require_enabled()

    tg = telegram_link_service.unlink_by_user(db, user)
    if tg is None:
        return TelegramUnlinkResponse(unlinked=False)

    try:
        audit_service.record(
            db,
            action="telegram.link.unlinked_by_user",
            actor_user_id=user.id,
            target_type="telegram_user",
            target_id=tg.id,
            metadata={"telegram_id": tg.telegram_id},
            ip_address=_client_ip(request),
        )
    except Exception:  # noqa: BLE001
        pass

    # Fire-and-forget Telegram notification.
    try:
        from app.services import telegram_bot_messages, telegram_service
        msg = telegram_bot_messages.render(db, "unlink_success")
        if msg:
            await telegram_service.send_message(tg.telegram_id, msg)
    except Exception:  # noqa: BLE001 — best-effort
        logger.debug("failed to notify telegram of unlink", exc_info=True)

    return TelegramUnlinkResponse(unlinked=True, telegram_id=tg.telegram_id)


def _client_ip(request: Request) -> str | None:
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else None
