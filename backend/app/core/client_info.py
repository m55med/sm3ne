"""Helpers to extract the real client IP + device info from a Request.

The backend sits behind nginx-proxy-manager, which sits behind Cloudflare,
so request.client.host is always the proxy IP. Use headers instead.
"""
from __future__ import annotations

import re
from typing import Optional

from fastapi import Request

# Trust order: Cloudflare → direct proxy → socket
_TRUSTED_IP_HEADERS = ("cf-connecting-ip", "x-real-ip", "x-forwarded-for")


def get_client_ip(request: Request) -> Optional[str]:
    for header in _TRUSTED_IP_HEADERS:
        value = request.headers.get(header)
        if not value:
            continue
        # X-Forwarded-For can be "client, proxy1, proxy2" — take the first
        ip = value.split(",")[0].strip()
        if ip:
            return ip
    client = request.client
    return client.host if client else None


_IOS_RE = re.compile(r"iPhone|iPad|iPod", re.IGNORECASE)
_ANDROID_RE = re.compile(r"Android", re.IGNORECASE)
_IOS_VERSION_RE = re.compile(r"OS (\d+[_.]\d+(?:[_.]\d+)?)", re.IGNORECASE)
_ANDROID_VERSION_RE = re.compile(r"Android (\d+(?:\.\d+)*)", re.IGNORECASE)
_MAC_VERSION_RE = re.compile(r"Mac OS X (\d+[_.]\d+(?:[_.]\d+)?)", re.IGNORECASE)
_WIN_VERSION_RE = re.compile(r"Windows NT (\d+\.\d+)", re.IGNORECASE)
_CLI_RE = re.compile(r"^(curl|wget|httpie|python-requests|Go-http-client|PostmanRuntime|node-fetch|axios|Insomnia)/?([\w.\-]*)", re.IGNORECASE)
_CHROME_VERSION_RE = re.compile(r"Chrome/(\d+(?:\.\d+)*)", re.IGNORECASE)
_FIREFOX_VERSION_RE = re.compile(r"Firefox/(\d+(?:\.\d+)*)", re.IGNORECASE)
_SAFARI_VERSION_RE = re.compile(r"Version/(\d+(?:\.\d+)*).*Safari", re.IGNORECASE)
_EDGE_VERSION_RE = re.compile(r"Edg/(\d+(?:\.\d+)*)", re.IGNORECASE)


def parse_user_agent(ua: Optional[str]) -> dict:
    """Extract a coarse platform/model/os_version from a User-Agent string.
    Mobile app may also send X-Device-* headers; those win if present (set by caller)."""
    if not ua:
        return {"platform": None, "model": None, "os_version": None}

    # CLI tools (curl, wget, python-requests, etc.)
    if m := _CLI_RE.match(ua):
        tool, ver = m.group(1), m.group(2)
        return {"platform": "cli", "model": tool, "os_version": ver or None}

    # Mobile — check before "web" because iOS Safari also matches Mozilla
    if _IOS_RE.search(ua):
        m = _IOS_VERSION_RE.search(ua)
        os_version = m.group(1).replace("_", ".") if m else None
        m2 = _IOS_RE.search(ua)
        return {"platform": "ios", "model": m2.group(0) if m2 else "iPhone", "os_version": os_version}

    if _ANDROID_RE.search(ua):
        m = _ANDROID_VERSION_RE.search(ua)
        return {"platform": "android", "model": None, "os_version": m.group(1) if m else None}

    # Desktop browsers — surface OS in model, browser version in os_version
    if any(b in ua for b in ("Mozilla", "Chrome", "Safari", "Firefox", "Edg")):
        os_name = None
        if m := _MAC_VERSION_RE.search(ua):
            os_name = f"macOS {m.group(1).replace('_', '.')}"
        elif _WIN_VERSION_RE.search(ua):
            os_name = "Windows"
        elif "Linux" in ua:
            os_name = "Linux"

        browser = None
        for rx, name in [
            (_EDGE_VERSION_RE, "Edge"),
            (_CHROME_VERSION_RE, "Chrome"),
            (_FIREFOX_VERSION_RE, "Firefox"),
            (_SAFARI_VERSION_RE, "Safari"),
        ]:
            if m := rx.search(ua):
                browser = f"{name} {m.group(1)}"
                break

        return {"platform": "web", "model": os_name, "os_version": browser}

    return {"platform": None, "model": None, "os_version": None}


def get_device_info(request: Request) -> dict:
    """Merge UA parsing with explicit X-Device-* headers (mobile app can set these)."""
    ua = request.headers.get("user-agent")
    info = parse_user_agent(ua)

    # App-provided overrides
    hdr_platform = request.headers.get("x-device-platform")
    hdr_model = request.headers.get("x-device-model")
    hdr_os = request.headers.get("x-device-os-version")
    hdr_app = request.headers.get("x-app-version")

    return {
        "user_agent": (ua or "")[:500] or None,
        "platform": (hdr_platform or info["platform"] or "unknown")[:32],
        "model": (hdr_model or info["model"] or None),
        "os_version": (hdr_os or info["os_version"] or None),
        "app_version": hdr_app,
    }
