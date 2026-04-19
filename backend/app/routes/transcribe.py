import os

from fastapi import APIRouter, Depends, Request, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.auth.deps import check_daily_quota, check_rpm_limit, get_user_or_api_key
from app.core.config import ALLOWED_EXTENSIONS, RATE_LIMIT, limiter
from app.db.database import get_db
from app.db.models import User, TranscriptionRequest
from app.services import whisper_service
from app.services.text_analyzer import build_response
from app.services.audio_utils import probe_duration, trim_audio
from app.services.subscription_service import get_user_plan

router = APIRouter()


@router.post("/transcribe")
@limiter.limit(RATE_LIMIT)  # baseline per-principal rate limit (bucket keyed by auth_principal)
async def transcribe(
    request: Request,
    file: UploadFile = File(...),
    user: User = Depends(get_user_or_api_key),
    db: Session = Depends(get_db),
):
    # Enforce per-key RPM override + daily quota before doing any I/O.
    check_rpm_limit(request, user, db)
    check_daily_quota(request, user, db)

    # Validate file type
    ext = os.path.splitext(file.filename or "")[1].lower()
    if not (file.content_type and file.content_type.startswith("audio")) and ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, "Unsupported file type. Send an audio file.")

    # Get user plan
    plan = getattr(request.state, "plan", None) or get_user_plan(db, user.id)
    max_seconds = plan.max_audio_seconds if plan else 30

    # Save and optionally trim
    import tempfile
    suffix = os.path.splitext(file.filename or ".wav")[1]
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    was_trimmed = False
    original_duration = probe_duration(tmp_path)
    trimmed_path = None

    try:
        if max_seconds > 0 and original_duration > max_seconds:
            trimmed_path = trim_audio(tmp_path, max_seconds)
            was_trimmed = True
            process_path = trimmed_path
        else:
            process_path = tmp_path

        result = await whisper_service.transcribe_from_path(process_path)
    except Exception as e:
        raise HTTPException(500, f"Transcription failed: {str(e)}")
    finally:
        os.unlink(tmp_path)
        if trimmed_path and os.path.exists(trimmed_path):
            os.unlink(trimmed_path)

    response_data = build_response(result)
    response_data["was_trimmed"] = was_trimmed

    # Log request (always — this is also the source of truth for daily quota)
    api_key = getattr(request.state, "api_key", None)
    req_log = TranscriptionRequest(
        user_id=user.id,
        api_key_id=api_key.id if api_key else None,
        filename=file.filename,
        duration_seconds=original_duration,
        processed_seconds=float(response_data.get("duration", 0)),
        language=str(response_data.get("lang", "")),
        word_count=int(response_data.get("word_count", 0)),
        was_trimmed=was_trimmed,
    )
    db.add(req_log)
    db.commit()

    response_data["request_id"] = req_log.id
    return JSONResponse(content=response_data)
