package com.planet.flutter_plugin2;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.net.Uri;
import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.opengl.GLUtils;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;

import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;

/**
 * Flutter PlatformView that renders a Live2D model using GLSurfaceView.
 * Handles method channel calls from Dart for loading models, playing motions,
 * setting expressions, and controlling lip sync.
 */
public class Live2dView implements PlatformView, MethodChannel.MethodCallHandler {
    private static final String TAG = "[Live2D]";
    private static final String DEFAULT_MODEL_ASSET_PATH =
            "flutter_assets/packages/flutter_plugin2/assets/model/march 7th.model3.json";
    private static final String DEFAULT_BACKGROUND_ASSET_PATH =
            "flutter_assets/packages/flutter_plugin2/assets/background/backgrund VA .png";
    private final FrameLayout rootView;
    private final BackgroundQuadRenderer backgroundRenderer;
    private GLSurfaceView glSurfaceView;
    private final MethodChannel methodChannel;
    private final Context context;
    private boolean surfaceReady = false;
    private String pendingModelPath = null;
    // Track the last loaded model path so it can be reloaded on surface recreation
    private String lastModelPath = null;
    private String lastBackgroundPath = null;
    private boolean isHidden = false;

    public Live2dView(final Context context,
                      BinaryMessenger messenger,
                      int id,
                      Map<String, Object> params,
                      View containerView) {
        this.context = context;

        // Initialize LAppDelegate
        LAppDelegate.getInstance().onStart(context);

        rootView = new FrameLayout(context);
        rootView.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        rootView.setBackgroundColor(Color.TRANSPARENT);
        backgroundRenderer = new BackgroundQuadRenderer();

        // Create GLSurfaceView
        glSurfaceView = new GLSurfaceView(context);
        glSurfaceView.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        glSurfaceView.setEGLContextClientVersion(2);

        // Enable transparent background so Flutter background shows through
        glSurfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0);
        glSurfaceView.getHolder().setFormat(android.graphics.PixelFormat.TRANSLUCENT);
        // Removed setZOrderOnTop(true) — it forces the GL surface above all Flutter widgets.
        // Without it, Flutter can composite its UI on top of this view correctly.
        glSurfaceView.setZOrderMediaOverlay(false);
        // Preserve the EGL context across pause/resume to keep loaded textures valid.
        glSurfaceView.setPreserveEGLContextOnPause(true);

