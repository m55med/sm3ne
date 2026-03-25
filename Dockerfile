FROM python:3.11-slim

# Install ffmpeg (required by whisper)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Pre-download model at build time (optional, remove if image size is a concern)
# RUN python -c "import whisper; whisper.load_model('large-v3')"

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
