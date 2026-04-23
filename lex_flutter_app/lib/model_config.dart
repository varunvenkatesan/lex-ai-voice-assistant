// ═══════════════════════════════════════════════════════════════════════════════
//
//   📐  MODEL POSITION & SCALE — EASY ADJUSTMENT GUIDE
//
//   To move/resize a model, just change the numbers in its transform block.
//
//   ┌─────────────────────────────────────────────────────────────────────┐
//   │  PARAMETER    │  WHAT IT DOES              │  EXAMPLE VALUES       │
//   ├─────────────────────────────────────────────────────────────────────┤
//   │  offsetX      │  Horizontal position       │  0.0 = center         │
//   │               │  ← negative   positive →   │  -1.0 = far left     │
//   │               │                             │  +1.0 = far right    │
//   ├─────────────────────────────────────────────────────────────────────┤
//   │  offsetY      │  Vertical position         │  0.0 = center         │
//   │               │  ↓ negative   positive ↑   │  -1.0 = bottom       │
//   │               │                             │  +1.0 = top          │
//   ├─────────────────────────────────────────────────────────────────────┤
//   │  scale        │  Size of the model         │  0.5 = half size      │
//   │               │  smaller ←──→ bigger       │  1.0 = default        │
//   │               │                             │  1.5 = 1.5x bigger   │
//   └─────────────────────────────────────────────────────────────────────┘
//
//   💡 TIP: Change a value → hot restart → see the result → repeat!
//
// ═══════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// ✏️  MARCH 7TH — Position & Scale
// ─────────────────────────────────────────────────────────────────────────────
const _march7thTransform = ModelTransform(
  offsetX: 0.9, // horizontal: 0=center, negative=left, positive=right
  offsetY: 0.55, // vertical:   0=center, negative=down, positive=up
  scale: 0.85, // size:       1.0=default, smaller=zoom out, bigger=zoom in
);

// ─────────────────────────────────────────────────────────────────────────────
// ✏️  ICEGIRL — Position & Scale
// ─────────────────────────────────────────────────────────────────────────────
const _icegirlTransform = ModelTransform(
  offsetX: 1.3, // horizontal: 0=center, negative=left, positive=right
  offsetY: 0.62, // vertical:   0=center, negative=down, positive=up
  scale: 0.85, // size:       1.0=default, smaller=zoom out, bigger=zoom in
);

// ─────────────────────────────────────────────────────────────────────────────
// ✈️  ICEGIRL — Hidden Parts (forced off every frame)
// ─────────────────────────────────────────────────────────────────────────────
const _icegirlHiddenParams = {
  'Param41': 0.0, // 翅膀 (wings) parameter — 0 = off
  'ParamHairFront7': 0.0, // 翅膀 physics — 0 = no wing movement
};

