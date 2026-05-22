from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from app.core.config import (
    ALGORITHM,
    JWT_AUDIENCE,
    JWT_ISSUER,
    REFRESH_TOKEN_EXPIRE_DAYS,
    SECRET_KEY,
    TOKEN_EXPIRE_MINUTES,
)
from app.db.database import get_db
from app.db.models import User

bearer_scheme = HTTPBearer()


def create_access_token(user_id: int, role: str = "user") -> str:
    """Mints a short-lived access JWT. The `username` claim used to be in the
    payload — it was dropped along with the username column. Anything that
    needs the display name re-reads it from the user row."""
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": int(now.timestamp()),
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
        "exp": expire,
        "typ": "access",
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(user_id: int) -> str:
    """Long-lived token whose ONLY job is to issue new access tokens via
    POST /auth/refresh. Doesn't carry role/username — we re-read them from
    the DB on refresh so privilege changes propagate within one access cycle."""
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
        "exp": expire,
        "typ": "refresh",
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_refresh_token(token: str) -> int:
    """Validates a refresh token and returns the user_id. Raises 401 on any
    invalid/expired/wrong-type token."""
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            issuer=JWT_ISSUER,
            audience=JWT_AUDIENCE,
            options={"require": ["exp", "iat", "iss", "aud"]},
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
    if payload.get("typ") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not a refresh token")
    sub = payload.get("sub")
    if not sub:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
    return int(sub)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            issuer=JWT_ISSUER,
            audience=JWT_AUDIENCE,
            options={"require": ["exp", "iat", "iss", "aud"]},
        )
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
        # Refresh tokens must NEVER be accepted as access tokens. Older tokens
        # without a "typ" claim default to "access" for backwards compat.
        if payload.get("typ", "access") != "access":
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Wrong token type")
        iat_raw = payload.get("iat")
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

    # If the user's password was changed AFTER this token was issued, reject.
    # The column is added defensively (migration owned by Backend-3); if missing
    # this is a no-op so existing flows still work.
    pwd_changed = getattr(user, "password_changed_at", None)
    if pwd_changed and iat_raw:
        if pwd_changed.tzinfo is None:
            pwd_changed = pwd_changed.replace(tzinfo=timezone.utc)
        iat_dt = datetime.fromtimestamp(int(iat_raw), tz=timezone.utc)
        if pwd_changed > iat_dt:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token invalidated (password changed)",
            )

    return user


def get_current_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    return user
