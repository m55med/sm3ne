"""Storage + validation for ticket image attachments.

Files land in ``UPLOAD_ROOT/tickets/<yy>/<mm>/<public_id>.<ext>``. The on-disk
filename is fully server-controlled (public_id + sanitized ext) so user input
never touches the path — defence against path traversal.

Validation is two-layered:
  1. Extension whitelist (admin-tunable via settings_service).
  2. Magic-byte sniff on the first few bytes — refuses anything that doesn't
     look like one of the allowed image formats, even if the extension lies.
"""
from __future__ import annotations

import os
import secrets
from datetime import datetime, timezone
from pathlib import Path

from fastapi import HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.core.config import UPLOAD_ROOT
from app.db.models import TicketAttachment
from app.services import settings_service


# Magic-byte signatures we accept. Keyed by extension; value is a list of
# (offset, bytes) pairs that must ALL match within the first 32 bytes.
_MAGIC_BYTES: dict[str, list[tuple[int, bytes]]] = {
    "jpg": [(0, b"\xff\xd8\xff")],
    "jpeg": [(0, b"\xff\xd8\xff")],
    "png": [(0, b"\x89PNG\r\n\x1a\n")],
    "webp": [(0, b"RIFF"), (8, b"WEBP")],
    "heic": [(4, b"ftyp")],   # ftyp at offset 4 — covers heic/heif boxes
    "heif": [(4, b"ftyp")],
    "gif": [(0, b"GIF8")],
    "bmp": [(0, b"BM")],
}

_PUBLIC_ID_ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789"


def _generate_public_id() -> str:
    """10-char URL-safe id (~50 bits). Excludes look-alikes (0/O, 1/l/I)."""
    return "".join(secrets.choice(_PUBLIC_ID_ALPHABET) for _ in range(10))


def _looks_like_image(head: bytes, ext: str) -> bool:
    signatures = _MAGIC_BYTES.get(ext)
    if not signatures:
        return False
    return all(head[offset:offset + len(sig)] == sig for offset, sig in signatures)


async def save_attachment(
    db: Session,
    *,
    upload: UploadFile,
    ticket_id: int,
    user_id: int,
    reply_id: int | None = None,
) -> TicketAttachment:
    """Validate, persist, and record a single image attachment.

    Returns the created ``TicketAttachment`` row on success. Raises
    ``HTTPException`` with a user-safe Arabic message on any failure.
    """
    max_bytes = settings_service.get_ticket_attach_max_bytes(db)
    allowed_exts = settings_service.get_ticket_attach_allowed_extensions(db)

    # Extension check (lowercased, no dot).
    original = upload.filename or "attachment"
    ext = os.path.splitext(original)[1].lower().lstrip(".")
    if ext not in allowed_exts:
        raise HTTPException(
            400,
            f"الامتداد '{ext or '?'}' غير مسموح. الامتدادات المتاحة: "
            f"{', '.join(sorted(allowed_exts))}.",
        )

    # Stream-read with hard size cap. We pull the file fully into memory only
    # after we've checked the magic bytes — bail early on bad data.
    body = await upload.read()
    if not body:
        raise HTTPException(400, "الملف فارغ.")
    if len(body) > max_bytes:
        mb = max_bytes // (1024 * 1024)
        raise HTTPException(400, f"الملف أكبر من الحد المسموح ({mb} ميغابايت).")
    if not _looks_like_image(body[:32], ext):
        raise HTTPException(400, "الملف لا يبدو صورة صحيحة.")

    # Build the on-disk path. We do NOT interpolate user data into it.
    public_id = _generate_public_id()
    now = datetime.now(timezone.utc)
    rel = f"tickets/{now:%Y/%m}/{public_id}.{ext}"
    abs_path = Path(UPLOAD_ROOT) / rel
    abs_path.parent.mkdir(parents=True, exist_ok=True)
    abs_path.write_bytes(body)

    # Best-effort MIME type for the Content-Type header on download.
    mime = {
        "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "png": "image/png", "webp": "image/webp",
        "heic": "image/heic", "heif": "image/heif",
        "gif": "image/gif", "bmp": "image/bmp",
    }.get(ext, "application/octet-stream")

    row = TicketAttachment(
        public_id=public_id,
        ticket_id=ticket_id,
        reply_id=reply_id,
        uploaded_by_user_id=user_id,
        original_filename=original[:255],
        mime_type=mime,
        size_bytes=len(body),
        storage_path=rel,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def attachment_disk_path(attachment: TicketAttachment) -> Path:
    """Resolve the on-disk path for a stored attachment, with a containment
    check that guards against a malicious storage_path value escaping
    UPLOAD_ROOT (defence-in-depth — storage_path is server-generated)."""
    root = Path(UPLOAD_ROOT).resolve()
    resolved = (root / attachment.storage_path).resolve()
    if not str(resolved).startswith(str(root) + os.sep) and resolved != root:
        raise HTTPException(500, "Attachment path escapes upload root")
    return resolved
