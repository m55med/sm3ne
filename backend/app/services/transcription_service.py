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

All providers return the same Whisper-style dict that `text_analyzer.build_response`
consumes.
"""
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


_FALLBACK_ORDER = ("speechmatics", "gemini", "groq", "assemblyai", "whisper")

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
    """Pick the provider that will serve the next request.

    Plan-level pin wins; otherwise the global admin choice; otherwise the
    first available provider in the fallback chain.
    """
    chosen: str | None = None
    if plan and getattr(plan, "transcription_provider", None):
        chosen = plan.transcription_provider
    if not chosen:
        chosen = settings_service.get_transcription_provider(db)

    avail = provider_availability()
    if avail.get(chosen, False):
        return chosen
    for name in _FALLBACK_ORDER:
        if avail.get(name, False):
            return name
    return "whisper"


def resolve_model(db: Session, provider: str, plan: Plan | None = None) -> str | None:
    """Pick the specific sub-model within `provider`.

    Plan-level pin wins → otherwise the admin's per-provider choice → otherwise
    the service's built-in default.
    """
    if plan and getattr(plan, "transcription_model", None):
        return plan.transcription_model
    chosen = settings_service.get_provider_model(db, provider)
    return chosen or default_model(provider)


async def transcribe_from_path(
    db: Session,
    path: str,
    duration: float = 0.0,
    plan: Plan | None = None,
    provider: str | None = None,
    model: str | None = None,
) -> dict:
    """Dispatch a transcription using either an explicit provider/model pair
    or the plan/admin-derived defaults.

    F18: routes already call `resolve_provider` to stamp `provider_used` on the
    request row. They can now pass that same value back in here as `provider`
    so we don't re-resolve (and potentially get a different answer if the
    settings cache flipped between the two calls).
    """
    if provider is None:
        provider = resolve_provider(db, plan=plan)
    if model is None:
        model = resolve_model(db, provider, plan=plan)

    if provider == "speechmatics":
        return await speechmatics_service.transcribe_from_path(path, model=model)
    if provider == "gemini":
        return await gemini_service.transcribe_from_path(path, model=model, duration=duration)
    if provider == "groq":
        return await groq_service.transcribe_from_path(path, model=model)
    if provider == "assemblyai":
        return await assemblyai_service.transcribe_from_path(path, model=model)
    return await whisper_service.transcribe_from_path(path, model=model)


async def transcribe_with_provider(
    path: str, provider: str, model: str | None = None, duration: float = 0.0
) -> dict:
    """Bypass plan/setting resolution — used by the admin test endpoint to try
    a specific provider+model combination on a sample audio file.
    """
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
