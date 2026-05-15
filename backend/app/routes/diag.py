"""TEMPORARY remote-logging endpoint for diagnosing the iOS share-intent flow.

Devices POST short tagged messages here; the backend writes them to its own
container logs. Designed for short-term debugging — REMOVE THIS ROUTE once the
share-intent bug is closed. No auth (we need to see pre-login events) and the
payload is hard-capped to keep an attacker from filling our logs.
"""
from __future__ import annotations

import sys

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field


# No rate-limit on this temp diagnostic — we WANT every event to be captured
# while the share-intent bug is open. Remove the whole route once it's closed.
router = APIRouter(prefix="/diag", tags=["diag"])


class DiagLog(BaseModel):
    tag: str = Field(min_length=1, max_length=40)
    msg: str = Field(min_length=1, max_length=500)


@router.post("/log")
async def diag_log(request: Request, body: DiagLog) -> dict:
    ip = (request.client.host if request.client else "?") or "?"
    # Print direct to stdout (and flush) so docker logs picks it up reliably,
    # regardless of how uvicorn/python logging is configured.
    print(f"[DIAG {body.tag}] {body.msg} | {ip}", file=sys.stdout, flush=True)
    return {"ok": True}
