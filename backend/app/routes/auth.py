from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import User
from app.auth.jwt import create_access_token
from app.auth.password import hash_password, verify_password
from app.auth.social import verify_google_token, verify_apple_token
from app.schemas.auth import (
    RegisterRequest, LoginRequest, SocialAuthRequest,
    ForgotPasswordRequest, ResetPasswordRequest,
    TokenResponse, RegisterResponse,
)
from app.services.email_service import create_reset_otp, send_reset_email, verify_reset_otp

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=RegisterResponse)
async def register(body: RegisterRequest, db: Session = Depends(get_db)):
    if len(body.username) < 3:
        raise HTTPException(400, "Username must be at least 3 characters")
    if len(body.password) < 6:
        raise HTTPException(400, "Password must be at least 6 characters")

    if db.query(User).filter(User.username == body.username).first():
        raise HTTPException(409, "Username already exists")
    if body.email and db.query(User).filter(User.email == body.email).first():
        raise HTTPException(409, "Email already exists")

    user = User(
        username=body.username,
        email=body.email,
        password_hash=hash_password(body.password),
        full_name=body.full_name,
        auth_provider="local",
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token(user.id, user.username, user.role)
    return {"message": "User created", "access_token": token, "token_type": "bearer"}


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == body.username).first()
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash):
        raise HTTPException(401, "Invalid username or password")
    if not user.is_active:
        raise HTTPException(403, "Account is deactivated")

    token = create_access_token(user.id, user.username, user.role)
    return {"access_token": token, "token_type": "bearer"}


@router.post("/google", response_model=TokenResponse)
async def google_auth(body: SocialAuthRequest, db: Session = Depends(get_db)):
    info = await verify_google_token(body.token)
    if not info:
        raise HTTPException(401, "Invalid Google token")

    user = db.query(User).filter(User.provider_id == info["provider_id"], User.auth_provider == "google").first()
    if not user and info.get("email"):
        user = db.query(User).filter(User.email == info["email"]).first()

    if not user:
        user = User(
            username=info["email"].split("@")[0],
            email=info["email"],
            full_name=info.get("full_name"),
            auth_provider="google",
            provider_id=info["provider_id"],
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    token = create_access_token(user.id, user.username, user.role)
    return {"access_token": token, "token_type": "bearer"}


@router.post("/apple", response_model=TokenResponse)
async def apple_auth(body: SocialAuthRequest, db: Session = Depends(get_db)):
    info = await verify_apple_token(body.token)
    if not info:
        raise HTTPException(401, "Invalid Apple token")

    user = db.query(User).filter(User.provider_id == info["provider_id"], User.auth_provider == "apple").first()
    if not user and info.get("email"):
        user = db.query(User).filter(User.email == info["email"]).first()

    if not user:
        username = info["email"].split("@")[0] if info.get("email") else f"apple_{info['provider_id'][:8]}"
        user = User(
            username=username,
            email=info.get("email"),
            full_name=info.get("full_name"),
            auth_provider="apple",
            provider_id=info["provider_id"],
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    token = create_access_token(user.id, user.username, user.role)
    return {"access_token": token, "token_type": "bearer"}


@router.post("/forgot-password")
async def forgot_password(body: ForgotPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == body.email).first()
    if not user:
        return {"message": "If the email exists, a reset code has been sent"}

    otp = create_reset_otp(db, user.id)
    send_reset_email(body.email, otp)
    return {"message": "If the email exists, a reset code has been sent"}


@router.post("/reset-password")
async def reset_password(body: ResetPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == body.email).first()
    if not user:
        raise HTTPException(400, "Invalid request")

    if len(body.new_password) < 6:
        raise HTTPException(400, "Password must be at least 6 characters")

    if not verify_reset_otp(db, user.id, body.otp):
        raise HTTPException(400, "Invalid or expired code")

    user.password_hash = pwd_context.hash(body.new_password)
    db.commit()
    return {"message": "Password reset successfully"}


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(user: User = Depends(__import__("app.auth.jwt", fromlist=["get_current_user"]).get_current_user)):
    token = create_access_token(user.id, user.username, user.role)
    return {"access_token": token, "token_type": "bearer"}
