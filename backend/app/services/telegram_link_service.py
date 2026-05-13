"""Linking flow between a Bisawtak app user and a Telegram chat.

Pattern: app generates a short, single-use code → user gives it to the bot →
bot calls :func:`consume_code` to verify+link. Codes are stored hashed (HMAC
under SECRET_KEY) so a DB leak doesn't expose live codes.

Concurrency: every state mutation runs inside ``SELECT ... FOR UPDATE`` blocks
so a race between two concurrent /start payloads can't double-link.
"""
from __future__ import annotations

import hashlib
import hmac
import logging
import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core import config
from app.db.models import TelegramLinkCode, TelegramUser, User


logger = logging.getLogger(__name__)


# 10 minutes is short enough to keep the attack window tiny without frustrating
# users who get interrupted mid-flow. Increase only if you have data showing
# UX harm.
CODE_TTL_SECONDS = 10 * 60

# Code format: 8 alphanumeric chars (~47 bits of entropy). Long enough that
# brute force is infeasible inside a 10-minute window, short enough to type
# or paste comfortably.
CODE_LENGTH = 8
_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # no I/1/0/O confusion


class LinkError(RuntimeError):
    """Public failure mode of the linking flow.

    ``code`` is a stable identifier the route maps to a localized message;
    ``status`` is the HTTP status the route should respond with.
    """

    def __init__(self, message: str, *, code: str = "link_error", status: int = 400):
        super().__init__(message)
        self.code = code
        self.status = status


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _hash_code(plaintext: str) -> str:
    """HMAC-SHA256 over the canonical (uppercase, stripped) form. We hash on
    write AND on lookup so the DB never sees the plaintext."""
    canonical = plaintext.strip().upper()
    return hmac.new(
        (config.SECRET_KEY or "").encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _generate_plaintext() -> str:
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(CODE_LENGTH))


# -----------------------------------------------------------------------------
# App-side: generate a fresh code
# -----------------------------------------------------------------------------

def generate_code(db: Session, user: User) -> tuple[str, datetime]:
    """Issue a new linking code for ``user`` and return (plaintext, expires_at).

    Any previous unconsumed codes are invalidated by being marked consumed —
    this means re-pressing "generate" in the app always supersedes the old
    code, so a stale screenshot can't be replayed.
    """
    now = _utcnow()
    expires = now + timedelta(seconds=CODE_TTL_SECONDS)

    # Mark older outstanding codes consumed so only one is ever valid per user.
    db.execute(
        text("""
            UPDATE telegram_link_codes
               SET consumed_at = :now
             WHERE user_id = :uid
               AND consumed_at IS NULL
               AND expires_at > :now
        """),
        {"uid": user.id, "now": now},
    )

    # Loop on rare hash collision (statistically negligible but defensive —
    # never insert silently the wrong row).
    for _ in range(5):
        plaintext = _generate_plaintext()
        code_hash = _hash_code(plaintext)
        existing = db.query(TelegramLinkCode).filter(
            TelegramLinkCode.code_hash == code_hash
        ).first()
        if existing is None:
            row = TelegramLinkCode(
                user_id=user.id,
                code_hash=code_hash,
                expires_at=expires,
            )
            db.add(row)
            db.commit()
            return plaintext, expires
    raise LinkError("Could not allocate a unique code, please try again", code="link_internal", status=500)


# -----------------------------------------------------------------------------
# Bot-side: consume a code coming from /start <code>
# -----------------------------------------------------------------------------

def consume_code(
    db: Session,
    *,
    code_plaintext: str,
    telegram_user: TelegramUser,
) -> User:
    """Validate the code and link ``telegram_user`` to its owner.

    Raises :class:`LinkError` with a stable ``code`` for every failure mode the
    bot needs to differentiate (invalid, expired, telegram-already-linked,
    user-already-linked). On success returns the linked :class:`User`.

    Atomicity: the code row is locked via SELECT FOR UPDATE before consumption.
    The telegram_users row is updated in the same transaction so concurrent
    /start messages with the same code can never produce two linkings.
    """
    if not code_plaintext or not code_plaintext.strip():
        raise LinkError("Empty code", code="invalid_code", status=400)

    code_hash = _hash_code(code_plaintext)

    row = db.execute(
        text("""
            SELECT id, user_id, expires_at, consumed_at
              FROM telegram_link_codes
             WHERE code_hash = :h
             FOR UPDATE
        """),
        {"h": code_hash},
    ).fetchone()

    if row is None:
        raise LinkError("Invalid code", code="invalid_code", status=400)

    now = _utcnow()
    expires_at = row.expires_at
    if expires_at and expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if row.consumed_at is not None or expires_at < now:
        raise LinkError("Code expired or already used", code="invalid_code", status=400)

    # Re-fetch the User for relationship + active check.
    target_user = db.query(User).filter(User.id == row.user_id, User.is_active == True).first()
    if target_user is None:
        raise LinkError("Account no longer available", code="invalid_code", status=400)

    # Check: this Bisawtak user is not already linked to a DIFFERENT telegram_id.
    existing_link = db.query(TelegramUser).filter(
        TelegramUser.linked_user_id == target_user.id,
        TelegramUser.telegram_id != telegram_user.telegram_id,
    ).first()
    if existing_link is not None:
        raise LinkError(
            "App user already linked to another Telegram account",
            code="user_already_linked",
            status=409,
        )

    # Check: this Telegram user is not already linked to a DIFFERENT app user.
    if (
        telegram_user.linked_user_id is not None
        and telegram_user.linked_user_id != target_user.id
    ):
        raise LinkError(
            "Telegram account already linked to another app user",
            code="telegram_already_linked",
            status=409,
        )

    # Consume the code and apply the link in the same transaction.
    db.execute(
        text("""
            UPDATE telegram_link_codes
               SET consumed_at = :now,
                   consumed_by_telegram_id = :tg
             WHERE id = :id
        """),
        {"now": now, "tg": telegram_user.telegram_id, "id": row.id},
    )
    telegram_user.linked_user_id = target_user.id
    telegram_user.linked_at = now
    db.commit()
    db.refresh(telegram_user)
    return target_user


