from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.auth.api_key import generate_api_key
from app.db.database import get_db
from app.db.models import ApiKey, Coupon, LoginEvent, Plan, SupportTicket, TicketReply, TranscriptionRequest, User, UserSubscription
from app.auth.jwt import get_current_admin
from app.schemas.admin import (
    AdminStatsResponse, UserListResponse, UserListItem, UserUpdateRequest,
    RequestListResponse, RequestListItem,
    CouponCreate, CouponResponse, CouponUpdate,
    PlanAdminItem, PlanCreate, PlanUpdate,
    SessionItem, UserUsageInfo, UserSubscriptionInfo, UserDetailResponse,
    AdminSubscribeRequest, SubscriptionLogItem, SubscriptionLogResponse,
    PlanSubscriberItem,
)
from app.schemas.support import (
    AdminTicketSummary, AdminTicketListResponse,
    TicketDetail, TicketReplyItem, TicketReplyCreate, TicketStatusUpdate,
)
from app.core.lifespan import generate_public_id
from app.schemas.api_keys import (
    AdminApiKeyCreateRequest, AdminApiKeyListItem, AdminApiKeyListResponse,
    ApiKeyCreateResponse, ApiKeyResponse, ApiKeyUpdateRequest,
)
from app.services.subscription_service import get_user_plan, subscribe_user

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
    user_ids = [u.id for u in users]

    # Batch subscriptions
    subs = {}
    if user_ids:
        for s in db.query(UserSubscription).filter(
            UserSubscription.user_id.in_(user_ids),
            UserSubscription.is_active == True,
        ).all():
            subs[s.user_id] = s
    plan_ids = {s.plan_id for s in subs.values()}
    plans = {p.id: p for p in db.query(Plan).filter(Plan.id.in_(plan_ids)).all()} if plan_ids else {}

    # Batch session counts (active ≈ successful login in last 7 days)
    session_stats: dict[int, dict] = {}
    if user_ids:
        week_ago = datetime.now(timezone.utc) - timedelta(days=7)
        rows = db.query(
            LoginEvent.user_id,
            func.count(LoginEvent.id),
            func.max(LoginEvent.created_at),
        ).filter(
            LoginEvent.user_id.in_(user_ids),
            LoginEvent.success == True,
            LoginEvent.event_type.in_(["login", "register"]),
            LoginEvent.created_at >= week_ago,
        ).group_by(LoginEvent.user_id).all()
        for uid, count, last in rows:
            session_stats[uid] = {"active": count, "last": last}

    items = []
    for u in users:
        sub = subs.get(u.id)
        plan_name = plans.get(sub.plan_id).name if sub and plans.get(sub.plan_id) else "free"
        stats = session_stats.get(u.id, {})
        items.append(UserListItem(
            id=u.id, public_id=u.public_id, username=u.username, email=u.email, full_name=u.full_name,
            role=u.role, is_active=u.is_active, auth_provider=u.auth_provider,
            plan_name=plan_name,
            active_sessions=stats.get("active", 0),
            last_session_at=stats.get("last"),
            created_at=u.created_at,
        ))

    return UserListResponse(users=items, total=total, page=page, per_page=per_page)


