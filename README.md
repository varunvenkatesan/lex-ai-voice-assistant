# Lex AI Voice Assistant

Lex is an AI voice assistant project with a Flutter client, LiveKit-powered realtime voice, a FastAPI token/chat server, and optional memory support through Mem0. The backend is ready for Render deployment and is configured to keep runtime secrets outside the repository.

## Project Structure

```text
.
+-- agent.py                  # LiveKit agent worker
+-- token_server.py           # FastAPI token, chat, health, and utility API
+-- render.yaml               # Render Blueprint for the token server
+-- Dockerfile                # Container entrypoint for the backend
+-- requirements-server.txt   # Minimal backend deployment dependencies
+-- requirements.txt          # Full local agent/backend dependencies
+-- lex_flutter_app/          # Flutter app/plugin and Live2D assets
+-- supabase/                 # Supabase project files
+-- .env.example              # Environment variable template
```

## Features

- Realtime AI voice sessions through LiveKit.
- Flutter client with Live2D avatar assets.
- FastAPI backend for LiveKit token creation, chat streaming, health checks, and vision analysis.
- Google Gemini configuration for realtime and text responses.
- Optional Mem0 memory integration.
- Render Blueprint deployment support.

## Backend Setup

1. Create a virtual environment and install dependencies:

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements-server.txt
```

On Windows PowerShell:

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements-server.txt
```

2. Copy the environment template:

```bash
cp .env.example .env
```

3. Fill in the required values in `.env`:

```text
LIVEKIT_URL=
LIVEKIT_API_KEY=
LIVEKIT_API_SECRET=
GOOGLE_API_KEY=
```

4. Run the token server locally:

```bash
uvicorn token_server:app --reload --host 0.0.0.0 --port 8080
```

5. Check the server:

```bash
curl http://localhost:8080/health
```

## Render Deployment

This repository includes `render.yaml` for Blueprint deployment.

1. Create a new Render Blueprint from this repository.
2. Set the environment variables requested by `render.yaml`.
3. Deploy the `lex-token-server` web service.

Secrets such as API keys, LiveKit credentials, Gmail app passwords, and Mem0 keys should be configured in Render environment variables only. Do not commit `.env`.

## Flutter App

```bash
cd lex_flutter_app
flutter pub get
flutter run --dart-define=TOKEN_SERVER_URL=http://localhost:8080
```

For Android emulators, use `http://10.0.2.2:8080` instead of `localhost`.

## Public Repository Checklist

- `.env` is ignored and should stay local.
- Runtime logs and logcat dumps are ignored.
- GitHub tokens should never be embedded in remote URLs.
- Rotate any token that was previously copied into Git config or shared with another service.
- Review third-party model, asset, and SDK licenses before publishing publicly.

## License

No open-source license has been selected yet. Public visibility does not grant reuse rights unless a license is added.
