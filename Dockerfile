FROM python:3.12-slim

WORKDIR /app

COPY requirements-server.txt .
RUN pip install --no-cache-dir -r requirements-server.txt

# Copy server files (do NOT copy .env — secrets come from Render env vars)
COPY token_server.py .

EXPOSE 8080

# Render sets $PORT automatically; fall back to 8080 for local Docker runs
CMD gunicorn token_server:app --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:${PORT:-8080}
