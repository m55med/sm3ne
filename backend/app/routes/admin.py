from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.auth.api_key import generate_api_key
from app.db.database import get_db
from app.db.models import ApiKey, Coupon, Plan, TranscriptionRequest, User, UserSubscription
from app.auth.jwt import get_current_admin
from app.schemas.admin import (
    AdminStatsResponse, UserListResponse, UserListItem, UserUpdateRequest,
    RequestListResponse, RequestListItem,
    CouponCreate, CouponResponse, CouponUpdate,
)
from app.schemas.api_keys import (
    AdminApiKeyCreateRequest, AdminApiKeyListItem, AdminApiKeyListResponse,
    ApiKeyCreateResponse, ApiKeyResponse, ApiKeyUpdateRequest,
)
from app.services.subscription_service import get_user_plan

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/stats", response_model=AdminStatsResponse)
async def stats(admin: User = Depends(get_current_admin), db: Session = Depends(get_db)):
    now = datetime.now(timezone.utc)
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_ago = now - timedelta(days=7)
    month_ago = now - timedelta(days=30)

    total_users = db.query(func.count(User.id)).scalar()
    active_subs = db.query(func.count(UserSubscription.id)).filter(
        UserSubscription.is_active == True,
        UserSubscription.expires_at > now,
    ).scalar()

    total_req = db.query(func.count(TranscriptionRequest.id)).scalar()
    req_today = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.created_at >= today
    ).scalar()
    req_week = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.created_at >= week_ago
    ).scalar()
    req_month = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.created_at >= month_ago
    ).scalar()

    return AdminStatsResponse(
        total_users=total_users,
        active_subscribers=active_subs,
        requests_today=req_today,
        requests_week=req_week,
        requests_month=req_month,
        total_requests=total_req,
    )


