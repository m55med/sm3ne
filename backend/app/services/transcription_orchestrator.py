"""Orchestrator for a single transcription request.

The route layer (``routes/transcribe.py``) used to inline every step: validation,
tmpfile save, request-row logging, provider call, cleanup and error stamping.
That made the handler ~120 lines of tangled logic. This module lifts the heavy
lifting out so the route is a thin glue layer.

Public surface:

    run_transcription(...) -> dict

It accepts an already-validated/written tmp path plus the per-request metadata
and returns the JSON-able response body. It is responsible for:

  * resolving max_seconds (live vs upload)
  * creating the ``TranscriptionRequest`` row in ``processing`` state
  * trimming the audio when over the plan cap
  * calling the provider
  * stamping the row to ``completed`` / ``failed``
  * cleaning up tmp files (always)

Errors raised by the provider are re-raised as ``HTTPException(500, ...)`` with
a generic message; full traceback goes to ``logging.exception``. The caller does
NOT need to wrap the call in try/except.
"""
from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.db.models import TranscriptionRequest
from app.services import transcription_service
from app.services.audio_utils import probe_duration, trim_audio
from app.services.subscription_service import get_active_subscription
from app.services.text_analyzer import build_response


logger = logging.getLogger(__name__)

# Live recordings get a hard 10-minute cap, irrespective of plan. This matches
# the on-device behavior and is the same value previously hardcoded in the route.
LIVE_RECORDING_MAX_SECONDS = 600


async def run_transcription(
    db: Session,
    *,
    user_id: int,
    api_key_id: int | None,
    filename: str | None,
    tmp_path: str,
    plan,  # Plan ORM row or None
    is_live_recording: bool,
    resolved_source: str,
) -> dict[str, Any]:
    """Run the full pipeline against a tmp file that the route already wrote.

    The caller is responsible for:
      * authentication, rate limit, quota checks
      * writing the upload to ``tmp_path``
      * MIME / extension / magic-byte validation
      * size validation
    """
    # Resolve duration up-front so we have it on the row even if the provider fails.
    try:
        original_duration = probe_duration(tmp_path)
    except Exception:  # noqa: BLE001 — corrupt audio probe shouldn't break the row write
        logger.exception("probe_duration failed for %s", tmp_path)
        original_duration = 0.0

    trimmed_path: str | None = None

    # Plan-aware audio cap. Live recordings get the fixed 10-minute cap.
    if is_live_recording:
        max_seconds = LIVE_RECORDING_MAX_SECONDS
    else:
        max_seconds = plan.max_audio_seconds if plan else 30

    # Snapshot plan/subscription at request time. The admin dashboard must NOT
    # drift when the user later upgrades or downgrades; that's the whole point
    # of the *_at_request columns.
    sub = get_active_subscription(db, user_id)
    plan_source = "free"
    if sub:
        plan_source = (
            "coupon" if sub.coupon_id
            else ("purchase" if plan and plan.name != "free" else "free")
        )

    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    daily_used = db.query(func.count(TranscriptionRequest.id)).filter(
        TranscriptionRequest.user_id == user_id,
        TranscriptionRequest.created_at >= today_start,
        TranscriptionRequest.status != "failed",
    ).scalar() or 0

    provider_used = transcription_service.resolve_provider(db, plan=plan)

    req_log = TranscriptionRequest(
        user_id=user_id,
        api_key_id=api_key_id,
        filename=filename,
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
        provider_used=provider_used,
    )
    db.add(req_log)
    db.commit()
    db.refresh(req_log)

    was_trimmed = False
    try:
        if max_seconds > 0 and original_duration > max_seconds:
            trimmed_path = trim_audio(tmp_path, max_seconds)
            was_trimmed = True
            process_path = trimmed_path
            process_duration = float(max_seconds)
        else:
            process_path = tmp_path
            process_duration = original_duration

        result = await transcription_service.transcribe_from_path(
            db, process_path, duration=process_duration, plan=plan
        )
    except HTTPException:
        # Bubble up cleanly — these are intentional (e.g. provider 4xx mapped).
        req_log.status = "failed"
        db.commit()
        raise
    except Exception as e:  # noqa: BLE001
        # F9: never echo the provider's stack/message to the client.
        logger.exception("Transcription failed")
        req_log.status = "failed"
        req_log.error_message = str(e)[:500]
        db.commit()
        raise HTTPException(500, "Transcription failed. Please try again later.")
    finally:
        # Always clean up tmp files, even on exception. Failures here are
        # not user-actionable and shouldn't mask the real error.
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            logger.debug("tmp cleanup failed for %s", tmp_path, exc_info=True)
        if trimmed_path:
            try:
                if os.path.exists(trimmed_path):
                    os.unlink(trimmed_path)
            except OSError:
                logger.debug("tmp cleanup failed for %s", trimmed_path, exc_info=True)

    response_data = build_response(result)
    response_data["was_trimmed"] = was_trimmed

    req_log.processed_seconds = float(response_data.get("duration", 0))
    req_log.language = str(response_data.get("lang", ""))
    req_log.word_count = int(response_data.get("word_count", 0))
    req_log.was_trimmed = was_trimmed
    req_log.status = "completed"
    db.commit()

    response_data["request_id"] = req_log.id
    return response_data
