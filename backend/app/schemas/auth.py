from pydantic import BaseModel, EmailStr
from typing import Optional


class RegisterRequest(BaseModel):
    username: str
    email: Optional[str] = None
    password: str
    full_name: Optional[str] = None


class LoginRequest(BaseModel):
    username: str
    password: str


class SocialAuthRequest(BaseModel):
    token: str  # Google/Apple ID token


class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    email: str
    otp: str
    new_password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class RegisterResponse(BaseModel):
    message: str
    access_token: str
    token_type: str = "bearer"
