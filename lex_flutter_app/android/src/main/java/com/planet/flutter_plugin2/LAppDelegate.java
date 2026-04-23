package com.planet.flutter_plugin2;

import android.content.Context;
import android.opengl.GLES20;
import com.live2d.sdk.cubism.framework.CubismFramework;

import static android.opengl.GLES20.*;

/**
 * Singleton delegate for the Live2D Cubism SDK lifecycle.
 * Adapted from the official Cubism SDK v4 sample for use in a Flutter PlatformView.
 */
public class LAppDelegate {
    public static LAppDelegate getInstance() {
        if (s_instance == null) {
            s_instance = new LAppDelegate();
        }
        return s_instance;
    }

    public static void releaseInstance() {
        if (s_instance != null) {
            s_instance = null;
        }
    }

    public void onStart(Context context) {
        // ── Phase 1: Reset non-GL state (safe on UI thread) ──
        //
        // Java static fields survive Flutter hot restarts. If the Cubism
        // Framework was initialized on a previous PlatformView, the static
        // flags (s_isInitialized, s_isStarted) and CubismIdManager are stale.
        // The renderer's static shader program IDs point to an old GL context.
        //
        // Reset flags here so onSurfaceCreated() can reinitialize cleanly.
        LAppLive2DManager.releaseInstance();
        CubismFramework.cleanUp();           // resets flags, nulls IdManager
        CubismFramework.startUp(cubismOption); // re-registers options

        textureManager = new LAppTextureManager();
        LAppPal.setContext(context);
        LAppPal.updateTime();
    }

    public void onStop() {
        textureManager = null;
        LAppLive2DManager.releaseInstance();
        CubismFramework.dispose();
    }

    public void onDestroy() {
        releaseInstance();
    }

    public void onSurfaceCreated() {
        GLES20.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        GLES20.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

        GLES20.glEnable(GLES20.GL_BLEND);
        GLES20.glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

        // ── Phase 2: Reset GL state (must run on GL thread) ──
        //
        // Release stale static shader programs that belonged to the old EGL
        // context.  glDeleteProgram silently ignores invalid IDs, so this is
        // safe even if the old context is already destroyed.
        com.live2d.sdk.cubism.framework.rendering.android.CubismRendererAndroid.staticRelease();

        // Create a fresh CubismIdManager & mark framework as initialized.
        CubismFramework.initialize();
    }

    public void onSurfaceChanged(int width, int height) {
        GLES20.glViewport(0, 0, width, height);
        windowWidth = width;
        windowHeight = height;
    }

    public void run() {
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glClearDepthf(1.0f);

        renderLive2D();
    }

    public void renderLive2D() {
        LAppPal.updateTime();

        LAppLive2DManager manager = LAppLive2DManager.getInstance();
        if (manager != null) {
            manager.onUpdate();
        }
    }

    public LAppTextureManager getTextureManager() {
        return textureManager;
    }

    public int getWindowWidth() {
        return windowWidth;
    }

    public int getWindowHeight() {
        return windowHeight;
    }

    private static LAppDelegate s_instance;

    private LAppDelegate() {
        // v4 Framework: Option only has logFunction and loggingLevel
        cubismOption.logFunction = new LAppPal.PrintLogFunction();
        cubismOption.loggingLevel = LAppDefine.cubismLoggingLevel;

        CubismFramework.cleanUp();
        CubismFramework.startUp(cubismOption);
    }

    private final CubismFramework.Option cubismOption = new CubismFramework.Option();
    private LAppTextureManager textureManager;
    private int windowWidth;
    private int windowHeight;
}
