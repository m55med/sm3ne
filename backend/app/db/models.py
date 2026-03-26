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


class Plan(Base):
    __tablename__ = "plans"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(50), unique=True, nullable=False)  # free, monthly, annual
    price = Column(Float, default=0)
    original_price = Column(Float, default=0)
    max_audio_seconds = Column(Integer, default=30)  # -1 = unlimited
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
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    filename = Column(String(255), nullable=True)
    duration_seconds = Column(Float, default=0)
    processed_seconds = Column(Float, default=0)
    language = Column(String(10), nullable=True)
    word_count = Column(Integer, default=0)
    was_trimmed = Column(Boolean, default=False)
    created_at = Column(DateTime, default=utcnow)

    user = relationship("User", back_populates="transcription_requests")


class PasswordReset(Base):
    __tablename__ = "password_resets"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    otp = Column(String(6), nullable=False)
    expires_at = Column(DateTime, nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(DateTime, default=utcnow)
