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
KEY_PROVIDER_ORDER = "transcription_provider_order"
VALID_PROVIDERS = ("whisper", "speechmatics", "gemini", "groq", "assemblyai")

# Default failover priority when the admin hasn't customized the order.
# whisper is last on purpose — it's the always-available local safety net.
DEFAULT_PROVIDER_ORDER = ("speechmatics", "gemini", "groq", "assemblyai", "whisper")

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


def get_provider_order(db: Session) -> list[str]:
    """Admin-configured failover priority. When a provider fails mid-request
    (credit exhausted, rate-limited, 5xx), the dispatcher walks this list to
    pick the next provider to try.

    Stored as a comma-separated string. Always returns every valid provider:
    any provider missing from the stored value is appended at the end so a
    newly-added provider is never silently unreachable.
    """
    raw = get_setting(db, KEY_PROVIDER_ORDER, default=None)
    if raw:
        order = [p.strip() for p in raw.split(",") if p.strip() in VALID_PROVIDERS]
    else:
        order = list(DEFAULT_PROVIDER_ORDER)
    # Append any valid provider not present (e.g. one added after the setting
    # was last saved) so the failover chain stays exhaustive.
    for p in VALID_PROVIDERS:
        if p not in order:
            order.append(p)
    return order


def set_provider_order(
    db: Session, order: list[str], user_id: int | None = None
) -> AppSetting:
    cleaned = [p for p in order if p in VALID_PROVIDERS]
    if not cleaned:
        raise ValueError("Provider order must contain at least one valid provider")
    # De-duplicate while preserving order.
    seen: set[str] = set()
    deduped = [p for p in cleaned if not (p in seen or seen.add(p))]
    return set_setting(db, KEY_PROVIDER_ORDER, ",".join(deduped), user_id=user_id)


# --- Ticket attachment limits (admin-tunable) -------------------------------
# Defaults are conservative: 5 MB max, JPEG/PNG/WebP/HEIC only. Admin can widen
# both from the dashboard without redeploying.
KEY_TICKET_ATTACH_MAX_BYTES = "ticket_attach_max_bytes"
KEY_TICKET_ATTACH_EXTS = "ticket_attach_allowed_extensions"

DEFAULT_TICKET_ATTACH_MAX_BYTES = 5 * 1024 * 1024  # 5 MB
DEFAULT_TICKET_ATTACH_EXTS = "jpg,jpeg,png,webp,heic"


def get_ticket_attach_max_bytes(db: Session) -> int:
    raw = get_setting(db, KEY_TICKET_ATTACH_MAX_BYTES, default=str(DEFAULT_TICKET_ATTACH_MAX_BYTES))
    try:
        v = int(raw)
        return v if v > 0 else DEFAULT_TICKET_ATTACH_MAX_BYTES
    except (TypeError, ValueError):
        return DEFAULT_TICKET_ATTACH_MAX_BYTES


def get_ticket_attach_allowed_extensions(db: Session) -> set[str]:
    raw = get_setting(db, KEY_TICKET_ATTACH_EXTS, default=DEFAULT_TICKET_ATTACH_EXTS)
    return {p.strip().lower().lstrip(".") for p in (raw or "").split(",") if p.strip()}


def set_ticket_attach_max_bytes(db: Session, value: int, user_id: int | None = None) -> AppSetting:
    if value <= 0 or value > 100 * 1024 * 1024:
        raise ValueError("max_bytes must be between 1 byte and 100 MB")
    return set_setting(db, KEY_TICKET_ATTACH_MAX_BYTES, str(value), user_id=user_id)


def set_ticket_attach_allowed_extensions(
    db: Session, exts: list[str], user_id: int | None = None
) -> AppSetting:
    cleaned = sorted({e.strip().lower().lstrip(".") for e in exts if e and e.strip()})
    if not cleaned:
        raise ValueError("At least one extension is required")
    # Hard cap on what we'll ever accept (defence-in-depth — admin can't allow
    # executables/scripts even by typo).
    SAFE = {"jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "bmp"}
    invalid = [e for e in cleaned if e not in SAFE]
    if invalid:
        raise ValueError(
            f"Refusing to allow non-image extensions: {invalid}. "
            f"Permitted: {sorted(SAFE)}"
        )
    return set_setting(db, KEY_TICKET_ATTACH_EXTS, ",".join(cleaned), user_id=user_id)
