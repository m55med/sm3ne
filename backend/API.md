# Bisawtak API Documentation

Base URL: `https://voice.neojeen.com`

## Authentication

All endpoints except `/auth/*` and `/` require authentication. Two schemes are supported:

1. **JWT Bearer** — for mobile/web clients. `Authorization: Bearer eyJhbGc...` (from `/auth/login`, expires after 24h).
2. **API key** — for server-to-server / bots. Either `X-API-Key: bsw_live_...` or `Authorization: Bearer bsw_live_...`. Long-lived, revocable, rate-limited per key. See the `/keys` section.

A request may use either scheme; `/transcribe` accepts both. All other protected endpoints (profile, plans, keys management) are JWT-only.

### Register

```
POST /auth/register
```

**Body:**
```json
{
  "username": "mohamed",
  "password": "mypassword123"
}
```

**Response (201):**
```json
{
  "message": "User created",
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```

**Errors:**
- `400` — Username < 3 chars or password < 6 chars
- `409` — Username already exists

---

### Login

```
POST /auth/login
```

**Body:**
```json
{
  "username": "mohamed",
  "password": "mypassword123"
}
```

**Response (200):**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```

**Errors:**
- `401` — Invalid username or password

---

## Endpoints

### Health Check

```
GET /
```

**Response:**
```json
{
  "status": "ready",
  "model": "large-v3"
}
```

Status values: `starting`, `loading`, `ready`

---

### Transcribe Audio

```
POST /transcribe
Authorization: Bearer <token>
```

**Request:** `multipart/form-data` with `file` field.

```bash
curl -X POST https://voice.neojeen.com/transcribe \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@audio.mp3"
```

**Supported formats:** mp3, wav, m4a, ogg, flac, webm, mp4, aac, wma

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
        {
          "word": "تم",
          "start": 0.0,
          "end": 0.26,
          "probability": 0.9845
        },
        {
          "word": "إلغاء",
          "start": 0.26,
          "end": 0.8,
          "probability": 0.9551
        },
        {
          "word": "الحجز",
          "start": 0.8,
          "end": 1.28,
          "probability": 0.8293
        }
      ]
    }
  ],
  "duration": 1.28,
  "punctuation_count": {
    "comma": 0,
    "period": 0,
    "question_mark": 0,
    "exclamation_mark": 0,
    "semicolon": 0,
    "colon": 0,
    "ellipsis": 0
  }
}
```

**Response Fields:**

| Field | Type | Description |
|---|---|---|
| `lang` | string | ISO language code (e.g. `ar`, `en`) |
| `lang_name` | string | Full language name |
| `text` | string | Full transcription |
| `char_count` | int | Total characters |
| `char_count_no_spaces` | int | Characters without spaces |
| `word_count` | int | Total words |
| `segment_count` | int | Number of segments |
| `segments` | array | Segments with timestamps |
| `segments[].words` | array | Word-level timestamps with probability |
| `duration` | float | Audio duration in seconds |
| `punctuation_count` | object | Count of punctuation marks |

**Errors:**
- `400` — Unsupported file type
- `401` — Missing or invalid token / API key
- `429` — Rate limit exceeded (per-minute) **or** daily quota exceeded. For daily quota, the `detail` is an object:
  ```json
  {"error": "daily_quota_exceeded", "limit": 20, "used": 20, "resets_at_utc": "2026-04-20T00:00:00+00:00"}
  ```
  Daily quotas reset at **UTC midnight**.
- `500` — Transcription failed

---

## API Keys

Long-lived credentials for bots, integrations, or server-to-server use. Each key has its own rate limit + daily quota (optional; falls back to the plan's defaults).

### Create Key
```
POST /keys
Authorization: Bearer <jwt>
```
**Body:** `{ "name": "n8n-waha-bot", "expires_at": null }`

**Response (201):**
```json
{
  "id": 1,
  "name": "n8n-waha-bot",
  "key": "bsw_live_Kq9pZ7xY2aBcDeFgHiJkLm",
  "key_prefix": "bsw_live_Kq9p",
  "expires_at": null,
  "created_at": "2026-04-19T12:00:00Z"
}
```
⚠️ The `key` field is shown **once only**. Store it securely — it cannot be recovered.

Errors:
- `409` — Max API keys reached for your plan.

### List Keys
```
GET /keys
Authorization: Bearer <jwt>
```
Returns array (never includes the plaintext `key`):
```json
[
  {
    "id": 1,
    "name": "n8n-waha-bot",
    "key_prefix": "bsw_live_Kq9p",
    "last_used_at": "2026-04-19T12:05:00Z",
    "expires_at": null,
    "is_active": true,
    "created_at": "2026-04-19T12:00:00Z",
    "requests_per_minute": null,
    "requests_per_day": null,
    "usage_today": 14,
    "daily_limit": 100
  }
]
```

### Update Key
```
PUT /keys/{id}
```
**Body:** `{ "name": "new-name", "is_active": true, "expires_at": "2027-01-01T00:00:00Z" }` (all optional)

Setting `requests_per_minute` or `requests_per_day` from the user endpoint returns `403` — those fields are admin-only.

### Revoke Key
```
DELETE /keys/{id}
```
Soft-deletes (`is_active=false`). The key stops working immediately.

### Use an API Key
Either header works:
```bash
# Preferred
curl -X POST https://voice.neojeen.com/transcribe \
  -H "X-API-Key: bsw_live_Kq9pZ7xY2aBcDeFgHiJkLm" \
  -F "file=@audio.mp3"

# Also works (same result)
curl -X POST https://voice.neojeen.com/transcribe \
  -H "Authorization: Bearer bsw_live_Kq9pZ7xY2aBcDeFgHiJkLm" \
  -F "file=@audio.mp3"
```

### Admin: Create Key for Any User (with custom limits)
```
POST /admin/keys
Authorization: Bearer <admin-jwt>
```
**Body:**
```json
{
  "user_id": 5,
  "name": "whatsapp-bot-prod",
  "requests_per_minute": 60,
  "requests_per_day": 10000,
  "expires_at": null
}
```
Response is the same as `POST /keys`. Admins can also `GET /admin/keys`, `PUT /admin/keys/{id}`, `DELETE /admin/keys/{id}`.

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `WHISPER_MODEL` | `large-v3` | Whisper model |
| `RATE_LIMIT` | `10/minute` | Max requests per IP |
| `WORKERS` | `3` | Concurrent transcription threads |
| `SECRET_KEY` | — | JWT signing key (change in production!) |
| `TOKEN_EXPIRE_MINUTES` | `1440` | Token expiry (default 24h) |

---

## Full Example

```bash
# 1. Register
curl -X POST https://voice.neojeen.com/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "mohamed", "password": "mypassword123"}'

# 2. Login (save token)
TOKEN=$(curl -s -X POST https://voice.neojeen.com/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "mohamed", "password": "mypassword123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# 3. Transcribe
curl -X POST https://voice.neojeen.com/transcribe \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@audio.mp3"
```