        glSurfaceView.setRenderer(new GLSurfaceView.Renderer() {
            @Override
            public void onSurfaceCreated(GL10 gl, EGLConfig config) {
                LAppDelegate.getInstance().onSurfaceCreated();
                backgroundRenderer.onSurfaceCreated();
                surfaceReady = true;

                // Load pending model if one was requested before surface was ready
                if (pendingModelPath != null) {
                    loadModelOnGLThread(pendingModelPath);
                    pendingModelPath = null;
                } else if (lastModelPath != null) {
                    // Surface was recreated (e.g. EGL context lost after pause);
                    // reload the model so its textures are valid again.
                    Log.d(TAG, "Surface recreated — reloading model: " + lastModelPath);
                    loadModelOnGLThread(lastModelPath);
                }
                loadBackgroundOnGLThread(
                        lastBackgroundPath != null
                                ? lastBackgroundPath
                                : DEFAULT_BACKGROUND_ASSET_PATH
                );
            }

            @Override
            public void onSurfaceChanged(GL10 gl, int width, int height) {
                LAppDelegate.getInstance().onSurfaceChanged(width, height);
                backgroundRenderer.onSurfaceChanged(width, height);
            }

            @Override
            public void onDrawFrame(GL10 gl) {
                GLES20.glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
                GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT | GLES20.GL_DEPTH_BUFFER_BIT);
                GLES20.glClearDepthf(1.0f);
                backgroundRenderer.draw();
                LAppDelegate.getInstance().renderLive2D();
            }
        });

        glSurfaceView.setRenderMode(GLSurfaceView.RENDERMODE_CONTINUOUSLY);
        rootView.addView(glSurfaceView);

        setBackgroundAsset(DEFAULT_BACKGROUND_ASSET_PATH);

        // Touch handling
        glSurfaceView.setOnTouchListener(new View.OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
                float x = event.getX();
                float y = event.getY();
                int width = LAppDelegate.getInstance().getWindowWidth();
                int height = LAppDelegate.getInstance().getWindowHeight();
                if (width <= 0 || height <= 0) return true;

                float modelX = (x / width * 2.0f - 1.0f);
                float modelY = -(y / height * 2.0f - 1.0f);
                LAppLive2DManager manager = LAppLive2DManager.getInstance();
                if (manager == null) return true;

                switch (event.getAction()) {
                    case MotionEvent.ACTION_DOWN:
                        manager.onDrag(modelX, modelY);
                        break;
                    case MotionEvent.ACTION_MOVE:
                        // Drag: character's face/eyes follow the finger
                        manager.onDrag(modelX, modelY);
                        break;
                    case MotionEvent.ACTION_UP:
                        // Reset gaze to neutral on finger lift
                        manager.onDrag(0.0f, 0.0f);
                        manager.onTap(modelX, modelY);
                        break;
                }
                return true;
            }
        });

        // Set up method channel
        methodChannel = new MethodChannel(messenger, "plugins.felix.angelov/textview_" + id);
        methodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "l2d_setModelJsonPath": {
                Map<String, String> args = (Map<String, String>) call.arguments;
                String path = args.get("path");
                Log.d(TAG, "setModelJsonPath: " + path);

                if (surfaceReady) {
                    glSurfaceView.queueEvent(() -> loadModelOnGLThread(path));
                } else {
                    pendingModelPath = path;
                }
                result.success(null);
                break;
            }
            case "l2d_setBackgroundPath": {
                Map<String, String> args = (Map<String, String>) call.arguments;
                String path = args != null ? args.get("path") : null;
                setBackgroundAsset(path);
                result.success(null);
                break;
            }
            case "shakeEvent": {
                // Trigger random expression
                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null && manager.getModelNum() > 0) {
                        LAppModel model = manager.getModel(0);
                        if (model != null) {
                            model.setRandomExpression();
                        }
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_startMotion": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                String group = (String) args.get("group");
                int number = (int) args.get("number");
                int priority = (int) args.get("priority");

                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null && manager.getModelNum() > 0) {
                        LAppModel model = manager.getModel(0);
                        if (model != null) {
                            model.startMotion(group, number, priority);
                        }
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_startRandomMotion": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                String group = (String) args.get("group");
                int priority = (int) args.get("priority");

                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null && manager.getModelNum() > 0) {
                        LAppModel model = manager.getModel(0);
                        if (model != null) {
                            model.startRandomMotion(group, priority);
                        }
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_setExpression": {
                Map<String, String> args = (Map<String, String>) call.arguments;
                String expressionId = args.get("id");

                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null && manager.getModelNum() > 0) {
                        LAppModel model = manager.getModel(0);
                        if (model != null) {
                            model.setExpression(expressionId);
                        }
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_setRandomExpression": {
                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null && manager.getModelNum() > 0) {
                        LAppModel model = manager.getModel(0);
                        if (model != null) {
                            model.setRandomExpression();
                        }
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_setLipSync": {
                float value = ((Number) call.arguments).floatValue();
                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null && manager.getModelNum() > 0) {
                        LAppModel model = manager.getModel(0);
                        if (model != null) {
                            model.setLipSyncValue(value);
                        }
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_setMouthForm": {
                float formValue = ((Number) call.arguments).floatValue();
                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null && manager.getModelNum() > 0) {
                        LAppModel model = manager.getModel(0);
                        if (model != null) {
                            model.setMouthFormValue(formValue);
                        }
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_stopMotions": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                boolean resetPose = true;
                if (args != null && args.get("resetPose") instanceof Boolean) {
                    resetPose = (Boolean) args.get("resetPose");
                }

                final boolean finalResetPose = resetPose;
                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null) {
                        manager.stopAllMotions(finalResetPose);
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_SpeakMotion": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                boolean isSpeaking = false;
                if (args != null && args.get("isSpeaking") instanceof Boolean) {
                    isSpeaking = (Boolean) args.get("isSpeaking");
                }

                if (!isSpeaking) {
                    glSurfaceView.queueEvent(() -> {
                        LAppLive2DManager manager = LAppLive2DManager.getInstance();
                        if (manager != null) {
                            manager.stopAllMotions(true);
                        }
                    });
                }
                result.success(null);
                break;
            }
            case "l2d_hide": {
                // Hide the GL surface and stop continuous rendering.
                // We intentionally do NOT call onPause() here because that
                // destroys the EGL context and invalidates all loaded textures.
                // Switching to WHEN_DIRTY + GONE is enough to stop the GPU work.
                Log.d(TAG, "Hiding GL surface (no onPause — preserving context)");
                isHidden = true;
                glSurfaceView.setRenderMode(GLSurfaceView.RENDERMODE_WHEN_DIRTY);
                glSurfaceView.setVisibility(View.GONE);
                result.success(null);
                break;
            }
            case "l2d_show": {
                // Resume continuous GL rendering and make the surface visible.
                // No onResume() needed because we never called onPause().
                Log.d(TAG, "Showing GL surface (resuming render loop)");
                isHidden = false;
                if (surfaceReady && lastBackgroundPath != null) {
                    glSurfaceView.queueEvent(() -> loadBackgroundOnGLThread(lastBackgroundPath));
                }
                glSurfaceView.setVisibility(View.VISIBLE);
                glSurfaceView.setRenderMode(GLSurfaceView.RENDERMODE_CONTINUOUSLY);
                // If the model was loaded while hidden, force a redraw
                glSurfaceView.requestRender();
                result.success(null);
                break;
            }
            case "setText": {
                // Legacy method - ignore
                result.success(null);
                break;
            }
            case "l2d_setParameter": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                String paramId = (String) args.get("id");
                float value = ((Number) args.get("value")).floatValue();

                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null && manager.getModelNum() > 0) {
                        LAppModel model = manager.getModel(0);
                        if (model != null && model.getModel() != null) {
                            com.live2d.sdk.cubism.framework.id.CubismId cid =
                                com.live2d.sdk.cubism.framework.CubismFramework.getIdManager().getId(paramId);
                            int index = model.getModel().getParameterIndex(cid);
                            if (index >= 0) {
                                model.getModel().setParameterValue(index, value);
                                Log.d(TAG, "setParameter: " + paramId + " = " + value);
                            } else {
                                Log.w(TAG, "Parameter not found: " + paramId);
                            }
                        }
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_setPartOpacityOverride": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                String partId = (String) args.get("id");
                float opacity = ((Number) args.get("opacity")).floatValue();

                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null) {
                        manager.setPartOpacityOverride(partId, opacity);
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_clearPartOpacityOverrides": {
                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null) {
                        manager.clearPartOpacityOverrides();
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_setParameterOverride": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                String paramId = (String) args.get("id");
                float value = ((Number) args.get("value")).floatValue();

                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null) {
                        manager.setParameterOverride(paramId, value);
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_clearParameterOverrides": {
                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null) {
                        manager.clearParameterOverrides();
                    }
                });
                result.success(null);
                break;
            }
            case "l2d_setModelTransform": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                float offsetX = ((Number) args.get("offsetX")).floatValue();
                float offsetY = ((Number) args.get("offsetY")).floatValue();
                float scale = ((Number) args.get("scale")).floatValue();

                glSurfaceView.queueEvent(() -> {
                    LAppLive2DManager manager = LAppLive2DManager.getInstance();
                    if (manager != null) {
                        manager.setModelTransform(offsetX, offsetY, scale);
                    }
                });
                result.success(null);
                break;
            }
            default:
                result.notImplemented();
        }
    }

    private void loadModelOnGLThread(String fullPath) {
        lastModelPath = fullPath; // remember for surface recreation
        try {
            // Parse path: "flutter_assets/packages/flutter_plugin2/assets/model/march 7th.model3.json"
            int lastSlash = fullPath.lastIndexOf('/');
            String dir = fullPath.substring(0, lastSlash + 1);
            String fileName = fullPath.substring(lastSlash + 1);

            Log.d(TAG, "Loading model - dir: " + dir + ", file: " + fileName);

            // Diagnostic: list what's in the asset directories
            Log.d(TAG, "=== DIAGNOSTIC: Listing APK assets ===");
            LAppPal.listAssetsRecursive("flutter_assets");
            Log.d(TAG, "=== END DIAGNOSTIC ===");

            LAppLive2DManager manager = LAppLive2DManager.getInstance();
            manager.loadModel(dir, fileName);
        } catch (Exception e) {
            Log.e(TAG, "Error loading model: " + fullPath, e);
        }
    }

    private void setBackgroundAsset(String requestedPath) {
        final String resolvedPath = resolveBackgroundAssetPath(requestedPath);
        lastBackgroundPath = resolvedPath;
        if (!surfaceReady || glSurfaceView == null) {
            return;
        }

        glSurfaceView.queueEvent(() -> loadBackgroundOnGLThread(resolvedPath));
    }

    private void loadBackgroundOnGLThread(String assetPath) {
        Bitmap bitmap = decodeAssetBitmap(assetPath);
        if (bitmap != null) {
            backgroundRenderer.setBackgroundBitmap(bitmap);
            bitmap.recycle();
            return;
        }

        Log.w(TAG, "Background asset could not be loaded: " + assetPath);
        backgroundRenderer.clearBackground();
    }

    private String resolveBackgroundAssetPath(String requestedPath) {
        String normalized = normalizeModelPath(requestedPath);
        Set<String> candidates = new LinkedHashSet<>();

        if (!normalized.isEmpty()) {
            candidates.add(normalized);
            if (!normalized.startsWith("flutter_assets/")) {
                candidates.add("flutter_assets/" + normalized);
            }
            if (normalized.startsWith("assets/")) {
                candidates.add("flutter_assets/packages/flutter_plugin2/" + normalized);
            }
        }

        candidates.add(DEFAULT_BACKGROUND_ASSET_PATH);

        for (String candidate : candidates) {
            if (assetExists(candidate)) {
                return candidate;
            }
        }

        return DEFAULT_BACKGROUND_ASSET_PATH;
    }

    private Bitmap decodeAssetBitmap(String assetPath) {
        for (String candidate : buildAssetPathCandidates(assetPath)) {
            InputStream inputStream = null;
            try {
                inputStream = context.getAssets().open(candidate);
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inPreferredConfig = Bitmap.Config.RGB_565;
                options.inDither = true;
                return BitmapFactory.decodeStream(inputStream, null, options);
            } catch (IOException ignored) {
                // Try next candidate.
            } finally {
                if (inputStream != null) {
                    try {
                        inputStream.close();
                    } catch (IOException ignored) {
                        // Ignore close exceptions.
                    }
                }
            }
        }
        return null;
    }

    private String resolveModelAssetPath(String requestedPath) {
        String normalized = normalizeModelPath(requestedPath);
        Set<String> candidates = new LinkedHashSet<>();

        if (!normalized.isEmpty()) {
            candidates.add(normalized);
            if (!normalized.startsWith("flutter_assets/")) {
                candidates.add("flutter_assets/" + normalized);
            }
            if (normalized.startsWith("assets/")) {
                candidates.add("flutter_assets/packages/flutter_plugin2/" + normalized);
            }
        }

        candidates.add(DEFAULT_MODEL_ASSET_PATH);

        for (String candidate : candidates) {
            if (assetExists(candidate)) {
                return candidate;
            }
        }

        return DEFAULT_MODEL_ASSET_PATH;
    }

    private String normalizeModelPath(String path) {
        if (path == null) {
            return "";
        }

        String normalized = path.trim().replace('\\', '/');
        if (normalized.isEmpty()) {
            return "";
        }

        int assetsIndex = normalized.indexOf("/assets/");
        if (assetsIndex >= 0) {
            normalized = normalized.substring(assetsIndex + 1);
        }

        while (normalized.startsWith("/")) {
            normalized = normalized.substring(1);
        }
        return normalized;
    }

    private boolean assetExists(String assetPath) {
        for (String candidate : buildAssetPathCandidates(assetPath)) {
            InputStream inputStream = null;
            try {
                inputStream = context.getAssets().open(candidate);
                return true;
            } catch (IOException ignored) {
                // Try next candidate.
            } finally {
                if (inputStream != null) {
                    try {
                        inputStream.close();
                    } catch (IOException ignored) {
                        // Ignore close exceptions.
                    }
                }
            }
        }
        return false;
    }

    private Set<String> buildAssetPathCandidates(String rawPath) {
        Set<String> candidates = new LinkedHashSet<>();
        if (rawPath == null) {
            return candidates;
        }

        String normalized = rawPath.trim().replace('\\', '/');
        while (normalized.startsWith("/")) {
            normalized = normalized.substring(1);
        }
        if (normalized.isEmpty()) {
            return candidates;
        }

        candidates.add(normalized);
        if (normalized.startsWith("flutter_assets/")) {
            candidates.add(normalized.substring("flutter_assets/".length()));
        } else {
            candidates.add("flutter_assets/" + normalized);
        }

        String encoded = Uri.encode(normalized, "/");
        candidates.add(encoded);
        if (encoded.startsWith("flutter_assets/")) {
            candidates.add(encoded.substring("flutter_assets/".length()));
        } else {
            candidates.add("flutter_assets/" + encoded);
        }

        if (normalized.contains("%20")) {
            String decodedSpaces = normalized.replace("%20", " ");
            candidates.add(decodedSpaces);
            if (!decodedSpaces.startsWith("flutter_assets/")) {
                candidates.add("flutter_assets/" + decodedSpaces);
            }
        }

        return candidates;
    }

    private static final class BackgroundQuadRenderer {
        private static final String VERTEX_SHADER =
                "attribute vec4 aPosition;\n" +
                "attribute vec2 aTexCoord;\n" +
                "varying vec2 vTexCoord;\n" +
                "void main() {\n" +
                "  gl_Position = aPosition;\n" +
                "  vTexCoord = aTexCoord;\n" +
                "}";
        private static final String FRAGMENT_SHADER =
                "precision mediump float;\n" +
                "varying vec2 vTexCoord;\n" +
                "uniform sampler2D uTexture;\n" +
                "void main() {\n" +
                "  gl_FragColor = texture2D(uTexture, vTexCoord);\n" +
                "}";
        private static final float[] FULLSCREEN_VERTICES = {
                -1.0f, -1.0f,
                 1.0f, -1.0f,
                -1.0f,  1.0f,
                 1.0f,  1.0f,
        };

        private final FloatBuffer vertexBuffer = ByteBuffer
                .allocateDirect(FULLSCREEN_VERTICES.length * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer();
        private final FloatBuffer texCoordBuffer = ByteBuffer
                .allocateDirect(8 * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer();

        private int program = 0;
        private int textureId = 0;
        private int positionHandle = -1;
        private int texCoordHandle = -1;
        private int samplerHandle = -1;
        private int surfaceWidth = 0;
        private int surfaceHeight = 0;
        private int bitmapWidth = 0;
        private int bitmapHeight = 0;

        BackgroundQuadRenderer() {
            vertexBuffer.put(FULLSCREEN_VERTICES).position(0);
            updateTexCoords();
        }

        void onSurfaceCreated() {
            releaseProgram();
            program = buildProgram(VERTEX_SHADER, FRAGMENT_SHADER);
            if (program == 0) {
                return;
            }
            positionHandle = GLES20.glGetAttribLocation(program, "aPosition");
            texCoordHandle = GLES20.glGetAttribLocation(program, "aTexCoord");
            samplerHandle = GLES20.glGetUniformLocation(program, "uTexture");
            releaseTexture();
        }

        void onSurfaceChanged(int width, int height) {
            surfaceWidth = width;
            surfaceHeight = height;
            updateTexCoords();
        }

        void setBackgroundBitmap(@NonNull Bitmap bitmap) {
            bitmapWidth = bitmap.getWidth();
            bitmapHeight = bitmap.getHeight();
            updateTexCoords();

            if (textureId == 0) {
                int[] textureIds = new int[1];
                GLES20.glGenTextures(1, textureIds, 0);
                textureId = textureIds[0];
            }

            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId);
            GLES20.glTexParameteri(
                    GLES20.GL_TEXTURE_2D,
                    GLES20.GL_TEXTURE_MIN_FILTER,
                    GLES20.GL_LINEAR
            );
            GLES20.glTexParameteri(
                    GLES20.GL_TEXTURE_2D,
                    GLES20.GL_TEXTURE_MAG_FILTER,
                    GLES20.GL_LINEAR
            );
            GLES20.glTexParameteri(
                    GLES20.GL_TEXTURE_2D,
                    GLES20.GL_TEXTURE_WRAP_S,
                    GLES20.GL_CLAMP_TO_EDGE
            );
            GLES20.glTexParameteri(
                    GLES20.GL_TEXTURE_2D,
                    GLES20.GL_TEXTURE_WRAP_T,
                    GLES20.GL_CLAMP_TO_EDGE
            );
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0);
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0);
        }

        void clearBackground() {
            bitmapWidth = 0;
            bitmapHeight = 0;
            updateTexCoords();
            releaseTexture();
        }

        void draw() {
            if (program == 0 || textureId == 0) {
                return;
            }

            GLES20.glUseProgram(program);
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId);
            GLES20.glUniform1i(samplerHandle, 0);

            vertexBuffer.position(0);
            GLES20.glEnableVertexAttribArray(positionHandle);
            GLES20.glVertexAttribPointer(
                    positionHandle,
                    2,
                    GLES20.GL_FLOAT,
                    false,
                    0,
                    vertexBuffer
            );

            texCoordBuffer.position(0);
            GLES20.glEnableVertexAttribArray(texCoordHandle);
            GLES20.glVertexAttribPointer(
                    texCoordHandle,
                    2,
                    GLES20.GL_FLOAT,
                    false,
                    0,
                    texCoordBuffer
            );

            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);

            GLES20.glDisableVertexAttribArray(positionHandle);
            GLES20.glDisableVertexAttribArray(texCoordHandle);
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0);
            GLES20.glUseProgram(0);
        }

        void release() {
            releaseTexture();
            releaseProgram();
        }

        private void updateTexCoords() {
            float xMin = 0.0f;
            float xMax = 1.0f;
            float yMin = 0.0f;
            float yMax = 1.0f;

            if (surfaceWidth > 0 && surfaceHeight > 0 && bitmapWidth > 0 && bitmapHeight > 0) {
                float surfaceAspect = (float) surfaceWidth / (float) surfaceHeight;
                float bitmapAspect = (float) bitmapWidth / (float) bitmapHeight;

                if (surfaceAspect > bitmapAspect) {
                    float visibleHeight = bitmapAspect / surfaceAspect;
                    float inset = (1.0f - visibleHeight) * 0.5f;
                    yMin = inset;
                    yMax = 1.0f - inset;
                } else if (surfaceAspect < bitmapAspect) {
                    float visibleWidth = surfaceAspect / bitmapAspect;
                    float inset = (1.0f - visibleWidth) * 0.5f;
                    xMin = inset;
                    xMax = 1.0f - inset;
                }
            }

            texCoordBuffer.position(0);
            texCoordBuffer.put(new float[]{
                    xMin, yMax,
                    xMax, yMax,
                    xMin, yMin,
                    xMax, yMin,
            });
            texCoordBuffer.position(0);
        }

        private int buildProgram(String vertexSource, String fragmentSource) {
            int vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource);
            int fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource);
            if (vertexShader == 0 || fragmentShader == 0) {
                return 0;
            }

            int createdProgram = GLES20.glCreateProgram();
            GLES20.glAttachShader(createdProgram, vertexShader);
            GLES20.glAttachShader(createdProgram, fragmentShader);
            GLES20.glLinkProgram(createdProgram);

            int[] linkStatus = new int[1];
            GLES20.glGetProgramiv(createdProgram, GLES20.GL_LINK_STATUS, linkStatus, 0);
            if (linkStatus[0] == 0) {
                Log.e(TAG, "Background shader link failed: " + GLES20.glGetProgramInfoLog(createdProgram));
                GLES20.glDeleteProgram(createdProgram);
                createdProgram = 0;
            }

            GLES20.glDeleteShader(vertexShader);
            GLES20.glDeleteShader(fragmentShader);
            return createdProgram;
        }

        private int compileShader(int shaderType, String source) {
            int shader = GLES20.glCreateShader(shaderType);
            GLES20.glShaderSource(shader, source);
            GLES20.glCompileShader(shader);

            int[] compileStatus = new int[1];
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compileStatus, 0);
            if (compileStatus[0] == 0) {
                Log.e(TAG, "Background shader compile failed: " + GLES20.glGetShaderInfoLog(shader));
                GLES20.glDeleteShader(shader);
                return 0;
            }

            return shader;
        }

        private void releaseTexture() {
            if (textureId == 0) {
                return;
            }
            int[] textures = {textureId};
            GLES20.glDeleteTextures(1, textures, 0);
            textureId = 0;
        }

        private void releaseProgram() {
            if (program == 0) {
                return;
            }
            GLES20.glDeleteProgram(program);
            program = 0;
            positionHandle = -1;
            texCoordHandle = -1;
            samplerHandle = -1;
        }
    }

    @Override
    public View getView() {
        return rootView;
    }

    @Override
    public void dispose() {
        if (methodChannel != null) {
            methodChannel.setMethodCallHandler(null);
        }
        if (glSurfaceView != null) {
            // DON'T destroy the global LAppDelegate / CubismFramework singleton.
            // When Flutter recreates this PlatformView (e.g. Login → Home navigation),
            // the new instance's constructor + onSurfaceCreated will reinitialize
            // the engine. Destroying the singleton here creates a race condition
            // where the async cleanup on the GL thread can corrupt the new instance.
            //
            // Just release the models so we don't leak GPU memory, then stop
            // the GL thread cleanly.
            glSurfaceView.queueEvent(() -> {
                LAppLive2DManager manager = LAppLive2DManager.getInstance();
                if (manager != null) {
                    manager.releaseAllModel();
                }
                backgroundRenderer.release();
            });
            glSurfaceView.setVisibility(View.GONE);
            glSurfaceView.setRenderMode(GLSurfaceView.RENDERMODE_WHEN_DIRTY);
            glSurfaceView.onPause();
        }
        if (rootView != null) {
            rootView.setVisibility(View.GONE);
        }
    }
}
