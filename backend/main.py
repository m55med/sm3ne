from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded

from app.core.config import MODEL_NAME, limiter, CORS_ALLOWED_ORIGINS
from app.core.lifespan import lifespan
from app.core.security_headers import SecurityHeadersMiddleware
from app.routes.api_keys import router as api_keys_router
from app.routes.auth import router as auth_router
from app.routes.devices import router as devices_router
from app.routes.transcribe import router as transcribe_router
from app.routes.profile import router as profile_router
from app.routes.plans import router as plans_router
from app.routes.support import router as support_router
from app.routes.admin import router as admin_router
from app.routes.admin_telegram import router as admin_telegram_router
from app.routes.telegram import router as telegram_router
from app.routes.telegram_webhook import router as telegram_webhook_router
from app.routes.legal import router as legal_router
from app.routes.diag import router as diag_router  # TEMP: share-intent diagnostics
from app.services import whisper_service

app = FastAPI(title="Bisawtak - Speech-to-Text API", version="2.0.0", lifespan=lifespan)

# Middleware order in Starlette: the LAST added wraps OUTERMOST, so we add CORS
# FIRST and SecurityHeaders SECOND. That way SecurityHeaders runs outermost and
# its headers land on every response (including CORS preflight responses).
#
# CORS is locked down to an explicit allowlist via CORS_ALLOWED_ORIGINS env.
# Credentials stay OFF because admin auth uses Authorization: Bearer (no cookies).
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)
app.add_middleware(SecurityHeadersMiddleware)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, lambda req, exc: JSONResponse(
    status_code=429, content={"detail": "Rate limit exceeded. Try again later."}
))

API_PREFIX = "/api/v1"

app.include_router(auth_router, prefix=API_PREFIX)
app.include_router(profile_router, prefix=API_PREFIX)
app.include_router(plans_router, prefix=API_PREFIX)
app.include_router(api_keys_router, prefix=API_PREFIX)
app.include_router(devices_router, prefix=API_PREFIX)
app.include_router(transcribe_router, prefix=API_PREFIX)
app.include_router(support_router, prefix=API_PREFIX)
app.include_router(admin_router, prefix=API_PREFIX)
app.include_router(admin_telegram_router, prefix=API_PREFIX)
app.include_router(telegram_router, prefix=API_PREFIX)
# Webhook receiver lives under the same /api/v1 prefix as everything else;
# the URL the bot calls is /api/v1/webhooks/telegram.
app.include_router(telegram_webhook_router, prefix=API_PREFIX)
# TEMP: share-intent diagnostics. Remove once the bug is closed.
app.include_router(diag_router, prefix=API_PREFIX)
# Legal pages live at the root (/privacy, /terms, /support) because Apple &
# Google require the URLs to be plain-link friendly, not API-prefixed.
app.include_router(legal_router)


@app.get(f"{API_PREFIX}/health")
@app.get("/health")
async def health():
    if whisper_service.is_loading():
        return {"status": "loading", "model": MODEL_NAME}
    if not whisper_service.is_ready():
        return {"status": "starting", "model": MODEL_NAME}
    return {"status": "ready", "model": MODEL_NAME}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
