import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_plugin2/live2d_view.dart';
import 'package:flutter_plugin2/animation_controller.dart';
import 'package:flutter_plugin2/animation_config.dart';
import 'package:flutter_plugin2/models/chat_models.dart';
import 'package:flutter_plugin2/models/reminder_models.dart';
import 'package:flutter_plugin2/model_config.dart';
import 'package:flutter_plugin2/services/network_config.dart';
import 'package:flutter_plugin2/services/reminder_service.dart';
import 'package:flutter_plugin2/services/supabase_service.dart';
import 'package:flutter_plugin2/welcome_screen.dart';
import 'package:flutter_plugin2/widgets/sidebar_drawer.dart';
import 'package:flutter_plugin2/screens/settings_screen.dart';
import 'package:flutter_plugin2/screens/chat_screen.dart';
import 'package:flutter_plugin2/screens/reminder_overlay_screen.dart';
import 'package:flutter_plugin2/screens/reminders_screen.dart';
import 'package:flutter_plugin2/screens/splash_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config — URLs and ports are resolved via NetworkConfig (single source of
// truth).  The constants below are only used as initial controller values
// before NetworkConfig.initialize() completes.
// ─────────────────────────────────────────────────────────────────────────────
const bool _wakeWordEnabled = false;

const String _bgAsset =
    'packages/flutter_plugin2/assets/background/backgrund VA .png';

// ─────────────────────────────────────────────────────────────────────────────
// Animation state enum — defined in animation_controller.dart
// Re-exported here for convenience in UI code.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Entry
// ─────────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  try {
    await lk.LiveKitClient.initialize(bypassVoiceProcessing: false);
  } catch (_) {}
  final defaultRouteName =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  final overlayReminder =
      ReminderOverlayScreen.reminderFromRoute(defaultRouteName);

  if (overlayReminder != null) {
    await SupabaseService.initialize();
    final home = await _buildAppHome();
    runApp(
      LexApp(
        home: ReminderOverlayScreen(
          reminder: overlayReminder,
          homeBuilder: (_) => home,
        ),
      ),
    );
    return;
  }

  runApp(
    LexApp(
      home: SplashScreen(
        destinationFuture: _buildAppHome(),
      ),
    ),
  );
}

Future<Widget> _buildAppHome() async {
  await SupabaseService.initialize();
  String? fullName;
  if (SupabaseService.isLoggedIn) {
    fullName = await SupabaseService.currentUserFullName();
  }

  if (SupabaseService.isLoggedIn) {
    return LexHomePage(userName: fullName ?? 'Guest');
  }

  return const WelcomeScreen();
}

class LexApp extends StatelessWidget {
  const LexApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LEX Assistant',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: GoogleFonts.manrope().fontFamily,
        textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme),
      ),
      home: home,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────────────
class _Transcript {
  const _Transcript({
    required this.role,
    required this.text,
    required this.time,
  });
  final String role;
  final String text;
  final DateTime time;
}

enum _AssistantPopupMode {
  none,
  conversation,
  reminder,
}

// ═════════════════════════════════════════════════════════════════════════════
// Main screen
// ═════════════════════════════════════════════════════════════════════════════
class LexHomePage extends StatefulWidget {
  const LexHomePage({super.key, this.userName = 'Guest'});

  /// The logged-in user's display name (used for AI greeting).
  final String userName;

  @override
  State<LexHomePage> createState() => _LexHomePageState();
}

