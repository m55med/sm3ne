"""Telegram bot webhook receiver.

Endpoint: ``POST /api/v1/webhooks/telegram``

Security:
  * The request is authenticated via the ``X-Telegram-Bot-Api-Secret-Token``
    header — Telegram sends it back exactly as we registered with setWebhook.
    A wrong / missing token is rejected with 401 (the constant-time compare
    happens in :func:`telegram_service.verify_webhook_secret`).
  * Updates from unknown chat types (channel, group) are ignored — we only
    answer 1:1 conversations.

Behavior for a single update:
  * Always upsert ``telegram_users`` (so the admin dashboard sees everyone
    who's ever touched the bot, even spammers and the unlinked).
  * Commands: ``/start [code]``, ``/status``, ``/unlink``, ``/help``.
  * Voice / audio / video_note attachments: if linked → transcribe → reply
    with the text. If unlinked → reply with the "install the app" template.
  * Everything else: send the ``unsupported_message`` template.

Failure handling: the webhook ALWAYS returns 200 OK. Telegram retries on any
non-200 (up to 24 hours), and a retry on a bug would just loop. We log the
exception, swallow it, and reply to the user with the ``transcription_failed``
template when applicable.
"""
from __future__ import annotations

import logging
import os
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Header, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.config import TELEGRAM_ENABLED
from app.db.database import SessionLocal
from app.db.models import TelegramUser, User
from app.services import (
    file_validation,
    subscription_service,
    telegram_bot_messages,
    telegram_link_service,
    telegram_service,
    transcription_orchestrator,
)


router = APIRouter(tags=["telegram-webhook"])
logger = logging.getLogger(__name__)


# Telegram caps voice messages at 1MB/min audio; for documents and audio files
# we still need to refuse anything bigger than 20MB (api.telegram.org limit).
# DEFAULT_DOWNLOAD_LIMIT_BYTES from telegram_service is the source of truth.


@router.post("/webhooks/telegram")
async def webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    x_telegram_bot_api_secret_token: str | None = Header(default=None),
):
    """Receive a Telegram update.

    We acknowledge immediately (200 OK with `{"ok": true}`) and process the
    update in a background task. This keeps the response under Telegram's
    webhook timeout (~75s for the bot infra) so we never accidentally
    duplicate-process a long transcription.
    """
    if not TELEGRAM_ENABLED:
        # Don't 404 — Telegram retries 4xx. Quietly accept and discard while
        # the integration is being set up.
        return {"ok": True, "ignored": "telegram_disabled"}

    if not telegram_service.verify_webhook_secret(x_telegram_bot_api_secret_token):
        # 401 explicitly: anyone who can reach this URL but doesn't know the
        # secret should NOT get a 200, so Telegram's "you're not me" detection
        # works. Telegram itself never reaches this branch (it always sends
        # the secret), so this only catches misconfiguration or attackers.
        logger.warning("Telegram webhook rejected: bad/missing secret token")
        raise HTTPException(401, "Bad secret")

    try:
        update = await request.json()
    except Exception:  # noqa: BLE001
        logger.warning("Telegram webhook with non-JSON body")
        return {"ok": True}

    background_tasks.add_task(_process_update_safely, update)
    return {"ok": True}


async def _process_update_safely(update: dict) -> None:
    """Background task wrapper. Owns its own DB session and swallows
    exceptions — we never want a buggy handler to surface as a 500 to
    Telegram (which would trigger a retry loop)."""
    try:
        with SessionLocal() as db:
            await _dispatch_update(db, update)
    except Exception:  # noqa: BLE001
        logger.exception(
            "Telegram webhook background task crashed (update=%s)", _short(update),
        )


# -- Dispatcher --------------------------------------------------------------

