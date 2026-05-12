from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from app.core.config import (
    ALGORITHM,
    JWT_AUDIENCE,
    JWT_ISSUER,
    SECRET_KEY,
    TOKEN_EXPIRE_MINUTES,
)
from app.db.database import get_db
from app.db.models import User

bearer_scheme = HTTPBearer()


def create_access_token(user_id: int, username: str, role: str = "user") -> str:
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(user_id),
        "username": username,
        "role": role,
        "iat": int(now.timestamp()),
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
        "exp": expire,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


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
