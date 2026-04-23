// ═══════════════════════════════════════════════════════════════════════════════
// ANIMATION CONFIGURATION — Centralized animation definitions for Live2D
// ═══════════════════════════════════════════════════════════════════════════════
//
// This file is the SINGLE SOURCE OF TRUTH for all character animations.
// Developers can:
//   • Add / remove animations by editing the lists below
//   • Reorder animation priority via [PLAY_ORDER]
//   • Tune timing, smoothing, and intensity per-animation
//   • Map animations to Live2D parameters
//
// The animation controller reads this file and drives the Live2D model
// accordingly. No animation logic lives here — only data definitions.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_plugin2/model_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. ENUMS — Trigger types and Live2D parameter targets
// ─────────────────────────────────────────────────────────────────────────────

/// When an animation should be activated.
enum AnimationTrigger {
  /// Character is waiting / no activity.
  idle,

  /// AI voice assistant is actively speaking.
  aiSpeaking,

  /// User's microphone is active and capturing speech.
  userSpeaking,

  /// Waiting for AI response after user spoke.
  thinking,

  /// Personality and emotional reactions.
  emotion,

  /// Triggered by UI interactions (tap, gesture, etc.).
  interaction,
}

/// Which Live2D parameter an animation drives.
/// Each maps to a real parameter ID in the model.
enum AnimParamTarget {
  // ── Mouth ──
  /// ParamMouthOpenY — vertical mouth open/close.
  mouthOpenY,

  /// ParamMouthForm — mouth shape deformation (smile, phonemes).
  mouthForm,

  // ── Eyes ──
  /// ParamEyeLOpen — left eye open amount.
  eyeLOpen,

  /// ParamEyeROpen — right eye open amount.
  eyeROpen,

  // ── Head / Face direction ──
  /// ParamAngleX — head left/right rotation.
  angleX,

  /// ParamAngleY — head up/down tilt.
  angleY,

  /// ParamAngleZ — head roll (tilt sideways).
  angleZ,

  // ── Body ──
  /// ParamBodyAngleX — body sway left/right.
  bodyAngleX,

  /// ParamBreath — breathing cycle.
  breath,

  // ── Special ──
  /// Triggers a pre-built motion from the motion group (not a raw parameter).
  motionGroup,

  /// Forces one or more raw model parameters to specific values.
  parameterOverride,

  /// Triggers a named expression preset.
  expression,
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. ANIMATION ENTRY — Definition of a single animation
// ─────────────────────────────────────────────────────────────────────────────

/// Priority levels for animations. Higher priority overrides lower.
enum AnimPriority {
  /// Background animations (breathing, subtle idle).
  low,

  /// Standard animations (listening sway, thinking cycle).
  medium,

  /// Active animations (speaking lip sync, forced expressions).
  high,
}

/// How the animation generates its value over time.
enum AnimDriver {
  /// Driven by real-time audio amplitude from LiveKit.
  audioAmplitude,

  /// Procedural sine-wave oscillation (configurable frequencies).
  sineWave,

  /// Combination of audio amplitude + sine fallback.
  audioWithSineFallback,

  /// One-shot: triggers a Live2D motion or expression once.
  oneShot,

  /// Loops at a fixed interval (e.g., periodic idle motions).
  periodicLoop,

  /// Cycles through a list of values/expressions on a timer.
  cycleList,
}

/// Complete definition of one animation. Immutable configuration data.
class AnimationEntry {
  const AnimationEntry({
    required this.name,
    required this.trigger,
    required this.target,
    this.driver = AnimDriver.sineWave,
    this.priority = AnimPriority.medium,
    this.enabled = true,

    // ── Timing ──
    this.intervalMs = 40,
    this.durationMs,
    this.looping = false,
    this.randomIntervalMin,
    this.randomIntervalMax,

    // ── Value generation ──
    this.sineFrequencies = const [],
    this.sinePhaseOffsets = const [],
    this.sineAmplitudes = const [],
    this.baseValue = 0.0,
    this.jitterAmount = 0.0,
    this.audioGain = 1.35,

    // ── Smoothing ──
    this.smoothingFactor = 0.62,
    this.clampMin = 0.0,
    this.clampMax = 1.0,

    // ── Motion / Expression ──
    this.motionGroup,
    this.motionPriority = 1,
    this.parameterValues = const {},
    this.expressionId,
    this.expressionCycleList = const [],
    this.expressionCycleIntervalMs = 2000,

    // ── Description (for debug / documentation) ──
    this.description = '',
  });

  /// Human-readable animation name (e.g., "Mouth_OpenClose").
  final String name;

  /// What event activates this animation.
  final AnimationTrigger trigger;

  /// Which Live2D parameter this drives.
  final AnimParamTarget target;