async def _dispatch_update(db: Session, update: dict) -> None:
    # Channel posts, edited messages, and inline queries are unsupported.
    # Only message + my_chat_member are handled.
    if "my_chat_member" in update:
        _handle_my_chat_member(db, update["my_chat_member"])
        return

    message = update.get("message") or update.get("edited_message")
    if not message:
        return

    chat = message.get("chat") or {}
    if chat.get("type") != "private":
        # Group/channel — ignore, we're a DM bot.
        return

    from_user = message.get("from") or {}
    if not from_user.get("id"):
        return

    if from_user.get("is_bot"):
        # Bots shouldn't be talking to bots; ignore.
        return

    tg_user = telegram_link_service.upsert_telegram_user(
        db,
        telegram_id=int(from_user["id"]),
        first_name=from_user.get("first_name"),
        last_name=from_user.get("last_name"),
        username=from_user.get("username"),
        language_code=from_user.get("language_code"),
        is_premium=bool(from_user.get("is_premium")),
        is_bot=bool(from_user.get("is_bot")),
    )

    chat_id = int(chat["id"])
    text_raw = (message.get("text") or "").strip()

    # ----- Commands -----
    if text_raw.startswith("/"):
        await _handle_command(db, tg_user, chat_id, text_raw, message)
        return

    # ----- Voice / audio / video_note -----
    audio_file_id, audio_kind, file_size, mime_type, duration = _extract_audio(message)
    if audio_file_id:
        await _handle_audio(
            db, tg_user, chat_id, message,
            file_id=audio_file_id, kind=audio_kind,
            file_size=file_size, mime_type=mime_type, duration_hint=duration,
        )
        return

    # ----- Anything else -----
    await _safe_send(chat_id, telegram_bot_messages.render(db, "unsupported_message"))


# -- Commands ----------------------------------------------------------------

async def _handle_command(
    db: Session, tg_user: TelegramUser, chat_id: int, text: str, message: dict
) -> None:
    # Strip the optional "@botname" suffix Telegram appends in group contexts.
    head, _, rest = text.partition(" ")
    cmd = head.split("@", 1)[0].lower()
    args = rest.strip()

    if cmd == "/start":
        if args:
            await _handle_link_attempt(db, tg_user, chat_id, args)
            return
        # No payload — show contextual welcome.
        if tg_user.linked_user_id is not None:
            user = db.query(User).filter(User.id == tg_user.linked_user_id).first()
            first_name = (user.full_name or user.email) if user else (tg_user.first_name or "")
            await _safe_send(chat_id, telegram_bot_messages.render(
                db, "welcome_linked", first_name=first_name,
            ))
        else:
            await _safe_send(chat_id, telegram_bot_messages.render(db, "welcome_unlinked"))
        return

    if cmd == "/status":
        await _handle_status(db, tg_user, chat_id)
        return

    if cmd == "/unlink":
        prev_user_id = telegram_link_service.unlink_by_telegram(db, tg_user)
        if prev_user_id is None:
            await _safe_send(chat_id, telegram_bot_messages.render(db, "unlink_not_linked"))
        else:
            await _safe_send(chat_id, telegram_bot_messages.render(db, "unlink_success"))
        return

    if cmd == "/help":
        await _safe_send(chat_id, telegram_bot_messages.render(db, "help"))
        return

    # Unknown command — fall back to help.
    await _safe_send(chat_id, telegram_bot_messages.render(db, "help"))


async def _handle_link_attempt(
    db: Session, tg_user: TelegramUser, chat_id: int, candidate_code: str
) -> None:
    candidate_code = candidate_code.strip().split()[0][:64]  # 1st token, cap len
    try:
        linked_user = telegram_link_service.consume_code(
            db,
            code_plaintext=candidate_code,
            telegram_user=tg_user,
        )
    except telegram_link_service.LinkError as exc:
        if exc.code == "telegram_already_linked":
            key = "link_already_linked_other"
        elif exc.code == "user_already_linked":
            key = "link_user_already_linked"
        else:
            key = "link_invalid_code"
        await _safe_send(chat_id, telegram_bot_messages.render(db, key))
        return

    first_name = (linked_user.full_name or linked_user.email) if linked_user else (tg_user.first_name or "")
    await _safe_send(chat_id, telegram_bot_messages.render(
        db, "link_success", first_name=first_name,
    ))


