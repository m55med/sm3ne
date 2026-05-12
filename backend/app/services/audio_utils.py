"""Audio probing / trimming helpers backed by ffprobe and ffmpeg.

Security hardening:
 - Every invocation passes `-protocol_whitelist file,pipe` so a crafted input
   file cannot trick ffmpeg into opening http(s)/concat/etc. protocols.
 - subprocess.run uses `check=True`; failures raise `ValueError("Invalid audio file")`
   so the route layer can return a clean 400 instead of producing empty output.
 - `probe_duration` raises (instead of returning 0.0) on unparseable / zero / negative
   durations so we don't silently bill a user for a corrupt file.
"""
import subprocess
import tempfile
import os
import logging


logger = logging.getLogger(__name__)


# Block exotic protocols. ffmpeg/ffprobe accept this on both demuxer init and
# any nested input — pipe is needed for stdin chaining; file is the normal case.
_PROTO_WHITELIST = ["-protocol_whitelist", "file,pipe"]


def probe_duration(file_path: str) -> float:
    """Return audio duration in seconds, or raise ValueError on any failure."""
    try:
        result = subprocess.run(
            [
                "ffprobe", "-v", "error",
                *_PROTO_WHITELIST,
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                file_path,
            ],
            capture_output=True, text=True, timeout=10, check=True,
        )
    except subprocess.CalledProcessError as e:
        logger.warning("ffprobe failed for %s: %s", file_path, (e.stderr or "")[:200])
        raise ValueError("Invalid audio file") from e
    except subprocess.TimeoutExpired as e:
        logger.warning("ffprobe timed out for %s", file_path)
        raise ValueError("Invalid audio file") from e

    raw = (result.stdout or "").strip()
    try:
        duration = float(raw)
    except ValueError as e:
        logger.warning("ffprobe returned unparseable duration '%s' for %s", raw, file_path)
        raise ValueError("Invalid audio file") from e

    if duration <= 0.0:
        raise ValueError("Invalid audio file")
    return duration


def trim_audio(input_path: str, max_seconds: int) -> str:
    """Trim audio to max_seconds using ffmpeg. Returns path to trimmed file.

    Raises ValueError on any failure (instead of writing an empty output).
    """
    suffix = os.path.splitext(input_path)[1] or ".wav"
    trimmed = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    trimmed.close()

    try:
        subprocess.run(
            [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                *_PROTO_WHITELIST,
                "-i", input_path,
                "-t", str(max_seconds),
                "-c", "copy", trimmed.name,
            ],
            capture_output=True, timeout=30, check=True,
        )
    except subprocess.CalledProcessError as e:
        # Best-effort cleanup of the partial output.
        try:
            os.unlink(trimmed.name)
        except OSError:
            pass
        stderr = (e.stderr or b"")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", "replace")
        logger.warning("ffmpeg trim failed for %s: %s", input_path, stderr[:200])
        raise ValueError("Invalid audio file") from e
    except subprocess.TimeoutExpired as e:
        try:
            os.unlink(trimmed.name)
        except OSError:
            pass
        logger.warning("ffmpeg trim timed out for %s", input_path)
        raise ValueError("Invalid audio file") from e

    return trimmed.name
