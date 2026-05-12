from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.client_info import get_client_ip, get_device_info
from app.core.config import limiter
from app.core.lifespan import generate_public_id
from app.db.database import get_db
from app.db.models import LoginEvent, PasswordReset, User
from app.auth.jwt import create_access_token, get_current_user
from app.auth.password import hash_password, verify_password
from app.auth.social import verify_google_token, verify_apple_token
from app.schemas.auth import (
    LogoutResponse,
    RegisterRequest, LoginRequest, SocialAuthRequest,
    ForgotPasswordRequest, ResetPasswordRequest,
    TokenResponse, RegisterResponse,
)
from app.services import audit_service
from app.services.email_service import create_reset_otp, send_reset_email, verify_reset_otp

router = APIRouter(prefix="/auth", tags=["auth"])


# F18: a tiny deny-list catches the lowest-hanging credential-stuffing attempts.
# Not a substitute for haveibeenpwned, but stops the worst case (admin1234, etc.)
# without an extra dependency. Keep this list short — Pydantic field-level checks
# already enforce the structural minimums.
_WEAK_PASSWORDS = frozenset({
    "123456", "1234567", "12345678", "123456789", "1234567890",
    "password", "password1", "passw0rd", "qwerty123", "admin1234",
    "letmein123", "welcome123", "iloveyou1", "abcdef1234",
})

# F18: minimum length raised from 6 -> 10 (NIST SP 800-63B recommends >=8;
# 10 gives us a buffer + keeps things usable on mobile keyboards).
PASSWORD_MIN_LENGTH = 10

# F2: max OTP verify attempts before the row is killed. Mirrors what
# PasswordReset.failed_attempts in models.py promises.
OTP_MAX_FAILURES = 5


def _validate_password_strength(password: str) -> None:
    """Raise 400 if the password fails our minimum strength rules. Shared by
    register and reset-password so the policy can't drift between endpoints."""
    if not password or len(password) < PASSWORD_MIN_LENGTH:
        raise HTTPException(
            400,
            f"Password must be at least {PASSWORD_MIN_LENGTH} characters",
        )
    if password.lower() in _WEAK_PASSWORDS:
        raise HTTPException(400, "Password is too common; please choose another")


def _unique_username(db: Session, base: str) -> str:
    """F20: ensure the candidate username doesn't collide with an existing row.
    Appends a numeric suffix until free. Used by Google/Apple flows where we
    derive a username from the social profile."""
    # Strip to allowed charset (pattern ^[a-zA-Z0-9_]+$) so social emails like
    # "first.last@gmail.com" yield "firstlast" not "first.last".
    cleaned = "".join(ch for ch in base if ch.isalnum() or ch == "_") or "user"
    cleaned = cleaned[:25]  # leave room for "_999" suffix within max_length=30
    if not db.query(User).filter(User.username == cleaned).first():
        return cleaned
    # Try numeric suffixes; cap at 999 to avoid a runaway loop in pathological cases.
    for n in range(2, 1000):
        candidate = f"{cleaned}_{n}"
        if not db.query(User).filter(User.username == candidate).first():
            return candidate
    # Extremely unlikely — fall back to a random suffix from public_id.
    return f"{cleaned}_{generate_public_id()[:6]}"


def _record_login(
    db: Session,
    request: Request,
    *,
    user_id: int | None,
    username_attempted: str | None,
    provider: str,
    event_type: str,
    success: bool,
    error_message: str | None = None,
) -> None:
    """Best-effort login-event write; never raises."""
    try:
        info = get_device_info(request)
        ip = get_client_ip(request)
        evt = LoginEvent(
            user_id=user_id,
            username_attempted=username_attempted,
            auth_provider=provider,
            event_type=event_type,
            success=success,
            error_message=error_message[:255] if error_message else None,
            ip_address=ip,
            user_agent=info["user_agent"],
            device_platform=info["platform"],
            device_model=info["model"],
            device_os_version=info["os_version"],
            app_version=info["app_version"],
        )
        db.add(evt)
        db.commit()
    except Exception:
        db.rollback()


