import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text

from app.core.config import executor, ADMIN_USERNAME, ADMIN_PASSWORD, ADMIN_EMAIL
from app.auth.password import hash_password
from app.db.database import create_tables, SessionLocal
from app.db.models import User, Plan
from app.services import whisper_service


PLAN_DEFAULTS = {
    "free":    {"daily_request_limit": 20,   "rpm_default": 5,  "api_keys_allowed": 1},
    "monthly": {"daily_request_limit": 500,  "rpm_default": 20, "api_keys_allowed": 3},
    "annual":  {"daily_request_limit": 2000, "rpm_default": 30, "api_keys_allowed": 5},
}


def _run_idempotent_ddl(db):
    """Add columns/indexes introduced after initial deployment.
    All statements use IF NOT EXISTS so repeated startups are safe.
    """
    statements = [
        "ALTER TABLE plans ADD COLUMN IF NOT EXISTS daily_request_limit INTEGER DEFAULT 100",
        "ALTER TABLE plans ADD COLUMN IF NOT EXISTS rpm_default INTEGER DEFAULT 10",
        "ALTER TABLE plans ADD COLUMN IF NOT EXISTS api_keys_allowed INTEGER DEFAULT 1",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS api_key_id INTEGER REFERENCES api_keys(id)",
        "CREATE INDEX IF NOT EXISTS idx_requests_apikey_created ON transcription_requests(api_key_id, created_at)",
    ]
    for sql in statements:
        db.execute(text(sql))
    db.commit()


def _backfill_plan_limits(db):
    """Align existing plans with the intended per-tier defaults.

    The ALTER TABLE DEFAULT fills new columns on existing rows with a
    generic value (100/10/1). This function replaces those generic values
    with the tier-specific ones (free=20/5/1, monthly=500/20/3, annual=2000/30/5).
    We only overwrite when the current value still matches the generic default,
    so any admin-tuned values are preserved.
    """
    GENERIC = {"daily_request_limit": 100, "rpm_default": 10, "api_keys_allowed": 1}
    plans = db.query(Plan).all()
    touched = False
    for plan in plans:
        defaults = PLAN_DEFAULTS.get(plan.name)
        if not defaults:
            continue
        for field, intended in defaults.items():
            current = getattr(plan, field)
            if current is None or current == GENERIC[field]:
                if current != intended:
                    setattr(plan, field, intended)
                    touched = True
    if touched:
        db.commit()
        print("Plan defaults backfilled for API-key limits.")


def _seed_db():
    """Seed plans and admin user on first run."""
    db = SessionLocal()
    try:
        _run_idempotent_ddl(db)

        if not db.query(Plan).first():
            db.add_all([
                Plan(name="free",    price=0,   original_price=0,   max_audio_seconds=30,
                     daily_request_limit=20,   rpm_default=5,  api_keys_allowed=1),
                Plan(name="monthly", price=27,  original_price=27,  max_audio_seconds=-1,
                     daily_request_limit=500,  rpm_default=20, api_keys_allowed=3),
                Plan(name="annual",  price=150, original_price=325, max_audio_seconds=-1,
                     daily_request_limit=2000, rpm_default=30, api_keys_allowed=5),
            ])
            db.commit()
            print("Plans seeded.")
        else:
            _backfill_plan_limits(db)

        if not db.query(User).filter(User.role == "admin").first():
            admin = User(
                username=ADMIN_USERNAME,
                email=ADMIN_EMAIL,
                password_hash=hash_password(ADMIN_PASSWORD),
                role="admin",
                full_name="Admin",
                auth_provider="local",
            )
            db.add(admin)
            db.commit()
            print(f"Admin user '{ADMIN_USERNAME}' created.")
    finally:
        db.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_tables()
    _seed_db()
    threading.Thread(target=whisper_service._ensure_model, daemon=True).start()
    yield
    executor.shutdown(wait=False)
