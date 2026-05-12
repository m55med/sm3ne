"""Lightweight audit-trail helper.

Write-only from the caller's perspective: routes call :func:`record` after a
security-sensitive action and forget about it. Failures here NEVER raise back
into the caller — losing an audit row is preferable to failing the action that
triggered it (an admin bricking a user must not depend on this table existing).

The companion ``AuditLog`` SQLAlchemy model is owned by Backend-3 (``db/models.py``).
Until that lands we fall back to a no-op by catching ImportError/AttributeError
so the rest of the system keeps working in interim test runs.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Mapping

from sqlalchemy.orm import Session


logger = logging.getLogger(__name__)


def record(
    db: Session,
    *,
    action: str,
    actor_user_id: int | None = None,
    target_type: str | None = None,
    target_id: int | None = None,
    metadata: Mapping[str, Any] | None = None,
    ip_address: str | None = None,
) -> None:
    """Append an audit row. Swallows all exceptions on purpose.

    Conventions for ``action``:
      - ``admin.user.update``, ``admin.user.delete``, ``admin.user.subscribe``
      - ``admin.coupon.create``, ``admin.coupon.update``, ``admin.coupon.delete``
      - ``admin.plan.create``, ``admin.plan.update``, ``admin.plan.delete``
      - ``admin.settings.update``
      - ``auth.password.changed``, ``auth.account.deleted``
    """
    try:
        # Lazy import — model may not exist yet during the transitional window
        # while Backend-3 hasn't landed its DDL. Fall through to no-op then.
        try:
            from app.db.models import AuditLog  # type: ignore[attr-defined]
        except (ImportError, AttributeError):
            return

        meta_json: str | None = None
        if metadata is not None:
            try:
                meta_json = json.dumps(metadata, ensure_ascii=False, default=str)[:4000]
            except (TypeError, ValueError):
                meta_json = None

        row = AuditLog(
            actor_user_id=actor_user_id,
            action=action[:60],
            target_type=(target_type or None) and target_type[:40],
            target_id=target_id,
            metadata_json=meta_json,
            ip_address=ip_address[:64] if ip_address else None,
        )
        db.add(row)
        db.commit()
    except Exception:  # noqa: BLE001 — must not break the calling flow
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass
        logger.debug("audit_service.record failed (swallowed)", exc_info=True)