@router.post("/register", response_model=RegisterResponse)
@limiter.limit("3/minute")
async def register(body: RegisterRequest, request: Request, db: Session = Depends(get_db)):
    # Schema already enforces username pattern (F19) and email shape (F17).
    # Password strength is route-level (F18) so we can return a precise error.
    _validate_password_strength(body.password)

    if db.query(User).filter(User.username == body.username).first():
        _record_login(db, request, user_id=None, username_attempted=body.username,
                      provider="local", event_type="register", success=False,
                      error_message="username_taken")
        raise HTTPException(409, "Username already exists")
    if body.email and db.query(User).filter(User.email == body.email).first():
        _record_login(db, request, user_id=None, username_attempted=body.username,
                      provider="local", event_type="register", success=False,
                      error_message="email_taken")
        raise HTTPException(409, "Email already exists")

    user = User(
        public_id=generate_public_id(),
        username=body.username,
        email=body.email,
        password_hash=hash_password(body.password),
        full_name=body.full_name,
        auth_provider="local",
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    _record_login(db, request, user_id=user.id, username_attempted=user.username,
                  provider="local", event_type="register", success=True)
    token = create_access_token(user.id, user.username, user.role)
    return {"message": "User created", "access_token": token, "token_type": "bearer"}


@router.post("/login", response_model=TokenResponse)
@limiter.limit("5/minute")
async def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == body.username).first()
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash):
        _record_login(db, request, user_id=user.id if user else None,
                      username_attempted=body.username, provider="local",
                      event_type="login", success=False, error_message="invalid_credentials")
        raise HTTPException(401, "Invalid username or password")
    if not user.is_active:
        _record_login(db, request, user_id=user.id, username_attempted=user.username,
                      provider="local", event_type="login", success=False,
                      error_message="account_deactivated")
        raise HTTPException(403, "Account is deactivated")

    _record_login(db, request, user_id=user.id, username_attempted=user.username,
                  provider="local", event_type="login", success=True)
    token = create_access_token(user.id, user.username, user.role)
    return {"access_token": token, "token_type": "bearer"}


