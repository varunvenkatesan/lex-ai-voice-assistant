package com.planet.flutter_plugin2;

import android.content.Context;
import android.content.res.AssetManager;
import android.net.Uri;
import android.util.Log;
import com.live2d.sdk.cubism.core.ICubismLogger;

import java.io.IOException;
import java.io.InputStream;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Platform abstraction layer for Live2D, adapted for Flutter plugin.
 * Provides file loading using Android AssetManager and time management.
 */
public class LAppPal {

    private static Context appContext;

    public static void setContext(Context context) {
        appContext = context.getApplicationContext();
    }

    public static Context getContext() {
        return appContext;
    }

    public static class PrintLogFunction implements ICubismLogger {
        @Override
        public void print(String message) {
            Log.d(TAG, message);
        }
    }

    public static void updateTime() {
        s_currentFrame = getSystemNanoTime();
        _deltaNanoTime = s_currentFrame - _lastNanoTime;
        _lastNanoTime = s_currentFrame;
    }

    public static byte[] loadFileAsBytes(final String path) {
        if (appContext == null) {
            Log.e(TAG, "Context not set! Cannot load: " + path);
            return new byte[0];
        }
        IOException lastError = null;
        AssetManager assetManager = appContext.getAssets();

        Set<String> candidates = buildAssetPathCandidates(path);
        Log.d(TAG, "loadFileAsBytes: path=" + path + ", trying " + candidates.size() + " candidates:");
        for (String candidate : candidates) {
            Log.d(TAG, "  trying: [" + candidate + "]");
        }

        for (String candidate : candidates) {
            InputStream fileData = null;
            try {
                fileData = assetManager.open(candidate);

                int fileSize = fileData.available();
                byte[] fileBuffer = new byte[fileSize];
                fileData.read(fileBuffer, 0, fileSize);

                Log.d(TAG, "  SUCCESS with: [" + candidate + "], size=" + fileSize);
                return fileBuffer;
            } catch (IOException e) {
                lastError = e;
            } finally {
                try {
                    if (fileData != null) {
                        fileData.close();
                    }
                } catch (IOException ignored) {
                    // ignore
                }
            }
        }

        if (LAppDefine.DEBUG_LOG_ENABLE) {
            Log.e(TAG, "File open error: " + path, lastError);
        }
        return new byte[0];
    }

    private static Set<String> buildAssetPathCandidates(String rawPath) {
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

    public static float getDeltaTime() {
        return (float) (_deltaNanoTime / 1000000000.0f);
    }

    public static void printLog(String message) {
        Log.d(TAG, message);
    }

    /**
     * Diagnostic: recursively list all assets under the given directory path.
     */
    public static void listAssetsRecursive(String dirPath) {
        if (appContext == null) {
            Log.e(TAG, "Context not set for listAssets");
            return;
        }
        AssetManager am = appContext.getAssets();
        try {
            String[] items = am.list(dirPath);
            if (items == null || items.length == 0) {
                Log.d(TAG, "ASSETS[" + dirPath + "] -> (empty or not a directory)");
                return;
            }
            Log.d(TAG, "ASSETS[" + dirPath + "] -> " + items.length + " items:");
            for (String item : items) {
                String childPath = dirPath.isEmpty() ? item : dirPath + "/" + item;
                Log.d(TAG, "  => " + childPath);
                // Try to recurse into subdirectories
                String[] sub = am.list(childPath);
                if (sub != null && sub.length > 0) {
                    listAssetsRecursive(childPath);
                }
            }
        } catch (IOException e) {
            Log.e(TAG, "Error listing assets at: " + dirPath, e);
        }
    }

    private static long getSystemNanoTime() {
        return System.nanoTime();
    }

    private static double s_currentFrame;
    private static double _lastNanoTime;
    private static double _deltaNanoTime;

    private static final String TAG = "[Live2D]";

    private LAppPal() {}
}