async def _handle_status(db: Session, tg_user: TelegramUser, chat_id: int) -> None:
    if tg_user.linked_user_id is None:
        await _safe_send(chat_id, telegram_bot_messages.render(db, "status_unlinked"))
        return

    user = db.query(User).filter(User.id == tg_user.linked_user_id).first()
    if user is None:
        await _safe_send(chat_id, telegram_bot_messages.render(db, "status_unlinked"))
        return

    plan = subscription_service.get_user_plan(db, user.id)
    # Daily-used count: mirror the cheap query in deps._effective_daily_limit.
    from datetime import datetime, timezone
    from sqlalchemy import func
    from app.db.models import TranscriptionRequest
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    used_today = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= today_start,
        TranscriptionRequest.status != "failed",
    ).scalar() or 0

    daily_limit = plan.daily_request_limit if plan else 20
    max_seconds = plan.max_audio_seconds if plan else 30
    max_seconds_label = "بدون حد" if max_seconds < 0 else f"{max_seconds} ثانية"
    daily_limit_label = "بدون حد" if daily_limit < 0 else str(daily_limit)

    await _safe_send(chat_id, telegram_bot_messages.render(
        db, "status_linked",
        username=user.full_name or user.email or "",
        plan=plan.name if plan else "free",
        used_today=used_today,
        daily_limit=daily_limit_label,
        max_seconds_label=max_seconds_label,
    ))


# -- Voice / audio handling --------------------------------------------------

def _extract_audio(message: dict) -> tuple[str | None, str | None, int | None, str | None, int | None]:
    """Pick the best audio attachment off a Telegram message.

    Returns (file_id, kind, file_size, mime_type, duration_seconds). All
    optional. We accept ``voice`` (the recorded blob from the mic button),
    ``audio`` (audio file or song), ``video_note`` (the round video clip —
    has audio we can transcribe), and ``document`` with an audio mime type
    (rare, but some forwarders ship voice notes as documents).
    """
    for kind in ("voice", "audio", "video_note"):
        obj = message.get(kind)
        if obj:
            return (
                obj.get("file_id"),
                kind,
                obj.get("file_size"),
                obj.get("mime_type"),
                obj.get("duration"),
            )
    doc = message.get("document")
    if doc and (doc.get("mime_type") or "").lower().startswith(("audio/", "application/ogg")):
        return (
            doc.get("file_id"),
            "document",
            doc.get("file_size"),
            doc.get("mime_type"),
            None,
        )
    return None, None, None, None, None


_TG_MIME_TO_EXT = {
    "audio/ogg": ".ogg",
    "audio/opus": ".opus",
    "audio/mpeg": ".mp3",
    "audio/mp3": ".mp3",
    "audio/mp4": ".m4a",
    "audio/x-m4a": ".m4a",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/aac": ".aac",
    "audio/flac": ".flac",
    "audio/webm": ".webm",
    "video/mp4": ".mp4",  # video_note
    "application/ogg": ".ogg",
}


def _ext_from_mime(mime: str | None, kind: str | None) -> str:
    if mime:
        ext = _TG_MIME_TO_EXT.get(mime.lower())
        if ext:
            return ext
    # Telegram voice messages are always Opus-in-Ogg.
    if kind == "voice":
        return ".ogg"
    return ".bin"