@router.get("/users", response_model=UserListResponse)
async def list_users(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = None,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    q = db.query(User)
    if search:
        q = q.filter(
            (User.username.ilike(f"%{search}%")) |
            (User.email.ilike(f"%{search}%")) |
            (User.full_name.ilike(f"%{search}%"))
        )

    total = q.count()
    users = q.order_by(User.created_at.desc()).offset((page - 1) * per_page).limit(per_page).all()

    items = []
    for u in users:
        # Get active plan name
        sub = db.query(UserSubscription).filter(
            UserSubscription.user_id == u.id, UserSubscription.is_active == True
        ).first()
        plan_name = "free"
        if sub and sub.plan:
            plan_name = sub.plan.name

        items.append(UserListItem(
            id=u.id, username=u.username, email=u.email, full_name=u.full_name,
            role=u.role, is_active=u.is_active, auth_provider=u.auth_provider,
            plan_name=plan_name, created_at=u.created_at,
        ))

    return UserListResponse(users=items, total=total, page=page, per_page=per_page)


@router.get("/users/{user_id}")
async def get_user(
    user_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    sub = db.query(UserSubscription).filter(
        UserSubscription.user_id == user.id, UserSubscription.is_active == True
    ).first()

    req_count = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id
    ).scalar()

    return {
        "id": user.id, "username": user.username, "email": user.email,
        "full_name": user.full_name, "role": user.role, "is_active": user.is_active,
        "auth_provider": user.auth_provider, "survey_response": user.survey_response,
        "created_at": user.created_at.isoformat() if user.created_at else None,
        "plan": sub.plan.name if sub and sub.plan else "free",
        "subscription_expires": sub.expires_at.isoformat() if sub and sub.expires_at else None,
        "total_requests": req_count,
    }


@router.put("/users/{user_id}")
async def update_user(
    user_id: int,
    body: UserUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    if body.is_active is not None:
        user.is_active = body.is_active
    if body.role is not None:
        user.role = body.role
    db.commit()
    return {"message": "User updated"}


# --- Requests ---

@router.get("/requests", response_model=RequestListResponse)
async def list_requests(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user_id: Optional[int] = None,
    api_key_id: Optional[int] = None,
    language: Optional[str] = None,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    q = db.query(TranscriptionRequest)
    if user_id:
        q = q.filter(TranscriptionRequest.user_id == user_id)
    if api_key_id:
        q = q.filter(TranscriptionRequest.api_key_id == api_key_id)
    if language:
        q = q.filter(TranscriptionRequest.language == language)

    total = q.count()
    reqs = q.order_by(TranscriptionRequest.created_at.desc()).offset((page - 1) * per_page).limit(per_page).all()

    # Batch-load related users and api_keys to avoid N+1
    user_ids = {r.user_id for r in reqs}
    key_ids = {r.api_key_id for r in reqs if r.api_key_id}
    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}
    keys = {k.id: k for k in db.query(ApiKey).filter(ApiKey.id.in_(key_ids)).all()} if key_ids else {}

    items = []
    for r in reqs:
        user = users.get(r.user_id)
        api_key = keys.get(r.api_key_id) if r.api_key_id else None
        items.append(RequestListItem(
            id=r.id,
            username=user.username if user else "unknown",
            api_key_id=r.api_key_id,
            api_key_name=api_key.name if api_key else None,
            filename=r.filename, duration_seconds=r.duration_seconds,
            processed_seconds=r.processed_seconds, language=r.language,
            word_count=r.word_count, was_trimmed=r.was_trimmed,
            created_at=r.created_at,
        ))

    return RequestListResponse(requests=items, total=total, page=page, per_page=per_page)


# --- Coupons ---

@router.get("/coupons")
async def list_coupons(
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    coupons = db.query(Coupon).order_by(Coupon.created_at.desc()).all()
    return [CouponResponse.model_validate(c) for c in coupons]


@router.post("/coupons", response_model=CouponResponse)
async def create_coupon(
    body: CouponCreate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    if db.query(Coupon).filter(Coupon.code == body.code).first():
        raise HTTPException(409, "Coupon code already exists")

    coupon = Coupon(
        code=body.code,
        plan_id=body.plan_id,
        duration_days=body.duration_days,
        max_uses=body.max_uses,
        created_by=admin.id,
        expires_at=body.expires_at,
    )
    db.add(coupon)
    db.commit()
    db.refresh(coupon)
    return coupon


@router.put("/coupons/{coupon_id}", response_model=CouponResponse)
async def update_coupon(
    coupon_id: int,
    body: CouponUpdate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    coupon = db.query(Coupon).filter(Coupon.id == coupon_id).first()
    if not coupon:
        raise HTTPException(404, "Coupon not found")

    if body.is_active is not None:
        coupon.is_active = body.is_active
    if body.max_uses is not None:
        coupon.max_uses = body.max_uses
    if body.expires_at is not None:
        coupon.expires_at = body.expires_at
    db.commit()
    db.refresh(coupon)
    return coupon


@router.delete("/coupons/{coupon_id}")
async def delete_coupon(
    coupon_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    coupon = db.query(Coupon).filter(Coupon.id == coupon_id).first()
    if not coupon:
        raise HTTPException(404, "Coupon not found")
    coupon.is_active = False
    db.commit()
    return {"message": "Coupon deactivated"}


# --- API Keys ---

def _start_of_today_utc_admin() -> datetime:
    now = datetime.now(timezone.utc)
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def _daily_limit_for_key(db: Session, api_key: ApiKey) -> int:
    if api_key.requests_per_day is not None:
        return api_key.requests_per_day
    plan = get_user_plan(db, api_key.user_id)
    if plan and plan.daily_request_limit is not None:
        return plan.daily_request_limit
    return 100


def _usage_today_for_key(db: Session, api_key_id: int) -> int:
    return db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.api_key_id == api_key_id,
        TranscriptionRequest.created_at >= _start_of_today_utc_admin(),
    ).scalar() or 0


@router.get("/keys", response_model=AdminApiKeyListResponse)
async def admin_list_keys(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user_id: Optional[int] = None,
    search: Optional[str] = None,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    q = db.query(ApiKey, User).join(User, User.id == ApiKey.user_id)
    if user_id:
        q = q.filter(ApiKey.user_id == user_id)
    if search:
        like = f"%{search}%"
        q = q.filter(
            (ApiKey.name.ilike(like)) |
            (ApiKey.key_prefix.ilike(like)) |
            (User.username.ilike(like))
        )

    total = q.count()
    rows = q.order_by(ApiKey.created_at.desc()).offset((page - 1) * per_page).limit(per_page).all()

    items = []
    for api_key, user in rows:
        items.append(AdminApiKeyListItem(
            id=api_key.id,
            name=api_key.name,
            key_prefix=api_key.key_prefix,
            last_used_at=api_key.last_used_at,
            expires_at=api_key.expires_at,
            is_active=api_key.is_active,
            created_at=api_key.created_at,
            requests_per_minute=api_key.requests_per_minute,
            requests_per_day=api_key.requests_per_day,
            usage_today=_usage_today_for_key(db, api_key.id),
            daily_limit=_daily_limit_for_key(db, api_key),
            user_id=api_key.user_id,
            username=user.username,
        ))

    return AdminApiKeyListResponse(keys=items, total=total, page=page, per_page=per_page)


@router.post("/keys", response_model=ApiKeyCreateResponse, status_code=201)
async def admin_create_key(
    body: AdminApiKeyCreateRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    target_user = db.query(User).filter(User.id == body.user_id).first()
    if not target_user:
        raise HTTPException(404, "User not found")

    plaintext, prefix, key_hash = generate_api_key()
    api_key = ApiKey(
        user_id=body.user_id,
        name=body.name,
        key_prefix=prefix,
        key_hash=key_hash,
        expires_at=body.expires_at,
        requests_per_minute=body.requests_per_minute,
        requests_per_day=body.requests_per_day,
        created_by_admin_id=admin.id,
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


@router.put("/keys/{key_id}", response_model=ApiKeyResponse)
async def admin_update_key(
    key_id: int,
    body: ApiKeyUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    api_key = db.query(ApiKey).filter(ApiKey.id == key_id).first()
    if not api_key:
        raise HTTPException(404, "API key not found")

    if body.name is not None:
        api_key.name = body.name
    if body.is_active is not None:
        api_key.is_active = body.is_active
    if body.expires_at is not None:
        api_key.expires_at = body.expires_at
    if body.requests_per_minute is not None:
        api_key.requests_per_minute = body.requests_per_minute
    if body.requests_per_day is not None:
        api_key.requests_per_day = body.requests_per_day
    db.commit()
    db.refresh(api_key)

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
        usage_today=_usage_today_for_key(db, api_key.id),
        daily_limit=_daily_limit_for_key(db, api_key),
    )


@router.delete("/keys/{key_id}")
async def admin_delete_key(
    key_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    api_key = db.query(ApiKey).filter(ApiKey.id == key_id).first()
    if not api_key:
        raise HTTPException(404, "API key not found")
    api_key.is_active = False
    db.commit()
    return {"message": "API key deactivated"}
