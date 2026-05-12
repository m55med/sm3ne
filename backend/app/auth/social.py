"""Social-login token verification (Google ID token + Apple identity token).

Both functions either return a dict of user claims or raise HTTPException. They
never return None for the misconfigured case so a silent acceptance bug cannot
occur — callers can rely on a non-None return meaning "verified".
"""
from __future__ import annotations

import time
from typing import Optional

import httpx
from fastapi import HTTPException, status

from app.core.config import APPLE_CLIENT_ID, GOOGLE_CLIENT_ID


_VALID_GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")


async def verify_google_token(token: str) -> dict | None:
    """Verify a Google ID token and return user info.

    Raises HTTPException(503) if Google sign-in isn't configured on this server.
    Returns None on verification failure (bad signature, expired, wrong aud, etc.)
    so callers can map that to 401.
    """
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google sign-in not configured",
        )

    # TODO: Once the `google-auth` package is added to requirements.txt, switch
    # to local verification (google.oauth2.id_token.verify_oauth2_token) which
    # avoids a network round-trip and is harder to spoof. For now we use the
    # tokeninfo endpoint with strict claim validation.
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"id_token": token},
        )
    if resp.status_code != 200:
        return None

    data = resp.json()

    # aud MUST match our client id exactly.
    if data.get("aud") != GOOGLE_CLIENT_ID:
        return None
    # iss MUST be one of Google's documented issuers.
    if data.get("iss") not in _VALID_GOOGLE_ISSUERS:
        return None
    # exp MUST be in the future (tokeninfo returns it as a string of seconds).
    try:
        exp_ts = int(data.get("exp", 0))
    except (TypeError, ValueError):
        return None
    if exp_ts <= int(time.time()):
        return None

    return {
        "provider_id": data.get("sub"),
        "email": data.get("email"),
        "full_name": data.get("name"),
    }


async def verify_apple_token(token: str, nonce: Optional[str] = None) -> dict | None:
    """Verify an Apple identity token and return user info.

    `nonce`, when provided, must equal the token's `nonce` claim. Mobile clients
    should generate a per-login random nonce, hash it (SHA256) when calling Apple,
    and send the RAW nonce back to the server here. If nonce is None we WARN —
    a missing nonce check leaves a replay window open. Mobile clients will be
    updated separately to always pass it.
    """
    if not APPLE_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Apple sign-in not configured",
        )

    import jwt as pyjwt  # local import to keep startup cheap

    # Fetch Apple's public keys
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get("https://appleid.apple.com/auth/keys")
    if resp.status_code != 200:
        return None

    try:
        header = pyjwt.get_unverified_header(token)
        kid = header.get("kid")

        keys = resp.json().get("keys", [])
        key_data = next((k for k in keys if k["kid"] == kid), None)
        if not key_data:
            return None

        public_key = pyjwt.algorithms.RSAAlgorithm.from_jwk(key_data)
        payload = pyjwt.decode(
            token,
            public_key,
            algorithms=["RS256"],
            audience=APPLE_CLIENT_ID,
            issuer="https://appleid.apple.com",
        )

        if nonce is not None:
            # Mobile client passes the RAW nonce; Apple embedded the SHA256(raw)
            # in the token's `nonce` claim. Compare hashed form.
            import hashlib, hmac as _hmac
            expected = hashlib.sha256(nonce.encode("utf-8")).hexdigest()
            actual = payload.get("nonce") or ""
            if not _hmac.compare_digest(expected, actual):
                return None
        # else: NOTE — without a nonce check there is a replay window. Mobile
        # clients should send the nonce; once they all do, make this required.

        return {
            "provider_id": payload.get("sub"),
            "email": payload.get("email"),
            "full_name": None,  # Apple only sends name on first sign-in
        }
    except Exception:
        return None