@router.post("/google", response_model=TokenResponse)
@limiter.limit("10/minute")
async def google_auth(body: SocialAuthRequest, request: Request, db: Session = Depends(get_db)):
    info = await verify_google_token(body.token)
    if not info:
        _record_login(db, request, user_id=None, username_attempted=None,
                      provider="google", event_type="login", success=False,
                      error_message="invalid_google_token")
        raise HTTPException(401, "Invalid Google token")

    user = db.query(User).filter(
        User.provider_id == info["provider_id"], User.auth_provider == "google"
    ).first()
    if not user and info.get("email"):
        existing = db.query(User).filter(User.email == info["email"]).first()
        if existing:
            # F21: refuse to silently take over a local-password account. The
            # legitimate owner has to log in with their password first, then
            # explicitly link Google from inside the app (linking flow TBD).
            if existing.auth_provider == "local":
                _record_login(db, request, user_id=existing.id, username_attempted=existing.username,
                              provider="google", event_type="login", success=False,
                              error_message="account_exists_local")
                raise HTTPException(
                    409,
                    {
                        "error": "account_exists_local",
                        "message": "An account with this email exists. Please sign in with your password to link this provider.",
                    },
                )
            user = existing

    created = False
    if not user:
        # F20: derive a unique username (no longer 500s on collision).
        base = info["email"].split("@")[0] if info.get("email") else f"google_{info['provider_id'][:8]}"
        username = _unique_username(db, base)
        user = User(
            public_id=generate_public_id(),
            username=username,
            email=info["email"],
            full_name=info.get("full_name"),
            auth_provider="google",
            provider_id=info["provider_id"],
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        created = True

    _record_login(db, request, user_id=user.id, username_attempted=user.username,
                  provider="google", event_type="register" if created else "login",
                  success=True)
    token = create_access_token(user.id, user.username, user.role)
    return {"access_token": token, "token_type": "bearer"}


@router.post("/apple", response_model=TokenResponse)
@limiter.limit("10/minute")
async def apple_auth(body: SocialAuthRequest, request: Request, db: Session = Depends(get_db)):
    info = await verify_apple_token(body.token, nonce=body.nonce)
    if not info:
        _record_login(db, request, user_id=None, username_attempted=None,
                      provider="apple", event_type="login", success=False,
                      error_message="invalid_apple_token")
        raise HTTPException(401, "Invalid Apple token")

    user = db.query(User).filter(
        User.provider_id == info["provider_id"], User.auth_provider == "apple"
    ).first()
    if not user and info.get("email"):
        existing = db.query(User).filter(User.email == info["email"]).first()
        if existing:
            # F21: same takeover guard as Google.
            if existing.auth_provider == "local":
                _record_login(db, request, user_id=existing.id, username_attempted=existing.username,
                              provider="apple", event_type="login", success=False,
                              error_message="account_exists_local")
                raise HTTPException(
                    409,
                    {
                        "error": "account_exists_local",
                        "message": "An account with this email exists. Please sign in with your password to link this provider.",
                    },
                )
            user = existing

    created = False
    if not user:
        # F20: collision-safe username derivation.
        if info.get("email"):
            base = info["email"].split("@")[0]
        else:
            base = f"apple_{info['provider_id'][:8]}"
        username = _unique_username(db, base)
        user = User(
            public_id=generate_public_id(),
            username=username,
            email=info.get("email"),
            full_name=info.get("full_name"),
            auth_provider="apple",
            provider_id=info["provider_id"],
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        created = True

    _record_login(db, request, user_id=user.id, username_attempted=user.username,
                  provider="apple", event_type="register" if created else "login",
                  success=True)
    token = create_access_token(user.id, user.username, user.role)
    return {"access_token": token, "token_type": "bearer"}


@router.post("/forgot-password")
@limiter.limit("3/hour")
async def forgot_password(
    body: ForgotPasswordRequest, request: Request, db: Session = Depends(get_db)
):
    user = db.query(User).filter(User.email == body.email).first()
    if not user:
        # Don't reveal whether the email exists — same response either way.
        return {"message": "If the email exists, a reset code has been sent"}

    otp = create_reset_otp(db, user.id)
    send_reset_email(body.email, otp)
    return {"message": "If the email exists, a reset code has been sent"}


@router.post("/reset-password")
@limiter.limit("5/minute")
async def reset_password(
    body: ResetPasswordRequest, request: Request, db: Session = Depends(get_db)
):
    user = db.query(User).filter(User.email == body.email).first()
    if not user:
        raise HTTPException(400, "Invalid request")

    _validate_password_strength(body.new_password)

    if not verify_reset_otp(db, user.id, body.otp):
        # F2: increment the failure counter on the latest unused OTP. After 5
        # bad attempts mark it used so brute-forcing the 6-digit space becomes
        # impossible (attacker has to wait for a fresh OTP via email).
        #
        # We use getattr/setattr because the `failed_attempts` column was added
        # by Backend-3; defensively no-op on older deployments without the col.
        latest = db.query(PasswordReset).filter(
            PasswordReset.user_id == user.id,
            PasswordReset.used == False,  # noqa: E712
        ).order_by(PasswordReset.created_at.desc()).first()
        if latest is not None:
            current = getattr(latest, "failed_attempts", None)
            if current is not None:
                try:
                    new_val = int(current) + 1
                    setattr(latest, "failed_attempts", new_val)
                    if new_val >= OTP_MAX_FAILURES:
                        latest.used = True
                    db.commit()
                except Exception:
                    db.rollback()
        raise HTTPException(400, "Invalid or expired code")

    user.password_hash = hash_password(body.new_password)
    # F23 helper: stamp password_changed_at if Backend-1 has added the column.
    try:
        if hasattr(user, "password_changed_at"):
            from datetime import datetime, timezone
            setattr(user, "password_changed_at", datetime.now(timezone.utc))
    except Exception:
        pass
    db.commit()
    try:
        audit_service.record(
            db, action="auth.password.reset", actor_user_id=user.id,
            target_type="user", target_id=user.id,
        )
    except Exception:
        pass
    return {"message": "Password reset successfully"}


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("30/minute")
async def refresh_token(request: Request, user: User = Depends(get_current_user)):
    token = create_access_token(user.id, user.username, user.role)
    return {"access_token": token, "token_type": "bearer"}


@router.post("/logout", response_model=LogoutResponse)
async def logout(user: User = Depends(get_current_user)):
    """F24: client-side logout endpoint.

    NOTE / Limitation: we don't currently maintain a server-side token blocklist,
    so this endpoint is purely advisory — the JWT remains valid until its natural
    expiry. Real revocation requires either (a) a token-jti blocklist in Redis
    keyed by exp, or (b) bumping ``users.password_changed_at`` on logout and
    rejecting tokens issued before it in get_current_user. Both are larger
    changes; this stub gives the client a single endpoint to call so the UI can
    clear the in-app token consistently.
    """
    return {"message": "logged out"}
