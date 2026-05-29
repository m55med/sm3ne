import json
import logging
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.auth.jwt import get_current_user
from app.auth.password import hash_password, verify_password
from app.auth.social import verify_apple_token, verify_google_token
from app.core.client_info import get_client_ip, get_device_info
from app.db.database import get_db
from app.db.models import (
    AccountDeletion, ApiKey, PasswordReset, TranscriptionRequest, User,
    UserSubscription,
)
from app.schemas.auth import ChangePasswordRequest
from app.schemas.profile import (
    AccountDeleteRequest, AccountDeleteResponse,
    ProfileResponse, ProfileUpdateRequest, SurveyRequest,
)
from app.services import audit_service, social_revoke

router = APIRouter(prefix="/profile", tags=["profile"])
logger = logging.getLogger(__name__)

# F26: hard cap on the serialized survey blob. The schema validator already
# limits the parts (reasons<=20 entries, other_text<=4000 chars), but we
# defend in depth here on the JSON dump so even a hostile schema bypass
# can't write multi-MB rows.
SURVEY_MAX_BYTES = 16 * 1024

# F18 / shared password policy. We import lazily in change_password to avoid
# a route<->route circular import; the constants are intentionally duplicated
# at module level here for clarity.
PASSWORD_MIN_LENGTH = 10
_WEAK_PASSWORDS = frozenset({
    "123456", "1234567", "12345678", "123456789", "1234567890",
    "password", "password1", "passw0rd", "qwerty123", "admin1234",
    "letmein123", "welcome123", "iloveyou1", "abcdef1234",
})


def _validate_password_strength(password: str) -> None:
    if not password or len(password) < PASSWORD_MIN_LENGTH:
        raise HTTPException(400, f"Password must be at least {PASSWORD_MIN_LENGTH} characters")
    if password.lower() in _WEAK_PASSWORDS:
        raise HTTPException(400, "Password is too common; please choose another")


@router.get("", response_model=ProfileResponse)
async def get_profile(user: User = Depends(get_current_user)):
    return user


