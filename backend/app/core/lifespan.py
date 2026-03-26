import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.core.config import executor, ADMIN_USERNAME, ADMIN_PASSWORD, ADMIN_EMAIL
from app.auth.password import hash_password
from app.db.database import create_tables, SessionLocal
from app.db.models import User, Plan
from app.services import whisper_service


def _seed_db():
    """Seed plans and admin user on first run."""
    db = SessionLocal()
    try:
        if not db.query(Plan).first():
            db.add_all([
                Plan(name="free", price=0, original_price=0, max_audio_seconds=30),
                Plan(name="monthly", price=27, original_price=27, max_audio_seconds=-1),
                Plan(name="annual", price=150, original_price=325, max_audio_seconds=-1),
            ])
            db.commit()
            print("Plans seeded.")

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
