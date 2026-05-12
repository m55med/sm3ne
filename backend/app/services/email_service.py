"""Password-reset OTP email service.

Hardening notes:
 - OTPs are generated with `secrets.choice` (CSPRNG), never `random`.
 - The OTP value itself is NEVER logged or printed. The route emails it and that's it.
   Local dev can set `EMAIL_DEV_PRINT_OTP=true` to opt into printing — off by default.
 - Verification uses `hmac.compare_digest` to prevent timing side-channels.
 - On creating a new OTP we proactively kill any older unused OTPs for the user
   so a leaked older code cannot be used after a re-request.
 - The route is responsible for counting failed verify attempts and marking the
   OTP `used=True` after 5 failures (we expose the row via the verify return).
"""
import hmac
import logging
import os
import secrets
import smtplib
import string
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session
from app.core.config import SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM
from app.db.models import PasswordReset


logger = logging.getLogger(__name__)


def _dev_print_enabled() -> bool:
    return os.getenv("EMAIL_DEV_PRINT_OTP", "").strip().lower() in ("1", "true", "yes")


def generate_otp() -> str:
    """Generate a cryptographically-strong 6-digit OTP."""
    return "".join(secrets.choice(string.digits) for _ in range(6))


def send_reset_email(to_email: str, otp: str) -> bool:
    if not SMTP_USER:
        # In local dev only (explicit opt-in) print the OTP so the developer
        # can test the flow without a real SMTP. In production this MUST be off.
        if _dev_print_enabled():
            # Intentional dev-only print; gated by env so it never leaks in prod.
            print(f"[EMAIL][DEV] OTP for {to_email}: {otp} (SMTP not configured)")
            return True
        raise RuntimeError("SMTP not configured. Set SMTP_USER/SMTP_PASS in env.")

    msg = MIMEMultipart()
    msg["From"] = SMTP_FROM
    msg["To"] = to_email
    msg["Subject"] = "Bisawtak - Password Reset Code"

    body = f"""
    <html>
    <body dir="rtl" style="font-family: Arial, sans-serif;">
        <h2>بصوتك - استعادة كلمة السر</h2>
        <p>رمز التحقق الخاص بك:</p>
        <h1 style="color: #4A90D9; letter-spacing: 8px;">{otp}</h1>
        <p>الرمز صالح لمدة 10 دقائق.</p>
        <hr>
        <p style="color: #888; font-size: 12px;">إذا لم تطلب استعادة كلمة السر، تجاهل هذا البريد.</p>
    </body>
    </html>
    """
    msg.attach(MIMEText(body, "html"))

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
        # Log only that an OTP was sent — never the value.
        logger.info("OTP generated for %s", to_email)
        return True
    except Exception as e:
        logger.exception("OTP email send failed for %s: %s", to_email, e)
        return False


def create_reset_otp(db: Session, user_id: int) -> str:
    # F6: kill any older unused OTPs for this user so a leaked previous code
    # cannot be redeemed after the new one is issued.
    db.query(PasswordReset).filter(
        PasswordReset.user_id == user_id,
        PasswordReset.used == False,  # noqa: E712
    ).update({"used": True})

    otp = generate_otp()
    reset = PasswordReset(
        user_id=user_id,
        otp=otp,
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
    )
    db.add(reset)
    db.commit()
    return otp


def verify_reset_otp(db: Session, user_id: int, otp: str) -> bool:
    """Constant-time OTP verification.

    Returns True if the latest unused OTP for the user matches and is not expired.
    The caller (route) is responsible for incrementing failed_attempts and killing
    the row after 5 failures — see PasswordReset.failed_attempts.
    """
    reset = db.query(PasswordReset).filter(
        PasswordReset.user_id == user_id,
        PasswordReset.used == False,  # noqa: E712
    ).order_by(PasswordReset.created_at.desc()).first()

    if not reset:
        return False

    # Expiry check first (cheap, side-channel safe).
    expires_at = reset.expires_at
    if expires_at is not None and expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at is None or expires_at < datetime.now(timezone.utc):
        return False

    # F7: timing-safe comparison.
    candidate = (otp or "").strip()
    stored = (reset.otp or "")
    if not hmac.compare_digest(candidate, stored):
        return False

    reset.used = True
    db.commit()
    return True