class _LexHomePageState extends State<LexHomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Text controllers ──
  final TextEditingController _roomController = TextEditingController(
    text: 'lex-room',
  );
  late final TextEditingController _nameController = TextEditingController(
    text: widget.userName,
  );
  // Initialised with platform-aware defaults; updated after
  // NetworkConfig.initialize() resolves any persisted user overrides.
  late final TextEditingController _liveKitController = TextEditingController(
    text: NetworkConfig.instance.liveKitUrl,
  );
  late final TextEditingController _serverController = TextEditingController(
    text: NetworkConfig.instance.tokenServerUrl,
  );

  // ── LiveKit ──
  final lk.Room _room = lk.Room();
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  final FlutterTts _tts = FlutterTts();
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  final List<_Transcript> _transcript = [];
  final Map<String, DateTime> _recentVoiceReminderCommands = {};
  ReminderDraft? _pendingVoiceReminderDraft;
  DateTime? _pendingVoiceReminderCapturedAt;
  String? _currentChatSessionId;
  String? _currentTalkSessionId;
  bool _talkSessionSawUserMessage = false;
  bool _talkSessionHasAssistantTitle = false;

  bool _isConnecting = false;
  bool _micLive = false;

  String _status = 'Idle';
  String _lastError = '';
  String _identity = '';
  double _speechRate = 0.45;

  // ── Live2D ──
  bool _audioPlaybackActive = false;
  Timer? _remoteAudioLevelPollTimer;
  lk.AudioVisualizer? _remoteAudioVisualizer;
  lk.EventsListener<lk.AudioVisualizerEvent>? _remoteAudioVisualizerListener;
  String? _remoteAudioVisualizerTrackKey;
  Future<void>? _remoteAudioAmplitudeSetupFuture;
  Future<void>? _remoteAudioVisualizerDisposeFuture;

  // ── Current companion model ──
  CompanionModel _currentModel = CompanionRegistry.defaultModel;
  late ModelAnimationSet _currentAnimSet =
      AnimationConfig.forModel(_currentModel);

  // ── Animation controller (see animation_controller.dart) ──
  CharacterAnimationController? _animController;
  CharacterAnimState _animState = CharacterAnimState.idle;

  // ── UI mode ──
  bool _isTalkMode = true;
  bool _speakerOn = true;
  bool _showSettings =
      false; // state-based Settings rendering (avoids route compositing)
  bool _showChat = false; // state-based Chat rendering (avoids Live2D overlap)
  bool _showReminders = false;

  // ── Live2D delayed rendering ──
  // Prevents the native GL surface from being created immediately, which
  // causes bleed-through during route transitions (e.g. Login → Home overlap).
  bool _live2dReady = false;
  Timer? _live2dDelayTimer;

  // ── Live2D view controller reference (for hideView before dispose) ──
  Live2dViewController? _live2dCtrl;
  final AssetImage _talkBackgroundImage = const AssetImage(_bgAsset);
  Future<void>? _backgroundWarmupFuture;
  int _backgroundLayerVersion = 0;
  StreamSubscription<ReminderItem>? _reminderSubscription;
  Timer? _wakeWordRestartTimer;
  bool _wakeWordAvailable = false;
  bool _wakeWordListening = false;
  bool _wakeWordDetectedForCurrentListen = false;
  _AssistantPopupMode _assistantPopupMode = _AssistantPopupMode.none;
  ReminderItem? _activeReminder;

  bool get _isConnected =>
      _room.connectionState == lk.ConnectionState.connected;

  // ── Animation controllers ──
  late AnimationController _micPulseController;
  late AnimationController _stateGlowController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _stateGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Initialise NetworkConfig early so persisted URLs are available.
    unawaited(_initNetworkConfig());

    // Briefly delay Live2D creation so route transitions can settle.
    _startLive2dDelayTimer();
    _setupTts();
    _bindRoomEvents();
    unawaited(_initializeReminderService());
    if (_wakeWordEnabled) {
      unawaited(_initializeWakeWordListener());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleBackgroundWarmup();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_backgroundWarmupFuture == null) {
      _scheduleBackgroundWarmup();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live2dDelayTimer?.cancel();
    _remoteAudioLevelPollTimer?.cancel();
    unawaited(_disposeRemoteAudioVisualizer());
    _live2dCtrl?.hideView();
    _live2dCtrl = null;
    _animController?.dispose();
    _reminderSubscription?.cancel();
    _wakeWordRestartTimer?.cancel();
    _speechToText.stop();
    _micPulseController.dispose();
    _stateGlowController.dispose();
    _roomListener?.dispose();
    _room.dispose();
    _tts.stop();
    _roomController.dispose();
    _nameController.dispose();
    _liveKitController.dispose();
    _serverController.dispose();

    super.dispose();
  }

  // ── App lifecycle: re-precache background when returning from background ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _restoreTalkPresentation(forceBackgroundRefresh: true);
      if (_wakeWordEnabled) {
        unawaited(_startWakeWordListening());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_wakeWordEnabled) {
        unawaited(_stopWakeWordListening());
      }
    }
  }

  void _scheduleBackgroundWarmup({bool forceRefresh = false}) {
    _backgroundWarmupFuture = _warmBackgroundImage(forceRefresh: forceRefresh);
  }

  Future<void> _warmBackgroundImage({bool forceRefresh = false}) async {
    if (!mounted) return;

    try {
      if (forceRefresh) {
        await _talkBackgroundImage.evict();
      }
      await precacheImage(_talkBackgroundImage, context);
      if (!mounted) return;
      setState(() {
        _backgroundLayerVersion++;
      });
    } catch (e) {
      debugPrint('[LEX] Background warmup failed: $e');
    }
  }

  void _restoreTalkPresentation({bool forceBackgroundRefresh = false}) {
    if (forceBackgroundRefresh) {
      _scheduleBackgroundWarmup(forceRefresh: true);
    } else {
      _scheduleBackgroundWarmup();
    }

    _live2dCtrl?.live2dSetBackgroundPath(_bgAsset);
    _live2dCtrl?.hideView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showChat || _showSettings) return;
      _live2dCtrl?.live2dSetBackgroundPath(_bgAsset);
      _live2dCtrl?.showView();
      if (!_live2dReady) {
        _startLive2dDelayTimer();
      }
    });
  }

  Future<void> _initializeReminderService() async {
    await ReminderService.instance.initialize();
    _reminderSubscription?.cancel();
    _reminderSubscription =
        ReminderService.instance.triggeredReminders.listen((reminder) {
      ReminderService.instance.clearPendingTriggeredReminder(reminder.id);
      unawaited(_onReminderTriggered(reminder));
    });
    final pendingReminder =
        ReminderService.instance.takePendingTriggeredReminder();
    if (pendingReminder != null) {
      unawaited(_onReminderTriggered(pendingReminder));
    }
  }

  Future<void> _initializeWakeWordListener() async {
    try {
      final available = await _speechToText.initialize(
        onStatus: _handleWakeWordStatus,
        onError: (_) {
          _wakeWordListening = false;
          _scheduleWakeWordRestart();
        },
      );
      if (!mounted) return;
      setState(() {
        _wakeWordAvailable = available;
      });
      if (available) {
        await _startWakeWordListening();
      }
    } catch (error) {
      debugPrint('[LEX] Wake word init failed: $error');
    }
  }

  bool get _shouldKeepWakeWordListening =>
      mounted &&
      _wakeWordEnabled &&
      _wakeWordAvailable &&
      !_isConnected &&
      !_isConnecting &&
      !_showSettings;

  Future<void> _startWakeWordListening() async {
    if (!_shouldKeepWakeWordListening ||
        _wakeWordListening ||
        _speechToText.isListening) {
      return;
    }

    final micPermission = await Permission.microphone.request();
    if (!micPermission.isGranted) {
      return;
    }

    _wakeWordDetectedForCurrentListen = false;
    _wakeWordListening = true;
    await _speechToText.listen(
      onResult: (result) {
        final heard = result.recognizedWords.toLowerCase();
        if (_wakeWordDetectedForCurrentListen) return;
        if (heard.contains('hey lex') ||
            heard.contains('hi lex') ||
            heard.contains('hey leks')) {
          _wakeWordDetectedForCurrentListen = true;
          unawaited(_handleWakeWordDetected());
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_IN',
    );
  }

  Future<void> _stopWakeWordListening() async {
    _wakeWordRestartTimer?.cancel();
    _wakeWordListening = false;
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
  }

  void _handleWakeWordStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _wakeWordListening = false;
      _scheduleWakeWordRestart();
    } else if (status == 'listening') {
      _wakeWordListening = true;
    }
  }

  void _scheduleWakeWordRestart() {
    if (!_shouldKeepWakeWordListening) return;
    _wakeWordRestartTimer?.cancel();
    _wakeWordRestartTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_startWakeWordListening()),
    );
  }

  Future<void> _handleWakeWordDetected() async {
    await _stopWakeWordListening();
    if (!mounted) return;

    setState(() {
      _showChat = false;
      _showSettings = false;
      _showReminders = false;
      _isTalkMode = true;
      _assistantPopupMode = _AssistantPopupMode.conversation;
      _activeReminder = null;
    });
    _restoreTalkPresentation(forceBackgroundRefresh: true);
    _showInfoSnackbar('Press the mic button to start talking to Lex.');
  }

  void _capturePendingVoiceReminder(String text) {
    final draft = ReminderParser.parseVoiceCommand(
      text,
      source: ReminderItem.talkSource,
    );
    if (draft == null) return;

    _pendingVoiceReminderDraft = draft;
    _pendingVoiceReminderCapturedAt = DateTime.now();
  }

  ReminderDraft? _freshPendingVoiceReminderDraft() {
    final draft = _pendingVoiceReminderDraft;
    final capturedAt = _pendingVoiceReminderCapturedAt;
    if (draft == null || capturedAt == null) {
      return null;
    }
    if (DateTime.now().difference(capturedAt) > const Duration(minutes: 2)) {
      _pendingVoiceReminderDraft = null;
      _pendingVoiceReminderCapturedAt = null;
      return null;
    }
    return draft;
  }

  void _clearPendingVoiceReminderDraft() {
    _pendingVoiceReminderDraft = null;
    _pendingVoiceReminderCapturedAt = null;
  }

  Future<void> _scheduleReminderFromAssistantReply(String text) async {
    final draft = ReminderParser.parseAssistantReply(
      text,
      source: ReminderItem.talkSource,
      fallbackDraft: _freshPendingVoiceReminderDraft(),
    );
    if (draft == null) return;

    final normalizedCommand =
        text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final now = DateTime.now();
    _recentVoiceReminderCommands.removeWhere(
      (_, timestamp) => now.difference(timestamp) > const Duration(seconds: 15),
    );
    final previousTimestamp = _recentVoiceReminderCommands[normalizedCommand];
    if (previousTimestamp != null &&
        now.difference(previousTimestamp) < const Duration(seconds: 15)) {
      return;
    }
    _recentVoiceReminderCommands[normalizedCommand] = now;

    try {
      final reminder =
          await ReminderService.instance.createAndScheduleReminder(draft);
      _clearPendingVoiceReminderDraft();
      if (!mounted) return;
      _showInfoSnackbar(
        'Reminder set for ${_formatReminderTime(reminder.scheduledAt)}',
      );
    } catch (error) {
      debugPrint('[LEX] Failed to schedule reminder: $error');
      _showErrorSnackbar('Could not schedule that reminder.');
    }
  }

  Future<void> _onReminderTriggered(ReminderItem reminder) async {
    if (!mounted) return;

    final preferences =
        await ReminderService.instance.loadNotificationPreferences();
    if (!mounted) return;

    if (preferences.popupWithText || preferences.popupWithVoice) {
      setState(() {
        _showChat = false;
        _showSettings = false;
        _showReminders = false;
        _isTalkMode = true;
        _assistantPopupMode = _AssistantPopupMode.reminder;
        _activeReminder = reminder;
      });
      _restoreTalkPresentation(forceBackgroundRefresh: true);
    }

    if (preferences.popupWithVoice) {
      unawaited(
        _tts.speak(
          'Reminder. ${reminder.title}. Scheduled for ${_formatReminderTime(reminder.scheduledAt)}.',
        ),
      );
    }
  }

  void _dismissAssistantPopup() {
    if (!mounted) return;
    setState(() {
      _assistantPopupMode = _AssistantPopupMode.none;
      _activeReminder = null;
    });
  }

  String _formatReminderTime(DateTime dateTime) {
    final now = DateTime.now();
    final sameDay = now.year == dateTime.year &&
        now.month == dateTime.month &&
        now.day == dateTime.day;
    final dayPrefix = sameDay
        ? 'today'
        : '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}';
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final meridiem = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$dayPrefix at $hour:$minute $meridiem';
  }

  /// Brief delay before rendering the Live2D PlatformView.
  /// Just long enough for Flutter route transitions to settle (~300ms).
  void _startLive2dDelayTimer() {
    _live2dDelayTimer?.cancel();
    _live2dReady = false;
    _live2dDelayTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _live2dReady = true);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATION STATE MACHINE — delegates to CharacterAnimationController
  // ═══════════════════════════════════════════════════════════════════════════

  /// Transition the character to a new animation state.
  ///
  /// Delegates to [CharacterAnimationController.setState] which handles
  /// all timer management, parameter interpolation, and debug logging.
  /// The [_animState] field is kept in sync for the UI state indicator.
  void _setAnimState(CharacterAnimState newState) {
    if (_animState == newState) return;
    _animState = newState;
    _animController?.setState(newState);
    if (mounted) setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Live2D init
  // ═══════════════════════════════════════════════════════════════════════════

  void _onLive2dCreated(Live2dViewController controller) {
    _live2dCtrl = controller;

    // Create the animation controller now that we have the Live2D view.
    // Set debugMode: true to see [Animation] logs in logcat.
    _animController = CharacterAnimationController(
      controller: controller,
      animationSet: _currentAnimSet,
      baseParameterOverrides: _currentModel.hiddenParams,
      debugMode: false,
    );

    // Load the model shortly after the surface is ready.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      controller.live2dSetBackgroundPath(_bgAsset);
      controller.live2dSetModelJsonPath(
        _currentModel.nativePath,
      );
      // Apply this model's position/scale transform
      controller.live2dSetModelTransform(
        offsetX: _currentModel.transform.offsetX,
        offsetY: _currentModel.transform.offsetY,
        scale: _currentModel.transform.scale,
      );
      // Apply persistent parameter overrides (e.g., hide wings)
      for (final entry in _currentModel.hiddenParams.entries) {
        controller.live2dSetParameterOverride(entry.key, entry.value);
      }
      // Apply part opacity overrides (e.g., hide wing meshes)
      for (final entry in _currentModel.hiddenParts.entries) {
        controller.live2dSetPartOpacityOverride(entry.key, entry.value);
      }
      // Sync the current app state once the model is loaded so the first
      // idle/listening/speaking loop actually starts on this controller.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _animController?.setState(_animState);
        setState(() {});
      });
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TTS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _setupTts() async {
    await _tts.setLanguage('en-IN');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(_speechRate);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LiveKit — with animation state transitions
  // ═══════════════════════════════════════════════════════════════════════════

  void _bindRoomEvents() {
    _roomListener = _room.createListener()
      ..on<lk.RoomConnectedEvent>((_) async {
        if (!mounted) return;
        debugPrint('[LEX] Room connected');
        if (_wakeWordEnabled) {
          await _stopWakeWordListening();
        }
        // Android WebRTC requires explicit audio session start for remote
        // audio playback (AI voice response). Without this, audio never plays.
        try {
          await _room.startAudio();
          debugPrint('[LEX] Audio session started');
        } catch (e) {
          debugPrint('[LEX] startAudio error: $e');
        }
        // Ensure speaker output is on from the moment we connect.
        if (defaultTargetPlatform == TargetPlatform.android) {
          try {
            await _room.setSpeakerOn(_speakerOn,
                forceSpeakerOutput: _speakerOn);
            debugPrint('[LEX] Speaker set to $_speakerOn');
          } catch (e) {
            debugPrint('[LEX] setSpeakerOn error: $e');
          }
        }
        if (!mounted) return;
        setState(() => _status = _micLive ? 'Listening...' : 'Connected');
        _setAnimState(_passiveState());
      })
      ..on<lk.RoomReconnectingEvent>((_) {
        if (!mounted) return;
        setState(() => _status = 'Reconnecting...');
        _setAnimState(CharacterAnimState.thinking);
      })
      ..on<lk.RoomReconnectedEvent>((_) {
        if (!mounted) return;
        setState(() => _status = _micLive ? 'Listening...' : 'Connected');
        _setAnimState(_passiveState());
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        if (!mounted) return;
        final reason = event.reason?.name ?? 'unknown';
        setState(() {
          _status = 'Disconnected ($reason)';
          _micLive = false;
          if (reason != 'clientInitiated' && _lastError.isEmpty) {
            _lastError = 'Disconnected: $reason';
          }
        });
        _micPulseController.stop();
        _audioPlaybackActive = false;
        _clearRemoteAudioAmplitudeSource(resetLevel: true);
        _setAnimState(CharacterAnimState.idle);
        if (_assistantPopupMode == _AssistantPopupMode.conversation) {
          _dismissAssistantPopup();
        }
        if (_wakeWordEnabled) {
          unawaited(_startWakeWordListening());
        }
      })
      ..on<lk.TrackSubscribedEvent>((event) {
        if (!mounted ||
            !_isConnected ||
            !_audioPlaybackActive ||
            event.track is! lk.RemoteAudioTrack) {
          return;
        }
        unawaited(_ensureRemoteAudioAmplitudeSource());
      })
      ..on<lk.TrackUnsubscribedEvent>((event) {
        if (event.track is! lk.RemoteAudioTrack) return;
        final track = event.track as lk.RemoteAudioTrack;
        if (_visualizerTrackKey(track) != _remoteAudioVisualizerTrackKey) {
          return;
        }

        unawaited(_disposeRemoteAudioVisualizer());
        if (_audioPlaybackActive) {
          _startRemoteAudioLevelPolling();
          unawaited(_ensureRemoteAudioAmplitudeSource());
        }
      })
      ..on<lk.LocalTrackPublishedEvent>((event) {
        if (!mounted) return;
        if (event.publication.source == lk.TrackSource.microphone) {
          setState(() {
            _micLive = true;
            _status = 'Listening...';
          });
          _micPulseController.repeat(reverse: true);
          // User's mic is live — character should be listening
          if (_animState != CharacterAnimState.speaking) {
            _setAnimState(CharacterAnimState.listening);
          }
        }
      })
      ..on<lk.LocalTrackUnpublishedEvent>((event) {
        if (!mounted) return;
        if (event.publication.source == lk.TrackSource.microphone) {
          setState(() {
            _micLive = false;
            _status = 'Mic inactive';
          });
          _micPulseController.stop();
          if (_animState != CharacterAnimState.speaking) {
            _setAnimState(_passiveState());
          }
        }
      })
      ..on<lk.ActiveSpeakersChangedEvent>((event) {
        if (!mounted || !_isConnected) return;

        final localSid = _room.localParticipant?.sid;
        final remoteSpeakers = event.speakers
            .where((p) => p.sid != localSid && p.isSpeaking)
            .toList();

        if (_remoteAudioVisualizer == null) {
          _pushRemoteAudioLevel(
            remoteSpeakers.isNotEmpty
                ? _peakAudioLevel(remoteSpeakers)
                : _peakAudioLevel(_room.remoteParticipants.values),
          );
        }

        if (remoteSpeakers.isNotEmpty) {
          unawaited(_ensureRemoteAudioAmplitudeSource());
          if (_animState != CharacterAnimState.speaking) {
            setState(() => _status = 'Assistant speaking...');
            _setAnimState(CharacterAnimState.speaking);
          }
        } else if (_animState == CharacterAnimState.speaking &&
            !_audioPlaybackActive) {
          _clearRemoteAudioAmplitudeSource(resetLevel: true);
          setState(() => _status = _micLive ? 'Listening...' : 'Connected');
          _setAnimState(_passiveState());
        }
      })
      ..on<lk.AudioPlaybackStatusChanged>((event) {
        if (!mounted) return;
        _audioPlaybackActive = event.isPlaying;
        if (_isConnected) {
          if (event.isPlaying) {
            unawaited(_ensureRemoteAudioAmplitudeSource());
            // AI is speaking → speaking state with lip sync
            setState(() => _status = 'Assistant speaking...');
            _setAnimState(CharacterAnimState.speaking);
          } else {
            _clearRemoteAudioAmplitudeSource(resetLevel: true);
            // AI stopped speaking → transition to listening if mic is live
            setState(() => _status = _micLive ? 'Listening...' : 'Connected');
            _setAnimState(_passiveState());
          }
        }
      })
      ..on<lk.TranscriptionEvent>((event) {
        final text = event.segments
            .where((s) => s.isFinal)
            .map((s) => s.text.trim())
            .join(' ')
            .trim();
        if (text.isEmpty || !mounted) return;

        final isUserTranscript = event.participant is lk.LocalParticipant ||
            event.participant.identity == _identity;
        final role = isUserTranscript ? 'You' : 'LEX';
        setState(() {
          _transcript.insert(
            0,
            _Transcript(role: role, text: text, time: DateTime.now()),
          );
        });

        // ── Persist to Supabase ──
        if (SupabaseService.isLoggedIn) {
          _persistMessage(role == 'You' ? 'user' : 'assistant', text);
        }

        // If user finished speaking, transition to thinking while waiting
        // for AI response (only if not already in speaking state)
        if (isUserTranscript && _animState == CharacterAnimState.listening) {
          _setAnimState(CharacterAnimState.thinking);
        }

        // ── Voice Command Detection ──
        // 照相 animation must ONLY play when the USER says "take a photo".
        // It must NEVER play automatically or when LEX speaks.
        // The command animation overrides all other animations (highest priority).
        if (isUserTranscript && ReminderParser.looksLikeReminderCommand(text)) {
          _capturePendingVoiceReminder(text);
        } else if (!isUserTranscript &&
            ReminderParser.looksLikeReminderAssistantReply(text)) {
          unawaited(_scheduleReminderFromAssistantReply(text));
        }

        if (isUserTranscript) {
          final lower = text.toLowerCase();
          if (lower.contains('take a photo') ||
              lower.contains('taking a photo') ||
              lower.contains('take photo')) {
            debugPrint(
                '[LEX] Voice command detected: user said "take a photo" → triggering 照相');
            _animController?.triggerCommand('take_photo');
          }
        }
      })
      ..on<lk.TrackSubscriptionExceptionEvent>((event) {
        if (!mounted) return;
        setState(() {
          _lastError = 'Track subscribe failed: ${event.reason.name}';
          _status = 'Connection warning';
        });
      });
  }

  Future<void> _toggleVoiceConnection() async {
    if (_isConnected && _micLive) {
      await _disconnect();
      return;
    }
    if (_isConnected) {
      await _enableMicrophoneTrack();
      return;
    }
    await _connect(enableMicrophoneOnConnect: true);
  }

  Future<void> _initNetworkConfig() async {
    try {
      await NetworkConfig.instance.initialize();
      // Remove any stale local/LAN URLs that would override the deployed
      // cloud URL — this is the primary fix for "Cannot reach server" after
      // deploying to Render.
      await NetworkConfig.instance.clearStaleLocalOverrides();
      if (!mounted) return;
      // Refresh controllers with the (now cleaned) URLs.
      final savedServer = NetworkConfig.instance.tokenServerUrl;
      final savedLiveKit = NetworkConfig.instance.liveKitUrl;
      if (_serverController.text != savedServer) {
        _serverController.text = savedServer;
      }
      if (_liveKitController.text != savedLiveKit) {
        _liveKitController.text = savedLiveKit;
      }
    } catch (e) {
      debugPrint('[LEX] NetworkConfig init failed: $e');
    }
  }

  Future<void> _connect({bool enableMicrophoneOnConnect = false}) async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _lastError = '';
      _status = 'Requesting microphone permission...';
    });
    debugPrint('[LEX] Requesting microphone permission...');

    final mic = await Permission.microphone.request();
    debugPrint('[LEX] Microphone permission: ${mic.name}');
    if (!mic.isGranted) {
      setState(() {
        _isConnecting = false;
        _status = 'Microphone permission denied';
        _lastError =
            'Microphone permission was denied. Please grant it in Settings.';
      });
      _showErrorSnackbar('Microphone permission denied');
      return;
    }

    final roomName = _roomController.text.trim();
    final displayName = _nameController.text.trim().isEmpty
        ? 'Guest'
        : _nameController.text.trim();
    final liveKitUrl = _liveKitController.text.trim();
    _identity = _makeIdentity(displayName);

    try {
      // ── Step 1: Resolve the best reachable server URL ──
      // Tries: deployed cloud URL → local LAN URL → emulator URL
      setState(() => _status = 'Finding server...');
      debugPrint('[LEX] Resolving server URL...');
      final serverBase = await NetworkConfig.instance.resolveServerUrl();
      debugPrint('[LEX] Resolved server URL: $serverBase');

      // Update the controller to reflect the resolved URL.
      if (_serverController.text.trim() != serverBase) {
        _serverController.text = serverBase;
      }

      // ── Step 2: Pre-connection health check ──
      // Cloud servers (Render free tier) may need up to 30s to wake from
      // cold start, so we allow more retries for HTTPS endpoints.
      final isCloudUrl = serverBase.startsWith('https://');
      final healthRetries = isCloudUrl ? 3 : 1;
      debugPrint('[LEX] Health check: $serverBase/health (retries=$healthRetries)');
      setState(() => _status = isCloudUrl
          ? 'Waking up server (may take a moment)...'
          : 'Checking server...');
      final reachable = await NetworkConfig.instance
          .isServerReachableWithRetry(serverBase, retries: healthRetries);
      if (!reachable) {
        setState(() {
          _status = 'Server unreachable';
          _lastError = NetworkConfig.unreachableHint(serverBase);
        });
        _showErrorSnackbar(
          isCloudUrl
              ? 'Server is still starting up. Please wait a moment and try again.'
              : 'Cannot reach server. Check that it is running and you are '
                'on the correct network.',
        );
        return;
      }
      debugPrint('[LEX] Server reachable ✓');

      // ── Step 2: Fetch token with retry ──
      debugPrint(
          '[LEX] Fetching token from $serverBase for room=$roomName identity=$_identity');
      setState(() => _status = 'Getting token...');
      final token = await NetworkConfig.withRetry(
        () => _fetchToken(
          serverBase: serverBase,
          roomName: roomName,
          identity: _identity,
          name: displayName,
        ),
      );

      // ── Step 3: Connect to LiveKit ──
      debugPrint('[LEX] Token received, connecting to $liveKitUrl');
      setState(() => _status = 'Connecting to LiveKit...');
      try {
        await _room.connect(liveKitUrl, token);
      } catch (connectError) {
        final errorStr = connectError.toString().toLowerCase();
        // ICE / PeerConnection timeout — retry once with a fresh token.
        if (errorStr.contains('peerconnection') ||
            errorStr.contains('ice') ||
            errorStr.contains('timed out') ||
            errorStr.contains('mediaconnect')) {
          debugPrint(
            '[LEX] LiveKit connection failed (ICE/PeerConnection), '
            'retrying with fresh token...',
          );
          setState(() => _status = 'Retrying connection...');
          await Future.delayed(const Duration(seconds: 1));
          final retryToken = await _fetchToken(
            serverBase: serverBase,
            roomName: roomName,
            identity: _identity,
            name: displayName,
          );
          await _room.connect(liveKitUrl, retryToken);
        } else {
          rethrow;
        }
      }

      // ── Step 4: Persist working URL ──
      unawaited(NetworkConfig.instance.saveTokenServerUrl(serverBase));
      unawaited(NetworkConfig.instance.saveLiveKitUrl(liveKitUrl));

      if (enableMicrophoneOnConnect) {
        debugPrint('[LEX] Connected! Enabling microphone...');
        await _enableMicrophoneTrack();
        debugPrint('[LEX] Microphone enabled, voice assistant ready');
      } else {
        debugPrint('[LEX] Connected without enabling microphone');
      }
    } catch (e) {
      debugPrint('[LEX] Connection error: $e');
      if (_isConnected) {
        await _room.disconnect();
      }
      final errorStr = e.toString();
      final lowerError = errorStr.toLowerCase();
      String userMessage;
      if (lowerError.contains('peerconnection') ||
          lowerError.contains('ice') ||
          lowerError.contains('mediaconnect')) {
        userMessage = 'Network blocked WebRTC connection. '
            'Try switching between WiFi and mobile data.';
      } else if (lowerError.contains('room does not exist') ||
                 lowerError.contains('not_found')) {
        userMessage = 'Room setup failed. Please try again.';
      } else {
        userMessage = 'Connection failed: ${errorStr.split('\n').first}';
      }
      setState(() {
        _status = 'Connection failed';
        _lastError = errorStr;
      });
      _showErrorSnackbar(userMessage);
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _enableMicrophoneTrack() async {
    await _room.localParticipant?.setMicrophoneEnabled(
      true,
      audioCaptureOptions: const lk.AudioCaptureOptions(
        noiseSuppression: true,
        echoCancellation: true,
        autoGainControl: true,
        highPassFilter: true,
        voiceIsolation: true,
        stopAudioCaptureOnMute: false,
      ),
    );
    try {
      // Ensure audio session remains active for remote assistant playback.
      await _room.startAudio();
    } catch (_) {}
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _room.setSpeakerOn(_speakerOn, forceSpeakerOutput: _speakerOn);
    }
    if (!mounted) return;
    setState(() {
      _micLive = true;
      _status = 'Listening...';
    });
    _micPulseController.repeat(reverse: true);
    if (_animState != CharacterAnimState.speaking) {
      _setAnimState(CharacterAnimState.listening);
    }
  }

  Future<void> _toggleSpeakerOutput() async {
    final next = !_speakerOn;
    setState(() => _speakerOn = next);

    if (!_isConnected) return;

    try {
      await _room.startAudio();
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _room.setSpeakerOn(next, forceSpeakerOutput: next);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = 'Speaker update failed: $e');
    }
  }

  Future<void> _disconnect() async {
    await _room.disconnect();
    if (!mounted) return;
    setState(() {
      _status = 'Disconnected';
      _micLive = false;
    });
    _micPulseController.stop();
    _audioPlaybackActive = false;
    _clearRemoteAudioAmplitudeSource(resetLevel: true);
    _setAnimState(CharacterAnimState.idle);
  }

  double _peakAudioLevel(Iterable<lk.Participant> participants) {
    double peak = 0.0;
    for (final participant in participants) {
      if (participant.audioLevel > peak) {
        peak = participant.audioLevel;
      }
    }
    return peak.clamp(0.0, 1.0);
  }

  void _pushRemoteAudioLevel([double? level]) {
    final amplitude = (level ?? _peakRemoteParticipantAudio()).clamp(0.0, 1.0);
    _animController?.updateSpeechSignal(
      level: amplitude,
      mouthForm: 0.0,
      articulation: amplitude,
    );
  }

  void _pushRemoteSpeechSignal({
    required double amplitude,
    required double mouthForm,
    required double articulation,
  }) {
    _animController?.updateSpeechSignal(
      level: amplitude.clamp(0.0, 1.0),
      mouthForm: mouthForm.clamp(-1.0, 1.0),
      articulation: articulation.clamp(0.0, 1.0),
    );
  }

  double _peakRemoteParticipantAudio() {
    final localSid = _room.localParticipant?.sid;
    return _peakAudioLevel(
      _room.remoteParticipants.values
          .where((participant) => participant.sid != localSid),
    );
  }

  Future<void> _ensureRemoteAudioAmplitudeSource() {
    final pending = _remoteAudioAmplitudeSetupFuture;
    if (pending != null) {
      return pending;
    }

    late final Future<void> future;
    future = _ensureRemoteAudioAmplitudeSourceInternal().whenComplete(() {
      if (identical(_remoteAudioAmplitudeSetupFuture, future)) {
        _remoteAudioAmplitudeSetupFuture = null;
      }
    });
    _remoteAudioAmplitudeSetupFuture = future;
    return future;
  }

  Future<void> _ensureRemoteAudioAmplitudeSourceInternal() async {
    if (!_isConnected || !_audioPlaybackActive) return;

    final track = _resolveRemoteAudioTrack();
    if (track == null) {
      _startRemoteAudioLevelPolling();
      return;
    }

    final trackKey = _visualizerTrackKey(track);
    if (_remoteAudioVisualizer != null &&
        _remoteAudioVisualizerTrackKey == trackKey) {
      _stopRemoteAudioLevelPolling();
      return;
    }

    try {
      await _startRemoteAudioVisualizer(track);
      _stopRemoteAudioLevelPolling();
    } catch (_) {
      _startRemoteAudioLevelPolling();
    }
  }

  lk.RemoteAudioTrack? _resolveRemoteAudioTrack() {
    final localSid = _room.localParticipant?.sid;
    final remoteParticipants = _room.remoteParticipants.values
        .where((participant) => participant.sid != localSid)
        .toList();

    lk.RemoteAudioTrack? findTrack(
      Iterable<lk.RemoteParticipant> participants,
    ) {
      for (final participant in participants) {
        for (final publication in participant.audioTrackPublications) {
          final track = publication.track;
          if (track == null || !publication.subscribed) {
            continue;
          }
          if (publication.source == lk.TrackSource.microphone ||
              publication.source == lk.TrackSource.unknown) {
            return track;
          }
        }
      }
      return null;
    }

    return findTrack(
          remoteParticipants.where((participant) => participant.isSpeaking),
        ) ??
        findTrack(remoteParticipants);
  }

  Future<void> _startRemoteAudioVisualizer(lk.RemoteAudioTrack track) async {
    if (!_isConnected || !_audioPlaybackActive) {
      return;
    }

    final trackKey = _visualizerTrackKey(track);
    if (_remoteAudioVisualizer != null &&
        _remoteAudioVisualizerTrackKey == trackKey) {
      return;
    }

    await _disposeRemoteAudioVisualizer();
    if (!_isConnected || !_audioPlaybackActive) {
      return;
    }

    final visualizer = lk.createVisualizer(
      track,
      options: const lk.AudioVisualizerOptions(
        barCount: 16,
        centeredBands: false,
        smoothTransition: true,
      ),
    );
    final listener = visualizer.createListener();

    listener.on<lk.AudioVisualizerEvent>((event) {
      if (!mounted) return;
      final signal = _speechSignalFromBands(event.event);
      _pushRemoteSpeechSignal(
        amplitude: signal.amplitude,
        mouthForm: signal.mouthForm,
        articulation: signal.articulation,
      );
    });

    await visualizer.start();
    _remoteAudioVisualizer = visualizer;
    _remoteAudioVisualizerListener = listener;
    _remoteAudioVisualizerTrackKey = trackKey;
  }

  Future<void> _disposeRemoteAudioVisualizer() {
    final pending = _remoteAudioVisualizerDisposeFuture;
    if (pending != null) {
      return pending;
    }

    final visualizer = _remoteAudioVisualizer;
    final listener = _remoteAudioVisualizerListener;

    _remoteAudioVisualizer = null;
    _remoteAudioVisualizerListener = null;
    _remoteAudioVisualizerTrackKey = null;

    late final Future<void> future;
    future = () async {
      try {
        await visualizer?.stop();
        await visualizer?.dispose();
        await listener?.dispose();
      } catch (_) {}
    }()
        .whenComplete(() {
      if (identical(_remoteAudioVisualizerDisposeFuture, future)) {
        _remoteAudioVisualizerDisposeFuture = null;
      }
    });
    _remoteAudioVisualizerDisposeFuture = future;
    return future;
  }

  void _clearRemoteAudioAmplitudeSource({bool resetLevel = false}) {
    _remoteAudioAmplitudeSetupFuture = null;
    _stopRemoteAudioLevelPolling();
    unawaited(_disposeRemoteAudioVisualizer());
    if (resetLevel) {
      _animController?.updateAudioLevel(0.0);
    }
  }

  String _visualizerTrackKey(lk.RemoteAudioTrack track) =>
      track.sid ?? track.mediaStreamTrack.id!;

  ({double amplitude, double mouthForm, double articulation})
      _speechSignalFromBands(List<Object?> rawBands) {
    final bands = <double>[];
    for (final rawBand in rawBands) {
      if (rawBand is num) {
        bands.add(rawBand.toDouble().clamp(0.0, 1.0));
      }
    }

    if (bands.isEmpty) {
      return (amplitude: 0.0, mouthForm: 0.0, articulation: 0.0);
    }

    double peak = 0.0;
    double energy = 0.0;
    double weightedSum = 0.0;
    double weightTotal = 0.0;
    double low = 0.0;
    double mid = 0.0;
    double high = 0.0;

    final lastIndex = max(bands.length - 1, 1);
    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      peak = max(peak, band);
      energy += band * band;
      weightedSum += i * band;
      weightTotal += band;

      final normalizedIndex = i / lastIndex;
      if (normalizedIndex < 0.28) {
        low += band;
      } else if (normalizedIndex < 0.68) {
        mid += band;
      } else {
        high += band;
      }
    }

    final count = bands.length.toDouble();
    low /= count;
    mid /= count;
    high /= count;

    final rms = sqrt(energy / bands.length);
    final centroid =
        weightTotal > 0.0 ? (weightedSum / weightTotal) / lastIndex : 0.5;
    final speechBody = (mid * 0.75) + (low * 0.25) + (high * 0.2);
    final amplitude =
        ((peak * 0.42) + (rms * 0.36) + (speechBody * 0.22)) * 1.45;

    if (amplitude <= 0.03) {
      return (amplitude: 0.0, mouthForm: 0.0, articulation: 0.0);
    }

    final articulation =
        ((high * 0.75) + (mid * 0.35) - (low * 0.15)).clamp(0.0, 1.0);
    final roundedness = (low - (high * 0.6)).clamp(-1.0, 1.0);
    final spread = ((centroid - 0.5) * 2.0).clamp(-1.0, 1.0);
    final formWeight = (0.32 + amplitude.clamp(0.0, 1.0) * 0.68);
    final mouthForm =
        ((spread * 0.55) + (articulation * 0.35) - (roundedness * 0.25)) *
            formWeight;

    return (
      amplitude: amplitude.clamp(0.0, 1.0),
      mouthForm: mouthForm.clamp(-0.65, 0.75),
      articulation: articulation,
    );
  }

  void _startRemoteAudioLevelPolling() {
    if (_remoteAudioLevelPollTimer != null) return;
    _pushRemoteAudioLevel();
    _remoteAudioLevelPollTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) {
        if (!_isConnected || !_audioPlaybackActive) return;
        _pushRemoteAudioLevel();
      },
    );
  }

  void _stopRemoteAudioLevelPolling({bool resetLevel = false}) {
    _remoteAudioLevelPollTimer?.cancel();
    _remoteAudioLevelPollTimer = null;
    if (resetLevel) {
      _animController?.updateAudioLevel(0.0);
    }
  }

  CharacterAnimState _passiveState() {
    if (!_isConnected) return CharacterAnimState.idle;
    return _micLive ? CharacterAnimState.listening : CharacterAnimState.idle;
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showInfoSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1E88E5),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Network helpers — delegates to NetworkConfig for consistency
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _requestTokenFromUri({
    required Uri uri,
    required String roomName,
    required String identity,
    required String name,
  }) async {
    try {
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
              {'room': roomName, 'identity': identity, 'name': name},
            ),
          )
          .timeout(NetworkConfig.tokenRequestTimeout);
      if (resp.statusCode != 200) {
        throw Exception('Token error (${resp.statusCode}): ${resp.body}');
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final token = map['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Token missing in response');
      }
      return token;
    } on TimeoutException {
      final origin = '${uri.scheme}://${uri.host}';
      final port = uri.hasPort ? ':${uri.port}' : '';
      throw Exception(
        'Could not reach token server at $origin$port. '
        'Request timed out. ${NetworkConfig.platformConnectionHint()}',
      );
    } catch (error) {
      if (NetworkConfig.isTransientError(error)) {
        throw Exception(
          NetworkConfig.unreachableHint(
            '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}',
          ),
        );
      }
      rethrow;
    }
  }

  String _tokenServerHelpText() {
    return NetworkConfig.platformConnectionHint();
  }

  Future<String> _fetchToken({
    required String serverBase,
    required String roomName,
    required String identity,
    required String name,
  }) async {
    final base = NetworkConfig.normalizeBaseUrl(serverBase);
    final primaryUri = Uri.parse('$base/token');

    try {
      return await _requestTokenFromUri(
        uri: primaryUri,
        roomName: roomName,
        identity: identity,
        name: name,
      );
    } catch (error) {
      // If localhost fails on Android, retry emulator host once.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final host = primaryUri.host.toLowerCase();
        if (NetworkConfig.isLocalhostHost(host) &&
            NetworkConfig.isTransientError(error)) {
          final emulatorBase = NetworkConfig.withAndroidEmulatorHost(base);
          final fallbackUri = Uri.parse('$emulatorBase/token');
          debugPrint(
            '[LEX] Token fetch failed on localhost, retrying Android emulator host: $fallbackUri',
          );
          return _requestTokenFromUri(
            uri: fallbackUri,
            roomName: roomName,
            identity: identity,
            name: name,
          );
        }
      }
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Vision (kept for future use)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _captureImage() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      setState(() => _lastError = 'Camera permission denied');
      return;
    }
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1440,
    );
    if (image == null || !mounted) return;
    // Image captured — could be used for vision analysis
  }

  String _makeIdentity(String name) {
    final suffix = Random().nextInt(99999).toString().padLeft(5, '0');
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    return '$normalized-$suffix';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // ── State-based Settings screen ──
    // Settings screen is now overlaid in the widget tree (Layer 5)
    // to avoid tearing down the Live2D PlatformView entirely.

    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Layer 1: Background image (kept as an independent persistent layer) ──
          const ColoredBox(color: Colors.black),
          Image(
            key: ValueKey('talk-background-$_backgroundLayerVersion'),
            image: _talkBackgroundImage,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => const SizedBox.expand(
              child: ColoredBox(color: Colors.black),
            ),
          ),

          // ── Layer 2: Live2D character (delayed 3s to avoid GL bleed-through) ──
          if (_live2dReady)
            Positioned.fill(
              key: const ValueKey('live2d'),
              child: FlutterLive2dView(
                live2dType: LiveType.normal,
                onLive2dViewCreated: _onLive2dCreated,
              ),
            ),

          // ── Layer 3: State-dependent glow effect behind character ──
          if (_animState == CharacterAnimState.speaking)
            Positioned(
              bottom: 180,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _stateGlowController,
                builder: (_, __) => Center(
                  child: Container(
                    width: 200 + (_stateGlowController.value * 40),
                    height: 200 + (_stateGlowController.value * 40),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF7C4DFF).withValues(
                            alpha: 0.15 * _stateGlowController.value,
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Layer 4: UI overlays ──
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                _buildBottomPanel(bottomPad),
              ],
            ),
          ),

          // ── Layer 5: Settings Screen Overlay ──
          if (_showSettings)
            Positioned.fill(
              child: SettingsScreen(
                userName: widget.userName,
                userEmail: SupabaseService.client.auth.currentUser?.email ?? '',
                onBack: () {
                  if (!mounted) return;
                  setState(() {
                    _showSettings = false;
                  });
                  _restoreTalkPresentation(forceBackgroundRefresh: true);
                },
              ),
            ),

          // ── Layer 6: Chat Screen Overlay ──
          if (_showChat)
            Positioned.fill(
              child: ChatScreen(
                userName: widget.userName,
                serverBase: _serverController.text.trim(),
                initialSessionId: _currentChatSessionId,
                onSessionChanged: (sessionId) {
                  if (!mounted) return;
                  setState(() {
                    _currentChatSessionId = sessionId;
                  });
                },
                onOpenReminders: _openReminders,
                onBack: () {
                  if (!mounted) return;
                  setState(() {
                    _showChat = false;
                    _isTalkMode = true;
                  });
                  _restoreTalkPresentation(forceBackgroundRefresh: true);
                },
              ),
            ),

          if (_showReminders)
            Positioned.fill(
              child: RemindersScreen(
                onBack: () {
                  if (!mounted) return;
                  setState(() {
                    _showReminders = false;
                  });
                  if (!_showChat && !_showSettings) {
                    _restoreTalkPresentation(forceBackgroundRefresh: true);
                  }
                },
              ),
            ),

          if (_assistantPopupMode != _AssistantPopupMode.none)
            Positioned.fill(
              child: _buildAssistantPopupOverlay(bottomPad),
            ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Top bar
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          _GlassCircleButton(icon: Icons.menu, size: 40, onTap: _openSettings),
          const Spacer(),
          _buildModeToggle(),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TogglePill(
            label: 'Talk',
            selected: _isTalkMode,
            onTap: () => setState(() => _isTalkMode = true),
          ),
          _TogglePill(
            label: 'Chat',
            selected: !_isTalkMode,
            onTap: () {
              // Hide Live2D and show Chat overlay
              _live2dCtrl?.hideView();
              setState(() {
                _isTalkMode = false;
                _showChat = true;
              });
            },
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Bottom panel
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildBottomPanel(double bottomPad) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.3),
            Colors.black.withValues(alpha: 0.65),
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── State indicator pill ──
            _buildStateIndicator(),
            const SizedBox(height: 10),
            // ── Chat bubbles ──
            _buildChatBubbles(),
            const SizedBox(height: 16),
            // ── Control buttons ──
            _buildControlButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantPopupOverlay(double bottomPad) {
    final isReminder = _assistantPopupMode == _AssistantPopupMode.reminder;
    final reminder = _activeReminder;
    final lastAssistantText = _transcript
        .firstWhere(
          (item) => item.role == 'LEX',
          orElse: () => _Transcript(
            role: 'LEX',
            text: isReminder
                ? (reminder?.title ?? 'Reminder')
                : 'Listening for your next command.',
            time: DateTime.now(),
          ),
        )
        .text;

    return IgnorePointer(
      ignoring: false,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.05),
              Colors.black.withValues(alpha: 0.2),
              Colors.black.withValues(alpha: 0.55),
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad + 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isReminder
                                  ? const Color(0xFFFFC857)
                                      .withValues(alpha: 0.18)
                                  : const Color(0xFF7C4DFF)
                                      .withValues(alpha: 0.18),
                            ),
                            child: Icon(
                              isReminder
                                  ? Icons.alarm_rounded
                                  : Icons.graphic_eq_rounded,
                              color: isReminder
                                  ? const Color(0xFFFFC857)
                                  : const Color(0xFFB39DFF),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isReminder
                                      ? 'Reminder Alert'
                                      : 'LEX Assistant',
                                  style: GoogleFonts.manrope(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isReminder
                                      ? _formatReminderTime(
                                          reminder?.scheduledAt ??
                                              DateTime.now(),
                                        )
                                      : _status,
                                  style: GoogleFonts.manrope(
                                    color: Colors.white.withValues(alpha: 0.66),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _dismissAssistantPopup,
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isReminder
                            ? (reminder?.title ?? 'Reminder')
                            : lastAssistantText,
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: isReminder ? 20 : 16,
                          fontWeight:
                              isReminder ? FontWeight.w700 : FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _showChat = false;
                                  _showSettings = false;
                                  _showReminders = false;
                                  _isTalkMode = true;
                                  _assistantPopupMode =
                                      _AssistantPopupMode.conversation;
                                  _activeReminder = null;
                                });
                                _restoreTalkPresentation(
                                  forceBackgroundRefresh: true,
                                );
                                if (!_isConnected || !_micLive) {
                                  _showInfoSnackbar(
                                    'Press the mic button to start talking to Lex.',
                                  );
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Text(
                                isReminder ? 'Talk to LEX' : 'Keep Listening',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (!isReminder)
                            _GlassCircleButton(
                              icon: _isConnected ? Icons.mic : Icons.mic_none,
                              size: 52,
                              onTap: _isConnecting
                                  ? () {}
                                  : _toggleVoiceConnection,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStateIndicator() {
    final label = switch (_animState) {
      CharacterAnimState.idle => '● Idle',
      CharacterAnimState.listening => '◉ Listening',
      CharacterAnimState.thinking => '◎ Thinking...',
      CharacterAnimState.speaking => '◉ Speaking',
    };
    final color = switch (_animState) {
      CharacterAnimState.idle => Colors.grey,
      CharacterAnimState.listening => const Color(0xFF4FC3F7),
      CharacterAnimState.thinking => const Color(0xFFFFB74D),
      CharacterAnimState.speaking => const Color(0xFF81C784),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildChatBubbles() {
    final items = _transcript.take(3).toList().reversed.toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 90,
      child: ListView(
        reverse: false,
        children: items.map((item) {
          final isUser = item.role == 'You';
          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text(
                item.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildControlButtons() {
    final bool micActive = _isConnected && _micLive;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Left: Speaker icon (only visible when mic is active) ──
        AnimatedOpacity(
          opacity: micActive ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: AnimatedSlide(
            offset: micActive ? Offset.zero : const Offset(-0.5, 0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
              ignoring: !micActive,
              child: _GlassCircleButton(
                icon: _speakerOn
                    ? Icons.volume_up_rounded
                    : Icons.phone_in_talk_rounded,
                size: 52,
                onTap: _toggleSpeakerOutput,
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        _buildMicButton(),
        const SizedBox(width: 24),
        // ── Right: Close (X) icon (only visible when mic is active) ──
        AnimatedOpacity(
          opacity: micActive ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: AnimatedSlide(
            offset: micActive ? Offset.zero : const Offset(0.5, 0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
              ignoring: !micActive,
              child: _GlassCircleButton(
                icon: Icons.close_rounded,
                size: 52,
                onTap: () async {
                  await _disconnect();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMicButton() {
    final bool active = _isConnected && _micLive;

    return GestureDetector(
      onTap: _isConnecting ? null : _toggleVoiceConnection,
      child: AnimatedBuilder(
        animation: _micPulseController,
        builder: (context, child) {
          final double pulse =
              active ? 1.0 + (_micPulseController.value * 0.15) : 1.0;
          return Transform.scale(
            scale: pulse,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Glassy red when active, translucent white glass when idle
                color: active
                    ? const Color(0xFFE53935).withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: active
                      ? const Color(0xFFEF5350).withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.25),
                  width: active ? 2.0 : 1.5,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color:
                              const Color(0xFFE53935).withValues(alpha: 0.45),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: const Color(0xFFFF8A80).withValues(alpha: 0.2),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: _isConnecting
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Icon(
                      active ? Icons.mic : Icons.mic_none,
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.85),
                      size: 28,
                    ),
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Settings
  // ───────────────────────────────────────────────────────────────────────────
  /// Save a message to the current session (creates session on first message).
  Future<void> _persistMessage(String role, String text) async {
    try {
      if (_currentTalkSessionId == null) {
        final conversation = await SupabaseService.createConversation(
          title: 'Voice conversation',
          kind: ChatConversation.talkKind,
        );
        _currentTalkSessionId = conversation.id;
        _talkSessionSawUserMessage = false;
        _talkSessionHasAssistantTitle = false;
      }

      if (role == 'user') {
        _talkSessionSawUserMessage = true;
      } else if (role == 'assistant' &&
          _talkSessionSawUserMessage &&
          !_talkSessionHasAssistantTitle) {
        await SupabaseService.updateConversationTitle(
          _currentTalkSessionId!,
          SupabaseService.conversationTitleFromText(text),
          ChatConversation.talkKind,
        );
        _talkSessionHasAssistantTitle = true;
      }
      await SupabaseService.insertMessage(
        sessionId: _currentTalkSessionId!,
        role: role,
        message: text,
      );
    } catch (e) {
      debugPrint('[LEX] Failed to persist message: $e');
    }
  }

  void _openFreshChat() {
    if (!mounted) return;
    setState(() {
      _currentChatSessionId = null;
      _showChat = true;
      _isTalkMode = false;
    });
    _live2dCtrl?.hideView();
  }

  void _openChatSession(String sessionId) {
    if (!mounted) return;
    setState(() {
      _currentChatSessionId = sessionId;
      _showChat = true;
      _isTalkMode = false;
    });
    _live2dCtrl?.hideView();
  }

  void _openReminders() {
    if (!mounted) return;
    setState(() {
      _showReminders = true;
    });
    _live2dCtrl?.hideView();
  }

  Future<void> _openSettings() async {
    // The sidebar returns a string indicating which action was taken.
    // This ensures we handle navigation AFTER the sidebar has fully
    // closed (its showGeneralDialog Future resolved), avoiding the
    // race condition where an async onProfileTapped callback would
    // fire-and-forget (VoidCallback drops the Future).
    final result = await openSidebarDrawer(
      context,
      userName: widget.userName,
      currentSessionId:
          _isTalkMode ? _currentTalkSessionId : _currentChatSessionId,
      activeCompanionId: _currentModel.id,
      onNewChat: () {
        _openFreshChat();
      },
      onSessionSelected: (sessionId) {
        _openChatSession(sessionId);
      },
      onSessionDeleted: (sessionId) {
        if (!mounted) return;
        setState(() {
          if (_currentChatSessionId == sessionId) {
            _currentChatSessionId = null;
          }
          if (_currentTalkSessionId == sessionId) {
            _currentTalkSessionId = null;
            _talkSessionSawUserMessage = false;
            _talkSessionHasAssistantTitle = false;
          }
        });
      },
    );

    if (result == 'profile' && mounted) {
      // Pause the native GL surface without removing it
      _live2dCtrl?.hideView();

      // Show settings overlay
      setState(() => _showSettings = true);
    } else if (result == 'reminders' && mounted) {
      _openReminders();
    } else if (result != null && result.startsWith('companion:') && mounted) {
      final companionId = result.substring('companion:'.length);
      if (companionId != _currentModel.id) {
        _switchCompanion(CompanionRegistry.findById(companionId));
      }
    }
  }

  /// Switch the Live2D companion model.
  ///
  /// 1. Disposes the current animation controller
  /// 2. Loads the new model via live2dSetModelJsonPath (native side
  ///    calls releaseAllModel() first, so this is a clean swap)
  /// 3. Creates a new animation set and reconfigures the controller
  /// 4. Starts idle state after the model is loaded
  void _switchCompanion(CompanionModel newModel) {
    if (_currentModel.id == newModel.id) return;
    debugPrint(
        '[LEX] Switching companion: ${_currentModel.id} → ${newModel.id}');

    // Stop all animations
    _animController?.dispose();
    _animController = null;
    _animState = CharacterAnimState.idle;

    // Update state
    _currentModel = newModel;
    _currentAnimSet = AnimationConfig.forModel(newModel);

    // Load the new model on the existing Live2D surface
    _live2dCtrl?.live2dSetModelJsonPath(newModel.nativePath);

    // Apply the new model's position/scale transform
    _live2dCtrl?.live2dSetModelTransform(
      offsetX: newModel.transform.offsetX,
      offsetY: newModel.transform.offsetY,
      scale: newModel.transform.scale,
    );

    // Clear old overrides and apply new model's hidden params/parts
    _live2dCtrl?.live2dClearParameterOverrides();
    _live2dCtrl?.live2dClearPartOpacityOverrides();
    for (final entry in newModel.hiddenParams.entries) {
      _live2dCtrl?.live2dSetParameterOverride(entry.key, entry.value);
    }
    for (final entry in newModel.hiddenParts.entries) {
      _live2dCtrl?.live2dSetPartOpacityOverride(entry.key, entry.value);
    }

    // Recreate the animation controller after a short delay for model loading
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || _live2dCtrl == null) return;
      _animController = CharacterAnimationController(
        controller: _live2dCtrl!,
        animationSet: _currentAnimSet,
        baseParameterOverrides: newModel.hiddenParams,
        debugMode: false,
      );
      _animController?.setState(_animState);
      if (mounted) setState(() {});
      debugPrint('[LEX] Companion switched to ${newModel.id}');
    });

    if (mounted) setState(() {});
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Reusable widgets
// ═════════════════════════════════════════════════════════════════════════════

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.55),
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.controller,
    required this.enabled,
  });
  final String label;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}
