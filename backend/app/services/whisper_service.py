import os
import asyncio
import tempfile
import threading

import numpy as np
import whisper
from fastapi import UploadFile

from app.core.config import executor, MODEL_NAME


AVAILABLE_MODELS = [
    {"id": "tiny",          "label": "Tiny (~75MB)",        "description": "الأسرع، الجودة الأقل."},
    {"id": "base",          "label": "Base (~150MB)",       "description": "سريع، جودة معقولة."},
    {"id": "small",         "label": "Small (~500MB)",      "description": "توازن جيد للسرعة والجودة."},
    {"id": "medium",        "label": "Medium (~1.5GB)",     "description": "جودة أعلى، أبطأ."},
    {"id": "large-v3",      "label": "Large v3 (~3GB)",     "description": "أعلى جودة، الأبطأ والأثقل."},
    {"id": "large-v3-turbo", "label": "Large v3 Turbo (~1.5GB)", "description": "جودة large-v3 لكن أسرع بكثير."},
]

# Cache of loaded model instances keyed by model name so switching between
# admin-selected models doesn't repeatedly download and reload.
#
# Concurrency model:
#   * `_lock` guards mutations of `_models`, `_loaded_events`, `_started_events`.
#   * For each target model name we track two threading.Events:
#       - `_started_events[name]` is set while a load is in progress.
#       - `_loaded_events[name]` is set once the model is usable.
#   * A reader can ask `is_ready(name)` / `is_loading(name)` without taking the lock.
_models: dict[str, object] = {}
_loaded_events: dict[str, threading.Event] = {}
_started_events: dict[str, threading.Event] = {}
_lock = threading.Lock()


def default_model() -> str:
    return MODEL_NAME or "large-v3-turbo"


def _events_for(target: str) -> tuple[threading.Event, threading.Event]:
    """Get-or-create the (started, loaded) event pair for a target model."""
    with _lock:
        started = _started_events.get(target)
        if started is None:
            started = threading.Event()
            _started_events[target] = started
        loaded = _loaded_events.get(target)
        if loaded is None:
            loaded = threading.Event()
            _loaded_events[target] = loaded
        return started, loaded


def _ensure_model(name: str | None = None):
    target = name or default_model()
    started, loaded = _events_for(target)

    # Fast path: already loaded.
    if loaded.is_set():
        return _models[target]

    # Slow path: serialize load attempts for this target.
    with _lock:
        if loaded.is_set():
            return _models[target]
        # Mark started inside the lock so concurrent callers see "loading".
        started.set()
        print(f"Loading Whisper model: {target} ...")

    try:
        model_obj = whisper.load_model(target)
    except Exception:
        # On failure, clear `started` so a future call can retry; do NOT set `loaded`.
        with _lock:
            started.clear()
        raise

    # Publish the model + flip `loaded` atomically.
    with _lock:
        _models[target] = model_obj
        loaded.set()
    print(f"Whisper model {target} loaded.")
    return model_obj


def _transcribe_sync(path: str, model_name: str | None = None) -> dict:
    m = _ensure_model(model_name)
    audio = whisper.load_audio(path)
    # Pad short audio to at least 1 second (16000 samples) to avoid tensor mismatch
    if len(audio) < 16000:
        audio = np.pad(audio, (0, 16000 - len(audio)))
    return m.transcribe(audio, word_timestamps=True)


def is_ready(model_name: str | None = None) -> bool:
    target = model_name or default_model()
    loaded = _loaded_events.get(target)
    return bool(loaded and loaded.is_set())


def is_loading(model_name: str | None = None) -> bool:
    target = model_name or default_model()
    started = _started_events.get(target)
    loaded = _loaded_events.get(target)
    started_set = bool(started and started.is_set())
    loaded_set = bool(loaded and loaded.is_set())
    return started_set and not loaded_set


def is_configured() -> bool:
    return True  # local model is always 'configured'; lazy-loaded on first call


async def transcribe_from_path(path: str, model: str | None = None) -> dict:
    """Transcribe from an already-saved file path (used by transcribe route)."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, _transcribe_sync, path, model)


async def transcribe(file: UploadFile, model: str | None = None) -> dict:
    suffix = os.path.splitext(file.filename or ".wav")[1]
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, _transcribe_sync, tmp_path, model)
    finally:
        os.unlink(tmp_path)

    return result
