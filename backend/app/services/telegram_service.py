"""Thin async wrapper around the Telegram Bot HTTP API.

Why not python-telegram-bot? We only need a tiny subset (sendMessage, getFile,
download, getMe, setWebhook) and the heavyweight library adds asyncio context,
update polling threads, and conversation handlers we don't use. ~100 lines of
httpx beats a 30k-line dependency.

All public functions are async and accept the bot token implicitly from
``core.config.TELEGRAM_BOT_TOKEN``. They raise :class:`TelegramApiError` on
non-OK responses so callers can map to user-facing messages.
"""
from __future__ import annotations

import asyncio
import logging
import os
import tempfile
from typing import Any

import httpx

from app.core import config


logger = logging.getLogger(__name__)


# Telegram Bot API caps downloads at 20 MB for bots using api.telegram.org.
# A self-hosted Bot API server lifts this to 2 GB, in which case we honor
# the larger cap. Surfaced as a module constant so the webhook can decide
# whether to download or reply with the "file too large" message before
# spending an API call.
DEFAULT_DOWNLOAD_LIMIT_BYTES = 20 * 1024 * 1024
SELF_HOSTED_DOWNLOAD_LIMIT_BYTES = 2 * 1024 * 1024 * 1024


class TelegramApiError(RuntimeError):
    """Raised when the Bot API responds with ok=false or HTTP >= 400.

    ``description`` is Telegram's human-readable reason; ``error_code`` is its
    numeric code. ``status_code`` is the HTTP status.
    """

    def __init__(self, message: str, *, description: str = "", error_code: int | None = None,
                 status_code: int | None = None):
        super().__init__(message)
        self.description = description
        self.error_code = error_code
        self.status_code = status_code


def is_self_hosted() -> bool:
    return config.TELEGRAM_API_BASE != "https://api.telegram.org"


def max_download_bytes() -> int:
    return SELF_HOSTED_DOWNLOAD_LIMIT_BYTES if is_self_hosted() else DEFAULT_DOWNLOAD_LIMIT_BYTES


def _api_url(method: str) -> str:
    if not config.TELEGRAM_BOT_TOKEN:
        raise TelegramApiError("Telegram is not configured on this server")
    return f"{config.TELEGRAM_API_BASE}/bot{config.TELEGRAM_BOT_TOKEN}/{method}"


def _file_url(file_path: str) -> str:
    if not config.TELEGRAM_BOT_TOKEN:
        raise TelegramApiError("Telegram is not configured on this server")
    return f"{config.TELEGRAM_API_BASE}/file/bot{config.TELEGRAM_BOT_TOKEN}/{file_path}"


async def _call(method: str, payload: dict | None = None, *, timeout: float = 30.0) -> Any:
    """POST to a Bot API method and return the ``result`` field.

    httpx is used in async mode. We don't keep a global client because httpx
    AsyncClient lifetime is bound to a running loop — and FastAPI creates a
    fresh loop per request in some test/sync paths. Per-call clients are fine
    for our request volume (one outbound call per Telegram event).
    """
    url = _api_url(method)
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            resp = await client.post(url, json=payload or {})
        except httpx.HTTPError as exc:
            raise TelegramApiError(f"Telegram API network error: {exc}") from exc

    try:
        data = resp.json()
    except Exception:  # noqa: BLE001 — non-JSON body means upstream is unhealthy
        raise TelegramApiError(
            f"Telegram returned non-JSON ({resp.status_code})",
            status_code=resp.status_code,
        )

    if not data.get("ok", False):
        raise TelegramApiError(
            data.get("description") or f"Telegram error {resp.status_code}",
            description=data.get("description") or "",
            error_code=data.get("error_code"),
            status_code=resp.status_code,
        )
    return data.get("result")


# -- High-level helpers --------------------------------------------------------

async def get_me() -> dict:
    return await _call("getMe")


