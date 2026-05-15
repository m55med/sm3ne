"""TEMPORARY remote-logging endpoint for diagnosing the iOS share-intent flow.

Devices POST short tagged messages here; the backend writes them to its own
container logs. Designed for short-term debugging — REMOVE THIS ROUTE once the
share-intent bug is closed. No auth (we need to see pre-login events) and the
payload is hard-capped to keep an attacker from filling our logs.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from app.core.config import RATE_LIMIT, limiter


router = APIRouter(prefix="/diag", tags=["diag"])
logger = logging.getLogger("diag")


class DiagLog(BaseModel):
    tag: str = Field(min_length=1, max_length=40)
    msg: str = Field(min_length=1, max_length=500)


@router.post("/log")
@limiter.limit(RATE_LIMIT)  # IP-bucketed; keeps the firehose closed
async def diag_log(request: Request, body: DiagLog) -> dict:
    ip = (request.client.host if request.client else "?") or "?"
    # NOTE: only short strings — the schema caps msg at 500 chars.
    logger.info("[DIAG %s] %s | %s", body.tag, body.msg, ip)
    return {"ok": True}
