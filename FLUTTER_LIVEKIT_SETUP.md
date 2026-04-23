# Lex Flutter + LiveKit Setup

## 1) Install backend dependencies

```bash
pip install -r requirements.txt
```

## 2) Start token server (for mobile/web token generation)

The token server uses **port 8080** by default (configurable via `TOKEN_SERVER_PORT` in `.env`).

```bash
python token_server.py
```

Or manually with uvicorn:

```bash
uvicorn token_server:app --host 0.0.0.0 --port 8080 --reload
```

Health check:

```bash
curl http://localhost:8080/health
```

Network diagnostics:

```bash
curl http://localhost:8080/network/info
```

## 3) Start LiveKit agent worker

```bash
python agent.py dev
```

## 4) Start Flutter app

```bash
cd lex_flutter_app
flutter pub get
flutter run --dart-define=LIVEKIT_URL=<your_livekit_wss_url> --dart-define=TOKEN_SERVER_URL=http://10.0.2.2:8080
```

Use `10.0.2.2` for Android emulator to reach backend on your local machine.
For a physical device, replace with your computer LAN IP (example: `http://192.168.1.25:8080`).

## 5) Platform notes

- Android and iOS microphone permissions are already configured in:
  - `lex_flutter_app/android/app/src/main/AndroidManifest.xml`
  - `lex_flutter_app/ios/Runner/Info.plist`
- If Windows shows plugin/symlink warnings during Flutter commands, enable Developer Mode:

```bash
start ms-settings:developers
```

## 6) Network Troubleshooting

### Standard Port

The Lex system uses **port 8080** across all components. This is enforced in:
- `TOKEN_SERVER_PORT=8080` in `.env`
- `NetworkConfig.standardPort` in Flutter (`lib/services/network_config.dart`)

### The app says "Server unreachable"

1. Verify the token server is running: `curl http://localhost:8080/health`
2. Check the diagnostics endpoint: `curl http://localhost:8080/network/info`
3. On a **physical Android device**, use your computer's LAN IP instead of `localhost`:
   - Find your IP: `ipconfig` (Windows) or `ifconfig` / `ip addr` (Linux/Mac)
   - Example: `http://192.168.1.25:8080`
4. On an **Android emulator**, the app auto-detects and uses `10.0.2.2:8080`
5. Make sure your phone and computer are on the **same WiFi network**

### Different network connections

The Flutter app now:
- Runs a **health check** (`GET /health`) before attempting to connect
- **Retries** up to 3 times with exponential backoff on transient errors
- **Persists** the last working server URL (survives app restarts)
- Shows **platform-specific diagnostic hints** in error messages
