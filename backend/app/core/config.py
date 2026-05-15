import logging
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from dotenv import load_dotenv
from slowapi import Limiter
from slowapi.util import get_remote_address

# Load .env file
env_path = Path(__file__).resolve().parent.parent.parent / ".env"
load_dotenv(env_path)

logger = logging.getLogger(__name__)

# Whisper
MODEL_NAME = os.getenv("WHISPER_MODEL", "large-v3")
RATE_LIMIT = os.getenv("RATE_LIMIT", "10/minute")
MAX_WORKERS = int(os.getenv("WORKERS", "3"))
ALLOWED_EXTENSIONS = {".mp3", ".wav", ".m4a", ".ogg", ".flac", ".webm", ".mp4", ".aac", ".wma"}

# Speechmatics (third-party ASR provider — much faster than local Whisper)
SPEECHMATICS_API_KEY = os.getenv("SP", "").strip()
SPEECHMATICS_BASE_URL = os.getenv(
    "SPEECHMATICS_BASE_URL", "https://eu1.asr.api.speechmatics.com/v2"
).strip().rstrip("/")
SPEECHMATICS_LANGUAGE = os.getenv("SPEECHMATICS_LANGUAGE", "ar").strip()
SPEECHMATICS_OPERATING_POINT = os.getenv("SPEECHMATICS_OPERATING_POINT", "enhanced").strip()
SPEECHMATICS_POLL_INTERVAL = float(os.getenv("SPEECHMATICS_POLL_INTERVAL", "2.0"))
SPEECHMATICS_TIMEOUT_SECONDS = int(os.getenv("SPEECHMATICS_TIMEOUT_SECONDS", "600"))

# Gemini (Google Generative AI — multimodal model, cheap pay-as-you-go + generous free tier)
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-flash-latest").strip()
GEMINI_BASE_URL = os.getenv(
    "GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta"
).strip().rstrip("/")
GEMINI_LANGUAGE_HINT = os.getenv("GEMINI_LANGUAGE_HINT", "ar").strip()
GEMINI_INLINE_MAX_BYTES = int(os.getenv("GEMINI_INLINE_MAX_BYTES", str(15 * 1024 * 1024)))

# Groq (Whisper hosted on Groq's LPU — fastest Whisper inference available)
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "").strip()
GROQ_BASE_URL = os.getenv("GROQ_BASE_URL", "https://api.groq.com/openai/v1").strip().rstrip("/")
GROQ_MODEL = os.getenv("GROQ_MODEL", "whisper-large-v3-turbo").strip()
GROQ_LANGUAGE = os.getenv("GROQ_LANGUAGE", "ar").strip()

# AssemblyAI (managed ASR with diarization + sentiment, generous free credit)
ASSEMBLYAI_API_KEY = os.getenv("ASSEMBLYAI_API_KEY", "").strip()
ASSEMBLYAI_BASE_URL = os.getenv(
    "ASSEMBLYAI_BASE_URL", "https://api.assemblyai.com/v2"
).strip().rstrip("/")
ASSEMBLYAI_MODEL = os.getenv("ASSEMBLYAI_MODEL", "universal").strip()
ASSEMBLYAI_LANGUAGE = os.getenv("ASSEMBLYAI_LANGUAGE", "ar").strip()
ASSEMBLYAI_POLL_INTERVAL = float(os.getenv("ASSEMBLYAI_POLL_INTERVAL", "2.0"))
ASSEMBLYAI_TIMEOUT_SECONDS = int(os.getenv("ASSEMBLYAI_TIMEOUT_SECONDS", "600"))

# Provider selection: "speechmatics" | "gemini" | "groq" | "assemblyai" | "whisper".
# Auto-pick: prefer speechmatics > gemini > groq > assemblyai > whisper based on
# which keys are present.
_provider_env = os.getenv("TRANSCRIPTION_PROVIDER", "").strip().lower()
if _provider_env in ("speechmatics", "gemini", "groq", "assemblyai", "whisper"):
    TRANSCRIPTION_PROVIDER = _provider_env
elif SPEECHMATICS_API_KEY:
    TRANSCRIPTION_PROVIDER = "speechmatics"
elif GEMINI_API_KEY:
    TRANSCRIPTION_PROVIDER = "gemini"
elif GROQ_API_KEY:
    TRANSCRIPTION_PROVIDER = "groq"
elif ASSEMBLYAI_API_KEY:
    TRANSCRIPTION_PROVIDER = "assemblyai"
else:
    TRANSCRIPTION_PROVIDER = "whisper"