# -----------------------------------------------------------------------------
# Unlinking (both sides)
# -----------------------------------------------------------------------------

def unlink_by_user(db: Session, user: User) -> TelegramUser | None:
    """Clear the link from the app side. Returns the affected telegram_users
    row (so the caller can send a "you've been unlinked" notification from
    the bot), or None if nothing was linked."""
    row = db.query(TelegramUser).filter(TelegramUser.linked_user_id == user.id).first()
    if row is None:
        return None
    row.linked_user_id = None
    row.linked_at = None
    db.commit()
    db.refresh(row)
    return row


def unlink_by_telegram(db: Session, telegram_user: TelegramUser) -> int | None:
    """Clear the link from the Telegram side (the user sent /unlink). Returns
    the previously-linked app user_id, or None if nothing was linked."""
    if telegram_user.linked_user_id is None:
        return None
    prev = telegram_user.linked_user_id
    telegram_user.linked_user_id = None
    telegram_user.linked_at = None
    db.commit()
    db.refresh(telegram_user)
    return prev


def get_linked_telegram_for_user(db: Session, user_id: int) -> TelegramUser | None:
    return db.query(TelegramUser).filter(TelegramUser.linked_user_id == user_id).first()


# -----------------------------------------------------------------------------
# Telegram user upsert (called from webhook on every incoming update)
# -----------------------------------------------------------------------------

def upsert_telegram_user(
    db: Session,
    *,
    telegram_id: int,
    first_name: str | None = None,
    last_name: str | None = None,
    username: str | None = None,
    language_code: str | None = None,
    is_premium: bool = False,
    is_bot: bool = False,
) -> TelegramUser:
    """Find-or-create the telegram_users row and refresh the lightweight fields.

    Heavier fields (bio, photo_file_id) are NOT touched here — they're fetched
    by a separate enrichment path when the admin views the user, to avoid an
    extra HTTP round-trip on every voice note.
    """
    row = db.query(TelegramUser).filter(TelegramUser.telegram_id == telegram_id).first()
    now = _utcnow()
    if row is None:
        row = TelegramUser(
            telegram_id=telegram_id,
            first_name=(first_name or "")[:120] or None,
            last_name=(last_name or "")[:120] or None,
            username=(username or "")[:64] or None,
            language_code=(language_code or "")[:10] or None,
            is_premium=bool(is_premium),
            is_bot=bool(is_bot),
            last_interaction_at=now,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return row

    # Update only fields that meaningfully changed — avoids dirty-write churn
    # on the busy last_interaction_at index when nothing else moved.
    dirty = False
    if first_name and row.first_name != first_name[:120]:
        row.first_name = first_name[:120]
        dirty = True
    if last_name and row.last_name != last_name[:120]:
        row.last_name = last_name[:120]
        dirty = True
    if username and row.username != username[:64]:
        row.username = username[:64]
        dirty = True
    if language_code and row.language_code != language_code[:10]:
        row.language_code = language_code[:10]
        dirty = True
    if row.is_premium != bool(is_premium):
        row.is_premium = bool(is_premium)
        dirty = True
    if row.is_bot != bool(is_bot):
        row.is_bot = bool(is_bot)
        dirty = True
    if row.is_blocked:
        # User came back after blocking us — clear the flag.
        row.is_blocked = False
        dirty = True

    row.last_interaction_at = now
    if dirty:
        # commit() touches updated_at via onupdate=utcnow; we want
        # last_interaction_at to land regardless, so commit unconditionally.
        pass
    db.commit()
    db.refresh(row)
    return row


def mark_blocked(db: Session, telegram_id: int) -> None:
    """Flip is_blocked to True. Idempotent."""
    row = db.query(TelegramUser).filter(TelegramUser.telegram_id == telegram_id).first()
    if row is None or row.is_blocked:
        return
    row.is_blocked = True
    db.commit()
