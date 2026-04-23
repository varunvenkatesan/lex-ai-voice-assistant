// ═══════════════════════════════════════════════════════════════════════════════
// CHARACTER ANIMATION CONTROLLER — Engine that drives Live2D animations
// ═══════════════════════════════════════════════════════════════════════════════
//
// This controller reads animation definitions from [animation_config.dart]
// and drives the Live2D model through [Live2dViewController].
//
// Usage in main.dart:
//   _animController = CharacterAnimationController(
//     controller: _live2dCtrl!,
//     debugMode: true,
//   );
//   _animController.setState(CharacterAnimState.idle);
//   _animController.updateAudioLevel(0.5); // from LiveKit
//   _animController.dispose();
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_plugin2/live2d_view.dart';
import 'package:flutter_plugin2/animation_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATION STATE ENUM
// ─────────────────────────────────────────────────────────────────────────────

/// The high-level states the character can be in.
/// Each state activates a group of animations from [AnimationConfig].
enum CharacterAnimState {
  /// Resting: breathing, blinking, subtle idle motions.
  idle,

  /// User is speaking: character looks attentive and engaged.
  listening,

  /// Processing: waiting for AI response, cycling expressions.
  thinking,

  /// AI is speaking: lip sync active, lively expression.
  speaking,
}

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATION CONTROLLER
// ─────────────────────────────────────────────────────────────────────────────

/// Manages all Live2D character animations based on configuration.
///
/// The controller implements a state machine that transitions between
/// [CharacterAnimState]s, activating the appropriate animations from
/// [AnimationConfig] for each state.
///
/// All timer management, parameter interpolation, and debug logging
/// are encapsulated here — the caller only needs to call [setState]
/// and [updateAudioLevel].
class CharacterAnimationController {
  CharacterAnimationController({
    required Live2dViewController controller,
    required ModelAnimationSet animationSet,
    this.baseParameterOverrides = const {},
    this.debugMode = false,
  })  : _ctrl = controller,
        _animSet = animationSet;

  // ── Dependencies ──
  final Live2dViewController _ctrl;

  /// The active animation set (model-specific).
  ModelAnimationSet _animSet;

  /// Parameter overrides that should always stay applied for the current model.
  final Map<String, double> baseParameterOverrides;

  /// Set to true to print [Animation] debug logs.
  final bool debugMode;

  // ── Current state ──
  CharacterAnimState _currentState = CharacterAnimState.idle;
  CharacterAnimState get currentState => _currentState;

  /// Whether the controller has been disposed.
  bool _disposed = false;

  // ── Audio input from LiveKit ──
  double _audioLevel = 0.0;
  double _audioMouthForm = 0.0;
  double _audioArticulation = 0.0;
  DateTime _lastAudioLevelUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Smoothed parameter values ──
  double _smoothedMouthOpen = 0.0;
  double _smoothedMouthForm = 0.0;

  // ── Phase accumulator for sine wave generation ──
  double _phase = 0.0;

  // ── Random number generator ──
  final Random _rng = Random();

  // ── Event-driven lip sync: cached speaking animation entries ──
  AnimationEntry? _speakingMouthOpen;
  AnimationEntry? _speakingMouthForm;

  // ── Rate limiting for event-driven pushes ──
  /// Tracks elapsed time since last event-driven lip sync push.
  final Stopwatch _lipSyncStopwatch = Stopwatch();

  /// Minimum interval between event-driven pushes (≈120fps cap).
  static const int _minPushIntervalUs = 8000; // 8ms in microseconds

  // ── Active timers ──
  /// Speaking animation timer (drives mouth parameters every tick).
  Timer? _speakingTimer;

  /// Speaking expression cycle timer.
  Timer? _speakingExpressionTimer;

  /// Replays the speaking body-language motion while assistant audio is active.
  Timer? _speakingMotionTimer;

  /// Idle loop timer (schedules next random idle animation).
  Timer? _idleLoopTimer;

  /// One-time startup delay before idle gestures begin on app open.
  Timer? _initialIdleDelayTimer;

  /// Listening subtle movement timer.
  Timer? _listeningTimer;

  /// Replays the cute mic-on motion while the microphone stays active.
  Timer? _listeningMotionTimer;

  /// Cycles through listening expressions while the microphone stays active.
  Timer? _listeningExpressionTimer;

  /// Thinking expression cycle timer.
  Timer? _thinkingCycleTimer;

  /// Thinking fallback timeout timer.
  Timer? _thinkingFallbackTimer;

  /// Command animation duration timer (returns to previous state).
  Timer? _commandTimer;

  // ── Thinking cycle index ──
  int _thinkingCycleIndex = 0;
  int _listeningExpressionIndex = 0;
  int _speakingExpressionIndex = 0;

  // ── Command state ──
  /// True while a command animation is playing (overrides all).
  bool _isCommandActive = false;

  /// The state to return to after a command animation finishes.
  CharacterAnimState? _stateBeforeCommand;

