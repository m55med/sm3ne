from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.jwt import get_current_user
from app.core.lifespan import generate_public_id
from app.db.database import get_db
from app.db.models import SupportTicket, TicketReply, User
from app.schemas.support import (
    TicketCreateRequest, TicketReplyCreate, TicketReplyItem,
    TicketSummary, TicketDetail, TicketListResponse,
)

router = APIRouter(prefix="/support", tags=["support"])


def _reply_counts(db: Session, ticket_ids: list[int]) -> dict[int, int]:
    if not ticket_ids:
        return {}
    rows = db.query(TicketReply.ticket_id, func.count(TicketReply.id)).filter(
        TicketReply.ticket_id.in_(ticket_ids)
    ).group_by(TicketReply.ticket_id).all()
    return {tid: count for tid, count in rows}


@router.get("/tickets", response_model=TicketListResponse)
async def list_my_tickets(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    q = db.query(SupportTicket).filter(SupportTicket.user_id == user.id)
    total = q.count()
    tickets = q.order_by(SupportTicket.created_at.desc()).offset((page - 1) * per_page).limit(per_page).all()

    counts = _reply_counts(db, [t.id for t in tickets])
    items = [
        TicketSummary(
            public_id=t.public_id,
            ticket_type=t.ticket_type,
            subject=t.subject,
            status=t.status,
            reply_count=counts.get(t.id, 0),
            last_reply_at=t.last_reply_at,
            created_at=t.created_at,
        ) for t in tickets
    ]
    return TicketListResponse(tickets=items, total=total, page=page, per_page=per_page)


@router.post("/tickets", response_model=TicketDetail)
async def create_ticket(
    body: TicketCreateRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ticket = SupportTicket(
        public_id=generate_public_id(),
        user_id=user.id,
        ticket_type=body.ticket_type,
        subject=body.subject.strip(),
        message=body.message.strip(),
        status="open",
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)

    return TicketDetail(
        public_id=ticket.public_id,
        user_public_id=user.public_id,
        username=user.username,
        ticket_type=ticket.ticket_type,
        subject=ticket.subject,
        message=ticket.message,
        status=ticket.status,
        replies=[],
        created_at=ticket.created_at,
        updated_at=ticket.updated_at,
    )


def _load_ticket_for_user(db: Session, public_id: str, user: User) -> SupportTicket:
    ticket = db.query(SupportTicket).filter(SupportTicket.public_id == public_id).first()
    if not ticket:
        raise HTTPException(404, "Ticket not found")
    if ticket.user_id != user.id:
        raise HTTPException(403, "Not your ticket")
    return ticket


@router.get("/tickets/{public_id}", response_model=TicketDetail)
async def get_my_ticket(
    public_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ticket = _load_ticket_for_user(db, public_id, user)
    replies = db.query(TicketReply).filter(TicketReply.ticket_id == ticket.id).order_by(TicketReply.created_at).all()
    user_ids = {r.user_id for r in replies}
    users = {u.id: u for u in db.query(User).filter(User.id.in_(user_ids)).all()} if user_ids else {}
    reply_items = [
        TicketReplyItem(
            public_id=r.public_id,
            is_admin=r.is_admin,
            author_name=(users.get(r.user_id).full_name if users.get(r.user_id) and users[r.user_id].full_name else (users.get(r.user_id).username if users.get(r.user_id) else None)),
            message=r.message,
            created_at=r.created_at,
        ) for r in replies
    ]
    return TicketDetail(
        public_id=ticket.public_id,
        user_public_id=user.public_id,
        username=user.username,
        ticket_type=ticket.ticket_type,
        subject=ticket.subject,
        message=ticket.message,
        status=ticket.status,
        replies=reply_items,
        created_at=ticket.created_at,
        updated_at=ticket.updated_at,
    )


@router.post("/tickets/{public_id}/replies", response_model=TicketReplyItem)
async def reply_to_my_ticket(
    public_id: str,
    body: TicketReplyCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ticket = _load_ticket_for_user(db, public_id, user)
    if ticket.status == "closed":
        raise HTTPException(400, "Ticket is closed")

    reply = TicketReply(
        public_id=generate_public_id(),
        ticket_id=ticket.id,
        user_id=user.id,
        is_admin=False,
        message=body.message.strip(),
    )
    db.add(reply)

    ticket.last_reply_at = datetime.now(timezone.utc)
    if ticket.status == "resolved":
        # User replied to a resolved ticket — treat as reopened
        ticket.status = "open"
    db.commit()
    db.refresh(reply)

    author_name = user.full_name or user.username
    return TicketReplyItem(
        public_id=reply.public_id,
        is_admin=False,
        author_name=author_name,
        message=reply.message,
        created_at=reply.created_at,
    )
