import secrets
import string
import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text

from app.core.config import executor, ADMIN_USERNAME, ADMIN_PASSWORD, ADMIN_EMAIL
from app.auth.password import hash_password
from app.db.database import create_tables, SessionLocal
from app.db.models import User, Plan
from app.services import whisper_service


_PUBLIC_ID_ALPHABET = string.ascii_letters + string.digits


def generate_public_id() -> str:
    """Short URL-safe opaque id (~60 bits)."""
    return "".join(secrets.choice(_PUBLIC_ID_ALPHABET) for _ in range(10))


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
        "ALTER TABLE plans ADD COLUMN IF NOT EXISTS monthly_request_limit INTEGER",
        "ALTER TABLE plans ADD COLUMN IF NOT EXISTS api_daily_request_limit INTEGER DEFAULT -1",
        "ALTER TABLE plans ADD COLUMN IF NOT EXISTS description VARCHAR(500)",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS public_id VARCHAR(12)",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_public_id ON users(public_id)",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS plan_name_at_request VARCHAR(50)",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS plan_source_at_request VARCHAR(20)",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS daily_limit_at_request INTEGER",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS monthly_limit_at_request INTEGER",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS daily_used_at_request INTEGER",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS api_key_id INTEGER REFERENCES api_keys(id)",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'upload'",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS is_live_recording BOOLEAN DEFAULT FALSE",
        "CREATE INDEX IF NOT EXISTS idx_requests_source ON transcription_requests(source)",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'completed'",
        "ALTER TABLE transcription_requests ADD COLUMN IF NOT EXISTS error_message VARCHAR(500)",
        "CREATE INDEX IF NOT EXISTS idx_requests_apikey_created ON transcription_requests(api_key_id, created_at)",
        "CREATE INDEX IF NOT EXISTS idx_requests_status ON transcription_requests(status)",
        """CREATE TABLE IF NOT EXISTS login_events (
            id SERIAL PRIMARY KEY,
            user_id INTEGER REFERENCES users(id),
            username_attempted VARCHAR(100),
            auth_provider VARCHAR(20) NOT NULL DEFAULT 'local',
            event_type VARCHAR(20) NOT NULL DEFAULT 'login',
            success BOOLEAN DEFAULT TRUE,
            error_message VARCHAR(255),
            ip_address VARCHAR(64),
            user_agent VARCHAR(500),
            device_platform VARCHAR(32),
            device_model VARCHAR(128),
            device_os_version VARCHAR(64),
            app_version VARCHAR(32),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )""",
        "CREATE INDEX IF NOT EXISTS idx_login_events_user_ts ON login_events(user_id, created_at)",
        "CREATE INDEX IF NOT EXISTS idx_login_events_success ON login_events(success)",
        "CREATE INDEX IF NOT EXISTS idx_login_events_ip ON login_events(ip_address)",
        "CREATE INDEX IF NOT EXISTS idx_login_events_created ON login_events(created_at)",
        """CREATE TABLE IF NOT EXISTS support_tickets (
            id SERIAL PRIMARY KEY,
            public_id VARCHAR(12) UNIQUE,
            user_id INTEGER NOT NULL REFERENCES users(id),
            ticket_type VARCHAR(20) NOT NULL DEFAULT 'contact',
            subject VARCHAR(200) NOT NULL,
            message TEXT NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'open',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_reply_at TIMESTAMP
        )""",
        "CREATE INDEX IF NOT EXISTS idx_tickets_user_created ON support_tickets(user_id, created_at)",
        "CREATE INDEX IF NOT EXISTS idx_tickets_status_created ON support_tickets(status, created_at)",
        """CREATE TABLE IF NOT EXISTS ticket_replies (
            id SERIAL PRIMARY KEY,
            public_id VARCHAR(12) UNIQUE,
            ticket_id INTEGER NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
            user_id INTEGER NOT NULL REFERENCES users(id),
            is_admin BOOLEAN DEFAULT FALSE,
            message TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )""",
        "CREATE INDEX IF NOT EXISTS idx_ticket_replies_ticket_created ON ticket_replies(ticket_id, created_at)",
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


def _backfill_user_public_ids(db):
    """Assign a public_id to any user that doesn't have one. Runs every startup
    but is cheap once all users have IDs."""
    rows = db.execute(text("SELECT id FROM users WHERE public_id IS NULL")).fetchall()
    if not rows:
        return
    for (uid,) in rows:
        for _ in range(5):
            pid = generate_public_id()
            try:
                db.execute(text("UPDATE users SET public_id = :pid WHERE id = :id"),
                           {"pid": pid, "id": uid})
                db.commit()
                break
            except Exception:
                db.rollback()
    print(f"Backfilled public_id for {len(rows)} user(s).")


def _backfill_request_plan_snapshots(db):
    """Fill snapshot columns on historical transcription_requests rows with a
    best-effort value: the user's *current* effective plan (or free plan's
    limits for users with no active subscription). True history is lost for
    rows that predate the column but going forward every new request writes
    its own snapshot at creation time. Guarded by WHERE IS NULL so safe to
    run every startup."""
    rows = db.execute(text("""
        WITH free_plan AS (
          SELECT daily_request_limit AS dl, monthly_request_limit AS ml
          FROM plans WHERE name = 'free' LIMIT 1
        )
        SELECT tr.id, tr.user_id, tr.created_at,
               COALESCE(p.name, 'free') AS plan_name,
               COALESCE(p.daily_request_limit, (SELECT dl FROM free_plan)) AS daily_request_limit,
               COALESCE(p.monthly_request_limit, (SELECT ml FROM free_plan)) AS monthly_request_limit,
               CASE
                 WHEN us.coupon_id IS NOT NULL THEN 'coupon'
                 WHEN p.name IS NULL OR p.name = 'free' THEN 'free'
                 ELSE 'purchase'
               END AS plan_source
        FROM transcription_requests tr
        LEFT JOIN user_subscriptions us
          ON us.user_id = tr.user_id AND us.is_active = TRUE
        LEFT JOIN plans p ON p.id = us.plan_id
        WHERE tr.plan_name_at_request IS NULL
    """)).fetchall()
    if not rows:
        return
    for r in rows:
        db.execute(text("""
            UPDATE transcription_requests
            SET plan_name_at_request = :name,
                plan_source_at_request = :source,
                daily_limit_at_request = :dl,
                monthly_limit_at_request = :ml
            WHERE id = :id
        """), {
            "id": r.id,
            "name": r.plan_name,
            "source": r.plan_source,
            "dl": r.daily_request_limit,
            "ml": r.monthly_request_limit,
        })
    db.commit()
    print(f"Backfilled plan snapshots for {len(rows)} request(s).")


def _seed_db():
    """Seed plans and admin user on first run."""
    db = SessionLocal()
    try:
        _run_idempotent_ddl(db)
        _backfill_user_public_ids(db)
        _backfill_request_plan_snapshots(db)

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