@router.put("", response_model=ProfileResponse)
async def update_profile(
    body: ProfileUpdateRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.full_name is not None:
        user.full_name = body.full_name
    if body.email is not None:
        # Social accounts: the email is owned by the identity provider
        # (Apple/Google/etc) and changing it locally would diverge from
        # the IdP, breaking future logins. Mirror the change_password rule.
        if user.auth_provider != "local":
            raise HTTPException(
                400,
                "Email is managed by your sign-in provider and cannot be changed here.",
            )
        existing = db.query(User).filter(User.email == body.email, User.id != user.id).first()
        if existing:
            raise HTTPException(409, "Email already in use")
        user.email = body.email
    db.commit()
    db.refresh(user)
    return user


@router.post("/survey")
async def submit_survey(
    body: SurveyRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    data: dict = {"reasons": body.reasons}
    if body.other_text:
        data["other_text"] = body.other_text

    payload = json.dumps(data, ensure_ascii=False)
    # F26: enforce the 16 KB ceiling on the final serialized form.
    if len(payload.encode("utf-8")) > SURVEY_MAX_BYTES:
        raise HTTPException(
            413,
            {"error": "survey_too_large", "limit_bytes": SURVEY_MAX_BYTES},
        )
    user.survey_response = payload
    db.commit()
    return {"message": "Survey submitted"}


@router.post("/password")
async def change_password(
    body: ChangePasswordRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """F23: authenticated password-change endpoint.

    Verifies the old password (constant-time inside bcrypt) before accepting the
    new one. Also stamps ``users.password_changed_at`` so a future token
    blocklist / staleness check can invalidate older JWTs.
    """
    # Social accounts have no password to verify against — they should be
    # redirected to the provider's own password flow.
    if user.auth_provider != "local" or not user.password_hash:
        raise HTTPException(
            400,
            "Password is managed by your sign-in provider — change it there.",
        )

    if not verify_password(body.old_password, user.password_hash):
        raise HTTPException(401, "Current password is incorrect")

    _validate_password_strength(body.new_password)

    if verify_password(body.new_password, user.password_hash):
        raise HTTPException(400, "New password must be different from the current one")

    user.password_hash = hash_password(body.new_password)
    # Stamp the change timestamp if the column exists (Backend-1's migration).
    try:
        if hasattr(user, "password_changed_at"):
            setattr(user, "password_changed_at", datetime.now(timezone.utc))
    except Exception:
        pass
    db.commit()

    try:
        audit_service.record(
            db, action="auth.password.changed", actor_user_id=user.id,
            target_type="user", target_id=user.id,
        )
    except Exception:
        pass

    return {"message": "Password changed"}


async def _verify_identity(user: User, body: AccountDeleteRequest) -> None:
    """Re-authenticate the user against the same provider they registered with.
    Raises 401 on any mismatch — never reveals which check failed."""
    provider = user.auth_provider or "local"

    if provider == "local":
        if not body.password:
            raise HTTPException(401, "Password required to delete account")
        if not user.password_hash or not verify_password(body.password, user.password_hash):
            raise HTTPException(401, "Invalid password")
        return

    # F22: for social accounts, accept either (a) a freshly issued provider
    # token re-confirming identity, or (b) an explicit `confirmation=True`
    # flag from the client (interim until the proper re-auth UX ships).
    if provider == "google":
        if body.google_token:
            info = await verify_google_token(body.google_token)
            if not info or info.get("provider_id") != user.provider_id:
                raise HTTPException(401, "Google re-authentication failed")
            return
        if body.confirmation:
            return
        raise HTTPException(401, "Google re-authentication or confirmation required")

    if provider == "apple":
        if body.apple_token:
            info = await verify_apple_token(body.apple_token)
            if not info or info.get("provider_id") != user.provider_id:
                raise HTTPException(401, "Apple re-authentication failed")
            return
        if body.confirmation:
            return
        raise HTTPException(401, "Apple re-authentication or confirmation required")

    raise HTTPException(400, f"Unsupported auth provider: {provider}")


@router.delete("", response_model=AccountDeleteResponse)
async def delete_account(
    body: AccountDeleteRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Soft-delete the user account.

    F22: instead of hard-deleting (the previous behavior, which broke admin
    audit trails and required deletion of TranscriptionRequest rows referenced
    by foreign keys), we anonymize PII in-place:

      * email scrubbed to a deterministic ``deleted_<id>_<rand>@deleted.local``
        placeholder so the unique constraint stays satisfied
      * password hash wiped
      * is_active=False so future logins reject
      * all owned API keys deactivated (cascade-orphan)
      * a row in ``account_deletions`` keeps the audit trail
    """
    if user.role == "admin":
        raise HTTPException(403, "Admin accounts cannot self-delete from the app")

    await _verify_identity(user, body)

    # Capture identifiers BEFORE we scrub them (the deletion audit needs them).
    snapshot_public_id = user.public_id
    snapshot_email = user.email
    snapshot_provider = user.auth_provider
    snapshot_provider_id = user.provider_id
    snapshot_apple_refresh = user.apple_refresh_token

    audit = AccountDeletion(
        user_public_id=snapshot_public_id,
        email_snapshot=snapshot_email,
        auth_provider=user.auth_provider,
        reason=(body.reason or "")[:500] or None,
        ip_address=get_client_ip(request),
        user_agent=(get_device_info(request).get("user_agent") or "")[:500] or None,
    )
    db.add(audit)

    # Cascade-orphan: deactivate API keys + revoke any active subscription.
    db.query(ApiKey).filter(ApiKey.user_id == user.id).update(
        {"is_active": False}, synchronize_session=False
    )
    # Telegram: clear the link so the bot row remains in our DB (for the
    # admin's "all Telegram users" page) but no longer points at the
    # now-deleted app account. The user can re-link a fresh app account later.
    try:
        from app.db.models import TelegramUser
        db.query(TelegramUser).filter(TelegramUser.linked_user_id == user.id).update(
            {"linked_user_id": None, "linked_at": None},
            synchronize_session=False,
        )
    except Exception:  # noqa: BLE001 — telegram table may be missing in legacy deployments
        pass
    db.query(UserSubscription).filter(
        UserSubscription.user_id == user.id, UserSubscription.is_active == True,
    ).update({"is_active": False}, synchronize_session=False)
    # Kill outstanding password-reset OTPs so a stale email can't reanimate the
    # account through the reset flow.
    db.query(PasswordReset).filter(
        PasswordReset.user_id == user.id, PasswordReset.used == False,  # noqa: E712
    ).update({"used": True}, synchronize_session=False)

    # Scrub PII in-place. We use a random suffix so re-deletions don't collide
    # on the unique index (in case the same human re-registers later).
    # NOTE: we deliberately KEEP provider_id so /auth/google and /auth/apple
    # can match a re-sign-in attempt and reactivate this row — that's the
    # safety net for when the provider-side revoke below fails for any reason.
    rand = secrets.token_hex(4)
    user.is_active = False
    user.password_hash = None
    user.email = f"deleted_{user.id}_{rand}@deleted.local"
    user.full_name = None
    user.survey_response = None
    user.apple_refresh_token = None  # one-shot — we still need it below
    db.commit()

    # --- Tell the social provider to forget this user ------------------------
    # Done AFTER the local commit so a flaky provider doesn't block deletion.
    # Errors are logged inside the helpers; failure here just means the user
    # will be re-created if they re-sign-in (reactivation safety net runs).
    if snapshot_provider == "google" and body.google_access_token:
        await social_revoke.revoke_google(body.google_access_token)
    elif snapshot_provider == "apple" and snapshot_apple_refresh:
        await social_revoke.revoke_apple(snapshot_apple_refresh)

    try:
        audit_service.record(
            db, action="auth.account.deleted", actor_user_id=user.id,
            target_type="user", target_id=user.id,
            metadata={"original_email": snapshot_email},
            ip_address=get_client_ip(request),
        )
    except Exception:
        pass

    return AccountDeleteResponse(
        message="Account deleted permanently",
        deleted_user_public_id=snapshot_public_id,
    )


# --- Transcription history (F30) ---------------------------------------------

@router.get("/transcriptions")
async def my_transcriptions(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """F30: paginated transcription history for the current user.

    Defaults match support tickets (50 per page). Capped at 200 so a single
    request can't fan out into an unbounded JSON serialization.
    """
    q = db.query(TranscriptionRequest).filter(TranscriptionRequest.user_id == user.id)
    total = q.count()
    rows = (
        q.order_by(TranscriptionRequest.created_at.desc())
        .offset((page - 1) * per_page)
        .limit(per_page)
        .all()
    )
    items = [
        {
            "id": r.id,
            "filename": r.filename,
            "duration_seconds": r.duration_seconds,
            "processed_seconds": r.processed_seconds,
            "language": r.language,
            "word_count": r.word_count,
            "was_trimmed": r.was_trimmed,
            "status": r.status,
            "source": r.source,
            "is_live_recording": r.is_live_recording,
            # provider_used + model_used let the mobile app rebuild its local
            # history after a reinstall and still show the right "on-device vs
            # server" provenance chip. We deliberately do NOT return any
            # transcript text — the server never stores it (privacy).
            "provider_used": r.provider_used,
            "model_used": r.model_used,
            "created_at": r.created_at,
        }
        for r in rows
    ]
    return {
        "items": items,
        "total": total,
        "page": page,
        "per_page": per_page,
    }
