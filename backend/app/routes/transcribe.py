import os

from fastapi import APIRouter, Depends, Form, Request, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from datetime import datetime, timezone

from sqlalchemy import func

from app.auth.deps import check_daily_quota, check_rpm_limit, get_user_or_api_key
from app.core.config import ALLOWED_EXTENSIONS, RATE_LIMIT, limiter
from app.db.database import get_db
from app.db.models import User, TranscriptionRequest, UserSubscription
from app.services import whisper_service
from app.services.text_analyzer import build_response
from app.services.audio_utils import probe_duration, trim_audio
from app.services.subscription_service import get_active_subscription, get_user_plan

router = APIRouter()


LIVE_RECORDING_MAX_SECONDS = 600  # 10 minutes — fixed cap, applies to all plans


@router.post("/transcribe")
@limiter.limit(RATE_LIMIT)  # baseline per-principal rate limit (bucket keyed by auth_principal)
async def transcribe(
    request: Request,
    file: UploadFile = File(...),
    source: str = Form("upload"),
    is_live_recording: bool = Form(False),
    user: User = Depends(get_user_or_api_key),
    db: Session = Depends(get_db),
):
    # Live recordings bypass the daily quota by design — they're self-captured
    # on the device and naturally rate-limited by the user. RPM still applies.
    check_rpm_limit(request, user, db)
    if not is_live_recording:
        check_daily_quota(request, user, db)

    # Validate file type
    ext = os.path.splitext(file.filename or "")[1].lower()
    if not (file.content_type and file.content_type.startswith("audio")) and ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, "Unsupported file type. Send an audio file.")

    # Get user plan
    plan = getattr(request.state, "plan", None) or get_user_plan(db, user.id)
    # Live recordings get a fixed 10-min cap regardless of plan;
    # regular uploads honor the plan's max_audio_seconds (-1 = unlimited).
    if is_live_recording:
        max_seconds = LIVE_RECORDING_MAX_SECONDS
    else:
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

    # Create request row immediately with processing status so admin dashboard
    # sees it in-flight (and failures get recorded, not silently dropped).
    api_key = getattr(request.state, "api_key", None)

    # Snapshot the user's plan/subscription at request time — admin history must
    # not drift when the user later upgrades/downgrades.
    sub = get_active_subscription(db, user.id)
    plan_source = "free"
    if sub:
        plan_source = "coupon" if sub.coupon_id else ("purchase" if plan and plan.name != "free" else "free")

    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    daily_used = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= today_start,
        TranscriptionRequest.status != "failed",
    ).scalar() or 0

    resolved_source = source
    if is_live_recording:
        resolved_source = "recording"
    elif api_key is not None and source == "upload":
        resolved_source = "api"

    req_log = TranscriptionRequest(
        user_id=user.id,
        api_key_id=api_key.id if api_key else None,
        filename=file.filename,
        duration_seconds=original_duration,
        was_trimmed=False,
        status="processing",
        source=resolved_source,
        is_live_recording=is_live_recording,
        plan_name_at_request=plan.name if plan else "free",
        plan_source_at_request=plan_source,
        daily_limit_at_request=plan.daily_request_limit if plan else None,
        monthly_limit_at_request=plan.monthly_request_limit if plan else None,
        daily_used_at_request=daily_used,  # count BEFORE this request
    )
    db.add(req_log)
    db.commit()
    db.refresh(req_log)

    try:
        if max_seconds > 0 and original_duration > max_seconds:
            trimmed_path = trim_audio(tmp_path, max_seconds)
            was_trimmed = True
            process_path = trimmed_path
        else:
            process_path = tmp_path

        result = await whisper_service.transcribe_from_path(process_path)
    except Exception as e:
        req_log.status = "failed"
        req_log.error_message = str(e)[:500]
        db.commit()
        raise HTTPException(500, f"Transcription failed: {str(e)}")
    finally:
        os.unlink(tmp_path)
        if trimmed_path and os.path.exists(trimmed_path):
            os.unlink(trimmed_path)

    response_data = build_response(result)
    response_data["was_trimmed"] = was_trimmed

    req_log.processed_seconds = float(response_data.get("duration", 0))
    req_log.language = str(response_data.get("lang", ""))
    req_log.word_count = int(response_data.get("word_count", 0))
    req_log.was_trimmed = was_trimmed
    req_log.status = "completed"
    db.commit()

    response_data["request_id"] = req_log.id
    return JSONResponse(content=response_data)
