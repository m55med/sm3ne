import subprocess
import tempfile
import os


def probe_duration(file_path: str) -> float:
    """Get audio duration in seconds using ffprobe."""
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", file_path],
            capture_output=True, text=True, timeout=10
        )
        return float(result.stdout.strip())
    except (ValueError, subprocess.TimeoutExpired):
        return 0.0


def trim_audio(input_path: str, max_seconds: int) -> str:
    """Trim audio to max_seconds using ffmpeg. Returns path to trimmed file."""
    suffix = os.path.splitext(input_path)[1] or ".wav"
    trimmed = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    trimmed.close()

    subprocess.run(
        ["ffmpeg", "-y", "-i", input_path, "-t", str(max_seconds),
         "-c", "copy", trimmed.name],
        capture_output=True, timeout=30
    )
    return trimmed.name
