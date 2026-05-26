import logging
import os
import tempfile
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile
from sqlalchemy.orm import Session
from sqlalchemy import func

logger = logging.getLogger(__name__)

from app.auth.api_key import generate_api_key
from app.core.config import TOKEN_EXPIRE_MINUTES
from app.db.database import get_db
from app.db.models import ApiKey, AppSetting, Coupon, Device, LoginEvent, Plan, SupportTicket, TicketReply, TranscriptionRequest, User, UserSubscription
from app.auth.jwt import get_current_admin
from app.schemas.admin import (
    AdminStatsResponse, UserListResponse, UserListItem, UserUpdateRequest,
    RequestListResponse, RequestListItem,
    CouponCreate, CouponResponse, CouponUpdate,
    PlanAdminItem, PlanCreate, PlanUpdate,
    SessionItem, UserUsageInfo, UserSubscriptionInfo, UserDetailResponse,
    AdminSubscribeRequest, SubscriptionLogItem, SubscriptionLogResponse,
    PlanSubscriberItem,
    AnalyzeAudioResponse, AnalyzeFileInfo, AnalyzeWordCount, AnalyzeSegment,
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
from app.schemas.settings import (
    ModelOption, ProviderInfo, ProviderModelUpdateRequest, ProviderOrderUpdateRequest,
    ProviderTestResponse, TranscriptionProviderResponse,
    TranscriptionProviderUpdateRequest, TranscriptionProviderUsageResponse,
)
from app.services.subscription_service import get_user_plan, subscribe_user
from app.services import audit_service, settings_service, transcription_service, usage_service
from app.services import text_analyzer
from app.services.file_validation import validate_audio_upload


# Window during which a successful login still has a potentially-live access
# token. JWTs are stateless, so this is the best proxy we have for "alive
# session" without a real session table. Bumped slightly so a token that
# expires while the page is loading still counts as the same session.
_SESSION_LIVE_WINDOW = timedelta(minutes=max(TOKEN_EXPIRE_MINUTES, 5))


def _device_fingerprint(e: LoginEvent) -> tuple:
    """Group successive logins from the same device under one 'session'. We
    fall back to ip_address + user_agent when device fields are missing
    (web/admin sign-ins set those rather than device_*)."""
    return (
        (e.device_platform or "").strip().lower(),
        (e.device_model or "").strip().lower(),
        (e.app_version or "").strip().lower(),
        (e.ip_address or "").strip(),
        (e.user_agent or "")[:120],
    )


def _count_active_sessions(db: Session, user: User) -> tuple[int, Optional[datetime]]:
    """Returns (active_session_count, last_session_at) for one user.

    - Deactivated accounts always report 0 — their tokens are also rejected
      by ``get_current_user``, so any historical login row is dead weight.
    - Refresh events are excluded because they extend an existing session
      rather than open a new one.
    - Distinct device fingerprints are counted once even if the user
      re-logged on the same device.
    """
    if not user.is_active:
        return 0, None
    cutoff = datetime.now(timezone.utc) - _SESSION_LIVE_WINDOW
    events = db.query(LoginEvent).filter(
        LoginEvent.user_id == user.id,
        LoginEvent.success == True,
        LoginEvent.event_type.in_(["login", "register"]),
        LoginEvent.created_at >= cutoff,
    ).order_by(LoginEvent.created_at.desc()).all()
    devices: set = set()
    last: Optional[datetime] = None
    for e in events:
        devices.add(_device_fingerprint(e))
        if last is None:
            last = e.created_at
    return len(devices), last


def _batch_active_sessions(
    db: Session, users: list[User]
) -> dict[int, tuple[int, Optional[datetime]]]:
    """Per-user (active_count, last_at). One query, grouped in Python so we
    can apply the device-fingerprint dedupe that SQL can't do cleanly."""
    if not users:
        return {}
    active_ids = [u.id for u in users if u.is_active]
    if not active_ids:
        return {u.id: (0, None) for u in users}
    cutoff = datetime.now(timezone.utc) - _SESSION_LIVE_WINDOW
    events = db.query(LoginEvent).filter(
        LoginEvent.user_id.in_(active_ids),
        LoginEvent.success == True,
        LoginEvent.event_type.in_(["login", "register"]),
        LoginEvent.created_at >= cutoff,
    ).order_by(LoginEvent.created_at.desc()).all()
    per_user: dict[int, dict] = {}
    for e in events:
        slot = per_user.setdefault(e.user_id, {"devices": set(), "last": None})
        slot["devices"].add(_device_fingerprint(e))
        if slot["last"] is None:
            slot["last"] = e.created_at
    out: dict[int, tuple[int, Optional[datetime]]] = {}
    for u in users:
        if not u.is_active:
            out[u.id] = (0, None)
        else:
            slot = per_user.get(u.id)
            out[u.id] = (len(slot["devices"]), slot["last"]) if slot else (0, None)
    return out


def _safe_audit(db, **kwargs):
    """Best-effort audit-log write. NEVER raises so the calling admin action
    can't be silently broken by a missing table or schema drift. See F27."""
    try:
        audit_service.record(db, **kwargs)
    except Exception:
        pass

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

    # "Active" = login/register within the access-token lifetime, deduped by
    # device fingerprint, zero for deactivated accounts. See _count_active_sessions.
    session_stats = _batch_active_sessions(db, users)

    items = []
    for u in users:
        sub = subs.get(u.id)
        plan_name = plans.get(sub.plan_id).name if sub and plans.get(sub.plan_id) else "free"
        active_count, last_at = session_stats.get(u.id, (0, None))
        items.append(UserListItem(
            id=u.id, public_id=u.public_id, email=u.email, full_name=u.full_name,
            role=u.role, is_active=u.is_active, auth_provider=u.auth_provider,
            plan_name=plan_name,
            active_sessions=active_count,
            last_session_at=last_at,
            survey_response=u.survey_response,
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

    active_sessions, _ = _count_active_sessions(db, user)

    return UserDetailResponse(
        id=user.id, public_id=user.public_id, email=user.email,
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
            # F12: also block self-demotion explicitly (the schema only
            # restricts the value space; this guards the semantics).
            raise HTTPException(403, "You cannot remove your own admin role")

    # F12: protect other admins. A regular admin must not be able to disable
    # another admin's account; only the affected admin (handled above) can
    # change their own state. This keeps a hostile/compromised admin from
    # locking everyone else out.
    if body.is_active is False and user.role == "admin" and user.id != admin.id:
        raise HTTPException(403, "Cannot disable another admin")

    changed: dict = {}
    if body.is_active is not None and body.is_active != user.is_active:
        changed["is_active"] = (user.is_active, body.is_active)
        user.is_active = body.is_active
    if body.role is not None and body.role != user.role:
        changed["role"] = (user.role, body.role)
        user.role = body.role
    if body.full_name is not None and body.full_name != user.full_name:
        changed["full_name"] = (user.full_name, body.full_name)
        user.full_name = body.full_name
    if body.email is not None:
        if body.email != user.email:
            existing = db.query(User).filter(User.email == body.email, User.id != user.id).first()
            if existing:
                raise HTTPException(409, "Email already in use")
            changed["email"] = (user.email, body.email)
            user.email = body.email
    db.commit()

    if changed:
        _safe_audit(
            db, action="admin.user.update", actor_user_id=admin.id,
            target_type="user", target_id=user.id,
            metadata={"changes": {k: {"from": v[0], "to": v[1]} for k, v in changed.items()}},
        )
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
    # F12: 403 (not 400) — this is an authorization decision, not a validation error.
    if user.role == "admin":
        raise HTTPException(403, "Cannot disable another admin")
    user.is_active = False
    db.commit()
    _safe_audit(
        db, action="admin.user.delete", actor_user_id=admin.id,
        target_type="user", target_id=user.id,
        metadata={"email": user.email},
    )
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

    # Same definition the list/detail endpoints use — only the *latest* event
    # per device fingerprint is "still live", and only while its token hasn't
    # expired. Deactivated accounts → no event is active.
    cutoff = datetime.now(timezone.utc) - _SESSION_LIVE_WINDOW
    seen_devices: set = set()
    items: list[SessionItem] = []
    for e in events:
        created_aware = (
            e.created_at.replace(tzinfo=timezone.utc)
            if e.created_at and e.created_at.tzinfo is None
            else e.created_at
        )
        is_active = False
        if (
            user.is_active
            and e.success
            and e.event_type in ("login", "register")
            and created_aware
            and created_aware >= cutoff
        ):
            fp = _device_fingerprint(e)
            if fp not in seen_devices:
                seen_devices.add(fp)
                is_active = True
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
        # Use the atomic UPDATE...RETURNING service so the times_used counter
        # is bumped race-free (prevents single-use coupon being redeemed
        # concurrently by multiple admins). The service also enforces
        # plan/is_active/expiry rules in the same SQL statement.
        from app.services.subscription_service import validate_and_consume_coupon
        try:
            consumed = validate_and_consume_coupon(db, body.coupon_code, plan.id)
        except ValueError as exc:
            raise HTTPException(400, str(exc))
        coupon_id = consumed.id
        duration_days = duration_days or consumed.duration_days

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

    _safe_audit(
        db, action="admin.user.subscribe", actor_user_id=admin.id,
        target_type="user", target_id=user.id,
        metadata={
            "plan_id": plan.id, "plan_name": plan.name,
            "coupon_id": coupon_id, "duration_days": duration_days,
        },
    )

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
    _safe_audit(
        db, action="admin.user.unsubscribe", actor_user_id=admin.id,
        target_type="user", target_id=user.id,
        metadata={"subscription_id": sub.id, "plan_id": sub.plan_id},
    )
    return {"message": "Subscription cancelled"}


# --- Requests ---

@router.get("/requests", response_model=RequestListResponse)
async def list_requests(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user_id: Optional[int] = None,
    api_key_id: Optional[int] = None,
    language: Optional[str] = None,
    source: Optional[str] = None,
    # Filter by the engine that produced the transcription. Useful for
    # comparing on-device (`client_side`) volume against server providers
    # (`whisper` / `gemini` / `speechmatics` / `groq` / `assemblyai`).
    provider_used: Optional[str] = None,
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
    if source:
        q = q.filter(TranscriptionRequest.source == source)
    if provider_used:
        q = q.filter(TranscriptionRequest.provider_used == provider_used)

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
            email=user.email if user else None,
            full_name=user.full_name if user else None,
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
            source=r.source or "upload",
            is_live_recording=bool(r.is_live_recording),
            provider_used=r.provider_used,
            model_used=r.model_used,
            latency_ms=r.latency_ms,
            created_at=r.created_at,
        ))

    return RequestListResponse(requests=items, total=total, page=page, per_page=per_page)


# --- Coupons ---

@router.get("/coupons")
async def list_coupons(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    # F29: ensure stable default ordering + pagination.
    q = db.query(Coupon).order_by(Coupon.created_at.desc(), Coupon.id.desc())
    total = q.count()
    coupons = q.offset((page - 1) * per_page).limit(per_page).all()
    return {
        "coupons": [CouponResponse.model_validate(c) for c in coupons],
        "total": total,
        "page": page,
        "per_page": per_page,
    }


@router.post("/coupons", response_model=CouponResponse)
async def create_coupon(
    body: CouponCreate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    # F14: validate plan existence at the route layer with a clear 404 instead
    # of letting the FK violation surface as a generic 500 from the DB driver.
    plan = db.query(Plan).filter(Plan.id == body.plan_id).first()
    if not plan:
        raise HTTPException(404, "Plan not found")
    if not plan.is_active:
        raise HTTPException(400, "Plan is not active")

    # F13: code is already canonicalized to uppercase by the schema validator,
    # so we can compare directly without normalizing here.
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

    _safe_audit(
        db, action="admin.coupon.create", actor_user_id=admin.id,
        target_type="coupon", target_id=coupon.id,
        metadata={"code": coupon.code, "plan_id": coupon.plan_id},
    )
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
    _safe_audit(
        db, action="admin.coupon.update", actor_user_id=admin.id,
        target_type="coupon", target_id=coupon.id,
    )
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
    code = coupon.code
    # Hard-delete when the coupon was never redeemed. If it is still referenced
    # by a subscription (FK), fall back to deactivation to preserve history.
    referenced = db.query(UserSubscription.id).filter(UserSubscription.coupon_id == coupon_id).first()
    if referenced:
        coupon.is_active = False
        db.commit()
        _safe_audit(
            db, action="admin.coupon.delete", actor_user_id=admin.id,
            target_type="coupon", target_id=coupon_id,
            metadata={"code": code, "mode": "deactivated"},
        )
        return {"message": "Coupon deactivated"}
    db.delete(coupon)
    db.commit()
    _safe_audit(
        db, action="admin.coupon.delete", actor_user_id=admin.id,
        target_type="coupon", target_id=coupon_id,
        metadata={"code": code, "mode": "deleted"},
    )
    return {"message": "Coupon deleted"}


# --- Plans ---

@router.get("/plans", response_model=list[PlanAdminItem])
async def admin_list_plans(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    # F29: stable ordering + pagination. Plans table has no `created_at` column
    # so we order by id (which is monotonic) — keeps free plan first for legacy
    # callers that depend on insertion order.
    plans = (
        db.query(Plan)
        .order_by(Plan.id)
        .offset((page - 1) * per_page)
        .limit(per_page)
        .all()
    )
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
    _safe_audit(
        db, action="admin.plan.create", actor_user_id=admin.id,
        target_type="plan", target_id=plan.id,
        metadata={"name": plan.name},
    )
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

    _safe_audit(
        db, action="admin.plan.update", actor_user_id=admin.id,
        target_type="plan", target_id=plan.id,
        metadata={"changes": list(updates.keys())},
    )

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
    _safe_audit(
        db, action="admin.plan.delete", actor_user_id=admin.id,
        target_type="plan", target_id=plan.id,
        metadata={"name": plan.name},
    )
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
            email=u.email if u else None,
            full_name=u.full_name if u else None,
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
            user_email=u.email if u else None,
            user_full_name=u.full_name if u else None,
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
        return u.full_name or u.email

    # Load attachments + group by reply (mirrors /support/tickets/{id} logic).
    from app.db.models import TicketAttachment as _TA
    from app.schemas.support import TicketAttachmentItem as _TAItem
    atts = db.query(_TA).filter(_TA.ticket_id == t.id).order_by(_TA.created_at).all()
    reply_public_ids = {r.id: r.public_id for r in replies}
    on_msg: list = []
    by_reply: dict[int, list] = {}
    for a in atts:
        item = _TAItem(
            public_id=a.public_id,
            reply_public_id=reply_public_ids.get(a.reply_id) if a.reply_id else None,
            original_filename=a.original_filename,
            mime_type=a.mime_type,
            size_bytes=a.size_bytes,
            created_at=a.created_at,
        )
        if a.reply_id is None:
            on_msg.append(item)
        else:
            by_reply.setdefault(a.reply_id, []).append(item)

    reply_items = [
        TicketReplyItem(
            public_id=r.public_id,
            is_admin=r.is_admin,
            author_name=_name(r.user_id),
            message=r.message,
            created_at=r.created_at,
            attachments=by_reply.get(r.id, []),
        ) for r in replies
    ]
    return TicketDetail(
        public_id=t.public_id,
        user_public_id=owner.public_id if owner else None,
        user_email=owner.email if owner else None,
        user_full_name=owner.full_name if owner else None,
        ticket_type=t.ticket_type,
        subject=t.subject,
        message=t.message,
        status=t.status,
        replies=reply_items,
        attachments=on_msg,
        created_at=t.created_at,
        updated_at=t.updated_at,
    )


@router.get("/tickets/{public_id}/attachments/{attachment_public_id}")
async def admin_download_attachment(
    public_id: str,
    attachment_public_id: str,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Admin can view any attachment on any ticket (the user-facing endpoint
    is owner-scoped — admins need this separate path)."""
    from fastapi.responses import FileResponse
    from app.db.models import TicketAttachment as _TA
    from app.services import ticket_attachment_service as _tas
    t = _load_ticket_by_public_id(db, public_id)
    a = db.query(_TA).filter(
        _TA.public_id == attachment_public_id,
        _TA.ticket_id == t.id,
    ).first()
    if not a:
        raise HTTPException(404, "Attachment not found")
    path = _tas.attachment_disk_path(a)
    if not path.exists():
        raise HTTPException(404, "Attachment file missing from disk")
    return FileResponse(
        path=str(path),
        media_type=a.mime_type,
        filename=a.original_filename or f"{a.public_id}",
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
        author_name=admin.full_name or admin.email,
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
            (User.email.ilike(like)) |
            (User.full_name.ilike(like))
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
            user_email=user.email,
            user_full_name=user.full_name,
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


# --- Settings: transcription provider ----------------------------------------

_PROVIDER_META = {
    "whisper": {
        "label": "Whisper (محلي)",
        "description": "نموذج Whisper يعمل داخل السيرفر — جودة عالية لكن أبطأ ويستهلك موارد كبيرة.",
    },
    "speechmatics": {
        "label": "Speechmatics",
        "description": "ASR متخصص (سحابي) — سريع، دقّة عربية ممتازة، timestamps دقيقة. يحتاج مفتاح SP.",
    },
    "gemini": {
        "label": "Gemini",
        "description": "نموذج Google متعدد الوسائط — رخيص جداً وله free tier سخي. لا يعطي timestamps للكلمات.",
    },
    "groq": {
        "label": "Groq Whisper",
        "description": "Whisper مستضاف على Groq LPU — أسرع inference متاح، free tier يومي.",
    },
    "assemblyai": {
        "label": "AssemblyAI",
        "description": "ASR متخصص بـ diarization وتحليل المشاعر، $50 credit مجاناً عند التسجيل.",
    },
}


def _build_provider_response(db: Session) -> TranscriptionProviderResponse:
    current = settings_service.get_transcription_provider(db)
    effective = transcription_service.resolve_provider(db)
    availability = transcription_service.provider_availability()

    row = db.query(AppSetting).filter(
        AppSetting.key == settings_service.KEY_TRANSCRIPTION_PROVIDER
    ).first()

    providers = []
    for name in settings_service.VALID_PROVIDERS:
        models = transcription_service.available_models(name)
        providers.append(ProviderInfo(
            name=name,
            label=_PROVIDER_META[name]["label"],
            description=_PROVIDER_META[name]["description"],
            available=availability.get(name, False),
            models=[ModelOption(**m) for m in models],
            selected_model=settings_service.get_provider_model(db, name),
            default_model=transcription_service.default_model(name),
        ))

    return TranscriptionProviderResponse(
        current=current,
        effective=effective,
        updated_at=row.updated_at if row else None,
        updated_by_user_id=row.updated_by_user_id if row else None,
        providers=providers,
        provider_order=settings_service.get_provider_order(db),
    )


@router.get("/settings/transcription-provider", response_model=TranscriptionProviderResponse)
async def get_transcription_provider_setting(
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    return _build_provider_response(db)


@router.put("/settings/transcription-provider", response_model=TranscriptionProviderResponse)
async def update_transcription_provider_setting(
    body: TranscriptionProviderUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    availability = transcription_service.provider_availability()
    if not availability.get(body.provider, False):
        raise HTTPException(
            400,
            f"Provider '{body.provider}' is not configured on this server. "
            f"Configure it first, then switch."
        )
    try:
        settings_service.set_transcription_provider(db, body.provider, user_id=admin.id)
    except ValueError as e:
        raise HTTPException(400, str(e))
    _safe_audit(
        db, action="admin.settings.update", actor_user_id=admin.id,
        target_type="setting", metadata={"key": "transcription_provider", "value": body.provider},
    )
    return _build_provider_response(db)


@router.get(
    "/settings/transcription-provider/usage",
    response_model=TranscriptionProviderUsageResponse,
)
async def get_transcription_provider_usage(
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    providers = list(settings_service.VALID_PROVIDERS)
    items = await usage_service.build_all_usage(db, providers)
    return TranscriptionProviderUsageResponse(providers=items)


@router.put(
    "/settings/transcription-provider/model",
    response_model=TranscriptionProviderResponse,
)
async def update_provider_model(
    body: ProviderModelUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    # Validate that the model id is actually one this provider offers.
    options = transcription_service.available_models(body.provider)
    valid_ids = {m["id"] for m in options}
    if valid_ids and body.model not in valid_ids:
        raise HTTPException(
            400,
            f"Model '{body.model}' is not offered by '{body.provider}'. "
            f"Valid options: {sorted(valid_ids)}",
        )
    try:
        settings_service.set_provider_model(db, body.provider, body.model, user_id=admin.id)
    except ValueError as e:
        raise HTTPException(400, str(e))
    _safe_audit(
        db, action="admin.settings.update", actor_user_id=admin.id,
        target_type="setting",
        metadata={"key": "provider_model", "provider": body.provider, "model": body.model},
    )
    return _build_provider_response(db)


@router.put(
    "/settings/transcription-provider/order",
    response_model=TranscriptionProviderResponse,
)
async def update_provider_order(
    body: ProviderOrderUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Set the auto-failover priority order. When the active provider fails
    mid-request, the dispatcher walks this list to pick the next one to try."""
    try:
        settings_service.set_provider_order(db, list(body.order), user_id=admin.id)
    except ValueError as e:
        raise HTTPException(400, str(e))
    _safe_audit(
        db, action="admin.settings.update", actor_user_id=admin.id,
        target_type="setting",
        metadata={"key": "provider_order", "order": list(body.order)},
    )
    return _build_provider_response(db)


@router.post(
    "/settings/transcription-provider/test",
    response_model=ProviderTestResponse,
)
async def test_transcription_provider(
    provider: str = Form(...),
    model: str | None = Form(None),
    file: UploadFile = File(...),
    admin: User = Depends(get_current_admin),
):
    """Run a one-off transcription with a specific provider+model and return
    text + latency. Used by the admin 'test' button on the settings page —
    bypasses plan resolution and is NOT logged to transcription_requests.
    """
    if provider not in settings_service.VALID_PROVIDERS:
        raise HTTPException(400, f"Unknown provider '{provider}'")
    if not transcription_service.provider_availability().get(provider, False):
        raise HTTPException(400, f"Provider '{provider}' is not configured on this server.")

    import os
    import tempfile
    import time
    from app.services.audio_utils import probe_duration

    suffix = os.path.splitext(file.filename or ".wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        audio_duration = probe_duration(tmp_path)
        started = time.perf_counter()
        result = await transcription_service.transcribe_with_provider(
            tmp_path, provider, model=model, duration=audio_duration
        )
        elapsed_ms = int((time.perf_counter() - started) * 1000)
    except Exception as e:
        raise HTTPException(500, f"Provider test failed: {e}")
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    text = (result.get("text") or "").strip()
    segments = result.get("segments") or []
    return ProviderTestResponse(
        provider=provider,
        model=model,
        duration_ms=elapsed_ms,
        audio_seconds=round(audio_duration, 2),
        text=text,
        language=result.get("language"),
        word_count=len(text.split()) if text else 0,
        segment_count=len(segments),
    )


# --- Ticket attachment limits (admin) ---------------------------------------

from pydantic import BaseModel as _BM, Field as _F


class TicketAttachLimits(_BM):
    """Admin-tunable caps for support-ticket image attachments."""
    max_bytes: int = _F(..., ge=1, le=100 * 1024 * 1024)
    allowed_extensions: list[str]


class TicketAttachLimitsUpdate(_BM):
    max_bytes: int | None = _F(default=None, ge=1, le=100 * 1024 * 1024)
    allowed_extensions: list[str] | None = None


@router.get("/settings/ticket-attachments", response_model=TicketAttachLimits)
async def get_ticket_attach_limits(
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    return TicketAttachLimits(
        max_bytes=settings_service.get_ticket_attach_max_bytes(db),
        allowed_extensions=sorted(settings_service.get_ticket_attach_allowed_extensions(db)),
    )


@router.put("/settings/ticket-attachments", response_model=TicketAttachLimits)
async def update_ticket_attach_limits(
    body: TicketAttachLimitsUpdate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    try:
        if body.max_bytes is not None:
            settings_service.set_ticket_attach_max_bytes(db, body.max_bytes, user_id=admin.id)
        if body.allowed_extensions is not None:
            settings_service.set_ticket_attach_allowed_extensions(
                db, body.allowed_extensions, user_id=admin.id
            )
    except ValueError as e:
        raise HTTPException(400, str(e))
    return TicketAttachLimits(
        max_bytes=settings_service.get_ticket_attach_max_bytes(db),
        allowed_extensions=sorted(settings_service.get_ticket_attach_allowed_extensions(db)),
    )


# --- Admin audio analyzer ----------------------------------------------------
# Admin-only inspection tool: upload an audio file, get the transcript + rich
# linguistic stats. Does NOT touch the user's quota, does NOT create a
# TranscriptionRequest row — it's a one-off diagnostic, not a billable action.

_ANALYZE_MAX_BYTES = 100 * 1024 * 1024   # 100 MB
_ANALYZE_CHUNK = 1024 * 1024


async def _stream_admin_upload(file: UploadFile, suffix: str) -> tuple[str, bytes, int]:
    """Stream the upload to a tmp file in 1 MiB chunks, capped at the admin
    limit. Mirrors the safety properties of transcribe._stream_to_tmp but with
    a tighter ceiling — admin diagnostics shouldn't be moving 200 MB files."""
    advertised = getattr(file, "size", None)
    if advertised is not None and advertised > _ANALYZE_MAX_BYTES:
        raise HTTPException(413, {"error": "file_too_large", "limit_bytes": _ANALYZE_MAX_BYTES})
    fd, tmp_path = tempfile.mkstemp(suffix=suffix)
    total = 0
    head = b""
    try:
        with os.fdopen(fd, "wb") as out:
            while True:
                chunk = await file.read(_ANALYZE_CHUNK)
                if not chunk:
                    break
                total += len(chunk)
                if total > _ANALYZE_MAX_BYTES:
                    out.close()
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    raise HTTPException(
                        413, {"error": "file_too_large", "limit_bytes": _ANALYZE_MAX_BYTES})
                if not head:
                    head = chunk[:16]
                out.write(chunk)
    except HTTPException:
        raise
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        logger.exception("admin upload streaming failed")
        raise HTTPException(500, "Upload failed. Please try again.")
    return tmp_path, head, total


@router.post("/analyze-audio", response_model=AnalyzeAudioResponse)
async def analyze_audio(
    request: Request,
    file: UploadFile = File(...),
    provider: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Transcribe an audio file and return rich linguistic stats. Admin-only;
    bypasses user quota and does not persist a request row."""
    suffix = os.path.splitext(file.filename or ".wav")[1] or ".wav"
    tmp_path, head, total_bytes = await _stream_admin_upload(file, suffix)

    try:
        validate_audio_upload(file.filename, file.content_type, head)
    except HTTPException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    try:
        if provider:
            # Admin asked for a specific provider — bypass failover so the
            # response reflects what that provider actually returned.
            result = await transcription_service.transcribe_with_provider(
                tmp_path, provider=provider, model=model,
            )
            used_provider, used_model = provider, model
        else:
            result, used_provider, used_model = await transcription_service.transcribe_from_path(
                db, tmp_path, plan=None, provider=None, model=None,
            )
    except HTTPException:
        raise
    except Exception:
        logger.exception("admin analyze-audio transcription failed")
        raise HTTPException(502, "Transcription failed. Please try again.")
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    base = text_analyzer.build_response(result)
    extra = text_analyzer.extended_analysis(base["text"], base.get("duration", 0.0))

    _safe_audit(
        db,
        actor_id=admin.id,
        action="admin.analyze_audio",
        target_type="audio",
        target_id=None,
        metadata={
            "filename": file.filename,
            "size_bytes": total_bytes,
            "provider": used_provider,
            "model": used_model,
            "duration": base.get("duration", 0.0),
            "word_count": extra["word_count"],
        },
    )

    return AnalyzeAudioResponse(
        file=AnalyzeFileInfo(
            filename=file.filename or "audio",
            content_type=file.content_type,
            size_bytes=total_bytes,
        ),
        provider=used_provider,
        model=used_model,
        language=base["lang"],
        language_name=base["lang_name"],
        duration_seconds=base.get("duration", 0.0),
        text=base["text"],
        char_count=base["char_count"],
        char_count_no_spaces=base["char_count_no_spaces"],
        word_count=extra["word_count"],
        unique_word_count=extra["unique_word_count"],
        avg_word_length=extra["avg_word_length"],
        longest_word=extra["longest_word"],
        sentence_count=extra["sentence_count"],
        paragraph_count=extra["paragraph_count"],
        line_count=extra["line_count"],
        segment_count=base["segment_count"],
        speaking_rate_wpm=extra["speaking_rate_wpm"],
        punctuation=base["punctuation_count"],
        top_words=[AnalyzeWordCount(**w) for w in extra["top_words"]],
        segments=[
            AnalyzeSegment(id=s["id"], start=s["start"], end=s["end"], text=s["text"])
            for s in base["segments"]
        ],
    )


# --- Devices + push-notification fan-out -------------------------------------

from app.schemas.devices import (  # noqa: E402  — local-only routes file
    DeviceItem, DeviceListResponse,
    NotificationSendRequest, NotificationSendResponse,
)
from app.services import notification_service as _notif_service  # noqa: E402


def _device_to_item(d: Device, u: Optional[User]) -> DeviceItem:
    return DeviceItem(
        public_id=d.public_id,
        user_id=d.user_id,
        user_email=u.email if u else None,
        user_full_name=u.full_name if u else None,
        platform=d.platform,
        device_model=d.device_model,
        device_marketing_name=d.device_marketing_name,
        device_os=d.device_os,
        device_os_version=d.device_os_version,
        device_locale=d.device_locale,
        app_version=d.app_version,
        push_enabled=d.push_enabled,
        last_seen_at=d.last_seen_at,
        created_at=d.created_at,
    )


@router.get("/devices", response_model=DeviceListResponse)
async def admin_list_devices(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    platform: Optional[str] = Query(None, pattern="^(android|ios)$"),
    push_enabled: Optional[bool] = None,
    user_id: Optional[int] = None,
    search: Optional[str] = Query(None, max_length=120),
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """All registered devices, joined with their user for display purposes."""
    q = db.query(Device, User).join(User, User.id == Device.user_id)
    if platform:
        q = q.filter(Device.platform == platform)
    if push_enabled is not None:
        q = q.filter(Device.push_enabled == push_enabled)
    if user_id is not None:
        q = q.filter(Device.user_id == user_id)
    if search:
        like = f"%{search}%"
        q = q.filter(
            (User.email.ilike(like))
            | (User.full_name.ilike(like))
            | (Device.device_marketing_name.ilike(like))
            | (Device.device_model.ilike(like))
        )
    total = q.count()
    rows = (
        q.order_by(Device.last_seen_at.desc().nullslast())
        .offset((page - 1) * per_page)
        .limit(per_page)
        .all()
    )
    items = [_device_to_item(d, u) for d, u in rows]
    return DeviceListResponse(devices=items, total=total, page=page, per_page=per_page)


@router.get("/users/{user_ref}/devices", response_model=list[DeviceItem])
async def admin_user_devices(
    user_ref: str,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Per-user device list — surfaced on /users/[id] for the founder's
    "what device is this person on?" workflow."""
    user = _resolve_user(db, user_ref)
    rows = (
        db.query(Device)
        .filter(Device.user_id == user.id)
        .order_by(Device.last_seen_at.desc().nullslast())
        .all()
    )
    return [_device_to_item(d, user) for d in rows]


@router.post("/notifications/send", response_model=NotificationSendResponse)
async def admin_send_notification(
    body: NotificationSendRequest,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Fan a push notification out to a target slice (everyone, specific
    users, specific devices, or just hearing-impaired survey responders).

    No-ops if Firebase Admin isn't configured (logged as a warning) so
    pre-credential testing of the admin UI still works without crashing.
    """
    # Resolve the target set into a list of FCM tokens.
    q = db.query(Device).filter(Device.push_enabled == True)  # noqa: E712
    if body.target == "users":
        if not body.user_ids:
            raise HTTPException(400, "target=users requires user_ids")
        q = q.filter(Device.user_id.in_(body.user_ids))
    elif body.target == "devices":
        if not body.device_public_ids:
            raise HTTPException(400, "target=devices requires device_public_ids")
        q = q.filter(Device.public_id.in_(body.device_public_ids))
    elif body.target == "hearing_impaired":
        # Match users whose survey reasons include the deaf marker. SQL JSON
        # match would be cleaner but the column is plain TEXT, so a LIKE on
        # the serialised JSON gets us there with no migration.
        q = q.join(User, User.id == Device.user_id).filter(
            User.survey_response.ilike("%hearing_impaired%"),
        )
    elif body.target != "all":
        raise HTTPException(400, "Unknown target")

    devices = q.all()
    tokens = [d.fcm_token for d in devices if d.fcm_token]
    skipped = sum(1 for d in devices if not d.fcm_token)

    if not tokens:
        return NotificationSendResponse(sent=0, failed=0, skipped_no_token=skipped)

    data: dict[str, str] = {}
    if body.deep_link:
        data["deep_link"] = body.deep_link

    sent, failed = await _notif_service.send_to_tokens(
        tokens, title=body.title, body=body.body, data=data,
    )
    _safe_audit(
        db, actor_id=admin.id, action="admin.notification.send",
        target_type="broadcast", target_id=None,
        metadata={
            "target": body.target,
            "tokens": len(tokens),
            "sent": sent,
            "failed": failed,
            "title": body.title[:80],
        },
    )
    return NotificationSendResponse(sent=sent, failed=failed, skipped_no_token=skipped)
