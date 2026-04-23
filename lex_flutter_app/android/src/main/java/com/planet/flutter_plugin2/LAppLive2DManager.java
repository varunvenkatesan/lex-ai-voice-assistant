package com.planet.flutter_plugin2;

import android.util.Log;
import com.live2d.sdk.cubism.framework.CubismFramework;
import com.live2d.sdk.cubism.framework.id.CubismId;
import com.live2d.sdk.cubism.framework.math.CubismMatrix44;
import com.live2d.sdk.cubism.framework.model.CubismModel;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Manages Live2D models. Simplified from official v4 sample — loads a single model
 * from a given path instead of scanning asset directories.
 */
public class LAppLive2DManager {
    private static final String TAG = "[Live2D]";

    // ═══════════════════════════════════════════════════════════════════════
    // ▶ POSITION / SCALE — Defaults for the March 7th model.
    //   Per-model adjustments sent from Dart via setModelTransform().
    //   X: negative = left,  positive = right
    //   Y: negative = down,  positive = up
    //   SCALE: 1.0 = default, 2.0 = double size, 0.5 = half size
    // ═══════════════════════════════════════════════════════════════════════
    private float characterOffsetX =  0.9f;
    private float characterOffsetY = 0.55f;
    private float characterScale   =  0.85f;

