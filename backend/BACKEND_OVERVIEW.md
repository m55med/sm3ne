# Bisawtak Backend — Complete Overview

> A FastAPI service that turns audio files into transcribed Arabic/English text using Whisper, with user accounts, subscription plans, coupons, and an admin panel. This document explains the full mental model: every endpoint, what you send, what you get back, and how the pieces fit together. Use it as a reference or as a seed prompt for designing similar backends.

---

## 1. The Big Picture

```
┌─────────────┐      HTTPS       ┌──────────────────┐
│  Mobile app │ ───────────────► │  FastAPI server  │
│  (Flutter)  │ ◄─────────────── │  voice.neojeen   │
└─────────────┘    JSON / JWT    └──────────────────┘
                                          │
                          ┌───────────────┼─────────────────┐
                          ▼               ▼                 ▼
                  ┌─────────────┐ ┌───────────────┐ ┌──────────────┐
                  │  SQLite DB  │ │ Whisper model │ │ ffmpeg utils │
                  │ (users,     │ │ (large-v3,    │ │ (probe/trim  │
                  │  requests,  │ │  GPU/CPU)     │ │  audio)      │
                  │  plans,     │ └───────────────┘ └──────────────┘
                  │  coupons)   │
                  └─────────────┘
```

**Core flow:**
1. User registers/logs in → gets a **JWT token**
2. User uploads an **audio file** with the token
3. Server checks the user's **plan** (free vs paid → max audio length)
4. Server **trims** audio if it exceeds the limit
5. **Whisper** transcribes → text + word-level timestamps + stats
6. Server **logs the request** in DB and returns the result as JSON

**Tech stack:**
- **FastAPI** (Python web framework)
- **SQLAlchemy** (ORM) + **SQLite** (DB)
- **Whisper** (`large-v3` model) for speech-to-text
- **ffmpeg** for audio probing/trimming
- **JWT** (HS256) for auth
- **slowapi** for rate limiting (default 10 req/min per IP)
- **Docker** for deployment

---

## 2. Authentication Model

Two credential types are supported:

### JWT Bearer (interactive clients)
- Stateless, expires after 24 hours.
- Token contains: `user_id`, `username`, `role` (`user` or `admin`).
- Sent as: `Authorization: Bearer <jwt>`.
- Three ways to log in:
  1. **Username + password** (local accounts)
  2. **Google OAuth** (verify Google ID token)
  3. **Apple Sign In** (verify Apple ID token)
- Password reset via **email OTP** (6-digit code).