# -----------------------------------------------------------------------------
# Database  (required — no insecure default)
# -----------------------------------------------------------------------------
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is not set. Configure it in the environment, e.g. "
        "postgresql://user:pass@host:5432/dbname"
    )

# -----------------------------------------------------------------------------
# JWT secret  (required, must be strong)
# -----------------------------------------------------------------------------
SECRET_KEY = os.getenv("SECRET_KEY", "").strip()
# Minimum is 24 chars (down from the previous 32) so we don't invalidate every
# user's JWT when an older production key (e.g. the legacy 31-char one) is in
# use. Rotating to 32+ chars is still recommended — log a warning so it's
# tracked in observability without forcing a hard outage.
if not SECRET_KEY or SECRET_KEY == "change-me" or len(SECRET_KEY) < 24:
    raise RuntimeError(
        "SECRET_KEY is missing, equals the placeholder 'change-me', or is shorter "
        "than 24 characters. Generate one with: "
        "python -c \"import secrets; print(secrets.token_urlsafe(48))\""
    )
if len(SECRET_KEY) < 32:
    logger.warning(
        "SECRET_KEY is %d chars — below the recommended 32. Consider rotating "
        "to a longer key (token_urlsafe(48)) at a planned maintenance window.",
        len(SECRET_KEY),
    )
ALGORITHM = "HS256"
TOKEN_EXPIRE_MINUTES = int(os.getenv("TOKEN_EXPIRE_MINUTES", "1440"))
JWT_ISSUER = "bisawtak"
JWT_AUDIENCE = "bisawtak-app"

# -----------------------------------------------------------------------------
# API-key pepper (HMAC server-side secret applied to API keys before hashing).
# Falls back to SECRET_KEY when unset — works but rotating SECRET_KEY would then
# invalidate all keys, so a dedicated value is strongly preferred.
# -----------------------------------------------------------------------------
API_KEY_PEPPER = os.getenv("API_KEY_PEPPER", "").strip()
if not API_KEY_PEPPER:
    logger.warning(
        "API_KEY_PEPPER is not set; falling back to SECRET_KEY. Set a dedicated "
        "API_KEY_PEPPER so rotating SECRET_KEY does not invalidate API keys."
    )
    API_KEY_PEPPER = SECRET_KEY

# Email
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASS = os.getenv("SMTP_PASS", "")
SMTP_FROM = os.getenv("SMTP_FROM", "noreply@bisawtak.com")

# Social Auth
# GOOGLE_CLIENT_ID is the primary (Web) OAuth client — used as the
# `serverClientId` by the mobile app. But a Google ID token's `aud` claim can
# legitimately be ANY of our platform client IDs (Web / iOS / Android)
# depending on the SDK flow. Per Google's official guidance we verify the
# token's `aud` against the full set of OUR client IDs. Extra IDs are supplied
# comma-separated in GOOGLE_CLIENT_IDS_EXTRA (iOS + Android client IDs).
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "").strip()
_google_extra = os.getenv("GOOGLE_CLIENT_IDS_EXTRA", "")
GOOGLE_CLIENT_IDS = {
    cid.strip()
    for cid in ([GOOGLE_CLIENT_ID] + _google_extra.split(","))
    if cid.strip()
}
APPLE_TEAM_ID = os.getenv("APPLE_TEAM_ID", "").strip()
APPLE_KEY_ID = os.getenv("APPLE_KEY_ID", "").strip()
APPLE_CLIENT_ID = os.getenv("APPLE_CLIENT_ID", "").strip()
# If APPLE_CLIENT_ID is empty, /auth/apple endpoints should return 503; verify
# function in app/auth/social.py enforces this at request time.

# -----------------------------------------------------------------------------
# Admin bootstrap (required, strong password)
# -----------------------------------------------------------------------------
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "").strip()
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "")
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "admin@bisawtak.com").strip()
if not ADMIN_USERNAME:
    raise RuntimeError("ADMIN_USERNAME is required (no default allowed).")
if not ADMIN_PASSWORD or len(ADMIN_PASSWORD) < 12:
    raise RuntimeError(
        "ADMIN_PASSWORD is missing or shorter than 12 characters. Set a strong "
        "value in the environment before starting the server."
    )

# -----------------------------------------------------------------------------
# Uploads root. Holds ticket-attachment images. We never serve raw paths from
# user input — every file is keyed by its public_id and accessed through the
# /support/tickets/.../attachments/{public_id} endpoint (auth-gated).
# -----------------------------------------------------------------------------
UPLOAD_ROOT = os.getenv("UPLOAD_ROOT", "/app/uploads").strip()

