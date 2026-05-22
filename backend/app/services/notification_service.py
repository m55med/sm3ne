"""Server-side push-notification fan-out via Firebase Cloud Messaging.

Lazily initializes the firebase-admin SDK on first send so the rest of the
app boots fine even if the service-account JSON hasn't been provisioned yet
(initial install gets devices registering, sends start working as soon as
the credential file is dropped in + the server restarts).

The "send to many" path uses ``messaging.send_each_for_multicast`` which
parallelises the HTTP calls under the hood — Firebase enforces a 500-token
ceiling per call, the caller batches above that.
"""
from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Lazily resolved — checking at import time would tightly couple module
# imports to the env var being set, which makes local dev painful.
_firebase_app = None
_init_attempted = False


def _service_account_path() -> Optional[Path]:
    raw = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "").strip()
    if not raw:
        return None
    p = Path(raw)
    if not p.exists():
        logger.warning("FIREBASE_SERVICE_ACCOUNT_PATH set but file missing: %s", p)
        return None
    return p


def _initialize() -> bool:
    """Idempotent. Returns True if the SDK is ready for sends."""
    global _firebase_app, _init_attempted
    if _firebase_app is not None:
        return True
    if _init_attempted:
        return False
    _init_attempted = True
    sa_path = _service_account_path()
    if not sa_path:
        logger.info(
            "Firebase Admin not configured (FIREBASE_SERVICE_ACCOUNT_PATH missing) "
            "— push notifications will no-op until set."
        )
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials
        cred = credentials.Certificate(str(sa_path))
        _firebase_app = firebase_admin.initialize_app(cred, name="bisawtak-fcm")
        logger.info("Firebase Admin initialised — push send is live")
        return True
    except Exception as e:  # noqa: BLE001
        logger.warning("firebase-admin initialisation failed: %s", e)
        _firebase_app = None
        return False


def is_available() -> bool:
    """Cheap check used by routes to short-circuit before doing DB work."""
    return _initialize()


async def send_to_tokens(
    tokens: list[str],
    *,
    title: str,
    body: str,
    data: Optional[dict[str, str]] = None,
) -> tuple[int, int]:
    """Send the same payload to a list of FCM tokens. Returns
    ``(success_count, failure_count)``. Empty token list short-circuits."""
    if not tokens:
        return 0, 0
    if not _initialize():
        return 0, len(tokens)

    try:
        from firebase_admin import messaging
    except ImportError:
        logger.warning("firebase_admin not importable at send time")
        return 0, len(tokens)

    payload_data = data or {}
    # Notification payload (visible on device) + optional data the client
    # reads to decide where to deep-link.
    notification = messaging.Notification(title=title, body=body)
    # Android + APNS hints — keeps a single API for both sides.
    android_cfg = messaging.AndroidConfig(
        priority="high",
        notification=messaging.AndroidNotification(sound="default"),
    )
    apns_cfg = messaging.APNSConfig(
        payload=messaging.APNSPayload(
            aps=messaging.Aps(sound="default", content_available=True),
        ),
    )

    success = 0
    failure = 0
    # FCM caps multicast at 500 tokens per call.
    for i in range(0, len(tokens), 500):
        chunk = tokens[i : i + 500]
        msg = messaging.MulticastMessage(
            tokens=chunk,
            notification=notification,
            data={k: str(v) for k, v in payload_data.items()},
            android=android_cfg,
            apns=apns_cfg,
        )
        try:
            # send_each_for_multicast is the modern (v6+) name — falls back
            # to send_multicast on older SDKs.
            sender = getattr(messaging, "send_each_for_multicast", None) or messaging.send_multicast
            response = sender(msg, app=_firebase_app)
            success += response.success_count
            failure += response.failure_count
            for idx, r in enumerate(response.responses):
                if not r.success:
                    logger.info(
                        "FCM send failed for token=%s…: %s",
                        chunk[idx][:12], r.exception,
                    )
        except Exception as e:  # noqa: BLE001
            logger.warning("FCM batch send errored: %s", e)
            failure += len(chunk)

    return success, failure
