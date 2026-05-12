from typing import Optional

from pydantic import BaseModel, EmailStr, Field


# Username constraint shared by register + (future) admin user-create paths.
# Restricted to ASCII alphanumerics and underscore to keep URL/log routes simple
# and to block lookalike-unicode account takeovers.
USERNAME_PATTERN = r"^[a-zA-Z0-9_]+$"


class RegisterRequest(BaseModel):
    # F19: enforce username pattern at the schema boundary.
    username: str = Field(min_length=3, max_length=30, pattern=USERNAME_PATTERN)
    # F17: validate emails with EmailStr (still optional — username-only signup allowed).
    email: Optional[EmailStr] = None
    # Min length is checked at the route layer (F18) so we can also reject
    # known-weak passwords with a specific error code.
    password: str
    full_name: Optional[str] = Field(default=None, max_length=100)


class LoginRequest(BaseModel):
    username: str
    password: str


class SocialAuthRequest(BaseModel):
    token: str  # Google/Apple ID token
    # Apple only: raw nonce that the client hashed to embed in the identity
    # token. Backend will compare sha256(nonce).hex() with payload.nonce when
    # provided. Optional for backwards compatibility with older clients.
    nonce: Optional[str] = None


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
    token_type: str = "bearer"


class RegisterResponse(BaseModel):
    message: str
    access_token: str
    token_type: str = "bearer"


class ChangePasswordRequest(BaseModel):
    """Body for POST /profile/password — F23."""
    old_password: str = Field(min_length=1)
    new_password: str = Field(min_length=1)


class LogoutResponse(BaseModel):
    message: str = "logged out"