  /// Only the very first app-open idle state waits before showing gestures.
  bool _hasConsumedInitialIdleDelay = false;

  /// Prevents identical idle gestures from repeating back-to-back.
  String? _lastIdleActionName;

  /// Tracks whether a temporary idle pose is currently using parameter overrides.
  bool _idleParameterOverrideActive = false;

  /// Whether the current state has been entered at least once.
  bool _hasActivatedState = false;

  static const Duration _initialIdleGestureDelay =
      Duration(milliseconds: 1200);

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Hot-swap the animation set (e.g., when switching companion models).
  ///
  /// Stops all current animations, replaces the config, and enters idle.
  void reconfigure(ModelAnimationSet newSet) {
    if (_disposed) return;
    _log('Reconfiguring animation set');
    _cancelAllTimers();
    _isCommandActive = false;
    _stateBeforeCommand = null;
    _clearIdleParameterOverridesIfNeeded();
    _lastIdleActionName = null;
    _animSet = newSet;
    _currentState = CharacterAnimState.idle;
    _hasActivatedState = true;
    _enterState(CharacterAnimState.idle);
  }

  /// Transition to a new animation state.
  ///
  /// Handles clean exit from the old state and entry into the new state.
  /// Duplicate state transitions are ignored.
  /// If a command animation is active, the state change is deferred —
  /// the command will return to this new state when it finishes.
  void setState(CharacterAnimState newState) {
    if (_disposed) return;
    if (!_hasActivatedState) {
      _currentState = newState;
      _hasActivatedState = true;
      _log('Initial State Activated: ${newState.name}');
      _enterState(newState);
      return;
    }
    if (_currentState == newState && !_isCommandActive) return;

    // If a command animation is playing, just update the return state
    if (_isCommandActive) {
      _stateBeforeCommand = newState;
      _log('State deferred (command active): will return to ${newState.name}');
      return;
    }

    final oldState = _currentState;
    _log('State Change: ${oldState.name} → ${newState.name}');

    // ── Exit old state ──
    _exitState(oldState);

    // ── Enter new state ──
    _currentState = newState;
    _enterState(newState);
  }

  /// Feed real-time audio amplitude from LiveKit (0.0–1.0).
  ///
  /// Called from [ActiveSpeakersChangedEvent] in the LiveKit event handler.
  /// The speaking animation timer reads this value each tick.
  void updateAudioLevel(double level) {
    updateSpeechSignal(
      level: level,
      mouthForm: 0.0,
      articulation: level,
    );
  }

  void updateSpeechSignal({
    required double level,
    double mouthForm = 0.0,
    double articulation = 0.0,
  }) {
    if (_disposed) return;
    _audioLevel = level.clamp(0.0, 1.0);
    _audioMouthForm = mouthForm.clamp(-1.0, 1.0);
    _audioArticulation = articulation.clamp(0.0, 1.0);
    _lastAudioLevelUpdate = DateTime.now();

    // ── Event-driven lip sync: push immediately when speaking ──
    // Instead of waiting for the next timer tick (up to 16ms delay),
    // compute and send lip sync values right now for real-time response.
    if (_currentState == CharacterAnimState.speaking &&
        _speakingMouthOpen != null) {
      // Rate-limit to ~120fps to avoid flooding the MethodChannel.
      if (!_lipSyncStopwatch.isRunning ||
          _lipSyncStopwatch.elapsedMicroseconds >= _minPushIntervalUs) {
        _lipSyncStopwatch.reset();
        _lipSyncStopwatch.start();
        _processSpeakingTick();
      }
    }
  }

  /// Trigger a named emotion animation (e.g., "Emotion_Happy").
  ///
  /// Looks up the animation in the active animation set by name
  /// and triggers the associated expression.
  void triggerEmotion(String animationName) {
    if (_disposed) return;
    final entry = _animSet.findByName(animationName);
    if (entry == null || !entry.enabled) {
      _log('Emotion "$animationName" not found or disabled');
      return;
    }
    _log('$animationName Triggered');
    if (entry.expressionId != null) {
      _ctrl.live2dStartExpression(entry.expressionId!);
    }
  }