  /// How the value is generated each tick.
  final AnimDriver driver;

  /// Animation priority level.
  final AnimPriority priority;

  /// Set to false to temporarily disable without removing.
  final bool enabled;

  // ── Timing ──

  /// Timer interval in milliseconds (default: 40ms ≈ 25fps).
  final int intervalMs;

  /// Optional duration — animation stops after this many ms. Null = runs until state changes.
  final int? durationMs;

  /// Whether this animation loops continuously.
  final bool looping;

  /// For periodic triggers: random interval range (min).
  final int? randomIntervalMin;

  /// For periodic triggers: random interval range (max).
  final int? randomIntervalMax;

  // ── Value generation (sine wave) ──

  /// Sine wave frequencies (multiplied by phase).
  final List<double> sineFrequencies;

  /// Phase offsets per sine component.
  final List<double> sinePhaseOffsets;

  /// Amplitude per sine component.
  final List<double> sineAmplitudes;

  /// Base value added to the sum of sine components.
  final double baseValue;

  /// Random jitter range (±half this value).
  final double jitterAmount;

  /// Audio amplitude gain multiplier.
  final double audioGain;

  // ── Smoothing ──

  /// EMA smoothing factor (0–1). Higher = more smoothing / slower response.
  /// Formula: smoothed = smoothed * factor + target * (1 - factor).
  final double smoothingFactor;

  /// Minimum output value.
  final double clampMin;

  /// Maximum output value.
  final double clampMax;

  // ── Motion / Expression ──

  /// Motion group name for oneShot/periodicLoop drivers (e.g., "Idle").
  final String? motionGroup;

  /// Native motion priority (1=Idle, 2=Normal, 3=Force).
  final int motionPriority;

  /// Raw parameter overrides applied for custom poses (e.g., facepalm).
  final Map<String, double> parameterValues;

  /// Single expression ID to trigger.
  final String? expressionId;

  /// List of expression IDs to cycle through.
  final List<String> expressionCycleList;

  /// Interval for cycling expressions (ms).
  final int expressionCycleIntervalMs;

  /// Human-readable description of what this animation does.
  final String description;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. EXPRESSION MAP — Named emotions → Live2D expression IDs
// ─────────────────────────────────────────────────────────────────────────────

/// Maps emotion names to the model's expression file IDs.
/// Based on the "March 7th" model's Expressions list in model3.json.
class ExpressionMap {
  ExpressionMap._();

  static const String happy = 'exp_08'; // Starry-eyed, cheerful
  static const String blushing = 'exp_04'; // Warm, attentive, engaged
  static const String darkFace = 'exp_05'; // Dark / serious face
  static const String crying = 'exp_06'; // Sad / crying
  static const String sweating = 'exp_07'; // Nervous / processing
  static const String starryEyed = 'exp_08'; // Starry / lively
  static const String neutral = 'exp_01'; // Default neutral
  static const String surprised = 'exp_02'; // Surprised
  static const String confident = 'exp_03'; // Confident / smirk
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. ANIMATION DEFINITIONS — Organized by category
// ─────────────────────────────────────────────────────────────────────────────
//
// ┌───────────────────────┐
// │  HOW TO EDIT:         │
// │  1. Find the category │
// │  2. Add/remove entry  │
// │  3. Update PLAY_ORDER │
// └───────────────────────┘

class AnimationConfig {
  AnimationConfig._();

  // ═════════════════════════════════════════════════════════════════════════
  // IDLE LOOP ANIMATIONS — played when assistant mic is OFF
  // ═════════════════════════════════════════════════════════════════════════
  //
  // ┌──────────────────────────────────────────────────────────────────────┐
  // │  EVENT_MIC_OFF → Start idle animation loop                         │
  // │  Behavior: Loop continuously, randomized order, 2–5s delay         │
  // │  Animations: 摇脸 (head shake), 比耶 (peace sign)                  │
  // │  These are Live2D motion GROUPS (not raw parameters).               │
  // └──────────────────────────────────────────────────────────────────────┘

