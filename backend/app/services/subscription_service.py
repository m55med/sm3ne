"""Subscription and coupon helpers.

Coupon handling uses an atomic `UPDATE ... RETURNING` so two concurrent
redemptions of the same single-use coupon cannot both succeed (closes the
classic read-modify-write race).
"""
from datetime import datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.models import UserSubscription, Plan, Coupon


def get_active_subscription(db: Session, user_id: int) -> UserSubscription | None:
    return db.query(UserSubscription).filter(
        UserSubscription.user_id == user_id,
        UserSubscription.is_active == True,  # noqa: E712
    ).first()


# F16: thin wrapper for callers that want "current sub" semantics without
# repeating the query everywhere.
def current_subscription(db: Session, user_id: int) -> UserSubscription | None:
    return get_active_subscription(db, user_id)


def get_user_plan(db: Session, user_id: int) -> Plan:
    sub = get_active_subscription(db, user_id)
    if sub and sub.plan:
        # Check if expired (DB column is timezone-aware now; defensive replace for legacy rows).
        expires_at = sub.expires_at
        if expires_at is not None and expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if expires_at and expires_at < datetime.now(timezone.utc):
            sub.is_active = False
            db.commit()
            return get_free_plan(db)
        return sub.plan
    return get_free_plan(db)


def get_free_plan(db: Session) -> Plan:
    return db.query(Plan).filter(Plan.name == "free").first()


# F16: explicit helper used by admin routes to cancel a user's active sub.
def cancel_current_subscription(db: Session, user_id: int) -> int:
    """Mark all active subscriptions for the user as is_active=False. Returns
    the number of rows updated. Commits inline."""
    affected = db.query(UserSubscription).filter(
        UserSubscription.user_id == user_id,
        UserSubscription.is_active == True,  # noqa: E712
    ).update({"is_active": False})
    db.commit()
    return affected


def _normalize_code(code: str) -> str:
    return (code or "").strip().upper()


def validate_coupon(db: Session, code: str, plan_id: int | None = None) -> Coupon:
    """Read-only coupon validation used by the `/plans/coupon` validate endpoint
    and as a pre-check in the admin gift-subscription flow.

    Does NOT increment times_used — use `validate_and_consume_coupon` when you
    actually want to redeem.
    """
    norm = _normalize_code(code)
    if not norm:
        raise ValueError("Coupon code is required")

    coupon = db.query(Coupon).filter(Coupon.code == norm).first()
    if not coupon:
        raise ValueError("Coupon not found")
    if not coupon.is_active:
        raise ValueError("Coupon is inactive")
    if plan_id is not None and coupon.plan_id != plan_id:
        raise ValueError("Coupon is not valid for this plan")
    if coupon.max_uses != -1 and coupon.times_used >= coupon.max_uses:
        raise ValueError("Coupon has reached its maximum uses")

    expires_at = coupon.expires_at
    if expires_at is not None and expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at and expires_at < datetime.now(timezone.utc):
        raise ValueError("Coupon has expired")

    # F2: also reject coupons whose plan is not active anymore.
    plan = db.query(Plan).filter(Plan.id == coupon.plan_id).first()
    if not plan or not plan.is_active:
        raise ValueError("Plan is not active")

    return coupon


def validate_and_consume_coupon(db: Session, code: str, plan_id: int) -> Coupon:
    """Atomically validate and increment times_used.

    Uses a single UPDATE ... RETURNING so two concurrent redemptions of the same
    single-use coupon can't both succeed. On failure to update, we issue a small
    follow-up SELECT to produce a precise error message ("expired" vs "wrong plan"
    vs "exhausted").
    """
    norm = _normalize_code(code)
    if not norm:
        raise ValueError("Coupon code is required")

    # F2: also require the linked plan to be active. We enforce it via the WHERE
    # clause through a join-like subquery on plans.is_active so the atomicity is
    # preserved.
    result = db.execute(
        text(
            """
            UPDATE coupons
               SET times_used = times_used + 1
             WHERE code = :code
               AND is_active = TRUE
               AND plan_id = :plan_id
               AND (expires_at IS NULL OR expires_at > NOW())
               AND (max_uses = -1 OR times_used < max_uses)
               AND EXISTS (
                       SELECT 1 FROM plans
                        WHERE plans.id = coupons.plan_id
                          AND plans.is_active = TRUE
                   )
         RETURNING id
            """
        ),
        {"code": norm, "plan_id": plan_id},
    ).fetchone()

    if not result:
        # Distinguish "not found" vs "exhausted" vs "wrong plan" by a follow-up read.
        existing = db.query(Coupon).filter(Coupon.code == norm).first()
        if not existing:
            raise ValueError("Coupon not found")
        if not existing.is_active:
            raise ValueError("Coupon is inactive")
        if existing.plan_id != plan_id:
            raise ValueError("Coupon is not valid for this plan")
        expires_at = existing.expires_at
        if expires_at is not None and expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if expires_at and expires_at < datetime.now(timezone.utc):
            raise ValueError("Coupon has expired")
        # If the linked plan is inactive, surface that.
        plan = db.query(Plan).filter(Plan.id == existing.plan_id).first()
        if not plan or not plan.is_active:
            raise ValueError("Plan is not active")
        raise ValueError("Coupon has reached its maximum uses")

    db.commit()
    # Return the freshly-mutated ORM row so callers can read times_used / duration_days.
    coupon = db.query(Coupon).filter(Coupon.id == result[0]).first()
    return coupon


def subscribe_user(
    db: Session, user_id: int, plan_id: int, coupon_code: str | None = None
) -> UserSubscription:
    plan = db.query(Plan).filter(Plan.id == plan_id, Plan.is_active == True).first()  # noqa: E712
    if not plan:
        raise ValueError("Plan not found")

    coupon_id: int | None = None
    duration_days = 30 if plan.name == "monthly" else 365

    if coupon_code:
        # Atomic consume — never double-spends a single-use coupon under load.
        coupon = validate_and_consume_coupon(db, coupon_code, plan_id)
        coupon_id = coupon.id
        duration_days = coupon.duration_days

    # Deactivate current subscription
    db.query(UserSubscription).filter(
        UserSubscription.user_id == user_id,
        UserSubscription.is_active == True,  # noqa: E712
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
