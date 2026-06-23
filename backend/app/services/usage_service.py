"""Per-provider usage stats for the admin dashboard.

Two data sources:
  1. **Local DB** — we always know how many requests/seconds *we* served via each
     provider, because every transcription writes `provider_used` on its row.
  2. **Remote** — for providers that expose a usage endpoint (currently
     Speechmatics) we additionally fetch authoritative numbers.

External-provider free-tier hints (Speechmatics/Gemini/...) are hard-coded
from each provider's public pricing page; they change slowly and don't need
to be queryable at runtime. They are informational text only — never enforced.

The *app's own* free-plan limits (max audio seconds, daily request limit,
etc.) ARE enforced — and they come from the `plans` table row where
`name = 'free'`. We cache that row for 30 seconds (`free_plan_snapshot`) so
the hot path stays cheap, while still picking up admin changes within seconds.
"""
import threading
import time
from datetime import datetime, timedelta, timezone

import httpx
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import (
    SPEECHMATICS_API_KEY,
    SPEECHMATICS_BASE_URL,
)
from app.db.models import Plan, TranscriptionRequest


# Hardcoded fallbacks used ONLY if no `free` row exists in the plans table.
_FREE_PLAN_FALLBACK = {
    "max_audio_seconds": 30,
    "daily_request_limit": 100,
    "monthly_request_limit": None,
    "rpm_default": 10,
}

_FREE_PLAN_CACHE_TTL = 30.0
_free_plan_cache_lock = threading.Lock()
_free_plan_cache: dict | None = None
_free_plan_cache_expires_at: float = 0.0


def free_plan_snapshot(db: Session) -> dict:
    """Return a small snapshot of the free-plan limits, cached for 30s.

    Falls back to `_FREE_PLAN_FALLBACK` if the row is missing. Returns a plain
    dict so callers don't have to worry about a stale ORM instance.
    """
    global _free_plan_cache, _free_plan_cache_expires_at
    now = time.monotonic()
    if _free_plan_cache is not None and now < _free_plan_cache_expires_at:
        return _free_plan_cache

    row = db.query(Plan).filter(Plan.name == "free").first()
    if row is None:
        snapshot = dict(_FREE_PLAN_FALLBACK)
    else:
        snapshot = {
            "max_audio_seconds": row.max_audio_seconds,
            "daily_request_limit": row.daily_request_limit,
            "monthly_request_limit": row.monthly_request_limit,
            "rpm_default": row.rpm_default,
        }

    with _free_plan_cache_lock:
        _free_plan_cache = snapshot
        _free_plan_cache_expires_at = now + _FREE_PLAN_CACHE_TTL
    return snapshot


def invalidate_free_plan_cache() -> None:
    global _free_plan_cache, _free_plan_cache_expires_at
    with _free_plan_cache_lock:
        _free_plan_cache = None
        _free_plan_cache_expires_at = 0.0


# Hard-coded free-tier hints. Shown as text in the dashboard — informational only.
FREE_TIER: dict[str, dict] = {
    "speechmatics": {
        "label": "Speechmatics Free Plan",
        "limit_text": "8 ساعات / شهر مجاناً (Batch ASR)",
        "billing_unit": "ثواني صوت",
        "has_remote_usage": True,
    },
    "gemini": {
        "label": "Gemini Free Tier",
        "limit_text": "500 طلب/يوم · 250K tokens/min (مجاناً للنماذج Flash)",
        "billing_unit": "tokens",
        "has_remote_usage": False,
    },
    "groq": {
        "label": "Groq Free Tier",
        "limit_text": "حصص يومية مجانية متغيرة (28800 ثانية/يوم لـ Whisper)",
        "billing_unit": "ثواني صوت",
        "has_remote_usage": False,
    },
    "assemblyai": {
        "label": "AssemblyAI Trial",
        "limit_text": "$50 رصيد مجاناً عند التسجيل (~135 ساعة)",
        "billing_unit": "ثواني صوت",
        "has_remote_usage": False,
    },
}


def _start_of_today_utc() -> datetime:
    return datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)


def _start_of_month_utc() -> datetime:
    now = datetime.now(timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def local_usage(db: Session, provider: str) -> dict:
    """Aggregate our own DB rows for one provider."""
    today = _start_of_today_utc()
    month = _start_of_month_utc()

    base = db.query(TranscriptionRequest).filter(
        TranscriptionRequest.provider_used == provider,
        TranscriptionRequest.status == "completed",
    )

    requests_today = base.filter(TranscriptionRequest.created_at >= today).count()
    requests_month = base.filter(TranscriptionRequest.created_at >= month).count()
    requests_total = base.count()

    seconds_today = float(
        base.filter(TranscriptionRequest.created_at >= today)
            .with_entities(func.coalesce(func.sum(TranscriptionRequest.processed_seconds), 0))
            .scalar() or 0
    )
    seconds_month = float(
        base.filter(TranscriptionRequest.created_at >= month)
            .with_entities(func.coalesce(func.sum(TranscriptionRequest.processed_seconds), 0))
            .scalar() or 0
    )
    seconds_total = float(
        base.with_entities(func.coalesce(func.sum(TranscriptionRequest.processed_seconds), 0))
            .scalar() or 0
    )

    return {
        "requests_today": requests_today,
        "requests_month": requests_month,
        "requests_total": requests_total,
        "seconds_today": round(seconds_today, 2),
        "seconds_month": round(seconds_month, 2),
        "seconds_total": round(seconds_total, 2),
    }


async def speechmatics_remote_usage() -> dict | None:
    """Fetch authoritative usage from Speechmatics' /usage endpoint.
    Returns None when not configured or the endpoint fails (we degrade
    gracefully — the local numbers still show)."""
    if not SPEECHMATICS_API_KEY:
        return None
    today = datetime.now(timezone.utc).date()
    since = today.replace(day=1).isoformat()
    until = today.isoformat()
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            r = await client.get(
                f"{SPEECHMATICS_BASE_URL}/usage",
                headers={"Authorization": f"Bearer {SPEECHMATICS_API_KEY}"},
                params={"since": since, "until": until},
            )
        if r.status_code != 200:
            return None
        data = r.json()
    except Exception:
        return None

    # Response shape: {"since": "...", "until": "...", "summary": [{"total_hrs": X, "type": "transcription", "operating_point": "enhanced"}, ...]}
    total_hours = 0.0
    summary = data.get("summary") or data.get("details") or []
    for entry in summary:
        # Different SDKs key this differently — try the common ones.
        hrs = entry.get("total_hrs") or entry.get("hours") or entry.get("duration_hrs") or 0
        total_hours += float(hrs)

    return {
        "period": f"{since} → {until}",
        "total_hours_month": round(total_hours, 2),
        "raw": data,  # keep for transparency; UI can ignore
    }


async def build_provider_usage(db: Session, provider: str) -> dict:
    info = FREE_TIER.get(provider, {})
    payload = {
        "provider": provider,
        "free_tier_label": info.get("label"),
        "free_tier_limit_text": info.get("limit_text"),
        "billing_unit": info.get("billing_unit"),
        "local": local_usage(db, provider),
        "remote": None,
    }
    if provider == "speechmatics":
        payload["remote"] = await speechmatics_remote_usage()
    return payload


async def build_all_usage(db: Session, providers: list[str]) -> list[dict]:
    return [await build_provider_usage(db, p) for p in providers]
