"""Admin endpoints for the Telegram bot integration.

Mounted under ``/admin/telegram``. Every endpoint requires ``get_current_admin``.

Endpoints:
  * GET    /admin/telegram/users              — paginated list (linked/blocked filter)
  * GET    /admin/telegram/users/{id}         — full row + linked app account
  * POST   /admin/telegram/users/{id}/message — send single message
  * POST   /admin/telegram/users/{id}/refresh — fetch fresh bio/photo from Telegram
  * DELETE /admin/telegram/users/{id}         — delete a Telegram row (rejects if linked)
  * POST   /admin/telegram/broadcast          — fanout to many users
  * GET    /admin/telegram/messages           — list editable bot templates
  * PUT    /admin/telegram/messages/{key}     — update one template
  * GET    /admin/telegram/webhook            — current webhook info from Telegram
  * POST   /admin/telegram/webhook/register   — call setWebhook with our URL + secret
  * DELETE /admin/telegram/webhook            — call deleteWebhook
"""
from __future__ import annotations

import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.auth.jwt import get_current_admin
from app.core import config
from app.db.database import SessionLocal, get_db
from app.db.models import TelegramUser, User
from app.schemas.telegram import (
    AdminTelegramBotMessageUpdateRequest,
    AdminTelegramBotMessagesResponse,
    AdminTelegramBroadcastRequest,
    AdminTelegramBroadcastResponse,
    AdminTelegramMessageRequest,
    AdminTelegramSendResponse,
    AdminTelegramSetWebhookRequest,
    AdminTelegramUserItem,
    AdminTelegramUserListResponse,
    AdminTelegramWebhookInfo,
)
from app.services import (
    audit_service,
    telegram_bot_messages,
    telegram_link_service,
    telegram_service,
)


router = APIRouter(prefix="/admin/telegram", tags=["admin-telegram"])
logger = logging.getLogger(__name__)


def _safe_audit(db, **kwargs):
    try:
        audit_service.record(db, **kwargs)
    except Exception:  # noqa: BLE001
        pass


def _require_enabled() -> None:
    if not config.TELEGRAM_ENABLED:
        raise HTTPException(
            status_code=503,
            detail={"error": "telegram_disabled", "message": "Telegram integration is not configured."},
        )


def _to_item(db: Session, row: TelegramUser) -> AdminTelegramUserItem:
    linked = None
    if row.linked_user_id is not None:
        linked = db.query(User).filter(User.id == row.linked_user_id).first()
    return AdminTelegramUserItem(
        id=row.id,
        telegram_id=row.telegram_id,
        first_name=row.first_name,
        last_name=row.last_name,
        username=row.username,
        language_code=row.language_code,
        is_premium=bool(row.is_premium),
        is_blocked=bool(row.is_blocked),
        bio=row.bio,
        photo_url=None,  # resolved on detail endpoint (round-trip per row is expensive)
        linked_user_id=row.linked_user_id,
        linked_user_username=linked.username if linked else None,
        linked_user_public_id=linked.public_id if linked else None,
        linked_at=row.linked_at,
        last_interaction_at=row.last_interaction_at,
        created_at=row.created_at,
    )


# -- List + detail -----------------------------------------------------------

