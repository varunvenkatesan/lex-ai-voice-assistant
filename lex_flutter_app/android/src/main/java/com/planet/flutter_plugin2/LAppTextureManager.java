package com.planet.flutter_plugin2;

import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.opengl.GLES20;
import android.opengl.GLUtils;
import android.util.Log;
import com.live2d.sdk.cubism.framework.CubismFramework;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Texture management for Live2D models.
 * Loads PNG textures from Android assets and creates OpenGL textures.
 */
public class LAppTextureManager {

    public static class TextureInfo {
        public int id;
        public int width;
        public int height;
        public String filePath;
    }

    public TextureInfo createTextureFromPngFile(String filePath) {
        // Check if already loaded
        for (TextureInfo textureInfo : textures) {
            if (textureInfo.filePath.equals(filePath)) {
                return textureInfo;
            }
        }

        AssetManager assetManager = LAppPal.getContext().getAssets();

        // Build candidate paths (literal + URL-encoded variants)
        Set<String> candidates = new LinkedHashSet<>();
        String normalized = filePath.trim().replace('\\', '/');
        candidates.add(normalized);
        // URL-encode (preserving '/'), handles spaces -> %20
        String encoded = Uri.encode(normalized, "/");
        if (!encoded.equals(normalized)) {
            candidates.add(encoded);
        }

        InputStream stream = null;
        String successPath = null;
        for (String candidate : candidates) {
            try {
                stream = assetManager.open(candidate);
                successPath = candidate;
                Log.d("[Live2D]", "Texture opened with: " + candidate);
                break;
            } catch (IOException e) {
                // try next candidate
            }
        }
        if (stream == null) {
            Log.e("[Live2D]", "Cannot open texture (tried " + candidates.size() + " paths): " + filePath);
            Log.e("[Live2D]", "  Candidates: " + candidates);
            return null;
        }

        Bitmap bitmap = BitmapFactory.decodeStream(stream);
        if (bitmap == null) {
            Log.e("[Live2D]", "Failed to decode texture: " + filePath);
            return null;
        }

        try {
            if (stream != null) stream.close();
        } catch (IOException e) {
            // ignore
        }

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0);

        int[] textureId = new int[1];
        GLES20.glGenTextures(1, textureId, 0);
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId[0]);

        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0);

        GLES20.glGenerateMipmap(GLES20.GL_TEXTURE_2D);
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR_MIPMAP_LINEAR);
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);

        TextureInfo textureInfo = new TextureInfo();
        textureInfo.filePath = filePath;
        textureInfo.width = bitmap.getWidth();
        textureInfo.height = bitmap.getHeight();
        textureInfo.id = textureId[0];

        textures.add(textureInfo);

        bitmap.recycle();

        if (LAppDefine.DEBUG_LOG_ENABLE) {
            CubismFramework.coreLogFunction("Create texture: " + filePath);
        }

        return textureInfo;
    }

    private final List<TextureInfo> textures = new ArrayList<TextureInfo>();
}
