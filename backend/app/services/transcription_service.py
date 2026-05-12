"""Provider-agnostic transcription dispatcher.

Routes the request to whichever provider is currently selected in
`app_settings.transcription_provider` (managed via the admin dashboard).
Both providers return the same Whisper-style dict that
`text_analyzer.build_response` consumes.

If the configured provider can't actually serve (e.g. speechmatics chosen but
the SP token is missing), the dispatcher falls back to the other provider so
end-users never see a 500 from a misconfigured toggle.
"""
from sqlalchemy.orm import Session

from app.services import settings_service, speechmatics_service, whisper_service


def resolve_provider(db: Session) -> str:
    """Return the provider that will actually be used for the next request."""
    chosen = settings_service.get_transcription_provider(db)
    if chosen == "speechmatics" and not speechmatics_service.is_configured():
        return "whisper"
    return chosen


async def transcribe_from_path(db: Session, path: str) -> dict:
    provider = resolve_provider(db)
    if provider == "speechmatics":
        return await speechmatics_service.transcribe_from_path(path)
    return await whisper_service.transcribe_from_path(path)


def provider_availability() -> dict[str, bool]:
    """Snapshot of which providers can serve right now (used by admin UI)."""
    return {
        "whisper": True,  # local model always 'available' (lazy-loaded on first call)
        "speechmatics": speechmatics_service.is_configured(),
    }
