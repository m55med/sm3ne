"""Runtime app settings backed by the `app_settings` table.

Settings are read frequently (every transcription request) so values are kept
in an in-process cache and the DB is hit only on miss or after `set_setting`.
The cache is intentionally simple — there's no cross-process invalidation,
which is fine because a settings change is rare and a single backend process
serves traffic; multi-process setups can restart workers after a change.
"""
import threading

from sqlalchemy.orm import Session

from app.core.config import TRANSCRIPTION_PROVIDER as ENV_DEFAULT_PROVIDER
from app.db.models import AppSetting


KEY_TRANSCRIPTION_PROVIDER = "transcription_provider"
VALID_PROVIDERS = ("whisper", "speechmatics")

_cache: dict[str, str] = {}
_lock = threading.Lock()


def get_setting(db: Session, key: str, default: str | None = None) -> str | None:
    if key in _cache:
        return _cache[key]
    row = db.query(AppSetting).filter(AppSetting.key == key).first()
    value = row.value if row else default
    if value is not None:
        with _lock:
            _cache[key] = value
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
    with _lock:
        _cache[key] = value
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