async def send_message(
    chat_id: int,
    text: str,
    *,
    parse_mode: str | None = "Markdown",
    disable_web_page_preview: bool = True,
    reply_to_message_id: int | None = None,
) -> dict:
    """Send a text message. Returns the sent Message object on success."""
    payload: dict = {
        "chat_id": chat_id,
        "text": text,
        "disable_web_page_preview": disable_web_page_preview,
    }
    if parse_mode:
        payload["parse_mode"] = parse_mode
    if reply_to_message_id is not None:
        payload["reply_to_message_id"] = reply_to_message_id
        payload["allow_sending_without_reply"] = True
    return await _call("sendMessage", payload)


async def send_chat_action(chat_id: int, action: str = "typing") -> None:
    """Show a "..." indicator while we transcribe. Best-effort — we never let
    a chat action failure break the actual reply."""
    try:
        await _call("sendChatAction", {"chat_id": chat_id, "action": action}, timeout=10.0)
    except TelegramApiError:
        pass


async def get_file(file_id: str) -> dict:
    """Resolve a file_id to its ``file_path`` (and size if known)."""
    return await _call("getFile", {"file_id": file_id})


async def download_file_to_tempfile(file_path: str, *, suffix: str = "") -> str:
    """Download a resolved file to a tempfile. Returns the local path.

    Callers MUST unlink the returned path when done. Raises TelegramApiError
    on HTTP errors.
    """
    url = _file_url(file_path)
    fd, local_path = tempfile.mkstemp(suffix=suffix or os.path.splitext(file_path)[1] or ".bin")
    os.close(fd)
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            async with client.stream("GET", url) as resp:
                if resp.status_code != 200:
                    raise TelegramApiError(
                        f"Telegram file download HTTP {resp.status_code}",
                        status_code=resp.status_code,
                    )
                with open(local_path, "wb") as f:
                    async for chunk in resp.aiter_bytes(chunk_size=64 * 1024):
                        f.write(chunk)
    except Exception:
        # Clean up the empty/partial tempfile on any failure.
        try:
            os.unlink(local_path)
        except OSError:
            pass
        raise
    return local_path


async def set_webhook(public_base_url: str, *, secret_token: str) -> dict:
    """Install the webhook URL + secret on Telegram. Idempotent — calling
    twice with the same URL is a no-op on Telegram's side. We register only
    the update types we actually handle to cut bandwidth.
    """
    url = f"{public_base_url.rstrip('/')}/api/v1/webhooks/telegram"
    return await _call("setWebhook", {
        "url": url,
        "secret_token": secret_token,
        "allowed_updates": ["message", "edited_message", "my_chat_member"],
        "drop_pending_updates": False,
    })


async def delete_webhook(*, drop_pending: bool = False) -> dict:
    return await _call("deleteWebhook", {"drop_pending_updates": drop_pending})


async def get_webhook_info() -> dict:
    return await _call("getWebhookInfo")


async def get_user_profile_photos(user_id: int, *, limit: int = 1) -> dict:
    """Fetch the user's avatar metadata. Returns ``file_id`` of the most
    recent photo (largest size). May return empty ``photos`` array if the
    user has no avatar or it's hidden by their privacy settings."""
    return await _call("getUserProfilePhotos", {"user_id": user_id, "limit": limit, "offset": 0})


async def get_chat(chat_id: int) -> dict:
    """Fetch full chat info including bio (only via getChat, not in Message)."""
    return await _call("getChat", {"chat_id": chat_id})


# -- Throughput helpers --------------------------------------------------------

# Telegram caps single-chat sends at ~1 msg/sec to that chat and ~30 msg/sec
# across the whole bot. The admin broadcast path uses this delay between
# messages so we don't trip the global cap.
BROADCAST_DELAY_SECONDS = 0.05  # 20/sec — well under the 30/sec cap


async def broadcast_sleep() -> None:
    await asyncio.sleep(BROADCAST_DELAY_SECONDS)


# -- Webhook verification ------------------------------------------------------

def verify_webhook_secret(provided_token: str | None) -> bool:
    """Constant-time compare between the provided header and our configured
    secret. Returns False if either side is empty (refuse to accept unsigned
    webhooks even by accident)."""
    import hmac

    expected = config.TELEGRAM_WEBHOOK_SECRET or ""
    if not expected or not provided_token:
        return False
    return hmac.compare_digest(expected, provided_token)
