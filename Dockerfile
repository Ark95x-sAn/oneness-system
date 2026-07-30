
FROM python:3.11-slim

WORKDIR /app

# Install system deps for some Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY config/ ./config/
COPY memory/ ./memory/

# Healthcheck: ensure orchestrator process is alive
HEALTHCHECK --interval=30s --timeout=5s CMD pgrep -f "python.*oneness_orchestrator" || exit 1

CMD ["python", "-m", "src.oneness_orchestrator"]