  static const List<AnimationEntry> idleAnimations = [
    // ──────────────────────────────────────────────────────────────────────
    // Idle_摇脸  —  Head shake / playful face movement
    // ──────────────────────────────────────────────────────────────────────
    // When it plays  : During idle state (mic OFF / assistant not active)
    // Which state    : Idle (EVENT_MIC_OFF)
    // Loop behavior  : Loops continuously as part of the idle rotation
    // Motion group   : 摇脸
    // ──────────────────────────────────────────────────────────────────────
    AnimationEntry(
      name: 'Idle_摇脸',
      description: 'Head shake / playful face movement. '
          'Plays during idle loop with random delay between animations.',
      trigger: AnimationTrigger.idle,
      target: AnimParamTarget.motionGroup,
      driver: AnimDriver.periodicLoop,
      priority: AnimPriority.low,
      looping: true,
      motionGroup: '摇脸',
      motionPriority: 2, // Normal priority
      randomIntervalMin: 2000, // 2 second min delay
      randomIntervalMax: 5000, // 5 second max delay
    ),

    // ──────────────────────────────────────────────────────────────────────
    // Idle_比耶  —  Peace sign gesture
    // ──────────────────────────────────────────────────────────────────────
    // When it plays  : During idle state (mic OFF / assistant not active)
    // Which state    : Idle (EVENT_MIC_OFF)
    // Loop behavior  : Loops continuously as part of the idle rotation
    // Motion group   : 比耶
    // ──────────────────────────────────────────────────────────────────────
    AnimationEntry(
      name: 'Idle_比耶',
      description: 'Peace sign gesture animation. '
          'Plays during idle loop with random delay between animations.',
      trigger: AnimationTrigger.idle,
      target: AnimParamTarget.motionGroup,
      driver: AnimDriver.periodicLoop,
      priority: AnimPriority.low,
      looping: true,
      motionGroup: '比耶',
      motionPriority: 2, // Normal priority
      randomIntervalMin: 2000, // 2 second min delay
      randomIntervalMax: 5000, // 5 second max delay
    ),
  ];

  /// The idle loop list — developers can reorder or add animations here.
  /// The controller picks randomly from this list during idle state.
  static const List<String> IDLE_LOOP_ANIMATIONS = [
    'Idle_摇脸',
    'Idle_比耶',
  ];

  // ═════════════════════════════════════════════════════════════════════════
  // TALKING ANIMATIONS — activated when AI voice is speaking
  // ═════════════════════════════════════════════════════════════════════════
  //
  // ┌──────────────────────────────────────────────────────────────────────┐
  // │  ONLY two mouth parameters are used for talking:                   │
  // │  1. Talk_Mouth_OpenClose — 张开和闭合 (open / close)               │
  // │  2. Talk_Mouth_Transform — 变形 (shape deformation)                │
  // │  No other Live2D parameters are driven during speech.              │
  // └──────────────────────────────────────────────────────────────────────┘

  static const List<AnimationEntry> speakingAnimations = [
    // ──────────────────────────────────────────────────────────────────────
    // Talk_Mouth_OpenClose  —  Mouth Open/Close
    // ──────────────────────────────────────────────────────────────────────
    // What it controls : Main talking motion (mouth opening and closing).
    // Which parameter  : ParamMouthOpenY (mouthOpenY)
    // When it triggers : EVENT_AI_SPEAKING_START (LiveKit audio playback)
    // Source           : Real-time audio amplitude from LiveKit.
    //                    Higher amplitude → mouth opens more.
    //                    Falls back to procedural sine when audio is low.
    // Smoothing        : EMA with factor 0.62 (62% old + 38% new).
    // Stop condition   : Reset to 0 on EVENT_AI_SPEAKING_END.
    // ──────────────────────────────────────────────────────────────────────
    AnimationEntry(
      name: 'Talk_Mouth_OpenClose',
      description: 'Controls the opening and closing movement of the '
          'mouth during speech. Driven by real-time audio amplitude '
          'from LiveKit with smooth EMA interpolation.',
      trigger: AnimationTrigger.aiSpeaking,
      target: AnimParamTarget.mouthOpenY,
      driver: AnimDriver.audioWithSineFallback,
      priority: AnimPriority.high,
      looping: true,
      intervalMs: 40, // ~25fps update rate
      sineFrequencies: [1.0, 2.7, 0.4], // Multi-frequency sine fallback
      sineAmplitudes: [0.35, 0.2, 0.15], // Amplitude per sine component
      sinePhaseOffsets: [0.0, 0.0, 0.0], // No phase offset
      baseValue: 0.5, // Neutral center offset
      jitterAmount: 0.1, // Micro-variation ±0.05
      audioGain: 1.35, // Audio amplitude multiplier
      smoothingFactor: 0.62, // EMA: smooth transitions
      clampMin: 0.0, // Allow natural closures on silence
      clampMax: 1.0, // Full open
    ),

    // ──────────────────────────────────────────────────────────────────────
    // Talk_Mouth_Transform  —  Mouth Transform (变形)
    // ──────────────────────────────────────────────────────────────────────
    // What it controls : Mouth shape deformation during speech.
    // Which parameter  : ParamMouthForm (mouthForm)
    // When it triggers : EVENT_AI_SPEAKING_START (LiveKit audio playback)
    // Source           : Speech variation — offset sine frequencies
    //                    correlated with audio amplitude for phoneme
    //                    shape changes. Adds natural variety.
    // Smoothing        : EMA with factor 0.70 (slightly more smoothing).
    // Stop condition   : Reset to 0 on EVENT_AI_SPEAKING_END.
    // ──────────────────────────────────────────────────────────────────────
    AnimationEntry(
      name: 'Talk_Mouth_Transform',
      description: 'Controls mouth shape deformation to simulate '
          'phoneme changes during speech. Adds slight shape variation '
          'driven by speech variation and audio correlation.',
      trigger: AnimationTrigger.aiSpeaking,
      target: AnimParamTarget.mouthForm,
      driver: AnimDriver.audioWithSineFallback,
      priority: AnimPriority.high,
      looping: true,
      intervalMs: 40, // Synced with OpenClose
      sineFrequencies: [0.73, 1.9, 0.31], // Offset freqs for variety
      sineAmplitudes: [0.3, 0.2, 0.15], // Subtler than OpenClose
      sinePhaseOffsets: [1.2, 0.5, 2.8], // Phase offsets for desync
      baseValue: 0.5, // Neutral center
      jitterAmount: 0.06, // Small randomness
      audioGain: 0.8, // Lower gain — subtler
      smoothingFactor: 0.70, // More smoothing for shape
      clampMin: 0.0, // Neutral shape
      clampMax: 1.0, // Full deformation
    ),
  ];

