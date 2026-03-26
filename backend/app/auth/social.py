import httpx
from app.core.config import GOOGLE_CLIENT_ID


async def verify_google_token(token: str) -> dict | None:
    """Verify Google ID token and return user info."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"https://oauth2.googleapis.com/tokeninfo?id_token={token}"
        )
    if resp.status_code != 200:
        return None

    data = resp.json()
    if GOOGLE_CLIENT_ID and data.get("aud") != GOOGLE_CLIENT_ID:
        return None

    return {
        "provider_id": data.get("sub"),
        "email": data.get("email"),
        "full_name": data.get("name"),
    }


async def verify_apple_token(token: str) -> dict | None:
    """Verify Apple identity token and return user info."""
    import jwt as pyjwt

    # Fetch Apple's public keys
    async with httpx.AsyncClient() as client:
        resp = await client.get("https://appleid.apple.com/auth/keys")
    if resp.status_code != 200:
        return None

    try:
        # Decode header to get kid
        header = pyjwt.get_unverified_header(token)
        kid = header.get("kid")

        keys = resp.json().get("keys", [])
        key_data = next((k for k in keys if k["kid"] == kid), None)
        if not key_data:
            return None

        public_key = pyjwt.algorithms.RSAAlgorithm.from_jwk(key_data)
        payload = pyjwt.decode(
            token, public_key, algorithms=["RS256"],
            audience="com.bisawtak.app", issuer="https://appleid.apple.com"
        )

        return {
            "provider_id": payload.get("sub"),
            "email": payload.get("email"),
            "full_name": None,  # Apple only sends name on first sign-in
        }
    except Exception:
        return None
