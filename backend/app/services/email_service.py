import smtplib
import random
import string
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session
from app.core.config import SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM
from app.db.models import PasswordReset


def generate_otp() -> str:
    return "".join(random.choices(string.digits, k=6))


def send_reset_email(to_email: str, otp: str) -> bool:
    if not SMTP_USER:
        print(f"[EMAIL] OTP for {to_email}: {otp} (SMTP not configured)")
        return True

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
        return True
    except Exception as e:
        print(f"[EMAIL] Failed to send: {e}")
        return False


def create_reset_otp(db: Session, user_id: int) -> str:
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
    reset = db.query(PasswordReset).filter(
        PasswordReset.user_id == user_id,
        PasswordReset.otp == otp,
        PasswordReset.used == False,
    ).order_by(PasswordReset.created_at.desc()).first()

    if not reset:
        return False

    if reset.expires_at < datetime.now(timezone.utc):
        return False

    reset.used = True
    db.commit()
    return True