  // ═════════════════════════════════════════════════════════════════════════
  // LISTENING ANIMATIONS — when user's microphone is active
  // ═════════════════════════════════════════════════════════════════════════

  static const List<AnimationEntry> listeningAnimations = [
    // ── Listen_HeadTilt ──
    // Close the mouth and set an attentive expression.
    AnimationEntry(
      name: 'Listen_HeadTilt',
      description: 'Sets the blushing/attentive expression when '
          'listening. Closes the mouth to show the character is '
          'not speaking.',
      trigger: AnimationTrigger.userSpeaking,
      target: AnimParamTarget.expression,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.medium,
      expressionId: ExpressionMap.blushing,
    ),

    // ── Listen_EyeFocus ──
    // Very subtle mouth/breathing oscillation to show the character
    // is alive and engaged while listening.
    // Drives: ParamMouthOpenY (tiny values 0–0.08)
    AnimationEntry(
      name: 'Listen_EyeFocus',
      description: 'Very subtle mouth/breathing movement while '
          'listening. Tiny oscillation (0–0.08) shows the character '
          'is alive and attentive without looking like speech.',
      trigger: AnimationTrigger.userSpeaking,
      target: AnimParamTarget.mouthOpenY,
      driver: AnimDriver.sineWave,
      priority: AnimPriority.medium,
      looping: true,
      intervalMs: 80, // Slower tick rate for subtle effect
      sineFrequencies: [1.5],
      sineAmplitudes: [0.03],
      sinePhaseOffsets: [0.0],
      baseValue: 0.03,
      smoothingFactor: 0.5,
      clampMin: 0.0,
      clampMax: 0.08,
    ),

    // ── Listen_SmallBlink ──
    // Blinking during listening — handled by native CubismEyeBlink.
    AnimationEntry(
      name: 'Listen_SmallBlink',
      description: 'Eye blinking while listening. Handled natively.',
      trigger: AnimationTrigger.userSpeaking,
      target: AnimParamTarget.eyeLOpen,
      driver: AnimDriver.sineWave,
      priority: AnimPriority.low,
      enabled: false, // Native SDK handles blinking
    ),
  ];

  // ═════════════════════════════════════════════════════════════════════════
  // THINKING ANIMATIONS — waiting for AI response
  // ═════════════════════════════════════════════════════════════════════════

  static const List<AnimationEntry> thinkingAnimations = [
    // ── Think_ExpressionCycle ──
    // Cycles through expressions to show the character is "processing":
    //   sweating → dark face → starry → sweating (repeat)
    AnimationEntry(
      name: 'Think_ExpressionCycle',
      description: 'Cycles through sweating → dark face → starry '
          'expressions in a loop to show the character is thinking '
          'and processing. Each expression lasts ~2 seconds.',
      trigger: AnimationTrigger.thinking,
      target: AnimParamTarget.expression,
      driver: AnimDriver.cycleList,
      priority: AnimPriority.medium,
      looping: true,
      expressionCycleList: [
        ExpressionMap.sweating, // Nervous / processing
        ExpressionMap.darkFace, // Serious thought
        ExpressionMap.starryEyed, // Brief hope
        ExpressionMap.sweating, // Back to processing
      ],
      expressionCycleIntervalMs: 2000, // 2s per expression
    ),

    // ── Think_FallbackTimeout ──
    // If the AI takes too long to respond, return to passive state.
    // This is handled in the controller logic, not as a parameter driver.
    AnimationEntry(
      name: 'Think_FallbackTimeout',
      description: 'Safety fallback: if thinking state lasts longer '
          'than 8 seconds, automatically transition back to idle/listening. '
          'Prevents the character from being stuck in thinking forever.',
      trigger: AnimationTrigger.thinking,
      target: AnimParamTarget.expression,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.low,
      durationMs: 8000, // 8 second timeout
    ),
  ];

