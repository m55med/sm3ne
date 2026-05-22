"""Server-driven revocation of Google / Apple sign-in.

Called from /profile DELETE so that when a user nukes their account on our
side, the social provider also forgets the consent. Without this, signing in
again with the same Google/Apple account would return the same provider_id
but no email/full_name (Apple only emits those on the FIRST consent), which
breaks account creation.

Failures are intentionally swallowed and logged: the user has already asked
us to delete their account; we must complete OUR side regardless of whether
the upstream call worked. The reactivation safety-net in /auth/google and
/auth/apple covers the rare case where revoke fails AND the user signs back
in before consent expires.
"""
from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Optional

import httpx
import jwt as pyjwt

from app.core.config import (
    APPLE_CLIENT_ID,
    APPLE_KEY_ID,
    APPLE_SIGNIN_PRIVATE_KEY_PATH,
    APPLE_SIGNIN_PRIVATE_KEY_PEM,
    APPLE_TEAM_ID,
)

logger = logging.getLogger(__name__)

_GOOGLE_REVOKE_URL = "https://oauth2.googleapis.com/revoke"
_APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke"
_APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"


async def revoke_google(token: str) -> bool:
    """Revoke a Google access/refresh token. Returns True on success.

    Google accepts either an access token or refresh token — we forward
    whichever the mobile client sent. Endpoint is anonymous (no client
    credentials needed), which means even a leaked endpoint URL can't be
    weaponized against arbitrary users."""
    if not token:
        return False
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(_GOOGLE_REVOKE_URL, params={"token": token})
        # Google returns 200 on success. 400 means the token was already
        # invalid/revoked — which is FINE for our purposes (the desired
        # end-state is reached either way).
        if resp.status_code in (200, 400):
            return True
        logger.warning(
            "google revoke unexpected status: %s body=%s",
            resp.status_code, resp.text[:200],
        )
        return False
    except Exception as e:  # noqa: BLE001
        logger.warning("google revoke failed: %s", e)
        return False


def _load_apple_private_key() -> Optional[str]:
    """Read the Sign In with Apple .p8 from disk or env. Returns None if not
    configured — caller treats that as "Apple revoke not available"."""
    if APPLE_SIGNIN_PRIVATE_KEY_PEM:
        return APPLE_SIGNIN_PRIVATE_KEY_PEM
    if APPLE_SIGNIN_PRIVATE_KEY_PATH:
        try:
            return Path(APPLE_SIGNIN_PRIVATE_KEY_PATH).read_text()
        except OSError as e:
            logger.warning("apple .p8 unreadable at %s: %s", APPLE_SIGNIN_PRIVATE_KEY_PATH, e)
    return None


def _apple_client_secret(audience: str = "https://appleid.apple.com") -> Optional[str]:
    """Build the JWT client_secret Apple expects on /auth/token and
    /auth/revoke. Returns None if any required env var is missing."""
    if not (APPLE_TEAM_ID and APPLE_KEY_ID and APPLE_CLIENT_ID):
        return None
    key = _load_apple_private_key()
    if not key:
        return None
    now = int(time.time())
    payload = {
        "iss": APPLE_TEAM_ID,
        "iat": now,
        "exp": now + 60 * 60 * 24 * 7 - 60,  # Apple caps at 6 months; we use 1 week
        "aud": audience,
        "sub": APPLE_CLIENT_ID,
    }
    headers = {"alg": "ES256", "kid": APPLE_KEY_ID}
    try:
        return pyjwt.encode(payload, key, algorithm="ES256", headers=headers)
    except Exception as e:  # noqa: BLE001
        logger.warning("failed to build apple client_secret: %s", e)
        return None


async def exchange_apple_code(authorization_code: str) -> Optional[dict]:
    """Trade an Apple `authorization_code` (from the mobile sign-in callback)
    for an access+refresh token pair. Stores ``refresh_token`` so we can call
    /auth/revoke later. Returns the JSON response dict on success, None on
    any failure (logged)."""
    client_secret = _apple_client_secret()
    if not client_secret:
        logger.info("apple code-exchange skipped — sign-in revoke not configured")
        return None
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                _APPLE_TOKEN_URL,
                data={
                    "client_id": APPLE_CLIENT_ID,
                    "client_secret": client_secret,
                    "code": authorization_code,
                    "grant_type": "authorization_code",
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
        if resp.status_code != 200:
            logger.warning("apple code exchange failed: %s body=%s",
                           resp.status_code, resp.text[:200])
            return None
        return resp.json()
    except Exception as e:  # noqa: BLE001
        logger.warning("apple code exchange errored: %s", e)
        return None


async def revoke_apple(refresh_token: str) -> bool:
    """Revoke a user's Sign-in-with-Apple authorization. Idempotent: Apple
    returns 200 even if the token was already invalid."""
    if not refresh_token:
        return False
    client_secret = _apple_client_secret()
    if not client_secret:
        logger.info("apple revoke skipped — sign-in revoke not configured")
        return False
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                _APPLE_REVOKE_URL,
                data={
                    "client_id": APPLE_CLIENT_ID,
                    "client_secret": client_secret,
                    "token": refresh_token,
                    "token_type_hint": "refresh_token",
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
        if resp.status_code == 200:
            return True
        logger.warning("apple revoke unexpected status: %s body=%s",
                       resp.status_code, resp.text[:200])
        return False
    except Exception as e:  # noqa: BLE001
        logger.warning("apple revoke failed: %s", e)
        return False
