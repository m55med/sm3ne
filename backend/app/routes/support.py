from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.jwt import get_current_user
from app.core.config import limiter
from app.core.lifespan import generate_public_id
from app.db.database import get_db
from app.db.models import SupportTicket, TicketAttachment, TicketReply, User
from app.schemas.support import (
    TicketAttachmentItem, TicketCreateRequest, TicketReplyCreate, TicketReplyItem,
    TicketSummary, TicketDetail, TicketListResponse,
)
from app.services import ticket_attachment_service


def _attachments_for(db: Session, ticket_id: int) -> list[TicketAttachment]:
    return db.query(TicketAttachment).filter(
        TicketAttachment.ticket_id == ticket_id
    ).order_by(TicketAttachment.created_at).all()


def _serialize_attachment(
    a: TicketAttachment, reply_public_id: str | None = None
) -> TicketAttachmentItem:
    return TicketAttachmentItem(
        public_id=a.public_id,
        reply_public_id=reply_public_id,
        original_filename=a.original_filename,
        mime_type=a.mime_type,
        size_bytes=a.size_bytes,
        created_at=a.created_at,
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
@limiter.limit("5/hour")
async def create_ticket(
    body: TicketCreateRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # F25: 5 tickets/hour per principal cap stops spam-bots from filling the
    # admin queue. Honest users hit this limit only in pathological cases.
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
        user_email=user.email,
        user_full_name=user.full_name,
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

    # Group attachments: ones with reply_id null hang off the original message;
    # otherwise they belong to a specific reply.
    attachments = _attachments_for(db, ticket.id)
    reply_public_ids = {r.id: r.public_id for r in replies}
    attachments_on_message: list[TicketAttachmentItem] = []
    attachments_by_reply: dict[int, list[TicketAttachmentItem]] = {}
    for a in attachments:
        if a.reply_id is None:
            attachments_on_message.append(_serialize_attachment(a))
        else:
            attachments_by_reply.setdefault(a.reply_id, []).append(
                _serialize_attachment(a, reply_public_id=reply_public_ids.get(a.reply_id))
            )

    def _author_name(uid: int) -> Optional[str]:
        u = users.get(uid)
        if not u:
            return None
        return u.full_name or u.email

    reply_items = [
        TicketReplyItem(
            public_id=r.public_id,
            is_admin=r.is_admin,
            author_name=_author_name(r.user_id),
            message=r.message,
            created_at=r.created_at,
            attachments=attachments_by_reply.get(r.id, []),
        ) for r in replies
    ]
    return TicketDetail(
        public_id=ticket.public_id,
        user_public_id=user.public_id,
        user_email=user.email,
        user_full_name=user.full_name,
        ticket_type=ticket.ticket_type,
        subject=ticket.subject,
        message=ticket.message,
        status=ticket.status,
        replies=reply_items,
        attachments=attachments_on_message,
        created_at=ticket.created_at,
        updated_at=ticket.updated_at,
    )


# --- Attachment endpoints ----------------------------------------------------


@router.post(
    "/tickets/{public_id}/attachments",
    response_model=TicketAttachmentItem,
    status_code=201,
)
@limiter.limit("10/hour")
async def upload_attachment(
    public_id: str,
    request: Request,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Attach an image to a ticket (or its latest reply by the user). Limit
    is 10 uploads/hour to protect disk + the admin queue from spam."""
    ticket = _load_ticket_for_user(db, public_id, user)
    if ticket.status == "closed":
        raise HTTPException(400, "Ticket is closed")
    attachment = await ticket_attachment_service.save_attachment(
        db, upload=file, ticket_id=ticket.id, user_id=user.id, reply_id=None,
    )
    return _serialize_attachment(attachment)


@router.get("/tickets/{public_id}/attachments/{attachment_public_id}")
async def download_attachment(
    public_id: str,
    attachment_public_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Download an attachment. Owner-only — admins use the admin endpoint."""
    ticket = _load_ticket_for_user(db, public_id, user)
    attachment = db.query(TicketAttachment).filter(
        TicketAttachment.public_id == attachment_public_id,
        TicketAttachment.ticket_id == ticket.id,
    ).first()
    if not attachment:
        raise HTTPException(404, "Attachment not found")
    path = ticket_attachment_service.attachment_disk_path(attachment)
    if not path.exists():
        raise HTTPException(404, "Attachment file missing from disk")
    return FileResponse(
        path=str(path),
        media_type=attachment.mime_type,
        filename=attachment.original_filename or f"{attachment.public_id}",
    )


@router.post("/tickets/{public_id}/replies", response_model=TicketReplyItem)
@limiter.limit("5/hour")
async def reply_to_my_ticket(
    public_id: str,
    body: TicketReplyCreate,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # F25: same 5/hour budget for replies. Bucket is per principal so a single
    # very chatty thread doesn't break for the user once they've spent it.
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

    author_name = user.full_name or user.email
    return TicketReplyItem(
        public_id=reply.public_id,
        is_admin=False,
        author_name=author_name,
        message=reply.message,
        created_at=reply.created_at,
    )
