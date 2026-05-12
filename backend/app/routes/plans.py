from typing import List

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.core.config import limiter
from app.db.database import get_db
from app.db.models import Plan, User
from app.auth.jwt import get_current_user
from app.schemas.plans import (
    CouponApplyRequest, PlanResponse, SubscribeRequest, SubscriptionResponse,
)
from app.services.subscription_service import (
    get_active_subscription, get_user_plan, subscribe_user, validate_coupon,
)

router = APIRouter(prefix="/plans", tags=["plans"])


@router.get("", response_model=List[PlanResponse])
async def list_plans(db: Session = Depends(get_db)):
    plans = db.query(Plan).filter(Plan.is_active == True).all()
    return plans


@router.get("/my")
async def my_subscription(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    plan = get_user_plan(db, user.id)
    sub = get_active_subscription(db, user.id)
    return {
        "plan": PlanResponse.model_validate(plan) if plan else None,
        "subscription": SubscriptionResponse.model_validate(sub) if sub else None,
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
