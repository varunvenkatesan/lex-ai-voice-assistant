package com.planet.flutter_plugin2;

import com.live2d.sdk.cubism.framework.CubismFrameworkConfig.LogLevel;

/**
 * Constants for the Live2D plugin, adapted from the official Cubism SDK sample.
 */
public class LAppDefine {

    public enum Scale {
        DEFAULT(1.0f),
        MAX(2.0f),
        MIN(0.8f);

        private final float value;
        Scale(float value) { this.value = value; }
        public float getValue() { return value; }
    }

    public enum LogicalView {
        LEFT(-1.0f),
        RIGHT(1.0f),
        BOTTOM(-1.0f),
        TOP(1.0f);

        private final float value;
        LogicalView(float value) { this.value = value; }
        public float getValue() { return value; }
    }

    public enum MaxLogicalView {
        LEFT(-2.0f),
        RIGHT(2.0f),
        BOTTOM(-2.0f),
        TOP(2.0f);

        private final float value;
        MaxLogicalView(float value) { this.value = value; }
        public float getValue() { return value; }
    }

    public enum MotionGroup {
        IDLE("Idle"),
        TAP_BODY("TapBody");

        private final String id;
        MotionGroup(String id) { this.id = id; }
        public String getId() { return id; }
    }

    public enum HitAreaName {
        HEAD("Head"),
        BODY("Body");

        private final String id;
        HitAreaName(String id) { this.id = id; }
        public String getId() { return id; }
    }

    public enum Priority {
        NONE(0),
        IDLE(1),
        NORMAL(2),
        FORCE(3);

        private final int priority;
        Priority(int priority) { this.priority = priority; }
        public int getPriority() { return priority; }
    }

    public static final boolean MOC_CONSISTENCY_VALIDATION_ENABLE = true;
    public static final boolean MOTION_CONSISTENCY_VALIDATION_ENABLE = true;
    public static final boolean DEBUG_LOG_ENABLE = true;
    public static final boolean DEBUG_TOUCH_LOG_ENABLE = false;
    public static final LogLevel cubismLoggingLevel = LogLevel.VERBOSE;
    public static final boolean PREMULTIPLIED_ALPHA_ENABLE = true;
}