async def _handle_audio(
    db: Session,
    tg_user: TelegramUser,
    chat_id: int,
    message: dict,
    *,
    file_id: str,
    kind: str,
    file_size: int | None,
    mime_type: str | None,
    duration_hint: int | None,
) -> None:
    """Common path for voice/audio/video_note/audio-document messages."""
    # Unlinked → reply with install-the-app, but still log the interaction.
    if tg_user.linked_user_id is None:
        await _safe_send(chat_id, telegram_bot_messages.render(
            db, "not_linked_voice",
            store_links=telegram_bot_messages.store_links_block(),
        ))
        return

    user = db.query(User).filter(
        User.id == tg_user.linked_user_id, User.is_active == True,  # noqa: E712
    ).first()
    if user is None:
        # Linked user soft-deleted — wipe the link silently and tell them.
        telegram_link_service.unlink_by_telegram(db, tg_user)
        await _safe_send(chat_id, telegram_bot_messages.render(db, "status_unlinked"))
        return

    # Pre-flight: file size cap.
    if file_size and file_size > telegram_service.max_download_bytes():
        await _safe_send(chat_id, telegram_bot_messages.render(db, "file_too_large"))
        return

    # Pre-flight: daily quota. We mirror check_daily_quota's logic but inline
    # because that helper requires a Request object — we don't have one here.
    plan = subscription_service.get_user_plan(db, user.id)
    if not _has_quota(db, user.id, plan):
        await _safe_send(chat_id, telegram_bot_messages.render(
            db, "quota_exceeded",
            limit=plan.daily_request_limit if plan else 20,
            plan=plan.name if plan else "free",
        ))
        return

    # Show typing indicator while we work.
    await telegram_service.send_chat_action(chat_id, "typing")

    # Resolve file_id → path → download to a tmpfile.
    tmp_path: str | None = None
    try:
        info = await telegram_service.get_file(file_id)
        file_path = info.get("file_path") or ""
        if not file_path:
            raise RuntimeError("getFile returned no file_path")
        # Telegram's authoritative size (vs the one in the message envelope).
        api_size = info.get("file_size")
        if api_size and api_size > telegram_service.max_download_bytes():
            await _safe_send(chat_id, telegram_bot_messages.render(db, "file_too_large"))
            return
        suffix = _ext_from_mime(mime_type, kind)
        tmp_path = await telegram_service.download_file_to_tempfile(file_path, suffix=suffix)
    except telegram_service.TelegramApiError as exc:
        logger.warning("Telegram file fetch failed: %s", exc)
        await _safe_send(chat_id, telegram_bot_messages.render(db, "transcription_failed"))
        return
    except Exception:  # noqa: BLE001
        logger.exception("Telegram file fetch crashed")
        await _safe_send(chat_id, telegram_bot_messages.render(db, "transcription_failed"))
        return

    # Validate magic bytes — if Telegram sent a malformed payload (rare) we
    # refuse rather than feed garbage to the provider.
    try:
        with open(tmp_path, "rb") as f:
            head = f.read(64)
        ok, _label = file_validation._looks_like_audio(head)
        if not ok:
            await _safe_send(chat_id, telegram_bot_messages.render(db, "transcription_failed"))
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            return
    except OSError:
        await _safe_send(chat_id, telegram_bot_messages.render(db, "transcription_failed"))
        return

    # Will the audio be trimmed because of the plan cap? If yes, we send a
    # heads-up BEFORE the transcription so the user understands the truncation.
    if plan and plan.max_audio_seconds > 0 and duration_hint and duration_hint > plan.max_audio_seconds:
        await _safe_send(chat_id, telegram_bot_messages.render(
            db, "audio_too_long", max_seconds=plan.max_audio_seconds,
        ))

    # Hand off to the existing transcription pipeline. The orchestrator
    # deletes the tmpfile on its way out (success OR failure) — we must not
    # touch it after this call.
    try:
        result = await transcription_orchestrator.run_transcription(
            db,
            user_id=user.id,
            api_key_id=None,
            filename=f"telegram_{kind or 'voice'}{os.path.splitext(tmp_path)[1]}",
            tmp_path=tmp_path,
            plan=plan,
            is_live_recording=False,
            resolved_source="telegram",
        )
    except HTTPException as exc:
        logger.info("Transcription rejected by pipeline: %s", exc.detail)
        await _safe_send(chat_id, telegram_bot_messages.render(db, "transcription_failed"))
        return
    except Exception:  # noqa: BLE001
        logger.exception("Transcription failed (telegram)")
        await _safe_send(chat_id, telegram_bot_messages.render(db, "transcription_failed"))
        return

    text_out = (result.get("text") or "").strip() if isinstance(result, dict) else ""
    if not text_out:
        # Pipeline succeeded but yielded an empty string (silent audio).
        await _safe_send(chat_id, "🤫 لم أستطع التعرف على أي كلام في هذا الملف.")
        return

    # Telegram cap on a single message body is 4096 chars. Split if longer.
    await _send_chunked(chat_id, text_out, reply_to=message.get("message_id"))


