from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.client_info import get_client_ip, get_device_info
from app.core.config import limiter
from app.core.lifespan import generate_public_id
from app.db.database import get_db
from app.db.models import LoginEvent, PasswordReset, User
from app.auth.jwt import (
    create_access_token,
    create_refresh_token,
    decode_refresh_token,
    get_current_user,
)
from app.auth.password import hash_password, verify_password
from app.auth.social import verify_google_token, verify_apple_token
from app.services import social_revoke
from app.schemas.auth import (
    LogoutResponse,
    RegisterRequest, LoginRequest, SocialAuthRequest,
    ForgotPasswordRequest, RefreshTokenRequest, ResetPasswordRequest,
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


def _reactivate_if_soft_deleted(
    user: User,
    *,
    email_from_provider: str | None,
    full_name_from_provider: str | None,
    db: Session,
) -> bool:
    """Safety net for the "user deleted, signs in again with same Google/Apple
    account" flow when our server-side revoke at the provider failed or was
    never configured.

    If ``user`` is currently soft-deleted (is_active=False and the email looks
    like the ``deleted_<id>_<rand>@deleted.local`` placeholder), restore it
    in place: flip is_active back on, push the provider's current email/name
    over the scrubbed values. Returns True if a reactivation happened so the
    caller can audit-log it as a fresh registration."""
    if user.is_active:
        return False
    scrubbed = (user.email or "").endswith("@deleted.local")
    if not scrubbed:
        return False
    user.is_active = True
    if email_from_provider:
        # Try to push the real email back. If a NEW user has registered with
        # this email in the meantime, the unique-constraint will trip — we
        # rollback that specific change and keep the scrubbed value. The
        # account still becomes usable; the user just can't reclaim their
        # email until the conflict resolves.
        original_email = user.email
        user.email = email_from_provider.lower().strip()
        try:
            db.flush()
        except Exception:
            db.rollback()
            user.email = original_email
            db.add(user)
    if full_name_from_provider and not user.full_name:
        user.full_name = full_name_from_provider
    db.commit()
    db.refresh(user)
    return True


def _record_login(
    db: Session,
    request: Request,
    *,
    user_id: int | None,
    email_attempted: str | None,
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
            email_attempted=email_attempted,
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
    # Schema enforces email shape. Password strength is route-level so we
    # can return a precise error.
    _validate_password_strength(body.password)

    email_normalized = body.email.lower().strip()
    if db.query(User).filter(User.email == email_normalized).first():
        _record_login(db, request, user_id=None, email_attempted=email_normalized,
                      provider="local", event_type="register", success=False,
                      error_message="email_taken")
        raise HTTPException(409, "Email already exists")

    user = User(
        public_id=generate_public_id(),
        email=email_normalized,
        password_hash=hash_password(body.password),
        full_name=body.full_name,
        auth_provider="local",
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    _record_login(db, request, user_id=user.id, email_attempted=user.email,
                  provider="local", event_type="register", success=True)
    return {
        "message": "User created",
        "access_token": create_access_token(user.id, user.role),
        "refresh_token": create_refresh_token(user.id),
        "token_type": "bearer",
    }


@router.post("/login", response_model=TokenResponse)
@limiter.limit("5/minute")
async def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)):
    email_normalized = body.email.lower().strip()
    user = db.query(User).filter(User.email == email_normalized).first()
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash):
        _record_login(db, request, user_id=user.id if user else None,
                      email_attempted=email_normalized, provider="local",
                      event_type="login", success=False, error_message="invalid_credentials")
        raise HTTPException(401, "Invalid email or password")
    if not user.is_active:
        _record_login(db, request, user_id=user.id, email_attempted=user.email,
                      provider="local", event_type="login", success=False,
                      error_message="account_deactivated")
        raise HTTPException(403, "Account is deactivated")

    _record_login(db, request, user_id=user.id, email_attempted=user.email,
                  provider="local", event_type="login", success=True)
    return {
        "access_token": create_access_token(user.id, user.role),
        "refresh_token": create_refresh_token(user.id),
        "token_type": "bearer",
    }


