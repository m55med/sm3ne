"""Audio upload validation helpers.

Strict validation pipeline used by the transcribe route. The accept rule is:

    extension is in the allow-list  AND  the first bytes look like a real audio
    container we recognize.

We refuse uploads whose extension/MIME claim is contradicted by the magic bytes,
because the cheapest attack vector for our pipeline is "POST an .exe renamed as
.mp3" and we don't want to hand that to ffmpeg/whisper.

The allowed extensions deliberately mirror ``ALLOWED_EXTENSIONS`` in
``app.core.config`` — keep them in sync if you add a new format.
"""
from __future__ import annotations

import os

from fastapi import HTTPException

# Extensions we accept on the route. Mirrors core.config.ALLOWED_EXTENSIONS but
# duplicated here to keep this module importable without a circular dep.
ALLOWED_EXTENSIONS = {
    ".mp3", ".wav", ".m4a", ".ogg", ".flac", ".webm", ".mp4", ".aac", ".wma",
}


def _looks_like_audio(head: bytes) -> tuple[bool, str | None]:
    """Inspect the first bytes for known audio container signatures.

    Returns (matched, format_label). format_label is informational only — the
    real decision is binary.
    """
    if not head or len(head) < 4:
        return False, None

    # MP3 frames: ID3 tag header, or a 0xFFEx / 0xFFFx sync word (MPEG audio frame)
    if head[:3] == b"ID3":
        return True, "mp3"
    if len(head) >= 2 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0:
        return True, "mp3"

    # WAV: RIFF....WAVE
    if head[:4] == b"RIFF" and len(head) >= 12 and head[8:12] == b"WAVE":
        return True, "wav"

    # Ogg / Opus / Vorbis
    if head[:4] == b"OggS":
        return True, "ogg"

    # FLAC
    if head[:4] == b"fLaC":
        return True, "flac"

    # MP4 / M4A / AAC-in-MP4: "....ftyp...." at offset 4
    if len(head) >= 12 and head[4:8] == b"ftyp":
        return True, "mp4"

    # WebM / Matroska: EBML header 0x1A45DFA3
    if head[:4] == b"\x1a\x45\xdf\xa3":
        return True, "webm"

    # AAC raw (ADTS) — 12-bit sync word 0xFFF
    if len(head) >= 2 and head[0] == 0xFF and (head[1] & 0xF6) == 0xF0:
        return True, "aac"

    # ASF / WMA: GUID 30 26 B2 75 8E 66 CF 11 ...
    if head[:4] == b"\x30\x26\xb2\x75":
        return True, "wma"

    return False, None


def validate_audio_upload(
    filename: str | None,
    content_type: str | None,
    head_bytes: bytes,
) -> str:
    """Validate an audio upload's filename/extension against its magic bytes.

    Returns the canonical lowercase extension (e.g. ``.mp3``). Raises 400 if:
      - the extension is missing or not in the allow-list
      - the magic-byte sniff doesn't match a known audio container

    ``content_type`` is accepted for backwards-compat with old callers but we
    intentionally trust the magic-byte sniff over the client-supplied MIME.
    """
    ext = os.path.splitext(filename or "")[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        # Be specific so the client can fix it; do not leak the magic-byte rule.
        raise HTTPException(
            400,
            f"Unsupported file extension '{ext or '(none)'}'. "
            f"Allowed: {', '.join(sorted(ALLOWED_EXTENSIONS))}",
        )

    matched, _label = _looks_like_audio(head_bytes)
    if not matched:
        # We don't echo what we saw — just refuse. The client can't fix this by
        # changing the extension; the actual bytes are wrong.
        raise HTTPException(
            400,
            "Uploaded file does not look like a valid audio file. "
            "Please send a real audio recording.",
        )

    return ext