  // ═════════════════════════════════════════════════════════════════════════
  // EMOTION ANIMATIONS — personality and expression
  // ═════════════════════════════════════════════════════════════════════════

  static const List<AnimationEntry> emotionAnimations = [
    // ── Emotion_Happy ──
    AnimationEntry(
      name: 'Emotion_Happy',
      description: 'Cheerful, starry-eyed expression. Used for '
          'positive interactions and greetings.',
      trigger: AnimationTrigger.emotion,
      target: AnimParamTarget.expression,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.high,
      expressionId: ExpressionMap.happy,
    ),

    // ── Emotion_Surprised ──
    AnimationEntry(
      name: 'Emotion_Surprised',
      description: 'Surprised expression. Triggered by unexpected '
          'user input or events.',
      trigger: AnimationTrigger.emotion,
      target: AnimParamTarget.expression,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.high,
      expressionId: ExpressionMap.surprised,
    ),

    // ── Emotion_Thinking ──
    AnimationEntry(
      name: 'Emotion_Thinking',
      description: 'Sweating / nervous expression. Shows the character '
          'is deep in thought or uncertain.',
      trigger: AnimationTrigger.emotion,
      target: AnimParamTarget.expression,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.high,
      expressionId: ExpressionMap.sweating,
    ),

    // ── Emotion_Confident ──
    AnimationEntry(
      name: 'Emotion_Confident',
      description: 'Confident smirk expression. Used when the character '
          'gives a definitive answer.',
      trigger: AnimationTrigger.emotion,
      target: AnimParamTarget.expression,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.high,
      expressionId: ExpressionMap.confident,
    ),
  ];

  // ═════════════════════════════════════════════════════════════════════════
  // INTERACTION ANIMATIONS — UI events (tap, gesture)
  // ═════════════════════════════════════════════════════════════════════════

  static const List<AnimationEntry> interactionAnimations = [
    // ── Wave_Hello ──
    AnimationEntry(
      name: 'Wave_Hello',
      description: 'Greets the user with a happy expression and '
          'an idle motion (wave / gesture).',
      trigger: AnimationTrigger.interaction,
      target: AnimParamTarget.motionGroup,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.high,
      motionGroup: 'Idle',
      motionPriority: 3, // Force priority — plays immediately
      expressionId: ExpressionMap.happy,
    ),

    // ── Nod_Yes ──
    AnimationEntry(
      name: 'Nod_Yes',
      description: 'Nods in agreement. Triggers an idle_nod motion.',
      trigger: AnimationTrigger.interaction,
      target: AnimParamTarget.motionGroup,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.high,
      motionGroup: 'Idle',
      motionPriority: 2,
    ),
  ];

  // ═════════════════════════════════════════════════════════════════════════
  // COMMAND ACTIONS — triggered by voice commands (highest priority)
  // ═════════════════════════════════════════════════════════════════════════
  //
  // ┌──────────────────────────────────────────────────────────────────────┐
  // │  Command animations OVERRIDE all other animations.                  │
  // │  They play ONCE then return to the current assistant state.          │
  // │  Priority: Command > Talking > Idle                                 │
  // └──────────────────────────────────────────────────────────────────────┘

  static const List<AnimationEntry> commandAnimations = [
    // ──────────────────────────────────────────────────────────────────────
    // Command_照相  —  Camera / take photo animation
    // ──────────────────────────────────────────────────────────────────────
    // When it plays  : Voice command "take a photo" detected
    // Which state    : Any state (overrides all)
    // Loop behavior  : Plays ONCE then returns to previous state
    // Motion group   : 照相
    // ──────────────────────────────────────────────────────────────────────
    AnimationEntry(
      name: 'Command_照相',
      description: 'Camera / photo-taking animation. '
          'Triggered by voice command. Plays once at Force priority '
          'and returns to previous assistant state.',
      trigger: AnimationTrigger.interaction,
      target: AnimParamTarget.motionGroup,
      driver: AnimDriver.oneShot,
      priority: AnimPriority.high,
      motionGroup: '照相',
      motionPriority: 3, // Force — overrides everything
      durationMs: 4000, // Estimated motion duration before returning
    ),
  ];

  /// Maps voice command keys to animation entry names.
  /// Used by the controller to look up which animation to play.
  ///
  /// Example:
  ///   COMMAND_ACTIONS = { "take_photo": "Command_照相" }
  static const Map<String, String> COMMAND_ACTIONS = {
    'take_photo': 'Command_照相',
  };