@router.post("/google", response_model=TokenResponse)
@limiter.limit("10/minute")
async def google_auth(body: SocialAuthRequest, request: Request, db: Session = Depends(get_db)):
    info = await verify_google_token(body.token)
    if not info:
        _record_login(db, request, user_id=None, email_attempted=None,
                      provider="google", event_type="login", success=False,
                      error_message="invalid_google_token")
        raise HTTPException(401, "Invalid Google token")

    # Match by provider_id WITHOUT the is_active filter so we can reactivate
    # a soft-deleted account in place (and avoid creating an orphan twin).
    user = db.query(User).filter(
        User.provider_id == info["provider_id"], User.auth_provider == "google"
    ).first()
    if not user and info.get("email"):
        existing = db.query(User).filter(User.email == info["email"]).first()
        if existing:
            # F21: refuse to silently take over a local-password account. The
            # legitimate owner has to log in with their password first, then
            # explicitly link Google from inside the app (linking flow TBD).
            # Exception: admin accounts (operator/owner) — see Apple endpoint below.
            if existing.auth_provider == "local":
                if existing.role != "admin":
                    _record_login(db, request, user_id=existing.id, email_attempted=existing.email,
                                  provider="google", event_type="login", success=False,
                                  error_message="account_exists_local")
                    raise HTTPException(
                        409,
                        {
                            "error": "account_exists_local",
                            "message": "An account with this email exists. Please sign in with your password to link this provider.",
                        },
                    )
                existing.auth_provider = "google"
                existing.provider_id = info["provider_id"]
                if not existing.full_name and info.get("full_name"):
                    existing.full_name = info["full_name"]
                db.commit()
                db.refresh(existing)
            user = existing

    reactivated = False
    if user:
        reactivated = _reactivate_if_soft_deleted(
            user,
            email_from_provider=info.get("email"),
            full_name_from_provider=info.get("full_name"),
            db=db,
        )

    created = False
    if not user:
        user = User(
            public_id=generate_public_id(),
            email=info["email"],
            full_name=info.get("full_name"),
            auth_provider="google",
            provider_id=info["provider_id"],
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        created = True

    if not user.is_active:
        # Edge case: matched a soft-deleted user but reactivation refused to
        # restore (e.g. their email was claimed by another account). Treat as
        # a deactivated account so the client surfaces a clear error.
        _record_login(db, request, user_id=user.id, email_attempted=user.email,
                      provider="google", event_type="login", success=False,
                      error_message="account_deactivated")
        raise HTTPException(403, "Account is deactivated")

    _record_login(db, request, user_id=user.id, email_attempted=user.email,
                  provider="google",
                  event_type="register" if (created or reactivated) else "login",
                  success=True)
    return {
        "access_token": create_access_token(user.id, user.role),
        "refresh_token": create_refresh_token(user.id),
        "token_type": "bearer",
    }


@router.post("/apple", response_model=TokenResponse)
@limiter.limit("10/minute")
async def apple_auth(body: SocialAuthRequest, request: Request, db: Session = Depends(get_db)):
    info = await verify_apple_token(body.token, nonce=body.nonce)
    if not info:
        _record_login(db, request, user_id=None, email_attempted=None,
                      provider="apple", event_type="login", success=False,
                      error_message="invalid_apple_token")
        raise HTTPException(401, "Invalid Apple token")

    # Match by provider_id WITHOUT is_active filter so we can reactivate a
    # soft-deleted Apple account (the common case Apple users hit when our
    # provider-side revoke wasn't configured — Apple still remembers them).
    user = db.query(User).filter(
        User.provider_id == info["provider_id"], User.auth_provider == "apple"
    ).first()
    if not user and info.get("email"):
        existing = db.query(User).filter(User.email == info["email"]).first()
        if existing:
            # F21 (Google/Apple): refuse to silently link a verified-provider sign-in
            # to a local-password account that didn't opt in. Exception: admin accounts
            # are the system operator/owner and bootstrap the deployment — the F21
            # takeover concern (attacker creating a social account with a victim's
            # email) doesn't apply, since admin emails are operator-set, not user-set.
            if existing.auth_provider == "local":
                if existing.role != "admin":
                    _record_login(db, request, user_id=existing.id, email_attempted=existing.email,
                                  provider="apple", event_type="login", success=False,
                                  error_message="account_exists_local")
                    raise HTTPException(
                        409,
                        {
                            "error": "account_exists_local",
                            "message": "An account with this email exists. Please sign in with your password to link this provider.",
                        },
                    )
                existing.auth_provider = "apple"
                existing.provider_id = info["provider_id"]
                if not existing.full_name and info.get("full_name"):
                    existing.full_name = info["full_name"]
                db.commit()
                db.refresh(existing)
            user = existing

    reactivated = False
    if user:
        reactivated = _reactivate_if_soft_deleted(
            user,
            email_from_provider=info.get("email"),
            full_name_from_provider=info.get("full_name"),
            db=db,
        )

    created = False
    if not user:
        user = User(
            public_id=generate_public_id(),
            email=info.get("email"),
            full_name=info.get("full_name"),
            auth_provider="apple",
            provider_id=info["provider_id"],
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        created = True

    if not user.is_active:
        _record_login(db, request, user_id=user.id, email_attempted=user.email,
                      provider="apple", event_type="login", success=False,
                      error_message="account_deactivated")
        raise HTTPException(403, "Account is deactivated")

    # Apple-specific: if the client sent the authorization_code, exchange it
    # server-side for a refresh_token and stash it. Required for /auth/revoke
    # at account-deletion time. Only worth doing on a freshly-created or
    # reactivated row, or if we don't already have a refresh token cached.
    if body.authorization_code and not user.apple_refresh_token:
        tokens = await social_revoke.exchange_apple_code(body.authorization_code)
        if tokens and tokens.get("refresh_token"):
            user.apple_refresh_token = tokens["refresh_token"][:512]
            db.commit()

    _record_login(db, request, user_id=user.id, email_attempted=user.email,
                  provider="apple",
                  event_type="register" if (created or reactivated) else "login",
                  success=True)
    return {
        "access_token": create_access_token(user.id, user.role),
        "refresh_token": create_refresh_token(user.id),
        "token_type": "bearer",
    }


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
async def refresh_token(
    body: RefreshTokenRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Exchange a long-lived refresh token for a fresh access token.

    Pre-fix bug: this endpoint required the (often-expired) access token via
    ``Depends(get_current_user)`` and ignored the refresh_token in the body,
    so refresh always failed once the access token expired — effectively
    logging users out every TOKEN_EXPIRE_MINUTES.
    """
    user_id = decode_refresh_token(body.refresh_token)
    user = db.query(User).filter(User.id == user_id).first()
    if not user or not user.is_active:
        raise HTTPException(401, "User not found or inactive")
    # We re-issue a fresh refresh token on every call so an active user's
    # session keeps rolling indefinitely. The old refresh token still works
    # until it expires (no server-side blocklist).
    _record_login(
        db, request, user_id=user.id, email_attempted=user.email,
        provider=user.auth_provider or "local", event_type="refresh", success=True,
    )
    return {
        "access_token": create_access_token(user.id, user.role),
        "refresh_token": create_refresh_token(user.id),
        "token_type": "bearer",
    }


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
