from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session
from app.db.models import UserSubscription, Plan, Coupon


def get_active_subscription(db: Session, user_id: int) -> UserSubscription | None:
    return db.query(UserSubscription).filter(
        UserSubscription.user_id == user_id,
        UserSubscription.is_active == True,
    ).first()


def get_user_plan(db: Session, user_id: int) -> Plan:
    sub = get_active_subscription(db, user_id)
    if sub and sub.plan:
        # Check if expired
        if sub.expires_at and sub.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
            sub.is_active = False
            db.commit()
            return get_free_plan(db)
        return sub.plan
    return get_free_plan(db)


def get_free_plan(db: Session) -> Plan:
    return db.query(Plan).filter(Plan.name == "free").first()


def subscribe_user(db: Session, user_id: int, plan_id: int, coupon_code: str = None) -> UserSubscription:
    plan = db.query(Plan).filter(Plan.id == plan_id, Plan.is_active == True).first()
    if not plan:
        raise ValueError("Plan not found")

    coupon_id = None
    duration_days = 30 if plan.name == "monthly" else 365

    if coupon_code:
        coupon = validate_coupon(db, coupon_code)
        coupon_id = coupon.id
        duration_days = coupon.duration_days
        coupon.times_used += 1

    # Deactivate current subscription
    db.query(UserSubscription).filter(
        UserSubscription.user_id == user_id,
        UserSubscription.is_active == True,
    ).update({"is_active": False})

    now = datetime.now(timezone.utc)
    sub = UserSubscription(
        user_id=user_id,
        plan_id=plan_id,
        starts_at=now,
        expires_at=now + timedelta(days=duration_days) if plan.name != "free" else None,
        is_active=True,
        coupon_id=coupon_id,
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    return sub


def validate_coupon(db: Session, code: str) -> Coupon:
    coupon = db.query(Coupon).filter(
        Coupon.code == code,
        Coupon.is_active == True,
    ).first()

    if not coupon:
        raise ValueError("Invalid coupon code")

    if coupon.max_uses != -1 and coupon.times_used >= coupon.max_uses:
        raise ValueError("Coupon has been fully redeemed")

    if coupon.expires_at and coupon.expires_at < datetime.now(timezone.utc):
        raise ValueError("Coupon has expired")

    return coupon