def _start_of_today_utc() -> datetime:
    now = datetime.now(timezone.utc)
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def _start_of_current_month_utc() -> datetime:
    now = datetime.now(timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def _resolve_user(db: Session, user_ref: str) -> User:
    """Accept either a numeric id or a public_id. Returns the user or 404s."""
    user = None
    if user_ref.isdigit():
        user = db.query(User).filter(User.id == int(user_ref)).first()
    if not user:
        user = db.query(User).filter(User.public_id == user_ref).first()
    if not user:
        raise HTTPException(404, "User not found")
    return user


@router.get("/users/{user_ref}", response_model=UserDetailResponse)
async def get_user(
    user_ref: str,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user = _resolve_user(db, user_ref)

    sub = db.query(UserSubscription).filter(
        UserSubscription.user_id == user.id, UserSubscription.is_active == True
    ).first()

    # Resolve effective plan (handle expired subs)
    now_utc = datetime.now(timezone.utc)
    effective_plan: Optional[Plan] = None
    sub_info = UserSubscriptionInfo(plan_name="free", plan_source="free", is_active=False)
    if sub and sub.plan:
        expired = sub.expires_at and sub.expires_at.replace(tzinfo=timezone.utc) < now_utc
        if not expired:
            effective_plan = sub.plan
            days_left = None
            if sub.expires_at:
                delta = sub.expires_at.replace(tzinfo=timezone.utc) - now_utc
                days_left = max(delta.days, 0)
            coupon_code = None
            if sub.coupon_id:
                c = db.query(Coupon).filter(Coupon.id == sub.coupon_id).first()
                coupon_code = c.code if c else None
            sub_info = UserSubscriptionInfo(
                plan_name=sub.plan.name,
                plan_source="coupon" if sub.coupon_id else ("purchase" if sub.plan.name != "free" else "free"),
                starts_at=sub.starts_at,
                expires_at=sub.expires_at,
                days_remaining=days_left,
                coupon_code=coupon_code,
                coupon_id=sub.coupon_id,
                is_active=True,
            )
    if effective_plan is None:
        effective_plan = db.query(Plan).filter(Plan.name == "free").first()

    # Usage
    today_start = _start_of_today_utc()
    month_start = _start_of_current_month_utc()
    total_count = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id
    ).scalar() or 0
    today_count = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= today_start,
        TranscriptionRequest.status != "failed",
    ).scalar() or 0
    month_count = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= month_start,
        TranscriptionRequest.status != "failed",
    ).scalar() or 0
    today_api_count = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= today_start,
        TranscriptionRequest.api_key_id.isnot(None),
        TranscriptionRequest.status != "failed",
    ).scalar() or 0

    usage = UserUsageInfo(
        requests_today=today_count,
        requests_this_month=month_count,
        requests_today_api=today_api_count,
        daily_limit=effective_plan.daily_request_limit if effective_plan else 0,
        monthly_limit=effective_plan.monthly_request_limit if effective_plan else None,
        api_daily_limit=effective_plan.api_daily_request_limit if effective_plan else -1,
        max_audio_seconds=effective_plan.max_audio_seconds if effective_plan else 30,
    )

    # Active sessions (last 7 days)
    week_ago = now_utc - timedelta(days=7)
    active_sessions = db.query(func.count(LoginEvent.id)).filter(
        LoginEvent.user_id == user.id,
        LoginEvent.success == True,
        LoginEvent.created_at >= week_ago,
    ).scalar() or 0

    return UserDetailResponse(
        id=user.id, public_id=user.public_id, username=user.username, email=user.email,
        full_name=user.full_name, role=user.role, is_active=user.is_active,
        auth_provider=user.auth_provider, survey_response=user.survey_response,
        created_at=user.created_at,
        total_requests=total_count,
        subscription=sub_info,
        usage=usage,
        active_sessions=active_sessions,
    )