### API Keys (bots / server-to-server)
- Long-lived, revocable credentials owned by a user.
- Format: `bsw_live_<22-char-secret>`.
- Sent via `X-API-Key:` header or `Authorization: Bearer bsw_live_...`.
- Stored as **SHA-256 hash** in DB (never in plaintext); `key_prefix` (first 4 chars) kept in DB for identification in listings.
- Each key can override the plan's default `requests_per_minute` and `requests_per_day` (admin-only setting — useful for BOT keys).
- Every transcribe call logs `api_key_id` to `TranscriptionRequest`, which is also the source of truth for **daily quota** (`SELECT COUNT(*)` on today's rows — no reset jobs, no divergence).
- Daily quotas reset at **UTC midnight**.

---

## 3. Endpoint Reference

Base URL: `https://voice.neojeen.com`

### 3.1 Health Check

```
GET /
```
No auth. Returns server/model status.

```bash
curl https://voice.neojeen.com/
```
**Response:**
```json
{ "status": "ready", "model": "large-v3" }
```
Status values: `starting`, `loading`, `ready`.

---

### 3.2 Auth Endpoints

#### Register
```
POST /auth/register
```
**Request body:**
```json
{
  "username": "mohamed",
  "password": "mypassword123",
  "email": "mo@example.com",
  "full_name": "Mohamed A."
}
```
**Validation:** username ≥ 3 chars, password ≥ 6 chars, username/email unique.

```bash
curl -X POST https://voice.neojeen.com/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"mohamed","password":"mypassword123"}'
```
**Response (201):**
```json
{
  "message": "User created",
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```
**Errors:** `400` (validation) · `409` (duplicate).

---

#### Login
```
POST /auth/login
```
```bash
curl -X POST https://voice.neojeen.com/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"mohamed","password":"mypassword123"}'
```
**Response (200):**
```json
{ "access_token": "eyJ...", "token_type": "bearer" }
```
**Errors:** `401` (wrong creds) · `403` (account deactivated).

---

#### Google / Apple Social Auth
```
POST /auth/google
POST /auth/apple
```
**Body:**
```json
{ "token": "<google_id_token_or_apple_token>" }
```
Server verifies with the provider, finds-or-creates the user, returns a JWT.
**Response:** same shape as `/auth/login`.

---

#### Forgot Password
```
POST /auth/forgot-password
```
**Body:** `{ "email": "mo@example.com" }`
Generates OTP, emails it. Always returns the same generic message (prevents email enumeration).
```json
{ "message": "If the email exists, a reset code has been sent" }
```

#### Reset Password
```
POST /auth/reset-password
```
**Body:**
```json
{ "email": "mo@example.com", "otp": "482910", "new_password": "newpass123" }
```
**Response:** `{ "message": "Password reset successfully" }`

---

#### Refresh Token
```
POST /auth/refresh
Authorization: Bearer <token>
```
Returns a fresh token without requiring credentials.

---

### 3.3 Profile Endpoints

#### Get Profile
```
GET /profile
Authorization: Bearer <token>
```
```bash
curl https://voice.neojeen.com/profile -H "Authorization: Bearer $TOKEN"
```
**Response:**
```json
{
  "id": 7,
  "username": "mohamed",
  "email": "mo@example.com",
  "full_name": "Mohamed A.",
  "role": "user",
  "auth_provider": "local",
  "is_active": true,
  "created_at": "2026-04-10T14:23:00Z"
}
```

#### Update Profile
```
PUT /profile
```
**Body:** `{ "full_name": "New Name", "email": "new@example.com" }` (both optional)

#### Survey
```
POST /profile/survey
```
**Body:** `{ "reasons": ["work","study"], "other_text": "..." }`
Stores user's reasons for using the app — used for onboarding analytics.

---

### 3.4a API Keys

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/keys` | Create a new key (plaintext returned **once**) |
| `GET` | `/keys` | List user's keys with `usage_today` / `daily_limit` |
| `PUT` | `/keys/{id}` | Rename, toggle active, change expiry |
| `DELETE` | `/keys/{id}` | Revoke (soft-delete) |
| `GET` | `/admin/keys` | Admin: all keys paginated |
| `POST` | `/admin/keys` | Admin: create key for any user with custom rate limits |
| `PUT` | `/admin/keys/{id}` | Admin: full update including rate overrides |
| `DELETE` | `/admin/keys/{id}` | Admin: revoke |

Creating a key:
```bash
curl -X POST https://voice.neojeen.com/keys \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"name":"n8n-waha-bot"}'
# → { "key": "bsw_live_...", "key_prefix": "bsw_live_ab12", ... }
```

Using the key:
```bash
curl -X POST https://voice.neojeen.com/transcribe \
  -H "X-API-Key: bsw_live_..." -F "file=@audio.mp3"
```

Daily quota exceeded → `429` with body:
```json
{"detail":{"error":"daily_quota_exceeded","limit":100,"used":100,"resets_at_utc":"..."}}
```

---

### 3.4 Plans & Subscriptions

#### List Available Plans
```
GET /plans
```
No auth required.
```bash
curl https://voice.neojeen.com/plans
```
**Response:**
```json
[
  {
    "id": 1,
    "name": "free",
    "price": 0,
    "max_audio_seconds": 30,
    "duration_days": 0,
    "is_active": true
  },
  {
    "id": 2,
    "name": "pro",
    "price": 99,
    "max_audio_seconds": 600,
    "duration_days": 30,
    "is_active": true
  }
]
```
Key field: `max_audio_seconds` — how long an audio clip the user can submit.

#### My Subscription
```
GET /plans/my
Authorization: Bearer <token>
```
**Response:**
```json
{
  "plan": { "id": 2, "name": "pro", "max_audio_seconds": 600, ... },
  "subscription": {
    "id": 15,
    "plan_id": 2,
    "started_at": "2026-04-01T00:00:00Z",
    "expires_at": "2026-05-01T00:00:00Z",
    "is_active": true
  }
}
```

#### Subscribe
```
POST /plans/subscribe
```
**Body:** `{ "plan_id": 2, "coupon_code": "PROMO50" }` (`coupon_code` optional)

#### Apply Coupon
```
POST /plans/coupon
```
**Body:** `{ "code": "PROMO50" }`
Subscribes the user to the plan tied to the coupon.

---

### 3.5 The Core: Transcription

```
POST /transcribe
Authorization: Bearer <token>
Content-Type: multipart/form-data
```
**Form field:** `file` — the audio file.
**Supported formats:** `mp3, wav, m4a, ogg, flac, webm, mp4, aac, wma`.
**Rate limit:** 10/minute per IP (configurable via `RATE_LIMIT` env var).

```bash
curl -X POST https://voice.neojeen.com/transcribe \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@audio.mp3"
```

**What happens server-side:**
1. Validate file extension & MIME type
2. Save to a temp file
3. Probe duration with ffmpeg
4. Look up user's plan → get `max_audio_seconds`
5. If audio is longer → trim with ffmpeg, set `was_trimmed = true`
6. Pass to Whisper → get raw segments with word timestamps
7. Run text analyzer (counts chars, words, punctuation)
8. Log a `TranscriptionRequest` row in DB
9. Delete temp files
10. Return JSON

**Response (200):**
```json
{
  "lang": "ar",
  "lang_name": "Arabic",
  "text": "تم إلغاء الحجز",
  "char_count": 14,
  "char_count_no_spaces": 12,
  "word_count": 3,
  "segment_count": 1,
  "segments": [
    {
      "id": 0,
      "start": 0.0,
      "end": 1.28,
      "text": "تم إلغاء الحجز",
      "words": [
        { "word": "تم",    "start": 0.00, "end": 0.26, "probability": 0.9845 },
        { "word": "إلغاء", "start": 0.26, "end": 0.80, "probability": 0.9551 },
        { "word": "الحجز", "start": 0.80, "end": 1.28, "probability": 0.8293 }
      ]
    }
  ],
  "duration": 1.28,
  "punctuation_count": {
    "comma": 0, "period": 0, "question_mark": 0,
    "exclamation_mark": 0, "semicolon": 0, "colon": 0, "ellipsis": 0
  },
  "was_trimmed": false,
  "request_id": 4231
}
```

| Field | Meaning |
|---|---|
| `lang` / `lang_name` | Detected language code & name |
| `text` | Full transcription |
| `char_count` / `word_count` / `segment_count` | Counts |
| `segments[]` | Time-aligned chunks |
| `segments[].words[]` | Each word with start/end seconds + confidence |
| `duration` | Audio length in seconds |
| `was_trimmed` | True if server trimmed it down to plan limit |
| `request_id` | DB row id for this request (used for client-side history) |

**Errors:** `400` (bad file) · `401` (no token) · `429` (rate limit) · `500` (transcription failure).

---

### 3.6 Admin Endpoints

All under `/admin/*` and require **JWT with `role = "admin"`**. Non-admins get `403`.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/admin/stats` | Total users, active subs, requests today/week/month |
| `GET` | `/admin/users?page=1&per_page=20&search=mo` | Paginated user list |
| `GET` | `/admin/users/{id}` | Single user with sub & request count |
| `PUT` | `/admin/users/{id}` | Toggle `is_active` or change `role` |
| `GET` | `/admin/requests?page=1&user_id=7&language=ar` | Paginated transcription requests |
| `GET` | `/admin/coupons` | List all coupons |
| `POST` | `/admin/coupons` | Create coupon `{ code, plan_id, duration_days, max_uses, expires_at }` |
| `PUT` | `/admin/coupons/{id}` | Update coupon |
| `DELETE` | `/admin/coupons/{id}` | Soft-delete (set inactive) |

**Example — stats:**
```bash
curl https://voice.neojeen.com/admin/stats -H "Authorization: Bearer $ADMIN_TOKEN"
```
```json
{
  "total_users": 1240,
  "active_subscribers": 87,
  "requests_today": 312,
  "requests_week": 2014,
  "requests_month": 8430,
  "total_requests": 51230
}
```

---

## 4. Database Schema (Mental Model)

| Table | Key columns | Purpose |
|---|---|---|
| `users` | `id, username, email, password_hash, role, auth_provider, provider_id, is_active, created_at` | Accounts (local + social) |
| `plans` | `id, name, price, max_audio_seconds, daily_request_limit, rpm_default, api_keys_allowed, is_active` | Pricing tiers + per-plan quotas |
| `user_subscriptions` | `id, user_id, plan_id, started_at, expires_at, is_active, coupon_used` | Active/past subscriptions |
| `coupons` | `id, code, plan_id, duration_days, max_uses, used_count, expires_at, is_active, created_by` | Promo codes |
| `api_keys` | `id, user_id, name, key_prefix, key_hash, requests_per_minute, requests_per_day, last_used_at, expires_at, is_active, created_by_admin_id, created_at` | Long-lived credentials |
| `transcription_requests` | `id, user_id, api_key_id, filename, duration_seconds, processed_seconds, language, word_count, was_trimmed, created_at` | Audit log of every transcription (source of truth for daily quota) |
| `password_reset_otps` | `id, user_id, otp_hash, expires_at, used` | Email reset codes |

---

## 5. Configuration (Environment Variables)

| Var | Default | Notes |
|---|---|---|
| `WHISPER_MODEL` | `large-v3` | Any Whisper checkpoint |
| `RATE_LIMIT` | `10/minute` | slowapi format |
| `WORKERS` | `3` | Concurrent transcription threads |
| `SECRET_KEY` | — | **Must be set in production** (JWT signing) |
| `TOKEN_EXPIRE_MINUTES` | `1440` | 24 hours |

---

## 6. End-to-End Example Flow

```bash
# 1. Register
TOKEN=$(curl -s -X POST https://voice.neojeen.com/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"demo","password":"demopass1"}' \
  | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# 2. Check plan
curl https://voice.neojeen.com/plans/my -H "Authorization: Bearer $TOKEN"
# → free plan, max 30 seconds

# 3. Transcribe a 25-second clip
curl -X POST https://voice.neojeen.com/transcribe \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@meeting.mp3"
# → full transcription, was_trimmed = false

# 4. Try a 5-minute clip on the free plan
curl -X POST https://voice.neojeen.com/transcribe \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@long.mp3"
# → only first 30 seconds transcribed, was_trimmed = true

# 5. Subscribe to pro
curl -X POST https://voice.neojeen.com/plans/subscribe \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"plan_id":2}'

# 6. Re-try the long clip
curl -X POST https://voice.neojeen.com/transcribe \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@long.mp3"
# → full transcription, was_trimmed = false
```

---

## 7. Reusable Patterns (For Prompt-Generating New Projects)

This backend is a **good template** for any "AI-as-a-service" SaaS. The reusable building blocks:

1. **JWT auth with roles** → `user` vs `admin`, both from the same endpoints
2. **Social login providers** → Google + Apple, normalized into the same `users` table
3. **Email OTP password reset** → 6-digit code, hashed, expiring
4. **Plan-gated quotas** → free vs paid, enforced at request time (here: max audio length; could be: max image size, max tokens, max calls/day)
5. **Auto-trim instead of reject** → friendlier UX than "file too big"; client gets `was_trimmed = true`
6. **Coupon system** → codes that grant a plan for N days with usage limits
7. **Rate limiting per IP** → slowapi with a single decorator
8. **Audit log table** → every paid action logged for analytics + admin dashboard
9. **Admin REST API** → stats, paginated lists, user management, coupon CRUD
10. **Health endpoint exposing model state** → `starting / loading / ready` so clients can show a spinner during cold-start

**The pattern in one sentence:**
> *"Wrap an AI model behind FastAPI, gate it with JWT + plan limits, log every call, expose an admin panel, deploy with Docker, and the mobile/web client just hits one endpoint with a file."*

Swap "Whisper transcribing audio" with any other model and you have:
- Image background remover
- PDF summarizer
- Image upscaler
- TTS service
- Translation API
- OCR service
- Music separator (vocals/drums/bass)
- Code reviewer

The auth, plans, coupons, admin, and quotas all stay the same — only the `/transcribe` endpoint changes to `/your-action` with a different model behind it.