def _has_quota(db: Session, user_id: int, plan) -> bool:
    """Return True if the user has at least one transcription left today.

    We deliberately don't call ``deps.check_daily_quota`` here because it
    needs a Request object (it bookkeeps slowapi state). For the webhook we
    implement the same SQL count + plan-limit comparison directly.
    """
    if plan is None:
        return True
    daily_limit = plan.daily_request_limit
    if daily_limit < 0:
        return True
    from datetime import datetime, timezone
    from sqlalchemy import func
    from app.db.models import TranscriptionRequest
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    used = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user_id,
        TranscriptionRequest.created_at >= today_start,
        TranscriptionRequest.status != "failed",
    ).scalar() or 0
    return used < daily_limit


async def _send_chunked(chat_id: int, body: str, *, reply_to: int | None) -> None:
    """Send ``body`` in <=4000-char chunks. Telegram's hard cap is 4096; we
    leave headroom for the header we prepend on multi-part messages."""
    CHUNK = 3900
    if len(body) <= CHUNK:
        await _safe_send(chat_id, body, reply_to=reply_to, parse_mode=None)
        return

    parts = []
    for i in range(0, len(body), CHUNK):
        parts.append(body[i:i + CHUNK])
    total = len(parts)
    for idx, part in enumerate(parts, start=1):
        prefix = f"[{idx}/{total}]\n" if total > 1 else ""
        await _safe_send(
            chat_id, prefix + part,
            reply_to=reply_to if idx == 1 else None,
            parse_mode=None,
        )


# -- Send helpers ------------------------------------------------------------

async def _safe_send(
    chat_id: int,
    text: str,
    *,
    reply_to: int | None = None,
    parse_mode: str | None = "Markdown",
) -> None:
    """Send a message and detect 'bot was blocked by the user' so we mark the
    row as blocked without spamming logs."""
    if not text:
        return
    try:
        await telegram_service.send_message(
            chat_id, text, parse_mode=parse_mode, reply_to_message_id=reply_to,
        )
    except telegram_service.TelegramApiError as exc:
        msg = (exc.description or str(exc)).lower()
        if (
            "blocked" in msg
            or "kicked" in msg
            or "user is deactivated" in msg
            or exc.error_code == 403
        ):
            try:
                from app.db.database import SessionLocal
                with SessionLocal() as db:
                    telegram_link_service.mark_blocked(db, chat_id)
            except Exception:  # noqa: BLE001
                pass
        else:
            logger.warning("send_message failed: %s", exc)


def _handle_my_chat_member(db: Session, payload: dict) -> None:
    """Telegram pushes a ``my_chat_member`` update whenever a user blocks or
    unblocks the bot. We use it as our authoritative block-state signal."""
    chat = payload.get("chat") or {}
    if chat.get("type") != "private":
        return
    new_status = ((payload.get("new_chat_member") or {}).get("status") or "").lower()
    chat_id = chat.get("id")
    if not chat_id:
        return
    # 'kicked' = the user blocked the bot. 'member' = unblocked / re-started.
    if new_status == "kicked":
        telegram_link_service.mark_blocked(db, int(chat_id))
    elif new_status == "member":
        # Clear the flag if we had it set.
        from app.db.models import TelegramUser
        row = db.query(TelegramUser).filter(TelegramUser.telegram_id == int(chat_id)).first()
        if row and row.is_blocked:
            row.is_blocked = False
            db.commit()


def _short(update: dict) -> str:
    """Compact one-liner for log messages (don't dump entire JSON in case it
    contains the message body — keep logs grep-friendly)."""
    update_id = update.get("update_id")
    msg = update.get("message") or update.get("edited_message") or {}
    kind = "msg" if "message" in update else ("edit" if "edited_message" in update else "other")
    from_user = (msg.get("from") or {}).get("id")
    return f"update_id={update_id} kind={kind} from={from_user}"
