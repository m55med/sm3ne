from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded

from app.core.config import MODEL_NAME, limiter
from app.core.lifespan import lifespan
from app.routes.api_keys import router as api_keys_router
from app.routes.auth import router as auth_router
from app.routes.transcribe import router as transcribe_router
from app.routes.profile import router as profile_router
from app.routes.plans import router as plans_router
from app.routes.admin import router as admin_router
from app.services import whisper_service

app = FastAPI(title="Bisawtak - Speech-to-Text API", version="2.0.0", lifespan=lifespan)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, lambda req, exc: JSONResponse(
    status_code=429, content={"detail": "Rate limit exceeded. Try again later."}
))

app.include_router(auth_router)
app.include_router(profile_router)
app.include_router(plans_router)
app.include_router(api_keys_router)
app.include_router(transcribe_router)
app.include_router(admin_router)


@app.get("/")
async def health():
    if whisper_service.is_loading():
        return {"status": "loading", "model": MODEL_NAME}
    if not whisper_service.is_ready():
        return {"status": "starting", "model": MODEL_NAME}
    return {"status": "ready", "model": MODEL_NAME}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
