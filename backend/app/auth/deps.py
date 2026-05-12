import logging
from datetime import timedelta

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.api_key import extract_api_key_from_request, hash_api_key
from app.auth.jwt import get_current_user
from app.core.time_utils import (
    days_remaining_in_month,
    start_of_current_month_utc,
    start_of_today_utc,
    utc_now,
)
from app.db.database import get_db
from app.db.models import ApiKey, TranscriptionRequest, User
from app.services.subscription_service import get_user_plan

logger = logging.getLogger(__name__)

# Minimum daily quota we hand back to users even when the smart-distribution
# math would otherwise floor to zero (e.g. monthly already exhausted with days
# still left). Stops users from being completely locked out mid-month. Only
# applies when monthly_limit >= 0 (finite); unlimited plans short-circuit.
SMART_DAILY_FLOOR = 10


def _set_principal(request: Request, kind: str, ident: int) -> None:
    request.state.auth_principal = (kind, ident)


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
            from datetime import timezone
            expires = expires.replace(tzinfo=timezone.utc)
        if expires < utc_now():
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "API key expired")

    user = db.query(User).filter(User.id == api_key.user_id).first()
    if not user or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found or inactive")

    _set_principal(request, "apikey", api_key.id)
    request.state.api_key = api_key
    request.state.user = user
    request.state.plan = get_user_plan(db, user.id)

    # Best-effort last_used_at update. A failure here MUST NOT break the
    # request: we use a nested transaction so a write race / unique-constraint
    # hiccup is contained, and we log rather than swallow silently.
    try:
        with db.begin_nested():
            api_key.last_used_at = utc_now()
        db.commit()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Failed to update api_key.last_used_at: %s", exc)
        try:
            db.rollback()
        except Exception:
            pass

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


def _smart_daily_from_monthly(monthly_limit: int, used_this_month: int) -> int:
    """Distribute remaining monthly quota across remaining days (incl. today).

    monthly_limit < 0 means unlimited; callers should short-circuit before
    calling. We apply a floor of SMART_DAILY_FLOOR so users aren't completely
    locked out mid-month if monthly got drained but daily was unused — a softer
    landing than returning 0. Floor only applies when monthly is finite.
    """
    remaining_monthly = max(monthly_limit - used_this_month, 0)
    days_left = max(days_remaining_in_month(), 1)
    base = max(remaining_monthly // days_left, 0)
    return max(base, SMART_DAILY_FLOOR)


def _effective_daily_limit(request: Request, db: Session, user_id: int) -> int:
    """Resolve today's effective cap. Returns -1 for unlimited."""
    api_key = getattr(request.state, "api_key", None)
    plan = getattr(request.state, "plan", None) or get_user_plan(db, user_id)

    # API-key path: plan-level API limit takes precedence over per-key override
    if api_key is not None:
        if plan is not None and plan.api_daily_request_limit is not None:
            api_cap = plan.api_daily_request_limit
            if api_cap == 0:
                return 0  # API disabled on this plan
            if api_cap > 0:
                return api_cap
            # api_cap == -1 → fall through to daily_request_limit / monthly logic
        if api_key.requests_per_day is not None:
            return api_key.requests_per_day

    static_daily = plan.daily_request_limit if plan and plan.daily_request_limit is not None else 100

    # Monthly smart distribution (applies to both app users and API-key users when api_cap == -1)
    if plan and plan.monthly_request_limit is not None and plan.monthly_request_limit >= 0:
        used_this_month = db.query(func.count(TranscriptionRequest.id)).filter(
            TranscriptionRequest.user_id == user_id,
            TranscriptionRequest.created_at >= start_of_current_month_utc(),
            TranscriptionRequest.status != "failed",
        ).scalar() or 0
        smart_daily = _smart_daily_from_monthly(plan.monthly_request_limit, used_this_month)
        if static_daily < 0:
            return smart_daily
        return min(static_daily, smart_daily)

    return static_daily


def check_daily_quota(request: Request, user: User, db: Session) -> None:
    limit = _effective_daily_limit(request, db, user.id)
    if limit < 0:
        return  # unlimited

    api_key = getattr(request.state, "api_key", None)
    if limit == 0 and api_key is not None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error": "api_disabled_on_plan", "message": "API access is not allowed on your current plan."},
        )

    q = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= start_of_today_utc(),
        TranscriptionRequest.status != "failed",
    )
    # SECURITY/QUOTA NOTE (F14):
    # When the caller is using an API key we deliberately count usage across
    # ALL of the user's API keys (filtered by api_key_id IS NOT NULL), not
    # just the current key. Filtering by api_key_id == current would let a
    # user with N keys do `daily_limit * N` requests/day — the plan-level
    # limit is meant to be a *user* limit, not a per-key limit. Per-key
    # sub-budgets are still enforced separately by api_key.requests_per_day.
    if api_key is not None:
        q = q.filter(TranscriptionRequest.api_key_id.isnot(None))

    used = q.scalar() or 0
    if used >= limit:
        resets_at = start_of_today_utc() + timedelta(days=1)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "error": "daily_quota_exceeded",
                "limit": limit,
                "used": used,
                "resets_at_utc": resets_at.isoformat(),
            },
        )


def _effective_rpm(request: Request) -> int | None:
    """Resolve the per-minute limit for this request. Returns None if no override
    is set on the api_key or plan (in which case slowapi's static RATE_LIMIT kicks in)."""
    api_key = getattr(request.state, "api_key", None)
    if api_key is not None and api_key.requests_per_minute is not None:
        return api_key.requests_per_minute

    plan = getattr(request.state, "plan", None)
    if plan is not None and plan.rpm_default is not None:
        return plan.rpm_default

    return None


def check_rpm_limit(request: Request, user: User, db: Session) -> None:
    """Per-key RPM enforcement via a DB count over the last 60 seconds.
    Done manually (not via slowapi's dynamic callable) because slowapi's
    limit-value callable is invoked with no arguments, so we can't read
    request-scoped state through it.
    """
    limit = _effective_rpm(request)
    if limit is None or limit < 0:
        return

    since = utc_now() - timedelta(seconds=60)
    api_key = getattr(request.state, "api_key", None)
    q = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= since,
    )
    if api_key is not None:
        q = q.filter(TranscriptionRequest.api_key_id == api_key.id)

    used = q.scalar() or 0
    if used >= limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "error": "rate_limit_exceeded",
                "limit_per_minute": limit,
                "used_last_minute": used,
            },
        )
