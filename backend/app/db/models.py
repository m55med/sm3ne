from datetime import datetime, timezone
from sqlalchemy import (
    Column, Integer, String, Float, Boolean, Text, DateTime, ForeignKey, Index
)
from sqlalchemy.orm import relationship
from app.db.database import Base


def utcnow():
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

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
    survey_response = Column(Text, nullable=True)  # JSON string
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

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

    subscriptions = relationship("UserSubscription", back_populates="plan")


class UserSubscription(Base):
    __tablename__ = "user_subscriptions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    plan_id = Column(Integer, ForeignKey("plans.id"), nullable=False)
    starts_at = Column(DateTime, default=utcnow)
    expires_at = Column(DateTime, nullable=True)  # null = free (never expires)
    is_active = Column(Boolean, default=True)
    coupon_id = Column(Integer, ForeignKey("coupons.id"), nullable=True)
    created_at = Column(DateTime, default=utcnow)

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
    created_at = Column(DateTime, default=utcnow)
    expires_at = Column(DateTime, nullable=True)

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
    # Point-in-time snapshot of the user's plan at the moment this request was created.
    # Never updated afterwards — gives the admin dashboard truthful history even after
    # the user upgrades/downgrades.
    plan_name_at_request = Column(String(50), nullable=True)
    plan_source_at_request = Column(String(20), nullable=True)
    daily_limit_at_request = Column(Integer, nullable=True)
    monthly_limit_at_request = Column(Integer, nullable=True)
    daily_used_at_request = Column(Integer, nullable=True)
    created_at = Column(DateTime, default=utcnow)

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
    last_used_at = Column(DateTime, nullable=True)
    expires_at = Column(DateTime, nullable=True)
    is_active = Column(Boolean, default=True)
    created_by_admin_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=utcnow)

    user = relationship("User", foreign_keys=[user_id], back_populates="api_keys")


class PasswordReset(Base):
    __tablename__ = "password_resets"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    otp = Column(String(6), nullable=False)
    expires_at = Column(DateTime, nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(DateTime, default=utcnow)


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
    created_at = Column(DateTime, default=utcnow, index=True)
