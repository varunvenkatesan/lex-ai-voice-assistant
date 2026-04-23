import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NetworkConfig — single source of truth for all Lex server connectivity
// ─────────────────────────────────────────────────────────────────────────────
//
// Centralises URL resolution, port standardisation, platform-aware defaults,
// health-checking, and retry logic.  Every HTTP call from the Flutter app
// (token fetch, chat stream, vision analyse) should route through this service
// so that network behaviour is consistent regardless of which WiFi / mobile
// network the device is connected to.
// ─────────────────────────────────────────────────────────────────────────────

class NetworkConfig {
  NetworkConfig._();

  static final NetworkConfig instance = NetworkConfig._();

  // ─── Standard port ───
  /// The canonical port that the Lex token server listens on.
  /// Both the Python backend and the Flutter client agree on this value.
  static const int standardPort = 8080;

  // ─── Deployed cloud URL ───
  // When the token server is deployed to a cloud service (Render, Railway,
  // Fly.io, etc.), set this URL so the app can reach it from ANY network.
  // Leave empty to use local-only mode (LAN / emulator).
  //
  // To set this, either:
  //   1. Change the constant below to your deployed URL, OR
  //   2. Pass it at build time: flutter run --dart-define=TOKEN_SERVER_URL=https://your-server.onrender.com
  static const String _deployedServerUrl = String.fromEnvironment(
    'DEPLOYED_SERVER_URL',
    defaultValue: '', // ← Set your deployed URL here after deploying
  );

  // ─── Preference keys ───
  static const String _prefTokenServerUrl = 'lex_token_server_url';
  static const String _prefLiveKitUrl = 'lex_livekit_url';

  // ─── Compile-time overrides (--dart-define) ───
  static const String _envLiveKitUrl = String.fromEnvironment(
    'LIVEKIT_URL',
    defaultValue: 'wss://aivirtualvoiceassistants-bk7zw6uy.livekit.cloud',
  );
  static const String _envTokenServerUrl = String.fromEnvironment(
    'TOKEN_SERVER_URL',
    defaultValue: '', // empty ⇒ use smart auto-detection
  );

  // ─── Timeouts ───
  static const Duration healthCheckTimeout = Duration(seconds: 5);
  static const Duration tokenRequestTimeout = Duration(seconds: 12);

  // ─── Retry settings ───
  static const int maxRetries = 3;
  static const Duration _retryBaseDelay = Duration(seconds: 2);

  // ─── Cached prefs ───
  SharedPreferences? _prefs;

  /// Initialise the service.  Safe to call multiple times.
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // URL resolution — priority: user override → compile-time → deployed → local
  // ═══════════════════════════════════════════════════════════════════════════

  /// The LiveKit WebSocket URL to connect to.
  String get liveKitUrl {
    // 1. Persisted user override
    final saved = _prefs?.getString(_prefLiveKitUrl);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    // 2. Compile-time override
    if (_envLiveKitUrl.isNotEmpty) return _envLiveKitUrl;
    // 3. Hardcoded cloud default
    return 'wss://aivirtualvoiceassistants-bk7zw6uy.livekit.cloud';
  }

  /// The token-server base URL (no trailing slash).
  ///
  /// Resolution order:
  ///   1. User-persisted override (from SharedPreferences)
  ///   2. Compile-time `TOKEN_SERVER_URL` (from --dart-define)
  ///   3. Deployed cloud URL (if configured)
  ///   4. Platform-aware local default (emulator / localhost)
  String get tokenServerUrl {
    // 1. Persisted user override
    final saved = _prefs?.getString(_prefTokenServerUrl);
    if (saved != null && saved.trim().isNotEmpty) {
      return normalizeBaseUrl(saved.trim());
    }
    // 2. Compile-time override
    if (_envTokenServerUrl.isNotEmpty) {
      return normalizeBaseUrl(_envTokenServerUrl);
    }
    // 3. Deployed cloud URL (works on ANY network)
    if (_deployedServerUrl.isNotEmpty) {
      return _deployedServerUrl.trim();
    }
    // 4. Platform-aware local default
    return defaultServerUrl;
  }

  /// Whether a deployed cloud URL is configured.
  static bool get hasDeployedUrl => _deployedServerUrl.isNotEmpty;

