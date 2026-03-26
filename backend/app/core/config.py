import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from dotenv import load_dotenv
from slowapi import Limiter
from slowapi.util import get_remote_address

# Load .env file
env_path = Path(__file__).resolve().parent.parent.parent / ".env"
load_dotenv(env_path)

# Whisper
MODEL_NAME = os.getenv("WHISPER_MODEL", "large-v3")
RATE_LIMIT = os.getenv("RATE_LIMIT", "10/minute")
MAX_WORKERS = int(os.getenv("WORKERS", "3"))
ALLOWED_EXTENSIONS = {".mp3", ".wav", ".m4a", ".ogg", ".flac", ".webm", ".mp4", ".aac", ".wma"}

# Database
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://bisawtak:bisawtak_pass@postgres:5432/bisawtak")

# JWT
SECRET_KEY = os.getenv("SECRET_KEY", "change-me")
ALGORITHM = "HS256"
TOKEN_EXPIRE_MINUTES = int(os.getenv("TOKEN_EXPIRE_MINUTES", "1440"))

# Email
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASS = os.getenv("SMTP_PASS", "")
SMTP_FROM = os.getenv("SMTP_FROM", "noreply@bisawtak.com")

# Social Auth
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
APPLE_TEAM_ID = os.getenv("APPLE_TEAM_ID", "")
APPLE_KEY_ID = os.getenv("APPLE_KEY_ID", "")

# Admin
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "admin123")
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "admin@bisawtak.com")

executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)
limiter = Limiter(key_func=get_remote_address)
