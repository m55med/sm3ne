from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class ProfileResponse(BaseModel):
    id: int
    username: str
    email: Optional[str]
    full_name: Optional[str]
    auth_provider: str
    role: str
    survey_response: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class ProfileUpdateRequest(BaseModel):
    full_name: Optional[str] = Field(default=None, max_length=100)
    email: Optional[str] = None


class SurveyRequest(BaseModel):
    # F26: cap each reason and the free-text 'other' so the JSON survey blob
    # we serialize to user.survey_response stays well under the 16 KB ceiling.
    # The DB column is Text but bloating it via a multi-MB blob is a cheap
    # storage DoS vector — close it at the schema boundary.
    reasons: List[str] = Field(default_factory=list, max_length=20)
    other_text: Optional[str] = Field(default=None, max_length=4000)

    @classmethod
    def _truncated_reasons(cls, reasons: List[str]) -> List[str]:
        return [r[:120] for r in reasons]


class AccountDeleteRequest(BaseModel):
    """Re-authentication required to delete the account.
    Send exactly one of: password (local), google_token (google), apple_token (apple).
    The token must be freshly issued by the provider — backend verifies it against the
    same provider_id as the logged-in user.

    F22: for social accounts the user can also set ``confirmation=True`` instead
    of re-providing the social token (interim until full re-auth UX ships).
    """
    password: Optional[str] = None
    google_token: Optional[str] = None
    apple_token: Optional[str] = None
    confirmation: bool = False  # F22
    reason: Optional[str] = Field(default=None, max_length=500)


class AccountDeleteResponse(BaseModel):
    message: str
    deleted_user_public_id: Optional[str] = None


class ChangePasswordRequest(BaseModel):
    """F23: body for POST /profile/password."""
    old_password: str = Field(min_length=1)
    new_password: str = Field(min_length=1)
