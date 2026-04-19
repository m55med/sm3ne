from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.api_key import generate_api_key
from app.auth.jwt import get_current_user
from app.db.database import get_db
from app.db.models import ApiKey, TranscriptionRequest, User
from app.schemas.api_keys import (
    ApiKeyCreateRequest,
    ApiKeyCreateResponse,
    ApiKeyResponse,
    ApiKeyUpdateRequest,
)
from app.services.subscription_service import get_user_plan

router = APIRouter(prefix="/keys", tags=["api-keys"])


def _start_of_today_utc() -> datetime:
    now = datetime.now(timezone.utc)
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def _usage_today_map(db: Session, user_id: int) -> dict[int, int]:
    """Return {api_key_id: count} for today's requests from this user."""
    rows = (
        db.query(TranscriptionRequest.api_key_id, func.count(TranscriptionRequest.id))
        .filter(
            TranscriptionRequest.user_id == user_id,
            TranscriptionRequest.created_at >= _start_of_today_utc(),
            TranscriptionRequest.api_key_id.isnot(None),
        )
        .group_by(TranscriptionRequest.api_key_id)
        .all()
    )
    return {k: c for k, c in rows}


def _to_response(api_key: ApiKey, usage_today: int, daily_limit: int) -> ApiKeyResponse:
    return ApiKeyResponse(
        id=api_key.id,
        name=api_key.name,
        key_prefix=api_key.key_prefix,
        last_used_at=api_key.last_used_at,
        expires_at=api_key.expires_at,
        is_active=api_key.is_active,
        created_at=api_key.created_at,
        requests_per_minute=api_key.requests_per_minute,
        requests_per_day=api_key.requests_per_day,
        usage_today=usage_today,
        daily_limit=daily_limit,
    )


@router.post("", response_model=ApiKeyCreateResponse, status_code=201)
async def create_key(
    body: ApiKeyCreateRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    plan = get_user_plan(db, user.id)
    allowed = plan.api_keys_allowed if plan and plan.api_keys_allowed is not None else 1

    active_count = db.query(func.count(ApiKey.id)).filter(
        ApiKey.user_id == user.id,
        ApiKey.is_active == True,
    ).scalar() or 0

    if allowed >= 0 and active_count >= allowed:
        raise HTTPException(409, f"Max API keys reached for your plan ({allowed})")

    plaintext, prefix, key_hash = generate_api_key()

    api_key = ApiKey(
        user_id=user.id,
        name=body.name,
        key_prefix=prefix,
        key_hash=key_hash,
        expires_at=body.expires_at,
        requests_per_minute=None,  # users cannot set their own overrides
        requests_per_day=None,
        is_active=True,
    )
    db.add(api_key)
    db.commit()
    db.refresh(api_key)

    return ApiKeyCreateResponse(
        id=api_key.id,
        name=api_key.name,
        key=plaintext,
        key_prefix=api_key.key_prefix,
        expires_at=api_key.expires_at,
        created_at=api_key.created_at,
    )


@router.get("", response_model=List[ApiKeyResponse])
async def list_keys(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    keys = db.query(ApiKey).filter(ApiKey.user_id == user.id).order_by(ApiKey.created_at.desc()).all()
    usage = _usage_today_map(db, user.id)
    plan = get_user_plan(db, user.id)
    plan_daily = plan.daily_request_limit if plan and plan.daily_request_limit is not None else 100

    result = []
    for k in keys:
        daily_limit = k.requests_per_day if k.requests_per_day is not None else plan_daily
        result.append(_to_response(k, usage.get(k.id, 0), daily_limit))
    return result


@router.delete("/{key_id}")
async def delete_key(
    key_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    api_key = db.query(ApiKey).filter(ApiKey.id == key_id, ApiKey.user_id == user.id).first()
    if not api_key:
        raise HTTPException(404, "API key not found")
    api_key.is_active = False
    db.commit()
    return {"message": "API key revoked"}


@router.put("/{key_id}", response_model=ApiKeyResponse)
async def update_key(
    key_id: int,
    body: ApiKeyUpdateRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.requests_per_minute is not None or body.requests_per_day is not None:
        raise HTTPException(403, "Rate limit overrides are admin-only")

    api_key = db.query(ApiKey).filter(ApiKey.id == key_id, ApiKey.user_id == user.id).first()
    if not api_key:
        raise HTTPException(404, "API key not found")

    if body.name is not None:
        api_key.name = body.name
    if body.is_active is not None:
        api_key.is_active = body.is_active
    if body.expires_at is not None:
        api_key.expires_at = body.expires_at
    db.commit()
    db.refresh(api_key)

    plan = get_user_plan(db, user.id)
    plan_daily = plan.daily_request_limit if plan and plan.daily_request_limit is not None else 100
    daily_limit = api_key.requests_per_day if api_key.requests_per_day is not None else plan_daily
    usage = _usage_today_map(db, user.id).get(api_key.id, 0)
    return _to_response(api_key, usage, daily_limit)
