from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.api_key import extract_api_key_from_request, hash_api_key
from app.auth.jwt import get_current_user
from app.core.config import RATE_LIMIT
from app.db.database import get_db
from app.db.models import ApiKey, TranscriptionRequest, User
from app.services.subscription_service import get_user_plan


def _set_principal(request: Request, kind: str, ident: int) -> None:
    request.state.auth_principal = (kind, ident)


def _start_of_today_utc() -> datetime:
    now = datetime.now(timezone.utc)
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def get_api_key_user(request: Request, db: Session = Depends(get_db)) -> User:
    raw = extract_api_key_from_request(request)
    if not raw:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "API key required")

    key_hash = hash_api_key(raw)
    api_key = db.query(ApiKey).filter(
        ApiKey.key_hash == key_hash,
        ApiKey.is_active == True,
    ).first()
    if not api_key:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid API key")

    if api_key.expires_at:
        expires = api_key.expires_at
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
        if expires < datetime.now(timezone.utc):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "API key expired")

    user = db.query(User).filter(User.id == api_key.user_id).first()
    if not user or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found or inactive")

    _set_principal(request, "apikey", api_key.id)
    request.state.api_key = api_key
    request.state.user = user
    request.state.plan = get_user_plan(db, user.id)

    try:
        api_key.last_used_at = datetime.now(timezone.utc)
        db.commit()
    except Exception:
        db.rollback()

    return user


def get_user_or_api_key(request: Request, db: Session = Depends(get_db)) -> User:
    """Accept either an API key (X-API-Key or Authorization: Bearer bsw_...)
    or a JWT bearer token. Sets request.state.auth_principal for rate limiting.
    """
    if extract_api_key_from_request(request):
        return get_api_key_user(request, db)

    auth = request.headers.get("authorization") or ""
    if not auth.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")

    from fastapi.security.http import HTTPAuthorizationCredentials
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=auth[7:].strip())
    user = get_current_user(credentials=credentials, db=db)
    _set_principal(request, "user", user.id)
    request.state.user = user
    request.state.plan = get_user_plan(db, user.id)
    return user


def _effective_daily_limit(request: Request, db: Session, user_id: int) -> int:
    api_key = getattr(request.state, "api_key", None)
    if api_key is not None and api_key.requests_per_day is not None:
        return api_key.requests_per_day

    plan = getattr(request.state, "plan", None) or get_user_plan(db, user_id)
    if plan and plan.daily_request_limit is not None:
        return plan.daily_request_limit
    return 100


def check_daily_quota(request: Request, user: User, db: Session) -> None:
    limit = _effective_daily_limit(request, db, user.id)
    if limit < 0:
        return  # unlimited

    api_key = getattr(request.state, "api_key", None)
    q = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= _start_of_today_utc(),
    )
    if api_key is not None:
        q = q.filter(TranscriptionRequest.api_key_id == api_key.id)

    used = q.scalar() or 0
    if used >= limit:
        resets_at = _start_of_today_utc() + timedelta(days=1)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "error": "daily_quota_exceeded",
                "limit": limit,
                "used": used,
                "resets_at_utc": resets_at.isoformat(),
            },
        )


def effective_rpm_limit_str(request: Request) -> str:
    """Callable passed to slowapi's @limiter.limit(...) — returns the per-minute
    limit string for the current request's principal. Reads from request.state
    which get_user_or_api_key populated.
    """
    api_key = getattr(request.state, "api_key", None)
    if api_key is not None and api_key.requests_per_minute is not None:
        return f"{api_key.requests_per_minute}/minute"

    plan = getattr(request.state, "plan", None)
    if plan is not None and plan.rpm_default:
        return f"{plan.rpm_default}/minute"

    return RATE_LIMIT
