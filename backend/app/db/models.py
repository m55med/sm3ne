from datetime import datetime, timezone
from sqlalchemy import (
    Column, Integer, String, Float, Boolean, Text, DateTime, ForeignKey, Index,
    text,
)
from sqlalchemy.orm import relationship
from app.db.database import Base


def utcnow():
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"
    # Partial unique index ensures (auth_provider, provider_id) pairs are unique
    # for social logins (provider_id IS NOT NULL). This guards against a stolen
    # social-id reuse from being attached to two different local accounts.
    __table_args__ = (
        Index(
            "idx_users_provider",
            "auth_provider", "provider_id",
            unique=True,
            postgresql_where=text("provider_id IS NOT NULL"),
        ),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    public_id = Column(String(12), unique=True, nullable=True, index=True)
    username = Column(String(50), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=True, index=True)
    password_hash = Column(String(255), nullable=True)  # null for social-only
    full_name = Column(String(100), nullable=True)
    auth_provider = Column(String(20), default="local")  # local, google, apple
    provider_id = Column(String(255), nullable=True)
    role = Column(String(20), default="user")  # user, admin
    is_active = Column(Boolean, default=True)
    # Capped at 20000 chars at the schema layer (Backend-2); kept as Text here so
    # legacy rows don't trip a DB-side CHECK during migration.
    survey_response = Column(Text, nullable=True)  # JSON string, max 20000 chars (enforced in schema)
    # Last password change timestamp. Used to invalidate tokens issued prior to
    # the change (defense-in-depth against stolen tokens).
    # NOTE: requires DDL: ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMP WITH TIME ZONE
    password_changed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    subscriptions = relationship("UserSubscription", back_populates="user")
    transcription_requests = relationship("TranscriptionRequest", back_populates="user")
    api_keys = relationship("ApiKey", foreign_keys="ApiKey.user_id", back_populates="user")


class Plan(Base):
    __tablename__ = "plans"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(50), unique=True, nullable=False)  # free, monthly, annual
    price = Column(Float, default=0)
    original_price = Column(Float, default=0)
    max_audio_seconds = Column(Integer, default=30)  # -1 = unlimited
    daily_request_limit = Column(Integer, default=100)  # -1 = unlimited
    monthly_request_limit = Column(Integer, nullable=True)  # null = not enforced; -1 = unlimited
    api_daily_request_limit = Column(Integer, default=-1)  # -1 = same as daily_request_limit; 0 = API disabled
    rpm_default = Column(Integer, default=10)
    api_keys_allowed = Column(Integer, default=1)
    description = Column(String(500), nullable=True)
    is_active = Column(Boolean, default=True)
    # Per-plan transcription routing — when set, overrides the global admin choice.
    # Both null = inherit from admin's global settings.
    transcription_provider = Column(String(20), nullable=True)
    transcription_model = Column(String(80), nullable=True)

    subscriptions = relationship("UserSubscription", back_populates="plan")


class UserSubscription(Base):
    __tablename__ = "user_subscriptions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    plan_id = Column(Integer, ForeignKey("plans.id"), nullable=False)
    starts_at = Column(DateTime(timezone=True), default=utcnow)
    expires_at = Column(DateTime(timezone=True), nullable=True)  # null = free (never expires)
    is_active = Column(Boolean, default=True)
    coupon_id = Column(Integer, ForeignKey("coupons.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", back_populates="subscriptions")
    plan = relationship("Plan", back_populates="subscriptions")
    coupon = relationship("Coupon")


class Coupon(Base):
    __tablename__ = "coupons"

    id = Column(Integer, primary_key=True, autoincrement=True)
    code = Column(String(50), unique=True, nullable=False, index=True)
    plan_id = Column(Integer, ForeignKey("plans.id"), nullable=False)
    duration_days = Column(Integer, default=30)
    max_uses = Column(Integer, default=-1)  # -1 = unlimited
    times_used = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)
    created_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)
    expires_at = Column(DateTime(timezone=True), nullable=True)

    plan = relationship("Plan")