@router.put("/users/{user_ref}")
async def update_user(
    user_ref: str,
    body: UserUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user = _resolve_user(db, user_ref)

    # Self-protection: prevent admin from demoting or disabling themselves
    if admin.id == user.id:
        if body.is_active is False:
            raise HTTPException(400, "You cannot deactivate your own account")
        if body.role is not None and body.role != "admin":
            raise HTTPException(400, "You cannot remove your own admin role")

    if body.is_active is not None:
        user.is_active = body.is_active
    if body.role is not None:
        user.role = body.role
    if body.full_name is not None:
        user.full_name = body.full_name
    if body.email is not None:
        if body.email != user.email:
            existing = db.query(User).filter(User.email == body.email, User.id != user.id).first()
            if existing:
                raise HTTPException(409, "Email already in use")
        user.email = body.email
    db.commit()
    return {"message": "User updated"}


@router.delete("/users/{user_ref}")
async def delete_user(
    user_ref: str,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user = _resolve_user(db, user_ref)
    if admin.id == user.id:
        raise HTTPException(400, "You cannot deactivate your own account")
    if user.role == "admin":
        raise HTTPException(400, "Cannot deactivate another admin account")
    user.is_active = False
    db.commit()
    return {"message": "User deactivated"}


@router.get("/users/{user_ref}/sessions", response_model=list[SessionItem])
async def list_user_sessions(
    user_ref: str,
    limit: int = Query(50, ge=1, le=200),
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user = _resolve_user(db, user_ref)

    events = db.query(LoginEvent).filter(
        LoginEvent.user_id == user.id
    ).order_by(LoginEvent.created_at.desc()).limit(limit).all()

    week_ago = datetime.now(timezone.utc) - timedelta(days=7)
    items = []
    for e in events:
        created_aware = e.created_at.replace(tzinfo=timezone.utc) if e.created_at and e.created_at.tzinfo is None else e.created_at
        is_active = bool(e.success and created_aware and created_aware >= week_ago)
        item = SessionItem.model_validate(e)
        item.is_active = is_active
        items.append(item)
    return items


@router.post("/users/{user_ref}/subscribe", response_model=UserDetailResponse)
async def admin_subscribe_user(
    user_ref: str,
    body: AdminSubscribeRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user = _resolve_user(db, user_ref)

    plan = db.query(Plan).filter(Plan.id == body.plan_id, Plan.is_active == True).first()
    if not plan:
        raise HTTPException(404, "Plan not found or inactive")

    # Deactivate current active subscription
    db.query(UserSubscription).filter(
        UserSubscription.user_id == user.id,
        UserSubscription.is_active == True,
    ).update({"is_active": False})

    coupon_id = None
    duration_days = body.duration_days
    if body.coupon_code:
        from app.services.subscription_service import validate_coupon
        coupon = validate_coupon(db, body.coupon_code)
        if coupon.plan_id != plan.id:
            raise HTTPException(400, "Coupon is not valid for this plan")
        coupon_id = coupon.id
        duration_days = duration_days or coupon.duration_days
        coupon.times_used += 1

    if duration_days is None:
        duration_days = 30 if plan.name == "monthly" else 365 if plan.name == "annual" else 0

    now_utc = datetime.now(timezone.utc)
    expires_at = now_utc + timedelta(days=duration_days) if (plan.name != "free" and duration_days > 0) else None

    sub = UserSubscription(
        user_id=user.id,
        plan_id=plan.id,
        starts_at=now_utc,
        expires_at=expires_at,
        is_active=True,
        coupon_id=coupon_id,
    )
    db.add(sub)
    db.commit()

    return await get_user(user_ref=user_ref, admin=admin, db=db)


@router.post("/users/{user_ref}/cancel-subscription")
async def admin_cancel_subscription(
    user_ref: str,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user = _resolve_user(db, user_ref)
    sub = db.query(UserSubscription).filter(
        UserSubscription.user_id == user.id,
        UserSubscription.is_active == True,
    ).first()
    if not sub:
        raise HTTPException(404, "No active subscription found")
    sub.is_active = False
    db.commit()
    return {"message": "Subscription cancelled"}


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

        # Prefer point-in-time snapshot; fall back to "free" for very old rows
        # that predate the backfill (should be none after startup).
        plan_name = r.plan_name_at_request or "free"
        plan_source = r.plan_source_at_request or "free"

        items.append(RequestListItem(
            id=r.id,
            user_public_id=user.public_id if user else None,
            username=user.username if user else "unknown",
            api_key_id=r.api_key_id,
            api_key_name=api_key.name if api_key else None,
            filename=r.filename, duration_seconds=r.duration_seconds,
            processed_seconds=r.processed_seconds, language=r.language,
            word_count=r.word_count, was_trimmed=r.was_trimmed,
            status=r.status or "completed",
            error_message=r.error_message,
            plan_name=plan_name,
            plan_source=plan_source,
            daily_used=r.daily_used_at_request if r.daily_used_at_request is not None else 0,
            daily_limit=r.daily_limit_at_request if r.daily_limit_at_request is not None else 0,
            monthly_limit=r.monthly_limit_at_request,
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


# --- Plans ---

@router.get("/plans", response_model=list[PlanAdminItem])
async def admin_list_plans(
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    plans = db.query(Plan).order_by(Plan.id).all()
    plan_ids = [p.id for p in plans]
    counts = dict(
        db.query(UserSubscription.plan_id, func.count(UserSubscription.id))
        .filter(
            UserSubscription.plan_id.in_(plan_ids),
            UserSubscription.is_active == True,
        )
        .group_by(UserSubscription.plan_id)
        .all()
    ) if plan_ids else {}

    free_plan_id = next((p.id for p in plans if p.name == "free"), None)
    # Users without an active subscription implicitly use the free plan
    free_implicit_count = 0
    if free_plan_id is not None:
        subbed_user_ids = {
            uid for (uid,) in db.query(UserSubscription.user_id)
            .filter(UserSubscription.is_active == True)
            .all()
        }
        free_implicit_count = db.query(func.count(User.id)).filter(
            ~User.id.in_(subbed_user_ids) if subbed_user_ids else True,
            User.role == "user",
        ).scalar() or 0

    items = []
    for p in plans:
        count = counts.get(p.id, 0)
        if p.id == free_plan_id:
            count += free_implicit_count
        item = PlanAdminItem.model_validate(p)
        item.subscriber_count = count
        items.append(item)
    return items


@router.post("/plans", response_model=PlanAdminItem)
async def admin_create_plan(
    body: PlanCreate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    if db.query(Plan).filter(Plan.name == body.name).first():
        raise HTTPException(409, "Plan name already exists")

    plan = Plan(**body.model_dump())
    db.add(plan)
    db.commit()
    db.refresh(plan)
    item = PlanAdminItem.model_validate(plan)
    item.subscriber_count = 0
    return item


@router.put("/plans/{plan_id}", response_model=PlanAdminItem)
async def admin_update_plan(
    plan_id: int,
    body: PlanUpdate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    plan = db.query(Plan).filter(Plan.id == plan_id).first()
    if not plan:
        raise HTTPException(404, "Plan not found")

    updates = body.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(plan, field, value)
    db.commit()
    db.refresh(plan)

    sub_count = db.query(func.count(UserSubscription.id)).filter(
        UserSubscription.plan_id == plan.id,
        UserSubscription.is_active == True,
    ).scalar() or 0
    item = PlanAdminItem.model_validate(plan)
    item.subscriber_count = sub_count
    return item


@router.delete("/plans/{plan_id}")
async def admin_delete_plan(
    plan_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    plan = db.query(Plan).filter(Plan.id == plan_id).first()
    if not plan:
        raise HTTPException(404, "Plan not found")
    if plan.name == "free":
        raise HTTPException(400, "Free plan cannot be deleted")
    plan.is_active = False
    db.commit()
    return {"message": "Plan deactivated"}


@router.get("/plans/{plan_id}/subscribers", response_model=list[PlanSubscriberItem])
async def admin_plan_subscribers(
    plan_id: int,
    only_active: bool = Query(True),
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    plan = db.query(Plan).filter(Plan.id == plan_id).first()
    if not plan:
        raise HTTPException(404, "Plan not found")

    q = db.query(UserSubscription).filter(UserSubscription.plan_id == plan_id)
    if only_active:
        q = q.filter(UserSubscription.is_active == True)
    subs = q.order_by(UserSubscription.starts_at.desc()).all()

    user_ids = {s.user_id for s in subs}
    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}
    coupon_ids = {s.coupon_id for s in subs if s.coupon_id}
    coupons = {c.id: c for c in db.query(Coupon).filter(Coupon.id.in_(coupon_ids)).all()} if coupon_ids else {}

    now_utc = datetime.now(timezone.utc)
    items = []
    for s in subs:
        u = users.get(s.user_id)
        if not u:
            continue
        days_left = None
        if s.expires_at:
            expires_aware = s.expires_at.replace(tzinfo=timezone.utc) if s.expires_at.tzinfo is None else s.expires_at
            delta = expires_aware - now_utc
            days_left = max(delta.days, 0)
        source = "coupon" if s.coupon_id else ("purchase" if plan.name != "free" else "free")
        items.append(PlanSubscriberItem(
            user_id=u.id,
            user_public_id=u.public_id,
            username=u.username,
            full_name=u.full_name,
            email=u.email,
            plan_source=source,
            coupon_code=coupons[s.coupon_id].code if s.coupon_id and s.coupon_id in coupons else None,
            starts_at=s.starts_at,
            expires_at=s.expires_at,
            days_remaining=days_left,
        ))
    return items


# --- Subscriptions log ---

@router.get("/subscriptions", response_model=SubscriptionLogResponse)
async def admin_list_subscriptions(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user_id: Optional[int] = None,
    plan_id: Optional[int] = None,
    include_inactive: bool = Query(True),
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    q = db.query(UserSubscription)
    if user_id:
        q = q.filter(UserSubscription.user_id == user_id)
    if plan_id:
        q = q.filter(UserSubscription.plan_id == plan_id)
    if not include_inactive:
        q = q.filter(UserSubscription.is_active == True)

    total = q.count()
    subs = q.order_by(UserSubscription.starts_at.desc().nullslast(), UserSubscription.id.desc()).offset((page - 1) * per_page).limit(per_page).all()

    user_ids = {s.user_id for s in subs}
    plan_ids = {s.plan_id for s in subs}
    coupon_ids = {s.coupon_id for s in subs if s.coupon_id}
    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}
    plans = {p.id: p for p in db.query(Plan).filter(Plan.id.in_(plan_ids)).all()} if plan_ids else {}
    coupons = {c.id: c for c in db.query(Coupon).filter(Coupon.id.in_(coupon_ids)).all()} if coupon_ids else {}

    items = []
    for s in subs:
        u = users.get(s.user_id)
        p = plans.get(s.plan_id)
        plan_name = p.name if p else "?"
        if s.coupon_id:
            source = "coupon"
        elif plan_name == "free":
            source = "free"
        else:
            source = "purchase"
        items.append(SubscriptionLogItem(
            id=s.id,
            user_id=s.user_id,
            user_public_id=u.public_id if u else None,
            username=u.username if u else "unknown",
            plan_id=s.plan_id,
            plan_name=plan_name,
            plan_source=source,
            coupon_code=coupons[s.coupon_id].code if s.coupon_id and s.coupon_id in coupons else None,
            starts_at=s.starts_at,
            expires_at=s.expires_at,
            is_active=s.is_active,
            created_at=s.created_at,
        ))

    return SubscriptionLogResponse(subscriptions=items, total=total, page=page, per_page=per_page)


# --- Tickets ---

def _reply_counts_admin(db: Session, ticket_ids: list[int]) -> dict[int, int]:
    if not ticket_ids:
        return {}
    rows = db.query(TicketReply.ticket_id, func.count(TicketReply.id)).filter(
        TicketReply.ticket_id.in_(ticket_ids)
    ).group_by(TicketReply.ticket_id).all()
    return {tid: count for tid, count in rows}


@router.get("/tickets", response_model=AdminTicketListResponse)
async def admin_list_tickets(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    status_filter: Optional[str] = Query(None, alias="status"),
    ticket_type: Optional[str] = None,
    user_id: Optional[int] = None,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    q = db.query(SupportTicket)
    if status_filter:
        q = q.filter(SupportTicket.status == status_filter)
    if ticket_type:
        q = q.filter(SupportTicket.ticket_type == ticket_type)
    if user_id:
        q = q.filter(SupportTicket.user_id == user_id)

    total = q.count()
    tickets = q.order_by(SupportTicket.created_at.desc()).offset((page - 1) * per_page).limit(per_page).all()

    user_ids = {t.user_id for t in tickets}
    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}
    counts = _reply_counts_admin(db, [t.id for t in tickets])

    items = []
    for t in tickets:
        u = users.get(t.user_id)
        items.append(AdminTicketSummary(
            public_id=t.public_id,
            user_public_id=u.public_id if u else None,
            username=u.username if u else None,
            ticket_type=t.ticket_type,
            subject=t.subject,
            status=t.status,
            reply_count=counts.get(t.id, 0),
            last_reply_at=t.last_reply_at,
            created_at=t.created_at,
        ))
    return AdminTicketListResponse(tickets=items, total=total, page=page, per_page=per_page)


def _load_ticket_by_public_id(db: Session, public_id: str) -> SupportTicket:
    t = db.query(SupportTicket).filter(SupportTicket.public_id == public_id).first()
    if not t:
        raise HTTPException(404, "Ticket not found")
    return t


@router.get("/tickets/{public_id}", response_model=TicketDetail)
async def admin_get_ticket(
    public_id: str,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    t = _load_ticket_by_public_id(db, public_id)
    owner = db.query(User).filter(User.id == t.user_id).first()
    replies = db.query(TicketReply).filter(TicketReply.ticket_id == t.id).order_by(TicketReply.created_at).all()
    uids = {r.user_id for r in replies}
    if owner:
        uids.add(owner.id)
    users = {u.id: u for u in db.query(User).filter(User.id.in_(uids)).all()} if uids else {}

    def _name(uid):
        u = users.get(uid)
        if not u:
            return None
        return u.full_name or u.username

    reply_items = [
        TicketReplyItem(
            public_id=r.public_id,
            is_admin=r.is_admin,
            author_name=_name(r.user_id),
            message=r.message,
            created_at=r.created_at,
        ) for r in replies
    ]
    return TicketDetail(
        public_id=t.public_id,
        user_public_id=owner.public_id if owner else None,
        username=owner.username if owner else None,
        ticket_type=t.ticket_type,
        subject=t.subject,
        message=t.message,
        status=t.status,
        replies=reply_items,
        created_at=t.created_at,
        updated_at=t.updated_at,
    )


@router.post("/tickets/{public_id}/replies", response_model=TicketReplyItem)
async def admin_reply_ticket(
    public_id: str,
    body: TicketReplyCreate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    t = _load_ticket_by_public_id(db, public_id)
    if t.status == "closed":
        raise HTTPException(400, "Ticket is closed")

    reply = TicketReply(
        public_id=generate_public_id(),
        ticket_id=t.id,
        user_id=admin.id,
        is_admin=True,
        message=body.message.strip(),
    )
    db.add(reply)

    t.last_reply_at = datetime.now(timezone.utc)
    # Admin replying transitions open → in_progress (if not already resolved/closed)
    if t.status == "open":
        t.status = "in_progress"
    db.commit()
    db.refresh(reply)

    return TicketReplyItem(
        public_id=reply.public_id,
        is_admin=True,
        author_name=admin.full_name or admin.username,
        message=reply.message,
        created_at=reply.created_at,
    )


@router.put("/tickets/{public_id}/status", response_model=TicketDetail)
async def admin_update_ticket_status(
    public_id: str,
    body: TicketStatusUpdate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    t = _load_ticket_by_public_id(db, public_id)
    t.status = body.status
    db.commit()
    return await admin_get_ticket(public_id=public_id, admin=admin, db=db)


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
