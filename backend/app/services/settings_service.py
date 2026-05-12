"""Runtime app settings backed by the `app_settings` table.

Settings are read on the hot path (every transcription request), so values are
cached in-process with a short TTL. The TTL means that in multi-worker setups
the *other* workers will eventually pick up the new value within a few seconds
even though there's no cross-process invalidation channel.

A direct call to `set_setting` invalidates only the local worker's entry; remote
workers expire it through TTL.
"""
import threading
import time

from sqlalchemy.orm import Session

from app.core.config import TRANSCRIPTION_PROVIDER as ENV_DEFAULT_PROVIDER
from app.db.models import AppSetting


KEY_TRANSCRIPTION_PROVIDER = "transcription_provider"
VALID_PROVIDERS = ("whisper", "speechmatics", "gemini", "groq", "assemblyai")

# Cache entries expire after this many seconds. Short enough that multi-worker
# setups feel near-real-time after an admin change; long enough that the hot
# path basically never hits the DB.
_CACHE_TTL_SECONDS = 30.0


def _model_key(provider: str) -> str:
    return f"transcription_model:{provider}"


# value: dict[str, tuple[value, expires_at_monotonic]]
_cache: dict[str, tuple[str, float]] = {}
_lock = threading.Lock()


def _cache_get(key: str) -> str | None:
    entry = _cache.get(key)
    if entry is None:
        return None
    value, expires_at = entry
    if time.monotonic() >= expires_at:
        # Lazy eviction — safe since reading a stale dict tuple is harmless.
        with _lock:
            cur = _cache.get(key)
            if cur is not None and cur[1] <= time.monotonic():
                _cache.pop(key, None)
        return None
    return value


def _cache_set(key: str, value: str) -> None:
    with _lock:
        _cache[key] = (value, time.monotonic() + _CACHE_TTL_SECONDS)


def get_setting(db: Session, key: str, default: str | None = None) -> str | None:
    cached = _cache_get(key)
    if cached is not None:
        return cached
    row = db.query(AppSetting).filter(AppSetting.key == key).first()
    value = row.value if row else default
    if value is not None:
        _cache_set(key, value)
    return value


def set_setting(db: Session, key: str, value: str, user_id: int | None = None) -> AppSetting:
    row = db.query(AppSetting).filter(AppSetting.key == key).first()
    if row is None:
        row = AppSetting(key=key, value=value, updated_by_user_id=user_id)
        db.add(row)
    else:
        row.value = value
        row.updated_by_user_id = user_id
    db.commit()
    db.refresh(row)
    _cache_set(key, value)
    return row


def invalidate_cache(key: str | None = None):
    with _lock:
        if key is None:
            _cache.clear()
        else:
            _cache.pop(key, None)


def get_transcription_provider(db: Session) -> str:
    """Resolve the active provider with cache → DB → env-default fallback."""
    value = get_setting(db, KEY_TRANSCRIPTION_PROVIDER, default=ENV_DEFAULT_PROVIDER)
    if value not in VALID_PROVIDERS:
        return ENV_DEFAULT_PROVIDER
    return value


def set_transcription_provider(db: Session, value: str, user_id: int | None = None) -> AppSetting:
    if value not in VALID_PROVIDERS:
        raise ValueError(f"Invalid provider '{value}'. Must be one of {VALID_PROVIDERS}")
    return set_setting(db, KEY_TRANSCRIPTION_PROVIDER, value, user_id=user_id)


def seed_default_transcription_provider(db: Session):
    """Seed the setting on first startup with the env-derived default.
    No-op if a row already exists, so admin choices survive restarts.
    """
    row = db.query(AppSetting).filter(AppSetting.key == KEY_TRANSCRIPTION_PROVIDER).first()
    if row is None:
        db.add(AppSetting(key=KEY_TRANSCRIPTION_PROVIDER, value=ENV_DEFAULT_PROVIDER))
        db.commit()


def get_provider_model(db: Session, provider: str) -> str | None:
    """Admin's chosen model for a given provider, or None to mean
    'use the service's default'."""
    if provider not in VALID_PROVIDERS:
        return None
    return get_setting(db, _model_key(provider), default=None)


def set_provider_model(
    db: Session, provider: str, model: str, user_id: int | None = None
) -> AppSetting:
    if provider not in VALID_PROVIDERS:
        raise ValueError(f"Invalid provider '{provider}'")
    return set_setting(db, _model_key(provider), model, user_id=user_id)
