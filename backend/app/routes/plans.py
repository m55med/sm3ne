from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import User, Plan
from app.auth.jwt import get_current_user
from app.schemas.plans import PlanResponse, SubscriptionResponse, SubscribeRequest, CouponApplyRequest
from app.services.subscription_service import get_user_plan, get_active_subscription, subscribe_user, validate_coupon

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


@router.post("/subscribe")
async def subscribe(
    body: SubscribeRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        sub = subscribe_user(db, user.id, body.plan_id, body.coupon_code)
    except ValueError as e:
        raise HTTPException(400, str(e))

    return {"message": "Subscribed successfully", "subscription_id": sub.id}


@router.post("/coupon")
async def apply_coupon(
    body: CouponApplyRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        coupon = validate_coupon(db, body.code)
    except ValueError as e:
        raise HTTPException(400, str(e))

    sub = subscribe_user(db, user.id, coupon.plan_id, body.code)
    return {"message": "Coupon applied successfully", "subscription_id": sub.id}
