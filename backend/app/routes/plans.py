from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import limiter
from app.db.database import get_db
from app.db.models import Plan, TranscriptionRequest, User
from app.auth.jwt import get_current_user
from app.schemas.plans import (
    CouponApplyRequest, CouponValidateRequest, CouponValidationResponse,
    PlanResponse, SubscribeRequest, SubscriptionResponse,
)
from app.services.subscription_service import (
    cancel_current_subscription, get_active_subscription, get_user_plan,
    subscribe_user, validate_coupon,
)

router = APIRouter(prefix="/plans", tags=["plans"])


@router.get("", response_model=List[PlanResponse])
async def list_plans(db: Session = Depends(get_db)):
    plans = db.query(Plan).filter(Plan.is_active == True).all()
    return plans


@router.get("/my")
@router.get("/current")  # alias — the mobile client calls /plans/current
async def my_subscription(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    plan = get_user_plan(db, user.id)
    sub = get_active_subscription(db, user.id)

    # Today's usage so the mobile app can render "12 / 50 requests today".
    today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    used_today = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= today,
        TranscriptionRequest.status != "failed",
    ).scalar() or 0

    return {
        "plan": PlanResponse.model_validate(plan) if plan else None,
        "subscription": SubscriptionResponse.model_validate(sub) if sub else None,
        "usage": {
            "requests_today": used_today,
            "daily_limit": plan.daily_request_limit if plan else 0,
            "max_audio_seconds": plan.max_audio_seconds if plan else 0,
        },
    }


# TODO: integrate payment gateway (Stripe / MyFatoorah / Tap). For now, paid
# plans require an admin-issued coupon. The 402 below is the canonical signal
# for "this would normally cost money".
@router.post("/subscribe")
@limiter.limit("5/minute")
async def subscribe(
    body: SubscribeRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # F3: gate paid plans behind a coupon (until payments ship). Free plan is
    # still self-serve so first-time signups can pick it without an admin.
    plan = db.query(Plan).filter(Plan.id == body.plan_id, Plan.is_active == True).first()
    if not plan:
        raise HTTPException(404, "Plan not found or inactive")

    is_free_plan = (plan.price == 0) and (plan.name == "free")
    if not is_free_plan and not body.coupon_code:
        return JSONResponse(
            status_code=402,
            content={
                "error": "payment_required",
                "message": (
                    "This plan requires a coupon or payment. "
                    "Payment integration not yet implemented."
                ),
            },
        )

    # F4: defense-in-depth coupon/plan binding check. The service layer also
    # enforces this atomically (subscription_service.validate_and_consume_coupon),
    # but a route-level check fails faster and produces a clearer error code.
    if body.coupon_code:
        try:
            coupon = validate_coupon(db, body.coupon_code)
        except ValueError as e:
            raise HTTPException(400, str(e))
        if coupon.plan_id != body.plan_id:
            raise HTTPException(400, "Coupon is not valid for the selected plan")

    try:
        sub = subscribe_user(db, user.id, body.plan_id, body.coupon_code)
    except ValueError as e:
        raise HTTPException(400, str(e))

    return {"message": "Subscribed successfully", "subscription_id": sub.id}


@router.post("/coupon")
@limiter.limit("5/minute")
async def apply_coupon(
    body: CouponApplyRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # F5: rate-limit the validate-coupon endpoint so an attacker can't brute
    # force coupon codes from one principal. The 5/min bucket is keyed by
    # auth_principal (see core.config._rate_limit_key).
    try:
        coupon = validate_coupon(db, body.code)
    except ValueError as e:
        raise HTTPException(400, str(e))

    sub = subscribe_user(db, user.id, coupon.plan_id, body.code)
    return {"message": "Coupon applied successfully", "subscription_id": sub.id}


@router.post("/coupon/validate", response_model=CouponValidationResponse)
@limiter.limit("10/minute")
async def validate_coupon_only(
    body: CouponValidateRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Read-only preview — tells the client what a coupon would grant WITHOUT
    redeeming it. Lets the mobile app show "this unlocks the Monthly plan,
    permanently" before the user confirms. Does not increment times_used."""
    try:
        coupon = validate_coupon(db, body.code, plan_id=body.plan_id)
    except ValueError as e:
        raise HTTPException(400, str(e))

    plan = db.query(Plan).filter(Plan.id == coupon.plan_id).first()
    is_permanent = coupon.duration_days == -1
    if is_permanent:
        msg = "كوبون صالح — يفعّل الباقة بشكل دائم"
    else:
        msg = f"كوبون صالح — يفعّل الباقة لمدة {coupon.duration_days} يوم"
    return CouponValidationResponse(
        valid=True,
        code=coupon.code,
        plan_id=coupon.plan_id,
        plan_name=plan.name if plan else "",
        duration_days=coupon.duration_days,
        is_permanent=is_permanent,
        message=msg,
    )


@router.post("/cancel")
@limiter.limit("5/minute")
async def cancel_my_subscription(
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """User cancels their own active subscription. They immediately fall back
    to the free plan. (Coupon-granted subscriptions can be cancelled too — the
    coupon itself is already consumed and is not refunded.)"""
    affected = cancel_current_subscription(db, user.id)
    if affected == 0:
        raise HTTPException(404, "No active subscription to cancel")
    return {"message": "Subscription cancelled", "cancelled_count": affected}