# -----------------------------------------------------------------------------
# Telegram Bot (optional — when unset, /webhooks/telegram returns 503 and the
# mobile linking endpoints respond with `telegram_disabled`).
#
# TELEGRAM_BOT_TOKEN     — issued by @BotFather (format: `<id>:<secret>`).
# TELEGRAM_WEBHOOK_SECRET — random string we register with setWebhook and then
#                          verify on every incoming update via the
#                          `X-Telegram-Bot-Api-Secret-Token` header. Without it,
#                          ANYONE can POST a forged update to our webhook URL.
#                          Generate with: python -c "import secrets; print(secrets.token_urlsafe(32))"
# TELEGRAM_BOT_USERNAME   — bot's @handle (without the @). Used to build deep
#                          links like `t.me/<username>?start=<code>` shown in
#                          the mobile linking screen.
# TELEGRAM_PUBLIC_BASE_URL — public origin the webhook is reachable at
#                          (e.g. https://voice.neojeen.com). Used by the admin
#                          "register webhook" action to call setWebhook with
#                          `<base>/api/v1/webhooks/telegram`.
# TELEGRAM_API_BASE       — override only if running a self-hosted Bot API
#                          server (e.g. to lift the 20 MB download cap).
# -----------------------------------------------------------------------------
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
TELEGRAM_WEBHOOK_SECRET = os.getenv("TELEGRAM_WEBHOOK_SECRET", "").strip()
TELEGRAM_BOT_USERNAME = os.getenv("TELEGRAM_BOT_USERNAME", "").strip().lstrip("@")
TELEGRAM_PUBLIC_BASE_URL = os.getenv("TELEGRAM_PUBLIC_BASE_URL", "").strip().rstrip("/")
TELEGRAM_API_BASE = os.getenv("TELEGRAM_API_BASE", "https://api.telegram.org").strip().rstrip("/")
TELEGRAM_ENABLED = bool(TELEGRAM_BOT_TOKEN)

if TELEGRAM_BOT_TOKEN and not TELEGRAM_WEBHOOK_SECRET:
    # Hard-fail: without the shared secret the webhook is unauthenticated and
    # anyone with the URL could push fake "user sent X" updates. Refuse to boot
    # rather than silently run insecurely.
    raise RuntimeError(
        "TELEGRAM_BOT_TOKEN is set but TELEGRAM_WEBHOOK_SECRET is empty. "
        "Generate one with: python -c \"import secrets; print(secrets.token_urlsafe(32))\""
    )

# App-store / Play-store links surfaced to unlinked Telegram users so they can
# install the app and link their account. Empty values are dropped from the
# fallback message at render time.
APP_STORE_URL = os.getenv("APP_STORE_URL", "").strip()
PLAY_STORE_URL = os.getenv("PLAY_STORE_URL", "").strip()

# -----------------------------------------------------------------------------
# CORS
# -----------------------------------------------------------------------------
_cors_raw = os.getenv("CORS_ALLOWED_ORIGINS", "https://voice.neojeen.com")
CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors_raw.split(",") if o.strip()]

# -----------------------------------------------------------------------------
# Rate limiter storage. Default in-memory works for single-process deployments
# only; for multi-worker uvicorn/gunicorn set RATE_LIMIT_STORAGE_URI (e.g.
# redis://host:6379/0) so limits are shared.
# -----------------------------------------------------------------------------
RATE_LIMIT_STORAGE_URI = os.getenv("RATE_LIMIT_STORAGE_URI", "").strip()

executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)


def _rate_limit_key(request):
    """Bucket rate limits by auth principal when available, else by IP.
    get_user_or_api_key sets request.state.auth_principal to ("apikey", id)
    or ("user", id) before the @limiter.limit callable runs.
    """
    principal = getattr(request.state, "auth_principal", None)
    if principal:
        return f"{principal[0]}:{principal[1]}"
    return get_remote_address(request)


if RATE_LIMIT_STORAGE_URI:
    limiter = Limiter(key_func=_rate_limit_key, storage_uri=RATE_LIMIT_STORAGE_URI)
else:
    logger.warning(
        "RATE_LIMIT_STORAGE_URI is not set; using in-memory rate-limit storage. "
        "This is per-process only — set a shared URI (e.g. redis://...) for "
        "multi-worker deployments."
    )
    limiter = Limiter(key_func=_rate_limit_key)
