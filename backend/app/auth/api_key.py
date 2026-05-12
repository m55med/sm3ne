import hashlib
import hmac
import secrets
from typing import Optional

from fastapi import Request

from app.core.config import API_KEY_PEPPER

KEY_PREFIX_NAMESPACE = "bsw_live_"
PREFIX_VISIBLE_CHARS = 4


def generate_api_key() -> tuple[str, str, str]:
    """Return (plaintext, key_prefix, key_hash).

    plaintext is shown to the user once.
    key_prefix is stored for identification in listings.
    key_hash is the HMAC-SHA256 hex of plaintext under the server-side pepper
    (see hash_api_key).
    """
    secret = secrets.token_urlsafe(16)
    plaintext = KEY_PREFIX_NAMESPACE + secret
    key_prefix = KEY_PREFIX_NAMESPACE + secret[:PREFIX_VISIBLE_CHARS]
    key_hash = hash_api_key(plaintext)
    return plaintext, key_prefix, key_hash


def hash_api_key(plaintext: str) -> str:
    """HMAC-SHA256 the plaintext under the server-side pepper.

    SECURITY NOTE: Switching from plain sha256 to HMAC with a pepper INVALIDATES
    every previously issued API key, because the stored hash format changes.
    Operators must rotate keys after deploying this change.
    """
    return hmac.new(
        API_KEY_PEPPER.encode("utf-8"),
        plaintext.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def extract_api_key_from_request(request: Request) -> Optional[str]:
    """Look for the API key in X-API-Key header first, then Authorization: Bearer.
    Returns None unless the candidate clearly starts with the bsw_ namespace
    (so JWT bearer tokens never get misidentified as API keys).
    """
    candidate = request.headers.get("x-api-key")
    if not candidate:
        auth = request.headers.get("authorization") or ""
        if auth.lower().startswith("bearer "):
            candidate = auth[7:].strip()

    if candidate and candidate.startswith("bsw_"):
        return candidate
    return None
