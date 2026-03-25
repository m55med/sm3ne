import os
import tempfile
import asyncio
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager

import whisper
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
import uvicorn

MODEL_NAME = os.getenv("WHISPER_MODEL", "large-v3")
model = None
executor = ThreadPoolExecutor(max_workers=int(os.getenv("WORKERS", "3")))


@asynccontextmanager
async def lifespan(app: FastAPI):
    global model
    print(f"Loading Whisper model: {MODEL_NAME} ...")
    model = whisper.load_model(MODEL_NAME)
    print("Model loaded successfully!")
    yield
    executor.shutdown(wait=False)


app = FastAPI(title="Whisper Speech-to-Text API", version="1.0.0", lifespan=lifespan)


def _transcribe_sync(path: str) -> dict:
    """Run whisper transcription (blocking) — called in thread pool."""
    return model.transcribe(path, word_timestamps=True)


@app.get("/")
async def health():
    return {"status": "ok", "model": MODEL_NAME}


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    # Validate file type
    allowed_extensions = {".mp3", ".wav", ".m4a", ".ogg", ".flac", ".webm", ".mp4", ".aac", ".wma"}
    ext = os.path.splitext(file.filename or "")[1].lower()
    if not (file.content_type and file.content_type.startswith("audio")) and ext not in allowed_extensions:
        raise HTTPException(status_code=400, detail="Unsupported file type. Send an audio file.")

    # Save uploaded file to temp
    suffix = os.path.splitext(file.filename or ".wav")[1]
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        # Run transcription in thread pool so other requests aren't blocked
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(executor, _transcribe_sync, tmp_path)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")
    finally:
        os.unlink(tmp_path)

    text = result.get("text", "").strip()
    language = result.get("language", "unknown")

    lang_names = {
        "ar": "Arabic", "en": "English", "fr": "French", "de": "German",
        "es": "Spanish", "it": "Italian", "pt": "Portuguese", "ru": "Russian",
        "zh": "Chinese", "ja": "Japanese", "ko": "Korean", "tr": "Turkish",
        "nl": "Dutch", "pl": "Polish", "sv": "Swedish", "da": "Danish",
        "no": "Norwegian", "fi": "Finnish", "cs": "Czech", "ro": "Romanian",
        "hu": "Hungarian", "el": "Greek", "he": "Hebrew", "hi": "Hindi",
        "th": "Thai", "uk": "Ukrainian", "vi": "Vietnamese", "id": "Indonesian",
        "ms": "Malay", "fa": "Persian", "ur": "Urdu", "bn": "Bengali",
        "ta": "Tamil", "te": "Telugu", "ml": "Malayalam", "sw": "Swahili",
    }

    punctuation_count = {
        "comma": text.count(",") + text.count("،"),
        "period": text.count("."),
        "question_mark": text.count("?") + text.count("؟"),
        "exclamation_mark": text.count("!"),
        "semicolon": text.count(";") + text.count("؛"),
        "colon": text.count(":"),
        "ellipsis": text.count("...") + text.count("…"),
    }

    segments = []
    for seg in result.get("segments", []):
        segment_data = {
            "id": seg.get("id", 0),
            "start": round(seg.get("start", 0), 2),
            "end": round(seg.get("end", 0), 2),
            "text": seg.get("text", "").strip(),
        }
        if "words" in seg:
            segment_data["words"] = [
                {
                    "word": w.get("word", "").strip(),
                    "start": round(w.get("start", 0), 2),
                    "end": round(w.get("end", 0), 2),
                    "probability": round(w.get("probability", 0), 4),
                }
                for w in seg["words"]
            ]
        segments.append(segment_data)

    duration = round(segments[-1]["end"], 2) if segments else 0.0
    words = text.split()

    response = {
        "lang": language,
        "lang_name": lang_names.get(language, language),
        "text": text,
        "char_count": len(text),
        "char_count_no_spaces": len(text.replace(" ", "")),
        "word_count": len(words),
        "segment_count": len(segments),
        "segments": segments,
        "duration": duration,
        "punctuation_count": punctuation_count,
    }

    return JSONResponse(content=response)


if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=False)