@router.get("/users", response_model=AdminTelegramUserListResponse)
async def list_telegram_users(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = None,
    filter_state: str = Query("all", pattern="^(all|linked|unlinked|blocked)$"),
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    q = db.query(TelegramUser)

    if filter_state == "linked":
        q = q.filter(TelegramUser.linked_user_id.isnot(None))
    elif filter_state == "unlinked":
        q = q.filter(TelegramUser.linked_user_id.is_(None), TelegramUser.is_blocked == False)  # noqa: E712
    elif filter_state == "blocked":
        q = q.filter(TelegramUser.is_blocked == True)  # noqa: E712

    if search:
        like = f"%{search}%"
        # `telegram_id` is numeric; try to parse as int for an exact match
        # alongside the textual columns.
        try:
            search_int = int(search)
        except (TypeError, ValueError):
            search_int = None
        clauses = [
            TelegramUser.first_name.ilike(like),
            TelegramUser.last_name.ilike(like),
            TelegramUser.username.ilike(like),
        ]
        if search_int is not None:
            clauses.append(TelegramUser.telegram_id == search_int)
        q = q.filter(or_(*clauses))

    total = q.count()
    rows = (
        q.order_by(TelegramUser.last_interaction_at.desc().nullslast())
        .offset((page - 1) * per_page)
        .limit(per_page)
        .all()
    )
    items = [_to_item(db, r) for r in rows]
    return AdminTelegramUserListResponse(items=items, total=total, page=page, per_page=per_page)


@router.get("/users/{telegram_user_id}", response_model=AdminTelegramUserItem)
async def get_telegram_user(
    telegram_user_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    row = db.query(TelegramUser).filter(TelegramUser.id == telegram_user_id).first()
    if row is None:
        raise HTTPException(404, "Not found")
    item = _to_item(db, row)
    # Resolve photo URL on demand.
    if row.photo_file_id and config.TELEGRAM_ENABLED:
        try:
            info = await telegram_service.get_file(row.photo_file_id)
            if info and info.get("file_path"):
                item.photo_url = telegram_service._file_url(info["file_path"])
        except Exception:  # noqa: BLE001
            pass
    return item


@router.post("/users/{telegram_user_id}/refresh", response_model=AdminTelegramUserItem)
async def refresh_telegram_user(
    telegram_user_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Pull fresh first/last/username/bio/photo from Telegram for one row.

    Called on-demand from the admin dashboard (the webhook only refreshes
    cheap fields on every message; bio/photo cost extra API calls and would
    bloat per-update cost if done eagerly).
    """
    _require_enabled()
    row = db.query(TelegramUser).filter(TelegramUser.id == telegram_user_id).first()
    if row is None:
        raise HTTPException(404, "Not found")

    try:
        chat = await telegram_service.get_chat(row.telegram_id)
    except telegram_service.TelegramApiError as exc:
        if exc.error_code == 403 or "blocked" in (exc.description or "").lower():
            row.is_blocked = True
            db.commit()
        raise HTTPException(502, f"Telegram API: {exc.description or exc}")

    dirty = False
    for src, dst, cap in (
        ("first_name", "first_name", 120),
        ("last_name", "last_name", 120),
        ("username", "username", 64),
        ("bio", "bio", None),
    ):
        val = chat.get(src)
        if val is not None:
            val = str(val)[:cap] if cap else str(val)
            if getattr(row, dst) != val:
                setattr(row, dst, val)
                dirty = True

    # Photo
    try:
        photos = await telegram_service.get_user_profile_photos(row.telegram_id, limit=1)
        if photos and photos.get("photos"):
            # Largest size of first photo set.
            sizes = photos["photos"][0]
            if sizes:
                file_id = sizes[-1].get("file_id")
                if file_id and row.photo_file_id != file_id:
                    row.photo_file_id = file_id
                    dirty = True
    except telegram_service.TelegramApiError:
        pass

    if dirty:
        db.commit()
        db.refresh(row)

    return await get_telegram_user(row.id, admin=admin, db=db)


@router.delete("/users/{telegram_user_id}", status_code=204)
async def delete_telegram_user(
    request: Request,
    telegram_user_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    row = db.query(TelegramUser).filter(TelegramUser.id == telegram_user_id).first()
    if row is None:
        raise HTTPException(404, "Not found")
    if row.linked_user_id is not None:
        raise HTTPException(
            409,
            "This Telegram account is linked to an app user. Unlink it first before deleting.",
        )
    db.delete(row)
    db.commit()
    _safe_audit(
        db, action="admin.telegram.user.delete", actor_user_id=admin.id,
        target_type="telegram_user", target_id=telegram_user_id,
        metadata={"telegram_id": row.telegram_id},
    )
    return None


# -- Send / broadcast --------------------------------------------------------

@router.post("/users/{telegram_user_id}/message", response_model=AdminTelegramSendResponse)
async def send_to_telegram_user(
    telegram_user_id: int,
    body: AdminTelegramMessageRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    _require_enabled()
    row = db.query(TelegramUser).filter(TelegramUser.id == telegram_user_id).first()
    if row is None:
        raise HTTPException(404, "Not found")
    if row.is_blocked:
        return AdminTelegramSendResponse(sent=False, error="User has blocked the bot.")
    try:
        await telegram_service.send_message(row.telegram_id, body.text)
    except telegram_service.TelegramApiError as exc:
        msg = (exc.description or str(exc)).lower()
        if "blocked" in msg or exc.error_code == 403:
            row.is_blocked = True
            db.commit()
            return AdminTelegramSendResponse(sent=False, error="User has blocked the bot.")
        return AdminTelegramSendResponse(sent=False, error=exc.description or str(exc))

    _safe_audit(
        db, action="admin.telegram.send", actor_user_id=admin.id,
        target_type="telegram_user", target_id=telegram_user_id,
        metadata={"telegram_id": row.telegram_id, "len": len(body.text)},
    )
    return AdminTelegramSendResponse(sent=True)


def _resolve_broadcast_audience(
    db: Session, audience: str, explicit_ids: list[int]
) -> list[TelegramUser]:
    """Translate the audience selector into a concrete list of telegram_users
    rows. We exclude blocked users from every fanout because messages to them
    fail anyway."""
    q = db.query(TelegramUser).filter(TelegramUser.is_blocked == False)  # noqa: E712
    if audience == "linked_only":
        q = q.filter(TelegramUser.linked_user_id.isnot(None))
    elif audience == "unlinked_only":
        q = q.filter(TelegramUser.linked_user_id.is_(None))
    elif audience == "selected":
        if not explicit_ids:
            return []
        q = q.filter(TelegramUser.id.in_(explicit_ids))
    # `all` → no extra filter
    return q.all()


async def _do_broadcast(rows: list[TelegramUser], text: str, admin_id: int) -> None:
    """Background task that fans the message out to each recipient with
    per-message pacing to stay under Telegram's 30-msg/sec global cap."""
    sent = 0
    blocked = 0
    failed = 0
    for row in rows:
        try:
            await telegram_service.send_message(row.telegram_id, text)
            sent += 1
        except telegram_service.TelegramApiError as exc:
            msg = (exc.description or str(exc)).lower()
            if "blocked" in msg or exc.error_code == 403:
                blocked += 1
                # Mark blocked in a fresh session so we don't carry a long-lived txn.
                try:
                    with SessionLocal() as db:
                        telegram_link_service.mark_blocked(db, row.telegram_id)
                except Exception:  # noqa: BLE001
                    pass
            elif exc.error_code == 429:
                # Hit the global rate limit — back off generously.
                await asyncio.sleep(2.0)
                failed += 1
            else:
                failed += 1
        except Exception:  # noqa: BLE001
            logger.exception("broadcast sendMessage crashed for telegram_id=%s", row.telegram_id)
            failed += 1

        await telegram_service.broadcast_sleep()

    logger.info(
        "broadcast complete: admin=%s sent=%d blocked=%d failed=%d total=%d",
        admin_id, sent, blocked, failed, len(rows),
    )
    try:
        with SessionLocal() as db:
            audit_service.record(
                db, action="admin.telegram.broadcast.done", actor_user_id=admin_id,
                target_type="telegram_users", target_id=None,
                metadata={
                    "sent": sent, "blocked": blocked,
                    "failed": failed, "total": len(rows),
                },
            )
    except Exception:  # noqa: BLE001
        pass


@router.post("/broadcast", response_model=AdminTelegramBroadcastResponse)
async def broadcast(
    body: AdminTelegramBroadcastRequest,
    background_tasks: BackgroundTasks,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Schedule a fanout to the chosen audience.

    Returns 202-ish: we respond with the queued count immediately and run the
    actual send in a background task. The admin dashboard can poll the audit
    log for ``admin.telegram.broadcast.done`` to see when it finished.
    """
    _require_enabled()
    if body.audience not in {"all", "linked_only", "unlinked_only", "selected"}:
        raise HTTPException(400, "Invalid audience")

    rows = _resolve_broadcast_audience(db, body.audience, body.telegram_user_ids)
    if not rows:
        return AdminTelegramBroadcastResponse(queued=0)

    _safe_audit(
        db, action="admin.telegram.broadcast.start", actor_user_id=admin.id,
        target_type="telegram_users", target_id=None,
        metadata={
            "audience": body.audience,
            "queued": len(rows),
            "len": len(body.text),
        },
    )
    background_tasks.add_task(_do_broadcast, rows, body.text, admin.id)
    return AdminTelegramBroadcastResponse(queued=len(rows))


# -- Bot message templates ---------------------------------------------------

@router.get("/messages", response_model=AdminTelegramBotMessagesResponse)
async def list_bot_messages(
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    return AdminTelegramBotMessagesResponse(items=telegram_bot_messages.list_all(db))


@router.put("/messages/{key}")
async def update_bot_message(
    key: str,
    body: AdminTelegramBotMessageUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    if key not in telegram_bot_messages.DEFAULTS:
        raise HTTPException(404, "Unknown message key")
    try:
        telegram_bot_messages.update(db, key, body.text_ar, admin_user_id=admin.id)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    _safe_audit(
        db, action="admin.telegram.message.update", actor_user_id=admin.id,
        target_type="telegram_bot_message", target_id=None,
        metadata={"key": key, "is_default": not body.text_ar.strip()},
    )
    return {"ok": True}


# -- Webhook administration --------------------------------------------------

@router.get("/webhook", response_model=AdminTelegramWebhookInfo)
async def get_webhook(
    admin: User = Depends(get_current_admin),
):
    if not config.TELEGRAM_ENABLED:
        return AdminTelegramWebhookInfo(configured=False)
    try:
        info = await telegram_service.get_webhook_info()
    except telegram_service.TelegramApiError as exc:
        raise HTTPException(502, f"Telegram API: {exc.description or exc}")

    me = await telegram_service.get_me() if info else None
    from datetime import datetime, timezone

    last_err_ts = info.get("last_error_date") if info else None
    return AdminTelegramWebhookInfo(
        configured=bool(info and info.get("url")),
        url=info.get("url") if info else None,
        pending_update_count=info.get("pending_update_count") if info else None,
        last_error_date=(
            datetime.fromtimestamp(last_err_ts, tz=timezone.utc) if last_err_ts else None
        ),
        last_error_message=info.get("last_error_message") if info else None,
        bot_username=(me or {}).get("username"),
    )


@router.post("/webhook/register")
async def register_webhook(
    body: AdminTelegramSetWebhookRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    _require_enabled()
    base = (body.public_base_url or config.TELEGRAM_PUBLIC_BASE_URL or "").strip().rstrip("/")
    if not base:
        raise HTTPException(400, "TELEGRAM_PUBLIC_BASE_URL is not configured")
    if not base.startswith("https://"):
        raise HTTPException(
            400,
            "Telegram requires the webhook URL to be served over HTTPS. Got: " + base[:60],
        )
    try:
        result = await telegram_service.set_webhook(
            base, secret_token=config.TELEGRAM_WEBHOOK_SECRET
        )
    except telegram_service.TelegramApiError as exc:
        raise HTTPException(502, f"setWebhook failed: {exc.description or exc}")
    _safe_audit(
        db, action="admin.telegram.webhook.register", actor_user_id=admin.id,
        target_type="telegram", target_id=None,
        metadata={"base": base},
    )
    return {"ok": True, "result": result}


@router.delete("/webhook")
async def delete_webhook(
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    _require_enabled()
    try:
        result = await telegram_service.delete_webhook(drop_pending=False)
    except telegram_service.TelegramApiError as exc:
        raise HTTPException(502, f"deleteWebhook failed: {exc.description or exc}")
    _safe_audit(
        db, action="admin.telegram.webhook.delete", actor_user_id=admin.id,
        target_type="telegram", target_id=None,
    )
    return {"ok": True, "result": result}


# -- Helper exposed for the admin/users detail page --------------------------

@router.get("/users-by-app-user/{user_id}", response_model=Optional[AdminTelegramUserItem])
async def get_telegram_for_app_user(
    user_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    row = db.query(TelegramUser).filter(TelegramUser.linked_user_id == user_id).first()
    if row is None:
        return None
    return _to_item(db, row)
