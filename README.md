# بصوتك - Bisawtak

Speech-to-Text API powered by OpenAI Whisper Large v3.

## Project Structure

```
sm3ne/
├── backend/          # FastAPI + Whisper API
│   ├── app/
│   │   ├── auth/     # JWT authentication
│   │   ├── core/     # Config, lifespan
│   │   ├── routes/   # API endpoints
│   │   └── services/ # Whisper & text analysis
│   ├── main.py
│   ├── Dockerfile
│   └── docker-compose.yml
├── mobile/           # Mobile app (coming soon)
└── README.md
```

## Quick Start

See [API Documentation](backend/API.md) for full details.