  // ═════════════════════════════════════════════════════════════════════════
  // ALL ANIMATIONS — combined flat list
  // ═════════════════════════════════════════════════════════════════════════

  /// Every animation defined above, in one list.
  static const List<AnimationEntry> allAnimations = [
    ...idleAnimations,
    ...speakingAnimations,
    ...listeningAnimations,
    ...thinkingAnimations,
    ...emotionAnimations,
    ...interactionAnimations,
    ...commandAnimations,
  ];

  /// Get all enabled animations for a given trigger.
  static List<AnimationEntry> getAnimationsForTrigger(
      AnimationTrigger trigger) {
    return allAnimations
        .where((a) => a.enabled && a.trigger == trigger)
        .toList();
  }

  /// Find an animation by name. Returns null if not found.
  static AnimationEntry? findByName(String name,
      {List<AnimationEntry>? fromList}) {
    try {
      return (fromList ?? allAnimations).firstWhere((a) => a.name == name);
    } catch (_) {
      return null;
    }
  }
  // ═════════════════════════════════════════════════════════════════════════
  // MODEL-SPECIFIC ANIMATION FACTORY
  // ═════════════════════════════════════════════════════════════════════════

  /// Generate a complete set of animation entries for a given [CompanionModel].
  ///
  /// Reuses the common speaking/listening/thinking structure but swaps
  /// expression IDs and motion groups based on the model's config.
  static ModelAnimationSet forModel(CompanionModel model) {
    final expr = model.expressions;
    final motions = model.motions;

    // ── Idle animations (model-specific motion groups) ──
    final idleAnims = <AnimationEntry>[
      for (final group in motions.idleGroups)
        if (model.id == CompanionRegistry.march7th.id && group == '捂脸')
          const AnimationEntry(
            name: 'Idle_捂脸',
            description: 'Facepalm pose held briefly during the idle loop.',
            trigger: AnimationTrigger.idle,
            target: AnimParamTarget.parameterOverride,
            driver: AnimDriver.oneShot,
            priority: AnimPriority.low,
            durationMs: 2600,
            parameterValues: {'Param26': 1.0},
            randomIntervalMin: 900,
            randomIntervalMax: 2200,
          )
        else
          AnimationEntry(
            name: 'Idle_$group',
            description: 'Idle loop animation using motion group $group.',
            trigger: AnimationTrigger.idle,
            target: AnimParamTarget.motionGroup,
            driver: AnimDriver.periodicLoop,
            priority: AnimPriority.low,
            looping: true,
            motionGroup: group,
            motionPriority: 2,
            durationMs: motions.idleGroupDurationsMs[group],
            randomIntervalMin: 900,
            randomIntervalMax: 2200,
          ),
    ];

    // ── Speaking animations (model-aware) ──
    final speakAnims = <AnimationEntry>[
      if (model.id == CompanionRegistry.icegirl.id)
        const AnimationEntry(
          name: 'Talk_Mouth_OpenClose',
          description: 'IceGirl-specific mouth open/close tuned for real-time '
              'LiveKit speech response with event-driven push.',
          trigger: AnimationTrigger.aiSpeaking,
          target: AnimParamTarget.mouthOpenY,
          driver: AnimDriver.audioWithSineFallback,
          priority: AnimPriority.high,
          looping: true,
          intervalMs: 16, // 60fps fallback timer (primary path is event-driven)
          sineFrequencies: [0.9, 2.1, 0.45],
          sineAmplitudes: [0.18, 0.1, 0.05],
          sinePhaseOffsets: [0.0, 0.0, 0.0],
          baseValue: 0.0,
          jitterAmount: 0.02,
          audioGain: 1.35, // Higher gain for more responsive mouth movement
          smoothingFactor: 0.18, // Lower = faster EMA convergence
          clampMin: 0.0,
          clampMax: 1.0,
        )
      else
        speakingAnimations[0],
      if (model.id == CompanionRegistry.icegirl.id)
        const AnimationEntry(
          name: 'Talk_Mouth_Transform',
          description: 'IceGirl-specific mouth shape tuned for real-time '
              'speech variation with event-driven push.',
          trigger: AnimationTrigger.aiSpeaking,
          target: AnimParamTarget.mouthForm,
          driver: AnimDriver.audioWithSineFallback,
          priority: AnimPriority.high,
          looping: true,
          intervalMs: 16, // 60fps fallback timer (primary path is event-driven)
          sineFrequencies: [0.7, 1.6, 0.28],
          sineAmplitudes: [0.16, 0.1, 0.05],
          sinePhaseOffsets: [1.1, 0.45, 2.4],
          baseValue: 0.0,
          jitterAmount: 0.02,
          audioGain: 1.1, // Slightly higher gain for better shape response
          smoothingFactor: 0.28, // Lower = faster EMA convergence
          clampMin: -0.55,
          clampMax: 0.75,
        )
      else if (model.id == CompanionRegistry.march7th.id)
        const AnimationEntry(
          name: 'Talk_Mouth_Transform',
          description: 'March 7th mouth form tuned for the assets/model rig so '
              'speech can swing between rounded and wide phoneme shapes.',
          trigger: AnimationTrigger.aiSpeaking,
          target: AnimParamTarget.mouthForm,
          driver: AnimDriver.audioWithSineFallback,
          priority: AnimPriority.high,
          looping: true,
          intervalMs: 40,
          sineFrequencies: [0.73, 1.9, 0.31],
          sineAmplitudes: [0.2, 0.12, 0.06],
          sinePhaseOffsets: [1.2, 0.5, 2.8],
          baseValue: 0.0,
          jitterAmount: 0.04,
          audioGain: 1.0,
          smoothingFactor: 0.48,
          clampMin: -0.55,
          clampMax: 0.75,
        )
      else
        speakingAnimations[1],
      if (motions.speakingGroup != null)
        AnimationEntry(
          name: 'Speak_BaseMotion',
          description: 'Looped speaking motion group for subtle body movement.',
          trigger: AnimationTrigger.aiSpeaking,
          target: AnimParamTarget.motionGroup,
          driver: AnimDriver.oneShot,
          priority: AnimPriority.medium,
          looping: true,
          motionGroup: motions.speakingGroup!,
          motionPriority: 2,
          durationMs: motions.speakingMotionIntervalMs,
        ),
      if (motions.speakingExpressions.isNotEmpty)
        AnimationEntry(
          name: 'Speak_ExpressionCycle',
          description: 'Cycles through friendly expressions while the AI is '
              'speaking.',
          trigger: AnimationTrigger.aiSpeaking,
          target: AnimParamTarget.expression,
          driver: AnimDriver.cycleList,
          priority: AnimPriority.medium,
          looping: true,
          expressionCycleList: motions.speakingExpressions,
          expressionCycleIntervalMs: motions.speakingExpressionIntervalMs,
        ),
    ];

    // ── Listening animations (model-specific expression) ──
    final listenAnims = <AnimationEntry>[
      AnimationEntry(
        name: 'Listen_HeadTilt',
        description: 'Attentive expression while listening.',
        trigger: AnimationTrigger.userSpeaking,
        target: AnimParamTarget.expression,
        driver: AnimDriver.oneShot,
        priority: AnimPriority.medium,
        expressionId: expr.blushing,
      ),
      if (motions.listeningExpressions.isNotEmpty)
        AnimationEntry(
          name: 'Listen_ExpressionCycle',
          description: 'Cycles cute expressions while the microphone is '
              'active.',
          trigger: AnimationTrigger.userSpeaking,
          target: AnimParamTarget.expression,
          driver: AnimDriver.cycleList,
          priority: AnimPriority.medium,
          looping: true,
          expressionCycleList: motions.listeningExpressions,
          expressionCycleIntervalMs: motions.listeningExpressionIntervalMs,
        ),
      if (motions.listeningGroup != null)
        AnimationEntry(
          name: 'Listen_BaseMotion',
          description: 'Cute mic-on motion loop for attentive head shakes and '
              'lively body language while the microphone is active.',
          trigger: AnimationTrigger.userSpeaking,
          target: AnimParamTarget.motionGroup,
          driver: AnimDriver.oneShot,
          priority: AnimPriority.medium,
          looping: true,
          motionGroup: motions.listeningGroup!,
          motionPriority: 2,
          durationMs: motions.listeningMotionIntervalMs,
        ),
      const AnimationEntry(
        name: 'Listen_EyeFocus',
        description: 'Subtle breathing while listening.',
        trigger: AnimationTrigger.userSpeaking,
        target: AnimParamTarget.mouthOpenY,
        driver: AnimDriver.sineWave,
        priority: AnimPriority.medium,
        looping: true,
        intervalMs: 80,
        sineFrequencies: [1.5],
        sineAmplitudes: [0.03],
        sinePhaseOffsets: [0.0],
        baseValue: 0.03,
        smoothingFactor: 0.5,
        clampMin: 0.0,
        clampMax: 0.08,
      ),
    ];

    // ── Thinking animations (model-specific expressions) ──
    final thinkAnims = <AnimationEntry>[
      AnimationEntry(
        name: 'Think_ExpressionCycle',
        description: 'Cycles expressions while thinking.',
        trigger: AnimationTrigger.thinking,
        target: AnimParamTarget.expression,
        driver: AnimDriver.cycleList,
        priority: AnimPriority.medium,
        looping: true,
        expressionCycleList: [
          expr.sweating,
          expr.darkFace,
          expr.happy,
          expr.sweating,
        ],
        expressionCycleIntervalMs: 2000,
      ),
      const AnimationEntry(
        name: 'Think_FallbackTimeout',
        description: 'Return to idle after 8s in thinking state.',
        trigger: AnimationTrigger.thinking,
        target: AnimParamTarget.expression,
        driver: AnimDriver.oneShot,
        priority: AnimPriority.low,
        durationMs: 8000,
      ),
    ];

    // ── Emotion animations (model-specific expressions) ──
    final emotionAnims = <AnimationEntry>[
      AnimationEntry(
        name: 'Emotion_Happy',
        description: 'Happy expression.',
        trigger: AnimationTrigger.emotion,
        target: AnimParamTarget.expression,
        driver: AnimDriver.oneShot,
        priority: AnimPriority.high,
        expressionId: expr.happy,
      ),
      AnimationEntry(
        name: 'Emotion_Surprised',
        description: 'Surprised expression.',
        trigger: AnimationTrigger.emotion,
        target: AnimParamTarget.expression,
        driver: AnimDriver.oneShot,
        priority: AnimPriority.high,
        expressionId: expr.surprised,
      ),
      AnimationEntry(
        name: 'Emotion_Thinking',
        description: 'Sweating / nervous expression.',
        trigger: AnimationTrigger.emotion,
        target: AnimParamTarget.expression,
        driver: AnimDriver.oneShot,
        priority: AnimPriority.high,
        expressionId: expr.sweating,
      ),
      AnimationEntry(
        name: 'Emotion_Confident',
        description: 'Confident expression.',
        trigger: AnimationTrigger.emotion,
        target: AnimParamTarget.expression,
        driver: AnimDriver.oneShot,
        priority: AnimPriority.high,
        expressionId: expr.confident,
      ),
    ];

    // ── Interaction animations (model-specific hello group) ──
    final interactionAnims = <AnimationEntry>[
      if (motions.helloGroup != null)
        AnimationEntry(
          name: 'Wave_Hello',
          description: 'Greeting animation.',
          trigger: AnimationTrigger.interaction,
          target: AnimParamTarget.motionGroup,
          driver: AnimDriver.oneShot,
          priority: AnimPriority.high,
          motionGroup: motions.helloGroup!,
          motionPriority: 3,
          durationMs: motions.helloDurationMs,
          expressionId: expr.happy,
        ),
    ];

    // ── Command animations (model-specific command groups) ──
    final commandAnims = <AnimationEntry>[
      for (final entry in motions.commandGroups.entries)
        AnimationEntry(
          name: 'Command_${entry.value}',
          description: 'Command animation for ${entry.key}.',
          trigger: AnimationTrigger.interaction,
          target: AnimParamTarget.motionGroup,
          driver: AnimDriver.oneShot,
          priority: AnimPriority.high,
          motionGroup: entry.value,
          motionPriority: 3,
          durationMs: 4000,
        ),
    ];

    final commandActions = <String, String>{
      for (final entry in motions.commandGroups.entries)
        entry.key: 'Command_${entry.value}',
    };

    final all = [
      ...idleAnims,
      ...speakAnims,
      ...listenAnims,
      ...thinkAnims,
      ...emotionAnims,
      ...interactionAnims,
      ...commandAnims,
    ];

    return ModelAnimationSet(
      allAnimations: all,
      commandActions: commandActions,
    );
  }
}

/// Holds a complete set of animations generated for a specific model.
class ModelAnimationSet {
  const ModelAnimationSet({
    required this.allAnimations,
    required this.commandActions,
  });

  final List<AnimationEntry> allAnimations;
  final Map<String, String> commandActions;

  /// Get all enabled animations for a given trigger.
  List<AnimationEntry> getAnimationsForTrigger(AnimationTrigger trigger) {
    return allAnimations
        .where((a) => a.enabled && a.trigger == trigger)
        .toList();
  }

  /// Find an animation by name.
  AnimationEntry? findByName(String name) {
    try {
      return allAnimations.firstWhere((a) => a.name == name);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. PLAY ORDER — Manual animation priority / arrangement
// ─────────────────────────────────────────────────────────────────────────────

const List<String> PLAY_ORDER = [
  'Idle_摇脸',
  'Idle_比耶',
  'Listen_HeadTilt',
  'Listen_EyeFocus',
  'Listen_SmallBlink',
  'Think_ExpressionCycle',
  'Think_FallbackTimeout',
  'Talk_Mouth_OpenClose',
  'Talk_Mouth_Transform',
  'Emotion_Happy',
  'Emotion_Surprised',
  'Emotion_Thinking',
  'Emotion_Confident',
  'Wave_Hello',
  'Nod_Yes',
  'Command_照相',
];
