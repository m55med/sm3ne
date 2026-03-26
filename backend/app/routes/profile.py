import json
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import User
from app.auth.jwt import get_current_user
from app.schemas.profile import ProfileResponse, ProfileUpdateRequest, SurveyRequest

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("", response_model=ProfileResponse)
async def get_profile(user: User = Depends(get_current_user)):
    return user


@router.put("", response_model=ProfileResponse)
async def update_profile(
    body: ProfileUpdateRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.full_name is not None:
        user.full_name = body.full_name
    if body.email is not None:
        existing = db.query(User).filter(User.email == body.email, User.id != user.id).first()
        if existing:
            raise HTTPException(409, "Email already in use")
        user.email = body.email
    db.commit()
    db.refresh(user)
    return user


@router.post("/survey")
async def submit_survey(
    body: SurveyRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    data = {"reasons": body.reasons}
    if body.other_text:
        data["other_text"] = body.other_text
    user.survey_response = json.dumps(data, ensure_ascii=False)
    db.commit()
    return {"message": "Survey submitted"}
