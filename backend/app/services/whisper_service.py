import os
import asyncio
import tempfile
import threading

import numpy as np
import whisper
from fastapi import UploadFile

from app.core.config import executor, MODEL_NAME

model = None
_loading = False
_lock = threading.Lock()


def _ensure_model():
    global model, _loading
    if model is not None:
        return
    with _lock:
        if model is not None:
            return
        _loading = True
        print(f"Loading Whisper model: {MODEL_NAME} ...")
        model = whisper.load_model(MODEL_NAME)
        print("Model loaded successfully!")
        _loading = False


def _transcribe_sync(path: str) -> dict:
    _ensure_model()
    audio = whisper.load_audio(path)
    # Pad short audio to at least 1 second (16000 samples) to avoid tensor mismatch
    if len(audio) < 16000:
        audio = np.pad(audio, (0, 16000 - len(audio)))
    return model.transcribe(audio, word_timestamps=True)


def is_ready() -> bool:
    return model is not None


def is_loading() -> bool:
    return _loading


async def transcribe_from_path(path: str) -> dict:
    """Transcribe from an already-saved file path (used by transcribe route)."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, _transcribe_sync, path)


async def transcribe(file: UploadFile) -> dict:
    suffix = os.path.splitext(file.filename or ".wav")[1]
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, _transcribe_sync, tmp_path)
    finally:
        os.unlink(tmp_path)

    return result