class TranscriptionRequest(Base):
    __tablename__ = "transcription_requests"
    __table_args__ = (
        Index("idx_requests_user_created", "user_id", "created_at"),
        Index("idx_requests_apikey_created", "api_key_id", "created_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    api_key_id = Column(Integer, ForeignKey("api_keys.id"), nullable=True, index=True)
    filename = Column(String(255), nullable=True)
    duration_seconds = Column(Float, default=0)
    processed_seconds = Column(Float, default=0)
    language = Column(String(10), nullable=True)
    word_count = Column(Integer, default=0)
    was_trimmed = Column(Boolean, default=False)
    status = Column(String(20), default="completed", index=True)  # processing | completed | failed
    error_message = Column(String(500), nullable=True)
    source = Column(String(20), default="upload", index=True)  # upload | recording | share | api
    is_live_recording = Column(Boolean, default=False)
    # Point-in-time snapshot of the user's plan at the moment this request was created.
    # Never updated afterwards — gives the admin dashboard truthful history even after
    # the user upgrades/downgrades.
    plan_name_at_request = Column(String(50), nullable=True)
    plan_source_at_request = Column(String(20), nullable=True)
    daily_limit_at_request = Column(Integer, nullable=True)
    monthly_limit_at_request = Column(Integer, nullable=True)
    daily_used_at_request = Column(Integer, nullable=True)
    # Which transcription backend served this request — used by the admin usage panel
    # to bill/credit each provider separately. Older rows are backfilled to 'whisper'.
    provider_used = Column(String(20), nullable=True, index=True)
    # The specific sub-model the provider used (e.g. 'whisper-large-v3-turbo',
    # 'gemini-flash-latest', 'enhanced'). Null for legacy rows.
    model_used = Column(String(80), nullable=True)
    # Wall-clock time spent in the transcription dispatch (provider call), ms.
    latency_ms = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", back_populates="transcription_requests")


class ApiKey(Base):
    __tablename__ = "api_keys"
    __table_args__ = (
        Index("idx_apikeys_user_active", "user_id", "is_active"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    name = Column(String(100), nullable=False)
    key_prefix = Column(String(20), nullable=False, index=True)
    key_hash = Column(String(64), nullable=False, unique=True, index=True)
    requests_per_minute = Column(Integer, nullable=True)  # null = use plan default
    requests_per_day = Column(Integer, nullable=True)  # null = use plan default
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Boolean, default=True)
    created_by_admin_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)

    user = relationship("User", foreign_keys=[user_id], back_populates="api_keys")


class PasswordReset(Base):
    __tablename__ = "password_resets"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    otp = Column(String(6), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used = Column(Boolean, default=False)
    # Backend-2 increments this on each failed verify; after 5 failures the
    # route marks `used=True` so the OTP becomes dead.
    # NOTE: requires DDL: ALTER TABLE password_resets ADD COLUMN IF NOT EXISTS failed_attempts INT DEFAULT 0
    failed_attempts = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), default=utcnow)


class SupportTicket(Base):
    __tablename__ = "support_tickets"
    __table_args__ = (
        Index("idx_tickets_user_created", "user_id", "created_at"),
        Index("idx_tickets_status_created", "status", "created_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    public_id = Column(String(12), unique=True, nullable=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    ticket_type = Column(String(20), nullable=False, default="contact")  # contact | suggestion | bug | other
    subject = Column(String(200), nullable=False)
    # Capped at the schema layer (Backend-2). Keep as Text so legacy rows are not truncated.
    message = Column(Text, nullable=False)
    status = Column(String(20), nullable=False, default="open", index=True)  # open | in_progress | resolved | closed
    created_at = Column(DateTime(timezone=True), default=utcnow)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    last_reply_at = Column(DateTime(timezone=True), nullable=True)


class TicketReply(Base):
    __tablename__ = "ticket_replies"
    __table_args__ = (
        Index("idx_ticket_replies_ticket_created", "ticket_id", "created_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    public_id = Column(String(12), unique=True, nullable=True, index=True)
    ticket_id = Column(Integer, ForeignKey("support_tickets.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    is_admin = Column(Boolean, default=False)
    message = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow)


class TicketAttachment(Base):
    """Image attachments on support tickets / replies. Used by the mobile
    contact form so deaf users can submit a screenshot of the issue. Files
    live on local disk; this row carries the metadata + a stable public_id
    that the download URL is built from.
    """
    __tablename__ = "ticket_attachments"
    __table_args__ = (
        Index("idx_ticket_attachments_ticket", "ticket_id", "created_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    public_id = Column(String(12), unique=True, nullable=False, index=True)
    ticket_id = Column(Integer, ForeignKey("support_tickets.id", ondelete="CASCADE"), nullable=False, index=True)
    # reply_id is set when the attachment was added with a specific reply; null
    # when it was attached at ticket creation time.
    reply_id = Column(Integer, ForeignKey("ticket_replies.id", ondelete="CASCADE"), nullable=True, index=True)
    uploaded_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    # Original filename — for the admin to see what the user submitted. Stored
    # filename on disk uses public_id so we don't have to sanitize this.
    original_filename = Column(String(255), nullable=True)
    mime_type = Column(String(80), nullable=False)
    size_bytes = Column(Integer, nullable=False)
    # Path relative to the uploads root, e.g. "tickets/<yy>/<mm>/<public_id>.png".
    # We never let user input near this path — see services/ticket_attachment_service.
    storage_path = Column(String(255), nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow)


class AccountDeletion(Base):
    """Audit trail of account deletions. Kept after the user row is hard-deleted
    so the admin can see who left, when, and why (legal / GDPR audit trail)."""
    __tablename__ = "account_deletions"
    __table_args__ = (
        Index("idx_account_deletions_created", "created_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_public_id = Column(String(12), nullable=True, index=True)
    username_snapshot = Column(String(50), nullable=True)
    email_snapshot = Column(String(255), nullable=True)
    auth_provider = Column(String(20), nullable=True)
    reason = Column(String(500), nullable=True)
    ip_address = Column(String(64), nullable=True)
    user_agent = Column(String(500), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)


class LoginEvent(Base):
    __tablename__ = "login_events"
    __table_args__ = (
        Index("idx_login_events_user_ts", "user_id", "created_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    username_attempted = Column(String(100), nullable=True)
    auth_provider = Column(String(20), nullable=False, default="local")
    event_type = Column(String(20), nullable=False, default="login")  # register | login | refresh
    success = Column(Boolean, default=True, index=True)
    error_message = Column(String(255), nullable=True)
    ip_address = Column(String(64), nullable=True, index=True)
    user_agent = Column(String(500), nullable=True)
    device_platform = Column(String(32), nullable=True)  # ios | android | web | unknown
    device_model = Column(String(128), nullable=True)
    device_os_version = Column(String(64), nullable=True)
    app_version = Column(String(32), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow, index=True)


class AppSetting(Base):
    """Generic key-value store for runtime-tunable app settings (admin dashboard).

    Used for cross-cutting toggles that should not require a deploy — currently
    just `transcription_provider`, but designed to grow.
    """
    __tablename__ = "app_settings"

    id = Column(Integer, primary_key=True, autoincrement=True)
    key = Column(String(80), unique=True, nullable=False, index=True)
    value = Column(String(255), nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    updated_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)


class TelegramUser(Base):
    """Every Telegram account that has interacted with the bot, regardless of
    whether they linked a Bisawtak app account.

    We store unlinked users too so the admin dashboard can broadcast / message
    them and so the same Telegram user keeps a stable history if they later
    link, unlink, and re-link.
    """
    __tablename__ = "telegram_users"
    __table_args__ = (
        Index("idx_tg_users_linked", "linked_user_id"),
        Index("idx_tg_users_last_seen", "last_interaction_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    # Telegram's own numeric user_id. Never reused, fits in BIGINT — but the
    # python int is unbounded so SQLAlchemy's Integer maps to BIGINT on
    # Postgres which is what we want.
    telegram_id = Column(Integer, unique=True, nullable=False, index=True)
    first_name = Column(String(120), nullable=True)
    last_name = Column(String(120), nullable=True)
    username = Column(String(64), nullable=True, index=True)
    language_code = Column(String(10), nullable=True)
    is_premium = Column(Boolean, default=False)
    is_bot = Column(Boolean, default=False)
    bio = Column(Text, nullable=True)
    # photo_file_id is Telegram's reference to the user's avatar; we resolve to
    # a download URL on-demand in the admin dashboard rather than rehosting.
    photo_file_id = Column(String(255), nullable=True)
    # Set when the user blocks the bot (we detect this via Bot API errors and
    # via "my_chat_member" updates with status='kicked').
    is_blocked = Column(Boolean, default=False, index=True)
    # The linked Bisawtak account, if any. NULL = unlinked. Cleared (not
    # deleted) when the user unlinks or deletes their app account.
    linked_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    linked_at = Column(DateTime(timezone=True), nullable=True)
    last_interaction_at = Column(DateTime(timezone=True), default=utcnow, index=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)

    linked_user = relationship("User", foreign_keys=[linked_user_id])


class TelegramLinkCode(Base):
    """One-time code generated in the mobile app and consumed by the Telegram
    bot to prove the same human controls both sides.

    Codes are single-use and expire after 10 minutes. We store a hashed copy
    (HMAC-SHA256 under SECRET_KEY, like API keys) so a DB leak doesn't hand the
    attacker working linking codes.
    """
    __tablename__ = "telegram_link_codes"
    __table_args__ = (
        Index("idx_tg_codes_user_active", "user_id", "consumed_at", "expires_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    code_hash = Column(String(64), nullable=False, unique=True, index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    consumed_at = Column(DateTime(timezone=True), nullable=True)
    consumed_by_telegram_id = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow)


class TelegramBotMessage(Base):
    """Admin-editable template strings the bot sends to users.

    Keys are stable identifiers (e.g. ``welcome``, ``link_success``, ``not_linked``,
    ``quota_exceeded``). Defaults are seeded on first startup; admins overwrite
    the row from the dashboard. When a key is missing from the DB the runtime
    falls back to a built-in default string.
    """
    __tablename__ = "telegram_bot_messages"

    id = Column(Integer, primary_key=True, autoincrement=True)
    key = Column(String(60), unique=True, nullable=False, index=True)
    text_ar = Column(Text, nullable=False)
    description = Column(String(255), nullable=True)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    updated_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)


class AuditLog(Base):
    """Append-only audit trail for security-sensitive actions.

    Backend-2's `audit_service.record(...)` writes here; admin routes read it
    for the activity panel. The companion DDL lives in lifespan.py so the table
    is created idempotently on every boot.
    """
    __tablename__ = "audit_logs"
    __table_args__ = (
        Index("idx_audit_actor_created", "actor_user_id", "created_at"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    actor_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    action = Column(String(60), nullable=False, index=True)
    target_type = Column(String(40), nullable=True)
    target_id = Column(Integer, nullable=True)
    # NOTE: SQLAlchemy reserves `metadata` on Declarative, so we expose the
    # Python attribute as `metadata_json` while keeping the DB column name `metadata`
    # to match the idempotent DDL in lifespan.py.
    metadata_json = Column("metadata", Text, nullable=True)
    ip_address = Column(String(64), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow, index=True)
