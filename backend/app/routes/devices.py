"""Mobile-facing endpoints for device + FCM-token registration.

The client calls POST /devices/register on every login + on FCM-token
rotation; the backend upserts by ``fcm_token`` so a long-lived install gets
exactly one row even across thousands of launches.

DELETE /devices/me is called on logout so an old session's token isn't
left active and able to receive notifications.
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.auth.jwt import get_current_user
from app.core.config import limiter
from app.core.lifespan import generate_public_id
from app.db.database import get_db
from app.db.models import Device, User
from app.schemas.devices import DeviceRegisterRequest

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("/register", status_code=201)
@limiter.limit("20/minute")
async def register_device(
    body: DeviceRegisterRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Idempotent: re-registering the same fcm_token updates ``last_seen_at``
    and refreshes the device metadata in place. Move a token between users
    by simply re-calling with the new auth — we reassign ``user_id``."""
    now = datetime.now(timezone.utc)
    existing = db.query(Device).filter(Device.fcm_token == body.fcm_token).first()
    if existing:
        existing.user_id = user.id
        existing.platform = body.platform
        existing.device_model = body.device_model
        existing.device_marketing_name = body.device_marketing_name
        existing.device_os = body.device_os
        existing.device_os_version = body.device_os_version
        existing.device_locale = body.device_locale
        existing.app_version = body.app_version
        existing.push_enabled = body.push_enabled
        existing.last_seen_at = now
        db.commit()
        return {"public_id": existing.public_id, "created": False}

    device = Device(
        public_id=generate_public_id(),
        user_id=user.id,
        fcm_token=body.fcm_token,
        platform=body.platform,
        device_model=body.device_model,
        device_marketing_name=body.device_marketing_name,
        device_os=body.device_os,
        device_os_version=body.device_os_version,
        device_locale=body.device_locale,
        app_version=body.app_version,
        push_enabled=body.push_enabled,
        last_seen_at=now,
    )
    db.add(device)
    db.commit()
    db.refresh(device)
    return {"public_id": device.public_id, "created": True}


@router.delete("/me", status_code=204)
async def delete_my_device(
    fcm_token: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Remove the device row matching ``fcm_token`` IF it belongs to the
    current user. Used on logout. Silently no-ops if the token isn't ours —
    avoids leaking which tokens exist server-side."""
    row = db.query(Device).filter(
        Device.fcm_token == fcm_token,
        Device.user_id == user.id,
    ).first()
    if row:
        db.delete(row)
        db.commit()
    return None
