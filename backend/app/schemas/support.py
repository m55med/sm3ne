from datetime import datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, Field


TicketType = Literal["contact", "suggestion", "bug", "other"]
TicketStatus = Literal["open", "in_progress", "resolved", "closed"]


class TicketCreateRequest(BaseModel):
    ticket_type: TicketType = "contact"
    subject: str = Field(..., min_length=3, max_length=200)
    message: str = Field(..., min_length=5, max_length=5000)


class TicketReplyCreate(BaseModel):
    message: str = Field(..., min_length=1, max_length=5000)


class TicketReplyItem(BaseModel):
    public_id: Optional[str] = None
    is_admin: bool = False
    author_name: Optional[str] = None
    message: str
    created_at: Optional[datetime] = None


class TicketSummary(BaseModel):
    public_id: Optional[str] = None
    ticket_type: TicketType
    subject: str
    status: TicketStatus
    reply_count: int = 0
    last_reply_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


class TicketDetail(BaseModel):
    public_id: Optional[str] = None
    user_public_id: Optional[str] = None
    username: Optional[str] = None
    ticket_type: TicketType
    subject: str
    message: str
    status: TicketStatus
    replies: List[TicketReplyItem] = []
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class TicketListResponse(BaseModel):
    tickets: List[TicketSummary]
    total: int
    page: int
    per_page: int


class AdminTicketSummary(TicketSummary):
    user_public_id: Optional[str] = None
    username: Optional[str] = None


class AdminTicketListResponse(BaseModel):
    tickets: List[AdminTicketSummary]
    total: int
    page: int
    per_page: int


class TicketStatusUpdate(BaseModel):
    status: TicketStatus
