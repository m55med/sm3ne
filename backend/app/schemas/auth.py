from typing import Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class RegisterRequest(BaseModel):
    # Accessibility-first signup: email + password (+ optional name) only.
    # `extra="ignore"` lets older clients that still send a `username` field
    # pass the schema check without erroring.
    model_config = ConfigDict(extra="ignore")

    email: EmailStr
    # Min length is checked at the route layer so we can also reject
    # known-weak passwords with a specific error code.
    password: str
    full_name: Optional[str] = Field(default=None, max_length=100)


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    email: EmailStr
    password: str


class SocialAuthRequest(BaseModel):
    token: str  # Google/Apple ID token
    # Apple only: raw nonce that the client hashed to embed in the identity
    # token. Backend will compare sha256(nonce).hex() with payload.nonce when
    # provided. Optional for backwards compatibility with older clients.
    nonce: Optional[str] = None
    # Apple only: the single-use `authorizationCode` returned alongside the
    # identity token. Backend exchanges it server-side for a refresh_token
    # which we store to enable /auth/revoke on account deletion. Optional —
    # absent on old clients; in that case revoke gracefully no-ops later.
    authorization_code: Optional[str] = None


class ForgotPasswordRequest(BaseModel):
    # F17: EmailStr ensures syntactically-valid email; the route still
    # returns a generic 200 to prevent user enumeration.
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    otp: str = Field(min_length=4, max_length=10)
    new_password: str


class TokenResponse(BaseModel):
    access_token: str
    # Optional because /auth/refresh doesn't always rotate the refresh token —
    # only login/register/google/apple do.
    refresh_token: str | None = None
    token_type: str = "bearer"


class RegisterResponse(BaseModel):
    message: str
    access_token: str
    refresh_token: str | None = None
    token_type: str = "bearer"


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class ChangePasswordRequest(BaseModel):
    """Body for POST /profile/password — F23."""
    old_password: str = Field(min_length=1)
    new_password: str = Field(min_length=1)


class LogoutResponse(BaseModel):
    message: str = "logged out"
