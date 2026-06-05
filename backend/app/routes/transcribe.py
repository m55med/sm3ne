"""Transcription route.

Heavy lifting (DB row creation, provider dispatch, cleanup) lives in
``services.transcription_orchestrator`` — this module is intentionally thin
so it's easy to audit security checks at a glance.

Quota / limit notes:

* ``is_live_recording`` is NO LONGER a blanket quota bypass (F6). Live recordings
  count against their OWN daily counter, capped per plan tier. Both daily quota
  and RPM apply.
* File uploads are capped at ``MAX_UPLOAD_BYTES`` (F7) and validated by extension
  AND magic bytes (F8) via ``services.file_validation``.
"""
from __future__ import annotations

import logging
import os
import tempfile
from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.deps import check_daily_quota, check_rpm_limit, get_user_or_api_key
from app.core.config import RATE_LIMIT, limiter
from app.db.database import get_db
from app.db.models import TranscriptionRequest, User
from app.schemas.transcribe import ClientLogIn
from app.services.file_validation import validate_audio_upload
from app.services.subscription_service import get_active_subscription, get_user_plan
from app.services.text_analyzer import LANG_NAMES
from app.services.transcription_orchestrator import run_transcription


router = APIRouter()
logger = logging.getLogger(__name__)


# F7: cap upload size (default 200 MB). Backend-1 will register MAX_UPLOAD_BYTES
# in core.config; until then we read directly from the env so this works either
# way without a deploy ordering hazard.
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", str(200 * 1024 * 1024)))
_CHUNK = 1024 * 1024  # 1 MiB chunks while streaming the body to disk

# F6: separate daily caps for live recordings. Live recording is allowed on
# every tier but tracked independently from the upload counter so a heavy
# uploader can still record voice notes (and vice versa).
LIVE_CAP_FREE = 20
LIVE_CAP_PAID = 200


def _today_start_utc() -> datetime:
    now = datetime.now(timezone.utc)
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def _live_cap_for_plan(plan) -> int:
    """Resolve the daily live-recording cap. -1 = unlimited."""
    if plan is None or plan.name == "free":
        return LIVE_CAP_FREE
    # Unlimited plans get unlimited live too.
    if getattr(plan, "daily_request_limit", None) == -1:
        return -1
    return LIVE_CAP_PAID


def _check_live_recording_quota(db: Session, user_id: int, plan) -> None:
    cap = _live_cap_for_plan(plan)
    if cap < 0:
        return  # unlimited
    today = _today_start_utc()
    used = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user_id,
        TranscriptionRequest.created_at >= today,
        TranscriptionRequest.is_live_recording == True,  # noqa: E712
        TranscriptionRequest.status != "failed",
    ).scalar() or 0
    if used >= cap:
        resets_at = today + timedelta(days=1)
        raise HTTPException(
            status_code=429,
            detail={
                "error": "live_recording_quota_exceeded",
                "limit": cap,
                "used": used,
                "resets_at_utc": resets_at.isoformat(),
            },
        )


async def _stream_to_tmp(file: UploadFile, suffix: str) -> tuple[str, bytes, int]:
    """Stream the upload to disk in 1 MiB chunks, capping at MAX_UPLOAD_BYTES.

    Returns ``(tmp_path, first_chunk_bytes, total_size)``. The first-chunk bytes
    are kept around so the route can run magic-byte validation without re-reading.
    On overflow we clean up the partial tmp file and raise 413.
    """
    # Early bail: if the client advertised a Content-Length / size > limit,
    # don't even start writing.
    advertised = getattr(file, "size", None)
    if advertised is not None and advertised > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail={"error": "file_too_large", "limit_bytes": MAX_UPLOAD_BYTES},
        )

    fd, tmp_path = tempfile.mkstemp(suffix=suffix)
    total = 0
    first: bytes = b""
    try:
        with os.fdopen(fd, "wb") as out:
            while True:
                chunk = await file.read(_CHUNK)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_UPLOAD_BYTES:
                    # Wipe partial file before raising so we don't leak disk.
                    out.close()
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    raise HTTPException(
                        status_code=413,
                        detail={
                            "error": "file_too_large",
                            "limit_bytes": MAX_UPLOAD_BYTES,
                        },
                    )
                if not first:
                    first = chunk[:16]  # enough for every magic header we check
                out.write(chunk)
    except HTTPException:
        raise
    except Exception:
        # On any other write error, clean up and re-raise as 500. Don't echo
        # the raw exception — see F9 in transcription_orchestrator.
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        logger.exception("upload streaming failed")
        raise HTTPException(500, "Upload failed. Please try again.")

    return tmp_path, first, total


