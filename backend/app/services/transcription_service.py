"""Provider-agnostic transcription dispatcher.

Provider selection has three layers (each falls back to the next):

1. **Plan override** — every plan (free / monthly / annual) can pin its own
   provider+model via `plans.transcription_provider` / `transcription_model`.
   This means premium tiers can use Speechmatics while free users go to Groq,
   for example.

2. **Global admin choice** — `app_settings.transcription_provider` (default
   when a plan doesn't override) and `app_settings.transcription_model:<provider>`
   (selected sub-model per provider).

3. **Availability fallback** — if the chosen provider isn't configured at all
   (missing key), we fall through to the next available provider so end-users
   never see a 500 from a misconfigured toggle.

**Auto-failover (runtime):** `transcribe_from_path` doesn't just pick one
provider — it builds a *chain* (the resolved provider first, then the
admin-configured priority order) and walks it. If a provider fails at request
time (credit exhausted, 429, 5xx, timeout, ...) the dispatcher transparently
moves to the next one. The request only fails if EVERY provider in the chain
fails. The function returns `(result, provider_actually_used)` so the caller
can record which provider really served the request.

All providers return the same Whisper-style dict that `text_analyzer.build_response`
consumes.
"""
import logging

from sqlalchemy.orm import Session

from app.db.models import Plan
from app.services import (
    assemblyai_service,
    gemini_service,
    groq_service,
    settings_service,
    speechmatics_service,
    whisper_service,
)

logger = logging.getLogger(__name__)

_SERVICE_BY_NAME = {
    "whisper": whisper_service,
    "speechmatics": speechmatics_service,
    "gemini": gemini_service,
    "groq": groq_service,
    "assemblyai": assemblyai_service,
}


def provider_availability() -> dict[str, bool]:
    """Snapshot of which providers can actually serve right now."""
    return {name: svc.is_configured() for name, svc in _SERVICE_BY_NAME.items()}


def available_models(provider: str) -> list[dict]:
    """All models offered by `provider` for the admin UI dropdown."""
    svc = _SERVICE_BY_NAME.get(provider)
    return list(getattr(svc, "AVAILABLE_MODELS", []) or []) if svc else []


def default_model(provider: str) -> str | None:
    svc = _SERVICE_BY_NAME.get(provider)
    fn = getattr(svc, "default_model", None) if svc else None
    return fn() if fn else None


def resolve_provider(db: Session, plan: Plan | None = None) -> str:
    """Pick the *primary* provider for the next request (before failover).

    Plan-level pin wins; otherwise the global admin choice; otherwise the
    first available provider in the configured priority order.
    """
    chosen: str | None = None
    if plan and getattr(plan, "transcription_provider", None):
        chosen = plan.transcription_provider
    if not chosen:
        chosen = settings_service.get_transcription_provider(db)

    avail = provider_availability()
    if avail.get(chosen, False):
        return chosen
    for name in settings_service.get_provider_order(db):
        if avail.get(name, False):
            return name
    return "whisper"


def resolve_model(db: Session, provider: str, plan: Plan | None = None) -> str | None:
    """Pick the specific sub-model within `provider`.

    Plan-level pin wins — but ONLY for the plan's pinned provider (a model id
    is provider-specific; applying a Speechmatics operating-point to Groq would
    be nonsense). Otherwise the admin's per-provider choice, else the service
    default.
    """
    if (
        plan
        and getattr(plan, "transcription_model", None)
        and getattr(plan, "transcription_provider", None) == provider
    ):
        return plan.transcription_model
    chosen = settings_service.get_provider_model(db, provider)
    return chosen or default_model(provider)


async def _call_provider(
    provider: str, path: str, model: str | None, duration: float
) -> dict:
    """Single-provider call. Raises the provider's own error on failure."""
    if provider == "speechmatics":
        return await speechmatics_service.transcribe_from_path(path, model=model)
    if provider == "gemini":
        return await gemini_service.transcribe_from_path(path, model=model, duration=duration)
    if provider == "groq":
        return await groq_service.transcribe_from_path(path, model=model)
    if provider == "assemblyai":
        return await assemblyai_service.transcribe_from_path(path, model=model)
    if provider == "whisper":
        return await whisper_service.transcribe_from_path(path, model=model)
    raise ValueError(f"Unknown provider '{provider}'")


def _failover_chain(db: Session, primary: str) -> list[str]:
    """Ordered list of providers to try: the primary first, then the
    admin-configured priority order, keeping only configured providers."""
    avail = provider_availability()
    order = settings_service.get_provider_order(db)
    chain: list[str] = []
    for p in [primary, *order]:
        if p not in chain and avail.get(p, False):
            chain.append(p)
    # whisper is the always-available local safety net.
    if not chain or "whisper" not in chain:
        chain.append("whisper")
    return chain


async def transcribe_from_path(
    db: Session,
    path: str,
    duration: float = 0.0,
    plan: Plan | None = None,
    provider: str | None = None,
    model: str | None = None,
) -> tuple[dict, str, str | None]:
    """Dispatch a transcription with automatic failover.

    Builds a chain (resolved/primary provider first, then the admin-configured
    priority order) and tries each in turn. A provider failure (credit
    exhausted, 429, 5xx, timeout, ...) transparently cascades to the next one.
    Only raises if EVERY provider in the chain fails.

    Returns ``(result_dict, provider_actually_used, model_actually_used)`` — the
    caller stamps the real provider+model on the request row so the usage
    dashboard stays accurate even when a failover happened.
    """
    primary = provider or resolve_provider(db, plan=plan)
    chain = _failover_chain(db, primary)

    last_error: Exception | None = None
    for p in chain:
        # The model pin applies only to the primary provider; fallback providers
        # use their own resolved/default model.
        p_model = model if (p == primary and model is not None) else resolve_model(db, p, plan=plan)
        try:
            result = await _call_provider(p, path, p_model, duration)
            if p != primary:
                logger.warning(
                    "transcription failover: %s failed, served by %s instead",
                    primary, p,
                )
            return result, p, p_model
        except Exception as e:  # noqa: BLE001
            last_error = e
            logger.warning("transcription provider '%s' failed: %s", p, e)
            continue

    raise last_error or RuntimeError("All transcription providers failed")


async def transcribe_with_provider(
    path: str, provider: str, model: str | None = None, duration: float = 0.0
) -> dict:
    """Bypass plan/setting resolution AND failover — used by the admin test
    endpoint to try one specific provider+model combination."""
    return await _call_provider(provider, path, model, duration)
