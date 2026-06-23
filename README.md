# بصوتك - Bisawtak

Speech-to-Text API powered by external ASR providers (Speechmatics, Google Gemini, Groq, AssemblyAI) with automatic failover.

## Project Structure

```
sm3ne/
├── backend/          # FastAPI transcription API
│   ├── app/
│   │   ├── auth/     # JWT authentication
│   │   ├── core/     # Config, lifespan
│   │   ├── routes/   # API endpoints
│   │   └── services/ # ASR providers & text analysis
│   ├── main.py
│   ├── Dockerfile
│   └── docker-compose.yml
├── mobile/           # Mobile app (coming soon)
└── README.md
```

## Quick Start

See [API Documentation](backend/API.md) for full details.