@router.post("/transcribe")
@limiter.limit(RATE_LIMIT)  # baseline per-principal rate limit (bucket keyed by auth_principal)
async def transcribe(
    request: Request,
    file: UploadFile = File(...),
    # F10: source is now a closed set — anything outside this Literal is
    # rejected by FastAPI/Pydantic with 422 before our handler runs.
    source: Literal["upload", "recording", "share", "api"] = Form("upload"),
    is_live_recording: bool = Form(False),
    # "Higher quality" re-do: the mobile app shows a free on-device transcript
    # and lets the user re-run it through the server for a better result. That
    # deliberate premium action costs 2 daily-quota units instead of 1. Only
    # honoured for non-live requests (live has its own separate counter).
    high_quality: bool = Form(False),
    user: User = Depends(get_user_or_api_key),
    db: Session = Depends(get_db),
):
    # F6: RPM applies to live recordings too — it's a per-minute hammer guard,
    # not a daily quota. We then enforce ONE of the two daily counters:
    # - live → _check_live_recording_quota (separate per-plan cap)
    # - upload → check_daily_quota (the existing per-plan counter)
    check_rpm_limit(request, user, db)

    plan = getattr(request.state, "plan", None) or get_user_plan(db, user.id)

    quota_cost = 2 if (high_quality and not is_live_recording) else 1

    if is_live_recording:
        _check_live_recording_quota(db, user.id, plan)
    else:
        check_daily_quota(request, user, db, incoming_cost=quota_cost)

    # F8: validate extension + magic bytes BEFORE we commit to a full upload.
    # We need at least the first chunk to run magic-byte detection, so we
    # always stream-to-disk; the head bytes get sniffed once we have them.
    suffix = os.path.splitext(file.filename or ".wav")[1] or ".wav"
    tmp_path, head_bytes, _total = await _stream_to_tmp(file, suffix)

    try:
        validate_audio_upload(file.filename, file.content_type, head_bytes)
    except HTTPException:
        # Validation failed — drop the tmp file and rethrow.
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    api_key = getattr(request.state, "api_key", None)

    # Resolve the source value we stamp on the row. The client may send
    # `source="upload"` even when calling through an API key; we override
    # so admin dashboards see "api" for those. Live recording always wins.
    if is_live_recording:
        resolved_source = "recording"
    elif api_key is not None and source == "upload":
        resolved_source = "api"
    else:
        resolved_source = source

    # F28: orchestrator owns the heavy lifting. It also unlinks the tmp file
    # on every code path so we don't double-unlink here.
    try:
        response_data = await run_transcription(
            db,
            user_id=user.id,
            api_key_id=api_key.id if api_key else None,
            filename=file.filename,
            tmp_path=tmp_path,
            plan=plan,
            is_live_recording=is_live_recording,
            resolved_source=resolved_source,
            quota_cost=quota_cost,
        )
    except HTTPException:
        raise
    except Exception:
        # F9: belt-and-suspenders generic error — orchestrator should already
        # have mapped exceptions, but if anything slips through we never
        # leak a stack trace.
        logger.exception("transcribe route failed")
        raise HTTPException(500, "Transcription failed. Please try again later.")

    return JSONResponse(content=response_data)


# Anti-abuse ceiling for client-side logs. We deliberately do NOT charge these
# against the daily transcription quota — the whole point of on-device STT is
# to give users unlimited free transcriptions. But we still cap raw insert
# volume per user/day so a compromised token can't fill the table.
CLIENT_LOG_DAILY_CAP = 500


def _word_count(text: str) -> int:
    stripped = text.strip()
    if not stripped:
        return 0
    return len(stripped.split())


def _resolve_plan_source(sub, plan) -> str:
    """Snapshot label matching the orchestrator's logic, extracted so the
    client-log handler can reuse it without inflating cyclomatic complexity."""
    if sub is None:
        return "free"
    if sub.coupon_id:
        return "coupon"
    if plan and plan.name != "free":
        return "purchase"
    return "free"


@router.post("/transcriptions/log")
@limiter.limit(RATE_LIMIT)
async def log_client_transcription(
    request: Request,
    payload: ClientLogIn,
    user: User = Depends(get_user_or_api_key),
    db: Session = Depends(get_db),
):
    """Persist metadata from an on-device transcription.

    Used when the mobile app's OS-level speech recognizer (Apple Speech /
    Android SpeechRecognizer) produced the text locally. Skips the entire
    Whisper/Gemini pipeline and the daily quota counter — these rows are
    flagged ``provider_used='client_side'`` so admin dashboards and quota
    code can tell them apart.

    Still rate-limited per-principal and capped at ``CLIENT_LOG_DAILY_CAP``
    inserts/day/user as belt-and-suspenders against token compromise.
    """
    check_rpm_limit(request, user, db)

    today = _today_start_utc()
    todays_logs = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user.id,
        TranscriptionRequest.created_at >= today,
        TranscriptionRequest.provider_used == "client_side",
    ).scalar() or 0
    if todays_logs >= CLIENT_LOG_DAILY_CAP:
        raise HTTPException(
            status_code=429,
            detail={
                "error": "client_log_cap_exceeded",
                "limit": CLIENT_LOG_DAILY_CAP,
            },
        )

    plan = getattr(request.state, "plan", None) or get_user_plan(db, user.id)
    sub = get_active_subscription(db, user.id)
    plan_source = _resolve_plan_source(sub, plan)

    text = payload.text.strip()
    lang_code = payload.lang.split("-", 1)[0].lower()
    lang_name = payload.lang_name or LANG_NAMES.get(lang_code, lang_code)
    resolved_source = "recording" if payload.is_live_recording else payload.source

    row = TranscriptionRequest(
        user_id=user.id,
        api_key_id=None,
        filename=None,
        duration_seconds=payload.duration_seconds,
        processed_seconds=payload.duration_seconds,
        language=lang_code,
        word_count=_word_count(text),
        was_trimmed=False,
        status="completed",
        source=resolved_source,
        is_live_recording=payload.is_live_recording,
        plan_name_at_request=plan.name if plan else "free",
        plan_source_at_request=plan_source,
        daily_limit_at_request=plan.daily_request_limit if plan else None,
        monthly_limit_at_request=plan.monthly_request_limit if plan else None,
        daily_used_at_request=todays_logs,
        provider_used="client_side",
        model_used=payload.client_engine,
        latency_ms=None,
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    return JSONResponse(content={
        "request_id": row.id,
        "text": text,
        "lang": lang_code,
        "lang_name": lang_name,
        "duration": payload.duration_seconds,
        "word_count": row.word_count,
        "char_count": len(text),
        "segments": None,
        "was_trimmed": False,
        "provider_used": "client_side",
    })