  /// Trigger a named interaction animation (e.g., "Wave_Hello").
  ///
  /// Triggers the associated motion and/or expression.
  /// Temporarily pauses the current state loop and returns to it after duration.
  void triggerInteraction(String animationName) {
    if (_disposed) return;
    final entry = _animSet.findByName(animationName);
    if (entry == null || !entry.enabled) {
      _log('Interaction "$animationName" not found or disabled');
      return;
    }

    _log('$animationName Triggered');

    // ── Save current state and stop everything ──
    _stateBeforeCommand = _currentState;
    _isCommandActive = true;
    _exitState(_currentState);

    if (entry.expressionId != null) {
      _ctrl.live2dStartExpression(entry.expressionId!);
    }
    if (entry.motionGroup != null) {
      _ctrl.live2dStartRandomMotion(entry.motionGroup!, entry.motionPriority);
    }

    // ── Return to previous state after the animation duration ──
    final duration = entry.durationMs ?? 3500;
    _commandTimer?.cancel();
    _commandTimer = Timer(Duration(milliseconds: duration), () {
      if (_disposed) return;
      _isCommandActive = false;
      _ctrl.live2dStopMotions(resetPose: true);
      final returnTo = _stateBeforeCommand ?? CharacterAnimState.idle;
      _stateBeforeCommand = null;
      _log(
          'Interaction "$animationName" Finished → returning to ${returnTo.name}');
      _currentState = returnTo;
      _enterState(returnTo);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMMAND TRIGGER — Voice command animations (highest priority)
  // ─────────────────────────────────────────────────────────────────────────
  // Priority: Command > Talking > Idle
  // Stops all current animations, plays once, returns to previous state.
  // ─────────────────────────────────────────────────────────────────────────

  /// Trigger a voice command animation by its command key.
  ///
  /// Looks up the key in [AnimationConfig.COMMAND_ACTIONS] to find the
  /// animation entry name, then plays the associated motion once.
  ///
  /// Example: `triggerCommand('take_photo')` → plays 照相 animation.
  ///
  /// The command overrides all current animations:
  ///   1. Saves the current state
  ///   2. Exits the current state (stops all timers)
  ///   3. Plays the command motion at Force priority
  ///   4. After the animation duration, returns to the saved state
  void triggerCommand(String commandKey) {
    if (_disposed) return;

    // Look up the animation name from the active model's command actions map
    final animName = _animSet.commandActions[commandKey];
    if (animName == null) {
      _log('Command "$commandKey" not found in COMMAND_ACTIONS');
      return;
    }

    final entry = _animSet.findByName(animName);
    if (entry == null || !entry.enabled) {
      _log('Command animation "$animName" not found or disabled');
      return;
    }

    _log('Command Triggered: $animName (key: $commandKey)');

    // ── Save current state and stop everything ──
    _stateBeforeCommand = _currentState;
    _isCommandActive = true;
    _exitState(_currentState);

    // ── Play the command motion at Force priority ──
    if (entry.motionGroup != null) {
      _ctrl.live2dStartRandomMotion(entry.motionGroup!, entry.motionPriority);
      _log('$animName Playing (motion group: ${entry.motionGroup}, '
          'priority: ${entry.motionPriority})');
    }
    if (entry.expressionId != null) {
      _ctrl.live2dStartExpression(entry.expressionId!);
    }

    // ── Return to previous state after the animation duration ──
    final duration = entry.durationMs ?? 4000;
    _commandTimer?.cancel();
    _commandTimer = Timer(Duration(milliseconds: duration), () {
      if (_disposed) return;
      _isCommandActive = false;
      _ctrl.live2dStopMotions(resetPose: true);
      final returnTo = _stateBeforeCommand ?? CharacterAnimState.idle;
      _stateBeforeCommand = null;
      _log('Command "$animName" Finished → returning to ${returnTo.name}');
      _currentState = returnTo;
      _enterState(returnTo);
    });
  }

  /// Clean up all timers and resources.
  void dispose() {
    _disposed = true;
    _cancelAllTimers();
    _clearIdleParameterOverridesIfNeeded();
    _log('Controller disposed');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATE EXIT HANDLERS — Clean up when leaving a state
  // ─────────────────────────────────────────────────────────────────────────

  void _exitState(CharacterAnimState state) {
    switch (state) {
      case CharacterAnimState.speaking:
        _exitSpeakingState();
        break;
      case CharacterAnimState.thinking:
        _exitThinkingState();
        break;
      case CharacterAnimState.listening:
        _exitListeningState();
        break;
      case CharacterAnimState.idle:
        _exitIdleState();
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATE ENTRY HANDLERS — Activate animations for the new state
  // ─────────────────────────────────────────────────────────────────────────

  void _enterState(CharacterAnimState state) {
    switch (state) {
      case CharacterAnimState.idle:
        _enterIdleState();
        break;
      case CharacterAnimState.listening:
        _enterListeningState();
        break;
      case CharacterAnimState.thinking:
        _enterThinkingState();
        break;
      case CharacterAnimState.speaking:
        _enterSpeakingState();
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //
  //  IDLE STATE (EVENT_MIC_OFF)
  //  Activated when: Mic is OFF, assistant is not active.
  //  Behavior: Waits briefly on first app open, then loops through
  //            facepalm / peace sign / photo actions in random order with
  //            short random gaps between animations.
  //  Animations: Idle_捂脸, Idle_比耶, Idle_照相
  //
  //  IDLE_LOOP_ANIMATIONS = ["捂脸", "比耶", "照相"]
  //
  // ═══════════════════════════════════════════════════════════════════════════

  void _enterIdleState() {
    _log('Idle State Entered');

    // Close mouth when entering idle
    _ctrl.live2dSetLipSync(0.0);
    _ctrl.live2dSetMouthForm(0.0);

    // Get the idle loop animation entries from the active model's animation set
    final idleAnims = _animSet
        .getAnimationsForTrigger(AnimationTrigger.idle)
        .where((a) =>
            a.motionGroup != null ||
            a.parameterValues.isNotEmpty ||
            a.expressionId != null)
        .toList();

    if (idleAnims.isEmpty) {
      _log('No idle loop animations configured');
      return;
    }

    if (!_hasConsumedInitialIdleDelay) {
      _hasConsumedInitialIdleDelay = true;
      _log(
          'Idle gestures armed with a ${_initialIdleGestureDelay.inMilliseconds}ms startup delay');
      _initialIdleDelayTimer?.cancel();
      _initialIdleDelayTimer = Timer(_initialIdleGestureDelay, () {
        if (_disposed || _currentState != CharacterAnimState.idle) return;
        _log('Initial idle delay elapsed — starting random gesture loop');
        _playRandomIdleAnimation(idleAnims);
      });
      return;
    }

    _playRandomIdleAnimation(idleAnims);
  }

  /// Plays a random idle animation from the list, then schedules the next
  /// one after a short random delay. This creates a natural,
  /// non-repetitive idle loop.
  void _playRandomIdleAnimation(List<AnimationEntry> idleAnims) {
    if (_disposed || _currentState != CharacterAnimState.idle) return;

    var anim = idleAnims[_rng.nextInt(idleAnims.length)];
    if (idleAnims.length > 1 &&
        _lastIdleActionName != null &&
        anim.name == _lastIdleActionName) {
      final filtered = idleAnims
          .where((candidate) => candidate.name != _lastIdleActionName)
          .toList();
      if (filtered.isNotEmpty) {
        anim = filtered[_rng.nextInt(filtered.length)];
      }
    }

    _clearIdleParameterOverridesIfNeeded();
    _lastIdleActionName = anim.name;

    if (anim.motionGroup != null) {
      _log('${anim.name} Playing (motion group: ${anim.motionGroup})');
      _ctrl.live2dStartRandomMotion(anim.motionGroup!, anim.motionPriority);
    } else if (anim.parameterValues.isNotEmpty) {
      _log('${anim.name} Playing (parameter pose)');
      _ctrl.live2dStopMotions(resetPose: true);
      for (final entry in anim.parameterValues.entries) {
        _ctrl.live2dSetParameterOverride(entry.key, entry.value);
      }
      _idleParameterOverrideActive = true;
    } else if (anim.expressionId != null) {
      _log('${anim.name} Playing (expression: ${anim.expressionId})');
      _ctrl.live2dStartExpression(anim.expressionId!);
    }

    // Schedule the NEXT idle animation after a short random gap
    final minDelay = anim.randomIntervalMin ?? 2000;
    final maxDelay = anim.randomIntervalMax ?? 5000;
    final gapDelay = minDelay + _rng.nextInt(maxDelay - minDelay + 1);
    final holdDelay = anim.durationMs ?? 0;
    final delay = holdDelay + gapDelay;

    _idleLoopTimer?.cancel();
    _idleLoopTimer = Timer(Duration(milliseconds: delay), () {
      _playRandomIdleAnimation(idleAnims);
    });
  }

  /// Called on EVENT_MIC_ON or any state transition out of idle.
  /// Stops the idle animation loop.
  void _exitIdleState() {
    _initialIdleDelayTimer?.cancel();
    _initialIdleDelayTimer = null;
    _idleLoopTimer?.cancel();
    _idleLoopTimer = null;
    _clearIdleParameterOverridesIfNeeded();
    _log('Idle State Exited — loop stopped');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //
  //  LISTENING STATE
  //  Activated when: User's microphone is active.
  //  Animations: Listen_HeadTilt, Listen_EyeFocus
  //  Parameters: expression, mouthOpenY (tiny breathing oscillation)
  //
  // ═══════════════════════════════════════════════════════════════════════════

  void _enterListeningState() {
    final anims =
        _animSet.getAnimationsForTrigger(AnimationTrigger.userSpeaking);
    _log('Listening State Entered (${anims.length} animations)');

    // ── Stop any in-progress motions from idle state ──
    // This ensures that idle gestures like 捂脸 / 比耶 / 照相 do not
    // continue playing after the microphone becomes active.
    _ctrl.live2dStopMotions(resetPose: true);

    // Close mouth
    _ctrl.live2dSetLipSync(0.0);
    _ctrl.live2dSetMouthForm(0.0);

    for (final anim in anims) {
      switch (anim.name) {
        // ── Listen_HeadTilt: Set attentive expression ──
        case 'Listen_HeadTilt':
          _log('${anim.name} Activated');
          if (anim.expressionId != null) {
            _ctrl.live2dStartExpression(anim.expressionId!);
          }
          break;

        case 'Listen_BaseMotion':
          _log('${anim.name} Activated (motion group: ${anim.motionGroup})');
          _playLoopedStateMotion(
            anim,
            state: CharacterAnimState.listening,
            timerSetter: (timer) {
              _listeningMotionTimer?.cancel();
              _listeningMotionTimer = timer;
            },
          );
          break;

        case 'Listen_ExpressionCycle':
          if (anim.expressionCycleList.isEmpty) {
            break;
          }
          _listeningExpressionIndex = 0;
          _ctrl.live2dStartExpression(anim.expressionCycleList.first);
          _log(
              '${anim.name} Activated (cycle: ${anim.expressionCycleList.join(" -> ")})');
          _listeningExpressionTimer?.cancel();
          _listeningExpressionTimer = Timer.periodic(
            Duration(milliseconds: anim.expressionCycleIntervalMs),
            (_) {
              if (_disposed || _currentState != CharacterAnimState.listening) {
                return;
              }
              _listeningExpressionIndex++;
              final expr = anim.expressionCycleList[
                  _listeningExpressionIndex % anim.expressionCycleList.length];
              _ctrl.live2dStartExpression(expr);
              _log('Listen_ExpressionCycle -> $expr');
            },
          );
          break;

        // ── Listen_EyeFocus: Subtle breathing oscillation ──
        case 'Listen_EyeFocus':
          _log('${anim.name} Activated (interval: ${anim.intervalMs}ms)');
          _listeningTimer = Timer.periodic(
            Duration(milliseconds: anim.intervalMs),
            (_) {
              if (_disposed) return;
              // Generate subtle sine oscillation for "alive" effect
              final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
              final freq = anim.sineFrequencies.isNotEmpty
                  ? anim.sineFrequencies[0]
                  : 1.5;
              final amp = anim.sineAmplitudes.isNotEmpty
                  ? anim.sineAmplitudes[0]
                  : 0.03;
              final value = (sin(t * freq) * amp + anim.baseValue)
                  .clamp(anim.clampMin, anim.clampMax);
              _ctrl.live2dSetLipSync(value);
            },
          );
          break;
      }
    }
  }

  void _exitListeningState() {
    _listeningTimer?.cancel();
    _listeningTimer = null;
    _listeningMotionTimer?.cancel();
    _listeningMotionTimer = null;
    _listeningExpressionTimer?.cancel();
    _listeningExpressionTimer = null;
    _log('Listening State Exited');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //
  //  THINKING STATE
  //  Activated when: Waiting for AI response after user spoke.
  //  Animations: Think_ExpressionCycle, Think_FallbackTimeout
  //  Parameters: expression (cycles through list)
  //
  // ═══════════════════════════════════════════════════════════════════════════

  void _enterThinkingState() {
    final anims = _animSet.getAnimationsForTrigger(AnimationTrigger.thinking);
    _log('Thinking State Entered (${anims.length} animations)');

    _ctrl.live2dStopMotions(resetPose: true);

    // Close mouth
    _ctrl.live2dSetLipSync(0.0);
    _ctrl.live2dSetMouthForm(0.0);

    for (final anim in anims) {
      switch (anim.name) {
        // ── Think_ExpressionCycle: Cycle through processing expressions ──
        case 'Think_ExpressionCycle':
          _log(
              '${anim.name} Activated (cycle: ${anim.expressionCycleList.join(" → ")})');
          _thinkingCycleIndex = 0;
          // Set initial expression
          if (anim.expressionCycleList.isNotEmpty) {
            _ctrl.live2dStartExpression(anim.expressionCycleList[0]);
          }
          // Start cycling timer
          _thinkingCycleTimer = Timer.periodic(
            Duration(milliseconds: anim.expressionCycleIntervalMs),
            (_) {
              if (_disposed) return;
              _thinkingCycleIndex++;
              if (anim.expressionCycleList.isNotEmpty) {
                final expr = anim.expressionCycleList[
                    _thinkingCycleIndex % anim.expressionCycleList.length];
                _ctrl.live2dStartExpression(expr);
                _log('Think_ExpressionCycle → $expr');
              }
            },
          );
          break;

        // ── Think_FallbackTimeout: Return to passive after timeout ──
        case 'Think_FallbackTimeout':
          if (anim.durationMs != null) {
            _log('${anim.name} Set (${anim.durationMs}ms timeout)');
            _thinkingFallbackTimer = Timer(
              Duration(milliseconds: anim.durationMs!),
              () {
                if (_disposed) return;
                if (_currentState != CharacterAnimState.thinking) return;
                _log('Think_FallbackTimeout Fired → returning to idle');
                setState(CharacterAnimState.idle);
              },
            );
          }
          break;
      }
    }
  }

  void _exitThinkingState() {
    _thinkingCycleTimer?.cancel();
    _thinkingCycleTimer = null;
    _thinkingFallbackTimer?.cancel();
    _thinkingFallbackTimer = null;
    _log('Thinking State Exited');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //
  //  TALKING STATE (EVENT_AI_SPEAKING_START / EVENT_AI_SPEAKING_END)
  //
  //  Activated when: AI voice assistant is speaking through LiveKit.
  //
  //  ONLY two mouth parameters are driven:
  //    1. Talk_Mouth_OpenClose — 张开和闭合 (open/close movement)
  //    2. Talk_Mouth_Transform — 变形 (shape deformation)
  //
  //  Both parameters run on a single synchronized timer (~25fps).
  //  Values are blended between real-time audio amplitude and procedural
  //  sine waves, then smoothed via EMA to prevent sudden jumps.
  //
  //  No other Live2D parameters (head, body, eyes, expressions) are
  //  modified during the talking state.
  //
  // ═══════════════════════════════════════════════════════════════════════════

  void _enterSpeakingState() {
    final anims = _animSet.getAnimationsForTrigger(AnimationTrigger.aiSpeaking);
    _log('AI Speaking Start (${anims.length} animations)');

    _ctrl.live2dStopMotions(resetPose: true);

    // Reset smoothed values to ensure a clean start
    _smoothedMouthOpen = 0.0;
    _smoothedMouthForm = 0.0;
    _phase = 0.0;

    // ── Cache the speaking animation configs as class fields ──
    // These are accessed by both the fallback timer AND the event-driven
    // path in updateSpeechSignal() for real-time lip sync.
    _speakingMouthOpen = _findAnim(anims, 'Talk_Mouth_OpenClose');
    _speakingMouthForm = _findAnim(anims, 'Talk_Mouth_Transform');
    final speakMotion = _findAnim(anims, 'Speak_BaseMotion');
    final speakExpressions = _findAnim(anims, 'Speak_ExpressionCycle');

    if (_speakingMouthOpen != null) {
      _log('Talk_Mouth_OpenClose Running '
          '(source: audio_amplitude, EMA: ${_speakingMouthOpen!.smoothingFactor})');
    }
    if (_speakingMouthForm != null) {
      _log('Talk_Mouth_Transform Running '
          '(source: speech_variation, EMA: ${_speakingMouthForm!.smoothingFactor})');
    }
    if (speakMotion?.motionGroup != null) {
      _playLoopedStateMotion(
        speakMotion!,
        state: CharacterAnimState.speaking,
        timerSetter: (timer) {
          _speakingMotionTimer?.cancel();
          _speakingMotionTimer = timer;
        },
      );
      _log(
          'Speak_BaseMotion Running (motion group: ${speakMotion.motionGroup})');
    }
    if (speakExpressions != null &&
        speakExpressions.expressionCycleList.isNotEmpty) {
      _speakingExpressionIndex = 0;
      _ctrl.live2dStartExpression(speakExpressions.expressionCycleList.first);
      _speakingExpressionTimer?.cancel();
      _speakingExpressionTimer = Timer.periodic(
        Duration(milliseconds: speakExpressions.expressionCycleIntervalMs),
        (_) {
          if (_disposed || _currentState != CharacterAnimState.speaking) return;
          _speakingExpressionIndex++;
          final expr = speakExpressions.expressionCycleList[
              _speakingExpressionIndex %
                  speakExpressions.expressionCycleList.length];
          _ctrl.live2dStartExpression(expr);
          _log('Speak_ExpressionCycle → $expr');
        },
      );
    }

    // Start the rate-limiting stopwatch for event-driven pushes.
    _lipSyncStopwatch.reset();
    _lipSyncStopwatch.start();

    // ── Start the fallback timer ──
    // The primary lip sync path is now event-driven (from updateSpeechSignal).
    // This timer serves as a fallback to:
    //   1. Smoothly close the mouth when audio events stop arriving
    //   2. Advance the sine phase for procedural variation
    //   3. Drive mouth movement when AudioVisualizer is unavailable
    final intervalMs = _speakingMouthOpen?.intervalMs ?? 16;
    _speakingTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) {
        if (_disposed) return;
        _processSpeakingTick();
      },
    );
  }

  /// Core lip sync computation — called from BOTH:
  ///   1. updateSpeechSignal() (event-driven, immediate response)
  ///   2. The fallback timer (smooth closure during silence)
  ///
  /// Computes mouth open/close and shape deformation values from the
  /// current audio signal, applies EMA smoothing, and pushes to native.
  void _processSpeakingTick() {
    _phase += 0.6; // Advance phase for sine wave generation

    final mouthOpen = _speakingMouthOpen;
    final mouthForm = _speakingMouthForm;

    // ── Talk_Mouth_OpenClose (张开和闭合) ──
    // Controls the main talking motion.
    // Higher audio amplitude → mouth opens more.
    if (mouthOpen != null) {
      final openValue = _computeNaturalSpeechMouthOpenValue(mouthOpen);
      _smoothedMouthOpen = _emaAttackRelease(
        _smoothedMouthOpen,
        openValue,
        // Fast attack: mouth opens quickly when audio arrives.
        // max(0.04, sf * 0.25) → ~96% of new value per tick.
        attackFactor: max(0.04, mouthOpen.smoothingFactor * 0.25),
        // Moderate release: mouth closes naturally between syllables.
        // min(0.72, sf + 0.18) → ~28-46% of new value per tick.
        releaseFactor: min(0.72, mouthOpen.smoothingFactor + 0.18),
      );
      _ctrl.live2dSetLipSync(_smoothedMouthOpen);
    }

    // ── Talk_Mouth_Transform (变形) ──
    // Adds shape variation during speech.
    // Driven by speech variation (offset sine + audio correlation).
    if (mouthForm != null) {
      final formValue = _computeSpeechMouthFormValue(mouthForm);
      _smoothedMouthForm = _emaAttackRelease(
        _smoothedMouthForm,
        formValue,
        // Moderate attack for shape changes.
        attackFactor: max(0.06, mouthForm.smoothingFactor * 0.35),
        // Slightly slower release for smoother shape transitions.
        releaseFactor: min(0.78, mouthForm.smoothingFactor + 0.14),
      );
      _ctrl.live2dSetMouthForm(_smoothedMouthForm);
    }
  }

  /// Called on EVENT_AI_SPEAKING_END.
  /// Stops updating the parameters and smoothly resets both to neutral (0).
  void _exitSpeakingState() {
    _speakingTimer?.cancel();
    _speakingTimer = null;
    _speakingExpressionTimer?.cancel();
    _speakingExpressionTimer = null;
    _speakingMotionTimer?.cancel();
    _speakingMotionTimer = null;
    _lipSyncStopwatch.stop();

    // Clear cached animation entries
    _speakingMouthOpen = null;
    _speakingMouthForm = null;

    // Reset both mouth parameters to neutral
    // Talk_Mouth_OpenClose (张开和闭合) = 0
    // Talk_Mouth_Transform (变形) = 0
    _audioLevel = 0.0;
    _audioMouthForm = 0.0;
    _audioArticulation = 0.0;
    _smoothedMouthOpen = 0.0;
    _smoothedMouthForm = 0.0;
    _ctrl.live2dSetLipSync(0.0);
    _ctrl.live2dSetMouthForm(0.0);

    _log('AI Speaking End — mouth parameters reset to 0');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PARAMETER COMPUTATION — generates smooth animation values
  // ─────────────────────────────────────────────────────────────────────────

  /// Compute a blended audio + sine wave value for a given animation entry.
  ///
  /// This is the core algorithm for natural mouth movement:
  /// 1. Generate a multi-frequency sine fallback (procedural speech pattern)
  /// 2. Read real-time audio amplitude from LiveKit
  /// 3. Blend them: prefer audio when available, fall back to sine
  /// 4. Add random jitter for micro-variation
  double _computeSpeechMouthOpenValue(AnimationEntry anim) {
    // ── Step 1: Multi-frequency sine fallback ──
    double sineSum = 0.0;
    for (int i = 0; i < anim.sineFrequencies.length; i++) {
      final freq = anim.sineFrequencies[i];
      final amp = i < anim.sineAmplitudes.length ? anim.sineAmplitudes[i] : 0.2;
      final offset =
          i < anim.sinePhaseOffsets.length ? anim.sinePhaseOffsets[i] : 0.0;
      sineSum += sin(_phase * freq + offset) * amp;
    }

    // Add random jitter for micro-variation
    final jitter = (anim.jitterAmount > 0)
        ? (_rng.nextDouble() - 0.5) * anim.jitterAmount
        : 0.0;
    final fallback =
        (anim.baseValue + sineSum + jitter).clamp(anim.clampMin, anim.clampMax);

    // ── Step 2: Audio-driven value ──
    final maxAudioAgeMs = max(anim.intervalMs * 4, 160);
    final hasRecentAudio =
        DateTime.now().difference(_lastAudioLevelUpdate).inMilliseconds <=
            maxAudioAgeMs;
    final audioDriven =
        hasRecentAudio ? (_audioLevel * anim.audioGain).clamp(0.0, 1.0) : 0.0;

    // ── Step 3: Blend ──
    // For speech sync, mouth openness should follow recent LiveKit audio first.
    // Procedural fallback is only used to add slight shape variation while audio
    // is actively coming in, not to flap continuously during silence.
    double target;
    if (audioDriven > 0.015) {
      if (anim.target == AnimParamTarget.mouthForm) {
        target = audioDriven * 0.65 + fallback * 0.2;
      } else {
        target = audioDriven;
      }
    } else {
      target = 0.0;
    }

    return target.clamp(anim.clampMin, anim.clampMax);
  }

  double _computeNaturalSpeechMouthOpenValue(AnimationEntry anim) {
    final base = _computeSpeechMouthOpenValue(anim);
    if (base <= 0.015) {
      return 0.0;
    }

    final articulationBoost = _audioArticulation * 0.22;
    final syllableOpen = pow(base, 0.82).toDouble();
    final gate = base < 0.08 ? base / 0.08 : 1.0;
    final target = ((syllableOpen + articulationBoost) * 0.92) * gate;
    return target.clamp(anim.clampMin, anim.clampMax);
  }

  double _computeSpeechMouthFormValue(AnimationEntry anim) {
    final base = _computeSpeechMouthOpenValue(anim);
    if (base <= 0.015) {
      return 0.0;
    }

    final fallback = _computeProceduralMouthVariation(anim);
    final openness = pow(base, 0.72).toDouble();
    final formSignal = (_audioMouthForm * anim.audioGain).clamp(-1.0, 1.0);
    final articulationOffset = (_audioArticulation - 0.35) * 0.18;
    final target = formSignal * (0.62 + openness * 0.28) +
        fallback * 0.1 +
        articulationOffset;
    final damped = target * (0.35 + openness * 0.65);
    return damped.clamp(anim.clampMin, anim.clampMax);
  }

  double _computeProceduralMouthVariation(AnimationEntry anim) {
    double sineSum = 0.0;
    for (int i = 0; i < anim.sineFrequencies.length; i++) {
      final freq = anim.sineFrequencies[i];
      final amp = i < anim.sineAmplitudes.length ? anim.sineAmplitudes[i] : 0.2;
      final offset =
          i < anim.sinePhaseOffsets.length ? anim.sinePhaseOffsets[i] : 0.0;
      sineSum += sin(_phase * freq + offset) * amp;
    }

    final jitter = anim.jitterAmount > 0
        ? (_rng.nextDouble() - 0.5) * anim.jitterAmount
        : 0.0;
    return (anim.baseValue + sineSum + jitter)
        .clamp(anim.clampMin, anim.clampMax);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SMOOTHING — Exponential Moving Average (EMA)
  // ─────────────────────────────────────────────────────────────────────────

  /// Exponential Moving Average for smooth parameter interpolation.
  ///
  /// [current] — the current smoothed value.
  /// [target] — the raw target value from this tick.
  /// [factor] — smoothing factor (0–1). Higher = smoother / slower.
  ///
  /// Formula: result = current * factor + target * (1 - factor)
  ///
  /// Example: factor = 0.62 means 62% of old value + 38% of new value,
  /// producing smooth transitions without sudden jumps.
  double _ema(double current, double target, double factor) {
    return current * factor + target * (1.0 - factor);
  }

  double _emaAttackRelease(
    double current,
    double target, {
    required double attackFactor,
    required double releaseFactor,
  }) {
    return target > current
        ? _ema(current, target, attackFactor)
        : _ema(current, target, releaseFactor);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UTILITIES
  // ─────────────────────────────────────────────────────────────────────────

  /// Find an animation entry by name in a list.
  AnimationEntry? _findAnim(List<AnimationEntry> anims, String name) {
    try {
      return anims.firstWhere((a) => a.name == name);
    } catch (_) {
      return null;
    }
  }

  void _playLoopedStateMotion(
    AnimationEntry anim, {
    required CharacterAnimState state,
    required void Function(Timer?) timerSetter,
  }) {
    if (anim.motionGroup == null) return;

    timerSetter(null);
    _ctrl.live2dStartRandomMotion(anim.motionGroup!, anim.motionPriority);

    if (!anim.looping) {
      return;
    }

    final repeatMs = anim.durationMs ?? 3600;
    final timer = Timer.periodic(Duration(milliseconds: repeatMs), (_) {
      if (_disposed || _currentState != state) return;
      _ctrl.live2dStartRandomMotion(anim.motionGroup!, anim.motionPriority);
    });
    timerSetter(timer);
  }

  void _clearIdleParameterOverridesIfNeeded() {
    if (!_idleParameterOverrideActive) return;
    _ctrl.live2dClearParameterOverrides();
    for (final entry in baseParameterOverrides.entries) {
      _ctrl.live2dSetParameterOverride(entry.key, entry.value);
    }
    _idleParameterOverrideActive = false;
  }

  /// Cancel all active timers.
  void _cancelAllTimers() {
    _speakingTimer?.cancel();
    _speakingTimer = null;
    _speakingExpressionTimer?.cancel();
    _speakingExpressionTimer = null;
    _speakingMotionTimer?.cancel();
    _speakingMotionTimer = null;
    _initialIdleDelayTimer?.cancel();
    _initialIdleDelayTimer = null;
    _idleLoopTimer?.cancel();
    _idleLoopTimer = null;
    _listeningTimer?.cancel();
    _listeningTimer = null;
    _listeningMotionTimer?.cancel();
    _listeningMotionTimer = null;
    _listeningExpressionTimer?.cancel();
    _listeningExpressionTimer = null;
    _thinkingCycleTimer?.cancel();
    _thinkingCycleTimer = null;
    _thinkingFallbackTimer?.cancel();
    _thinkingFallbackTimer = null;
    _commandTimer?.cancel();
    _commandTimer = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEBUG LOGGING
  // ─────────────────────────────────────────────────────────────────────────

  /// Print a debug log message with the [Animation] prefix.
  ///
  /// Only prints when [debugMode] is true.
  /// Example output: [Animation] Idle_Breath Activated
  void _log(String message) {
    if (debugMode) {
      debugPrint('[Animation] $message');
    }
  }
}