// ─────────────────────────────────────────────────────────────────────────────
// ✈️  ICEGIRL — Hidden Parts (part opacity forced to 0 every frame)
// ─────────────────────────────────────────────────────────────────────────────
const _icegirlHiddenParts = {
  'Part34': 0.0, // 翅膀 (wings mesh) — 0 = invisible
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Below this line is internal code — you normally don't need to edit it.
// ═══════════════════════════════════════════════════════════════════════════════

/// Position and scale transform for placing the model on screen.
class ModelTransform {
  const ModelTransform({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
  });

  final double offsetX;
  final double offsetY;
  final double scale;
}

/// Maps semantic expression names → model-specific expression IDs.
class ModelExpressionMap {
  const ModelExpressionMap({
    required this.happy,
    required this.surprised,
    required this.neutral,
    required this.confident,
    required this.blushing,
    required this.darkFace,
    required this.crying,
    required this.sweating,
  });

  final String happy;
  final String surprised;
  final String neutral;
  final String confident;
  final String blushing;
  final String darkFace;
  final String crying;
  final String sweating;
}

/// Motion group configuration per model.
class ModelMotionConfig {
  const ModelMotionConfig({
    required this.idleGroups,
    this.idleGroupDurationsMs = const {},
    this.helloGroup,
    this.helloDurationMs,
    this.listeningGroup,
    this.listeningMotionIntervalMs = 4200,
    this.listeningExpressions = const [],
    this.listeningExpressionIntervalMs = 1800,
    this.speakingGroup,
    this.speakingMotionIntervalMs = 3400,
    this.speakingExpressions = const [],
    this.speakingExpressionIntervalMs = 1800,
    this.commandGroups = const {},
  });

  final List<String> idleGroups;
  final Map<String, int> idleGroupDurationsMs;
  final String? helloGroup;
  final int? helloDurationMs;
  final String? listeningGroup;
  final int listeningMotionIntervalMs;
  final List<String> listeningExpressions;
  final int listeningExpressionIntervalMs;
  final String? speakingGroup;
  final int speakingMotionIntervalMs;
  final List<String> speakingExpressions;
  final int speakingExpressionIntervalMs;
  final Map<String, String> commandGroups;
}

/// Complete definition of one companion model.
class CompanionModel {
  const CompanionModel({
    required this.id,
    required this.displayName,
    required this.modelAssetKey,
    required this.posterAsset,
    required this.expressions,
    required this.motions,
    required this.transform,
    this.hiddenParams = const {},
    this.hiddenParts = const {},
  });

  final String id;
  final String displayName;
  final String modelAssetKey;
  final String posterAsset;
  final ModelExpressionMap expressions;
  final ModelMotionConfig motions;
  final ModelTransform transform;

  /// Parameters forced to specific values every frame (hide parts).
  /// Key = parameter ID, Value = forced value (0.0 = hidden).
  final Map<String, double> hiddenParams;

  /// Parts forced to specific opacity every frame (hide meshes).
  /// Key = part ID, Value = opacity (0.0 = hidden, 1.0 = visible).
  final Map<String, double> hiddenParts;

  /// Native path used by the Live2D SDK.
  String get nativePath => 'flutter_assets/$modelAssetKey';
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPANION REGISTRY
// ─────────────────────────────────────────────────────────────────────────────

class CompanionRegistry {
  CompanionRegistry._();

  // ── March 7th (female companion — default) ──
  static const march7th = CompanionModel(
    id: 'march7th',
    displayName: 'March 7th',
    modelAssetKey:
        'packages/flutter_plugin2/assets/model/march 7th.model3.json',
    posterAsset:
        'packages/flutter_plugin2/assets/UI image/female companion.png',
    expressions: ModelExpressionMap(
      happy: 'exp_08',
      // This rig only ships one clearly "cute neutral" facial preset,
      // so we avoid the gesture-bound exp_01/02/03 expressions here.
      surprised: 'exp_07',
      neutral: 'exp_04',
      confident: 'exp_08',
      blushing: 'exp_04',
      darkFace: 'exp_05',
      crying: 'exp_06',
      sweating: 'exp_07',
    ),
    motions: ModelMotionConfig(
      idleGroups: ['捂脸', '比耶', '照相'],
      idleGroupDurationsMs: const {
        '比耶': 3200,
        '照相': 4000,
      },
      helloGroup: 'Idle',
      listeningGroup: '摇脸',
      listeningMotionIntervalMs: 2600,
      listeningExpressions: ['exp_04', 'exp_08'],
      listeningExpressionIntervalMs: 1800,
      speakingGroup: '摇脸',
      speakingMotionIntervalMs: 2600,
      speakingExpressions: ['exp_04', 'exp_08', 'exp_04'],
      speakingExpressionIntervalMs: 1800,
      commandGroups: {'take_photo': '照相'},
    ),
    transform: _march7thTransform, // ← uses the values defined at top of file
  );

  // ── IceGirl ──
  static const icegirl = CompanionModel(
    id: 'icegirl',
    displayName: 'IceGirl',
    modelAssetKey:
        'packages/flutter_plugin2/assets/model_2/IceGirl Live2D/IceGirl.model3.json',
    posterAsset: 'packages/flutter_plugin2/assets/UI image/icegirl model2.png',
    expressions: ModelExpressionMap(
      happy: 'exp_xingxingyan',
      surprised: 'exp_jingya',
      neutral: 'exp_shetou',
      confident: 'exp_aixinyan',
      blushing: 'exp_lianhong',
      darkFace: 'exp_lianhei',
      crying: 'exp_liulei',
      sweating: 'exp_yihuo',
    ),
    motions: ModelMotionConfig(
      idleGroups: ['Idle', 'MeiYan'],
      helloGroup: 'HuiShou',
      helloDurationMs: 7000,
      listeningGroup: 'Speaking',
      listeningMotionIntervalMs: 2600,
      listeningExpressions: ['exp_lianhong', 'exp_aixinyan'],
      listeningExpressionIntervalMs: 1800,
      speakingGroup: 'Speaking',
      speakingExpressions: [
        'exp_lianhong',
        'exp_waizuiL',
        'exp_xingxingyan',
        'exp_waizuiR',
        'exp_aixinyan',
      ],
      speakingExpressionIntervalMs: 1600,
      commandGroups: {},
    ),
    transform: _icegirlTransform,
    hiddenParams: _icegirlHiddenParams,
    hiddenParts:
        _icegirlHiddenParts, // ← uses the values defined at top of file
  );

  /// All registered companions.
  static const List<CompanionModel> all = [march7th, icegirl];

  /// Default companion.
  static const CompanionModel defaultModel = march7th;

  /// Look up a companion by ID. Returns default if not found.
  static CompanionModel findById(String id) {
    for (final model in all) {
      if (model.id == id) return model;
    }
    return defaultModel;
  }
}