    /**
     * Update position and scale for the current model.
     * Called from Dart when switching companion models.
     */
    public void setModelTransform(float offsetX, float offsetY, float scale) {
        this.characterOffsetX = offsetX;
        this.characterOffsetY = offsetY;
        this.characterScale = scale;
        Log.d(TAG, "Transform updated: x=" + offsetX + " y=" + offsetY + " scale=" + scale);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ▶ PERSISTENT PARAMETER OVERRIDES
    //   Parameters in this map are forced to their value EVERY FRAME.
    //   Used to permanently hide model parts (e.g., wings: Param41=0).
    // ═══════════════════════════════════════════════════════════════════════
    private final Map<String, Float> parameterOverrides = new HashMap<>();

    /** Add a parameter that will be forced to a value every frame. */
    public void setParameterOverride(String paramId, float value) {
        parameterOverrides.put(paramId, value);
        Log.d(TAG, "Parameter override set: " + paramId + " = " + value);
    }

    /** Remove all parameter overrides (e.g., when switching to a different model). */
    public void clearParameterOverrides() {
        parameterOverrides.clear();
        Log.d(TAG, "All parameter overrides cleared");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ▶ PERSISTENT PART OPACITY OVERRIDES
    //   Parts in this map have their opacity forced every frame.
    //   Set opacity to 0.0 to completely hide a part (e.g., wings).
    // ═══════════════════════════════════════════════════════════════════════
    private final Map<String, Float> partOpacityOverrides = new HashMap<>();

    /** Force a part's opacity every frame. 0.0 = invisible, 1.0 = fully visible. */
    public void setPartOpacityOverride(String partId, float opacity) {
        partOpacityOverrides.put(partId, opacity);
        Log.d(TAG, "Part opacity override: " + partId + " = " + opacity);
    }

    /** Clear all part opacity overrides. */
    public void clearPartOpacityOverrides() {
        partOpacityOverrides.clear();
        Log.d(TAG, "All part opacity overrides cleared");
    }

    /**
     * Stop every active motion on every loaded model.
     */
    public void stopAllMotions(boolean resetPose) {
        for (int i = 0; i < models.size(); i++) {
            LAppModel model = getModel(i);
            if (model != null) {
                model.stopAllMotions(resetPose);
            }
        }
        Log.d(TAG, "All motions stopped (resetPose=" + resetPose + ")");
    }

    public static LAppLive2DManager getInstance() {
        if (s_instance == null) {
            s_instance = new LAppLive2DManager();
        }
        return s_instance;
    }

    public static void releaseInstance() {
        if (s_instance != null) {
            s_instance.releaseAllModel();
        }
        s_instance = null;
    }

    public void releaseAllModel() {
        for (LAppModel model : models) {
            model.deleteModel();
        }
        models.clear();
    }

    /**
     * Load a model from the given asset path.
     * @param modelDir Directory containing the model files
     * @param modelJsonName The .model3.json filename
     */
    public void loadModel(String modelDir, String modelJsonName) {
        releaseAllModel();

        LAppModel model = new LAppModel();
        model.loadAssets(modelDir, modelJsonName);
        models.add(model);

        Log.d(TAG, "Model loaded: " + modelDir + modelJsonName);
    }

    /**
     * Update and draw all models. Called each frame from the GL render loop.
     */
    public void onUpdate() {
        int width = LAppDelegate.getInstance().getWindowWidth();
        int height = LAppDelegate.getInstance().getWindowHeight();

        if (width == 0 || height == 0) return;

        for (int i = 0; i < models.size(); i++) {
            LAppModel model = models.get(i);

            if (model.getModel() == null) {
                continue;
            }

            projection.loadIdentity();

            if (model.getModel().getCanvasWidth() > 1.0f && width < height) {
                // Portrait mode: scale to fit width and center vertically
                float aspect = (float) width / (float) height;
                projection.scale(characterScale, aspect * characterScale);
            } else {
                projection.scale((float) height / (float) width * characterScale, characterScale);
            }

            // Apply manual position offset
            projection.translateX(characterOffsetX);
            projection.translateY(characterOffsetY);

            model.update();

            // Apply persistent parameter overrides AFTER update
            // so they take effect this frame regardless of physics/motion
            if (!parameterOverrides.isEmpty() || !partOpacityOverrides.isEmpty()) {
                CubismModel cubismModel = model.getModel();
                if (cubismModel != null) {
                    // Parameter overrides
                    for (Map.Entry<String, Float> entry : parameterOverrides.entrySet()) {
                        CubismId cid = CubismFramework.getIdManager().getId(entry.getKey());
                        int idx = cubismModel.getParameterIndex(cid);
                        if (idx >= 0) {
                            cubismModel.setParameterValue(idx, entry.getValue());
                        }
                    }
                    // Part opacity overrides (hide/show entire parts)
                    for (Map.Entry<String, Float> entry : partOpacityOverrides.entrySet()) {
                        CubismId cid = CubismFramework.getIdManager().getId(entry.getKey());
                        int idx = cubismModel.getPartIndex(cid);
                        if (idx >= 0) {
                            cubismModel.setPartOpacity(idx, entry.getValue());
                        }
                    }
                }
            }

            model.draw(projection);
        }
    }

    public void onDrag(float x, float y) {
        for (int i = 0; i < models.size(); i++) {
            LAppModel model = getModel(i);
            if (model != null) {
                model.setDragging(x, y);
            }
        }
    }

    public void onTap(float x, float y) {
        for (int i = 0; i < models.size(); i++) {
            LAppModel model = models.get(i);

            if (model.hitTest(LAppDefine.HitAreaName.HEAD.getId(), x, y)) {
                model.setRandomExpression();
            } else if (model.hitTest(LAppDefine.HitAreaName.BODY.getId(), x, y)) {
                model.startRandomMotion(
                    LAppDefine.MotionGroup.TAP_BODY.getId(),
                    LAppDefine.Priority.NORMAL.getPriority()
                );
            }
        }
    }

    public LAppModel getModel(int number) {
        if (number < models.size()) {
            return models.get(number);
        }
        return null;
    }

    public int getModelNum() {
        if (models == null) return 0;
        return models.size();
    }

    private static LAppLive2DManager s_instance;

    private LAppLive2DManager() {
        // No auto-load; model will be loaded explicitly via loadModel()
    }

    private final List<LAppModel> models = new ArrayList<>();
    private final CubismMatrix44 projection = CubismMatrix44.create();
}
