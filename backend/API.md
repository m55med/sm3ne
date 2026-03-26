# Bisawtak API Documentation

Base URL: `https://voice.neojeen.com`

## Authentication

All endpoints except `/auth/*` and `/` require a Bearer token.

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
- `401` — Missing or invalid token
- `429` — Rate limit exceeded (default: 10/minute per IP)
- `500` — Transcription failed

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
