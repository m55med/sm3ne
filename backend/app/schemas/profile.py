from pydantic import BaseModel
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
    full_name: Optional[str] = None
    email: Optional[str] = None


class SurveyRequest(BaseModel):
    reasons: List[str]  # ["hearing_impaired", "voice_messages", "lectures", "other"]
    other_text: Optional[str] = None
