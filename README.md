# Lex AI Anime Personal Assistant

Lex AI Anime Personal Assistant is an AI voice assistant project with a Flutter client, LiveKit-powered realtime voice, anime-style Live2D companions, a FastAPI token/chat server, and optional memory support through Mem0. The backend is ready for Render deployment and is configured to keep runtime secrets outside the repository.


## Screenshots

<table>
  <tr>
    <td align="center"><img width="220" alt="Lex app screenshot 1" src="https://github.com/user-attachments/assets/56b5e10c-3b60-4b44-a9fa-d90914fc41d9" /></td>
    <td align="center"><img width="220" alt="Lex app screenshot 2" src="https://github.com/user-attachments/assets/eecbad29-216a-472a-89eb-bd1e4144a52e" /></td>
    <td align="center"><img width="220" alt="Lex app screenshot 3" src="https://github.com/user-attachments/assets/38311eba-4768-41b2-853f-5427e43ec9af" /></td>
  </tr>
  <tr>
    <td align="center"><img width="220" alt="Lex app screenshot 4" src="https://github.com/user-attachments/assets/19546b9e-f2ec-49c5-b2ca-49e57118bd04" /></td>
    <td align="center"><img width="220" alt="Lex app screenshot 5" src="https://github.com/user-attachments/assets/ac63082f-51ad-4d1c-9997-8a61b9d1f597" /></td>
    <td align="center"><img width="220" alt="Lex app screenshot 6" src="https://github.com/user-attachments/assets/bc1ab39c-87dc-4fcd-8627-4e9959f412bb" /></td>
  </tr>
  <tr>
    <td align="center"><img width="220" alt="Lex app screenshot 7" src="https://github.com/user-attachments/assets/65dca8b9-2611-46c0-941f-6411e1203998" /></td>
     <td align="center"><img width="220" alt="Lex app screenshot 8" src="https://github.com/user-attachments/assets/595504a3-0d66-4ccd-a17c-4ca196392797" /></td>
    <td align="center"><img width="220" alt="Lex app screenshot 9" src="https://github.com/user-attachments/assets/9d8299c4-acaf-4a69-8804-1d145c73627b" /></td>
  </tr>
</table>


## Features

- Realtime AI voice sessions through LiveKit.
- Flutter client with Live2D avatar assets.
- Switchable Live2D companions, including March 7th and IceGirl.
- FastAPI backend for LiveKit token creation, chat streaming, health checks, and vision analysis.
- Google Gemini configuration for realtime and text responses.
- Optional Mem0 memory integration.
- Render Blueprint deployment support.




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


## Live2D Character System

Lex uses Live2D characters as the visual companion inside the Flutter app. The current companion registry includes March 7th as the default character and IceGirl as an alternate model. Each character has its own model JSON path, poster image, expression IDs, motion groups, screen position, scale, and optional hidden part overrides.

The Flutter layer controls which model is active and when the character should react. The native layer renders the actual Cubism model:

- `lex_flutter_app/lib/model_config.dart` registers each companion and stores model paths, expressions, motion groups, position, scale, and hidden parts.
- `lex_flutter_app/lib/live2d_view.dart` creates the platform Live2D view and exposes controller methods such as `live2dSetModelJsonPath`, `live2dStartMotion`, `live2dStartExpression`, `live2dSetLipSync`, and `live2dSetParameterOverride`.
- `lex_flutter_app/lib/animation_config.dart` defines animation triggers such as idle, AI speaking, user speaking, thinking, emotion, and interaction.
- `lex_flutter_app/lib/animation_controller.dart` reads the animation configuration and drives Live2D parameters through the controller.
- `lex_flutter_app/lib/main.dart` connects assistant state, LiveKit audio state, speech state, and UI events to the Live2D animation controller.
- `lex_flutter_app/ios/PPLive2D/` contains the iOS Live2D/Cubism rendering bridge.
- `lex_flutter_app/android/src/main/java/com/live2d/` and `lex_flutter_app/android/build.gradle` contain the Android Cubism integration.

Live2D assets are bundled through `lex_flutter_app/pubspec.yaml`:

```yaml
assets:
  - assets/model/
  - assets/model/exp/
  - assets/model/motions/
  - assets/model/March 7th.4096/
  - assets/model_2/IceGirl Live2D/
  - assets/model_2/IceGirl Live2D/IceGirl.8192/
```

To add or adjust a character, place the exported Live2D files under `lex_flutter_app/assets/`, add the asset folders to `pubspec.yaml`, then register the model in `CompanionRegistry` inside `model_config.dart`. Match the expression names and motion group names to the character's `.model3.json` file. If the model appears too large or off-screen, tune `offsetX`, `offsetY`, and `scale` in the model transform at the top of `model_config.dart`.

## How I Work On This Project

The project is split into three main areas:

- Backend work happens in `token_server.py`, `agent.py`, `requirements-server.txt`, `.env.example`, and `render.yaml`.
- Flutter app work happens in `lex_flutter_app/lib/`, especially `main.dart`, `screens/`, `services/`, `model_config.dart`, and the Live2D animation files.
- Native Live2D work happens in `lex_flutter_app/ios/PPLive2D/`, `lex_flutter_app/ios/Classes/`, and the Android Cubism files under `lex_flutter_app/android/`.

For backend changes, run the FastAPI server locally and verify `/health` before deploying to Render:

```bash
uvicorn token_server:app --reload --host 0.0.0.0 --port 8080
```

For Flutter changes, run the app from `lex_flutter_app`:

```bash
flutter pub get
flutter run --dart-define=TOKEN_SERVER_URL=http://localhost:8080
```

For Android emulator testing, use:

```bash
flutter run --dart-define=TOKEN_SERVER_URL=http://10.0.2.2:8080
```

For Live2D character work, the usual loop is:

1. Add or update model assets in `lex_flutter_app/assets/`.
2. Register asset folders in `pubspec.yaml`.
3. Configure the character in `model_config.dart`.
4. Map motions and expressions in `animation_config.dart`.
5. Run the Flutter app and test idle, listening, speaking, and switching states.
6. Tune position, scale, mouth movement, expressions, and hidden parts until the character feels natural.

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
