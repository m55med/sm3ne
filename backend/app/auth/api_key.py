import hashlib
import secrets
from typing import Optional

from fastapi import Request

KEY_PREFIX_NAMESPACE = "bsw_live_"
PREFIX_VISIBLE_CHARS = 4


def generate_api_key() -> tuple[str, str, str]:
    """Return (plaintext, key_prefix, key_hash).

    plaintext is shown to the user once.
    key_prefix is stored for identification in listings.
    key_hash is the sha256 hex stored in DB for lookup.
    """
    secret = secrets.token_urlsafe(16)
    plaintext = KEY_PREFIX_NAMESPACE + secret
    key_prefix = KEY_PREFIX_NAMESPACE + secret[:PREFIX_VISIBLE_CHARS]
    key_hash = hash_api_key(plaintext)
    return plaintext, key_prefix, key_hash


def hash_api_key(plaintext: str) -> str:
    return hashlib.sha256(plaintext.encode()).hexdigest()


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