  /// Platform-aware local-only default URL (emulator / localhost).
  static String get defaultServerUrl {
    if (kIsWeb) return 'http://localhost:$standardPort';
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:$standardPort';
      }
      if (Platform.isIOS) {
        return 'http://localhost:$standardPort';
      }
    } catch (_) {
      // Platform check can throw on some environments (web / desktop).
    }
    return 'http://localhost:$standardPort';
  }

  /// Try the deployed URL first; if unreachable, fall back to local.
  /// Returns the first reachable server URL, or the deployed URL if both fail.
  Future<String> resolveServerUrl() async {
    // If user has a persisted override, use that directly.
    final saved = _prefs?.getString(_prefTokenServerUrl);
    if (saved != null && saved.trim().isNotEmpty) {
      return normalizeBaseUrl(saved.trim());
    }

    // If compile-time override is set, use that directly.
    if (_envTokenServerUrl.isNotEmpty) {
      return normalizeBaseUrl(_envTokenServerUrl);
    }

    // Try deployed URL first (works on ANY network).
    if (_deployedServerUrl.isNotEmpty) {
      if (await isServerReachable(_deployedServerUrl.trim())) {
        return _deployedServerUrl.trim();
      }
      debugPrint('[NetworkConfig] Deployed URL unreachable, trying local...');
    }

    // Fall back to local.
    final localUrl = defaultServerUrl;
    if (await isServerReachable(localUrl)) {
      return localUrl;
    }

    // Nothing reachable — return the best candidate for the error message.
    return _deployedServerUrl.isNotEmpty
        ? _deployedServerUrl.trim()
        : localUrl;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Persistence
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save a custom token-server URL.  Called after a successful connection so
  /// the working URL survives app restarts.
  Future<void> saveTokenServerUrl(String url) async {
    await initialize();
    await _prefs?.setString(_prefTokenServerUrl, normalizeBaseUrl(url));
  }

  /// Save a custom LiveKit WSS URL.
  Future<void> saveLiveKitUrl(String url) async {
    await initialize();
    await _prefs?.setString(_prefLiveKitUrl, url.trim());
  }

  /// Clear any persisted overrides (reset to defaults).
  Future<void> clearPersistedUrls() async {
    await initialize();
    await _prefs?.remove(_prefTokenServerUrl);
    await _prefs?.remove(_prefLiveKitUrl);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Health check
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns `true` if the token server at [baseUrl] is reachable.
  Future<bool> isServerReachable(String baseUrl) async {
    final url = '${normalizeBaseUrl(baseUrl)}/health';
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(healthCheckTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Perform a health check with retry.  Returns `true` on first success.
  Future<bool> isServerReachableWithRetry(
    String baseUrl, {
    int retries = 2,
  }) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      if (await isServerReachable(baseUrl)) return true;
      if (attempt < retries) {
        await Future.delayed(_retryBaseDelay * (attempt + 1));
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Retry helper
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute [action] up to [maxRetries] times with exponential backoff.
  /// Only retries on transient/network errors (timeout, socket, connection
  /// refused).  Non-transient errors (4xx, auth) are rethrown immediately.
  static Future<T> withRetry<T>(
    Future<T> Function() action, {
    int retries = maxRetries,
    bool Function(Object error)? shouldRetry,
  }) async {
    final retryCheck = shouldRetry ?? isTransientError;
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        return await action();
      } catch (error) {
        if (attempt == retries || !retryCheck(error)) rethrow;
        final delay = _retryBaseDelay * attempt; // 2s, 4s, 6s
        debugPrint(
          '[NetworkConfig] Attempt $attempt failed, retrying in '
          '${delay.inSeconds}s: $error',
        );
        await Future.delayed(delay);
      }
    }
    // Unreachable — the loop always returns or rethrows.
    throw StateError('withRetry exhausted without result');
  }

  static bool isTransientError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('connection timed out') ||
        message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable') ||
        message.contains('timeoutexception') ||
        message.contains('timed out') ||
        error is TimeoutException ||
        error is SocketException;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // URL helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Normalise a base URL: trim whitespace, strip trailing slashes, ensure
  /// a scheme is present, and ensure the standard port is appended when
  /// no port is specified.
  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    // Strip trailing slashes.
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    // Default to http if no scheme.
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    // Append standard port if missing — but only for local (http) URLs.
    // Cloud deployments (https) handle port routing automatically.
    final uri = Uri.tryParse(url);
    if (uri != null && !uri.hasPort && uri.scheme != 'https') {
      url = '${uri.scheme}://${uri.host}:$standardPort';
      if (uri.path.isNotEmpty && uri.path != '/') {
        url += uri.path;
      }
    }
    return url;
  }

  /// Build the Android-emulator equivalent of a base URL by replacing the
  /// host with `10.0.2.2` (which maps to the host machine's localhost).
  static String withAndroidEmulatorHost(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return baseUrl;
    final port = uri.hasPort ? ':${uri.port}' : ':$standardPort';
    return '${uri.scheme}://10.0.2.2$port';
  }

  /// Returns `true` for localhost / 127.0.0.1.
  static bool isLocalhostHost(String host) {
    return host == 'localhost' || host == '127.0.0.1';
  }

  /// Returns `true` for Android emulator loopback IPs.
  static bool isEmulatorLoopbackHost(String host) {
    return host == '10.0.2.2' || host == '10.0.3.2';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Diagnostics
  // ═══════════════════════════════════════════════════════════════════════════

  /// Human-readable connection hint for the current platform.
  static String platformConnectionHint() {
    if (hasDeployedUrl) {
      return 'The app will connect to the deployed cloud server. '
          'If the server is down, check your deployment dashboard.';
    }
    if (kIsWeb) {
      return 'Token Server must be reachable from your browser. '
          'For cross-network support, deploy the token server to the cloud.';
    }
    try {
      if (Platform.isAndroid) {
        return 'Android emulator: use http://10.0.2.2:$standardPort. '
            'Physical device on same WiFi: use your computer\'s LAN IP '
            '(example: http://192.168.1.25:$standardPort). '
            'For any network: deploy the token server to the cloud.';
      }
      if (Platform.isIOS) {
        return 'iOS simulator: use http://localhost:$standardPort. '
            'iPhone on same WiFi: use your computer\'s LAN IP. '
            'For any network: deploy the token server to the cloud.';
      }
    } catch (_) {}
    return 'Use the backend URL reachable from this device. '
        'For any network: deploy the token server to the cloud.';
  }

  /// Build a user-friendly error message when the server is unreachable.
  static String unreachableHint(String serverUrl) {
    return 'Could not reach the Lex server at $serverUrl.\n\n'
        '${platformConnectionHint()}\n\n'
        'Make sure the token server is running:\n'
        '  python token_server.py';
  }
}
