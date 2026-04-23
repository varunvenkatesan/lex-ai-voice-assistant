import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

typedef void Live2dViewCreatedCallback(Live2dViewController controller);

class FlutterLive2dView extends StatefulWidget {
  const FlutterLive2dView({Key? key, this.onLive2dViewCreated, this.live2dType})
      : super(key: key);

  final Live2dViewCreatedCallback? onLive2dViewCreated;
  final String? live2dType;

  @override
  State<StatefulWidget> createState() => _FlutterLive2dViewState();
}

class LiveType {
  static final String face = "faceType";
  static final String normal = "normal";
}

class _FlutterLive2dViewState extends State<FlutterLive2dView> {
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Use Hybrid Composition to prevent the GL surface from disappearing
      // when LiveKit audio playback activates. Virtual Display mode (AndroidView)
      // can cause GLSurfaceView to lose its surface during audio focus changes.
      const String viewType = 'plugins.flutter.io/textView';
      return PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            // translucent: touches pass through to Flutter widgets above
            hitTestBehavior: PlatformViewHitTestBehavior.translucent,
          );
        },
        onCreatePlatformView: (params) {
          // initSurfaceAndroidView renders into a texture that Flutter can
          // composite with transparency — the native GL surface is already
          // configured with alpha (PixelFormat.TRANSLUCENT + glClearColor 0,0,0,0).
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener((id) {
              params.onPlatformViewCreated(id);
              _onPlatformViewCreated(id);
            })
            ..create();
        },
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final String viewType = 'platform-live2dView';
      final Map<String, dynamic> creationParams = <String, dynamic>{};
      return UiKitView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return Text(
        '$defaultTargetPlatform is not yet supported by the text_view plugin');
  }

  void _onPlatformViewCreated(int id) {
    if (widget.onLive2dViewCreated == null) {
      return;
    }
    widget.onLive2dViewCreated!(Live2dViewController._(id));
  }
}

class Live2dViewController {
  Live2dViewController._(int id)
      : _channel = MethodChannel('plugins.felix.angelov/textview_$id');

  final MethodChannel _channel;

  Future<void> setText(String text) async {
    return _channel.invokeMethod('setText', text);
  }

  Future<void> shakeEvent() async {
    return _channel.invokeMethod('shakeEvent');
  }

  /// Set the model JSON path to load the Live2D model.
  Future<void> live2dSetModelJsonPath(String modelJsonPath) async {
    return _channel
        .invokeMethod('l2d_setModelJsonPath', {"path": modelJsonPath});
  }

  /// Set the background image path.
  Future<void> live2dSetBackgroundPath(String path) async {
    return _channel.invokeMethod('l2d_setBackgroundPath', {"path": path});
  }

  /// Start a specific motion by group name, index number, and priority.
  /// Priority: 0=None, 1=Idle, 2=Normal, 3=Force
  Future<void> live2dStartMotion(String group, int number, int priority) async {
    return _channel.invokeMethod('l2d_startMotion', {
      "group": group,
      "number": number,
      "priority": priority,
    });
  }

  /// Start a random motion from the given group with the specified priority.
  /// Priority: 0=None, 1=Idle, 2=Normal, 3=Force
  Future<void> live2dStartRandomMotion(String group, int priority) async {
    return _channel.invokeMethod('l2d_startRandomMotion', {
      "group": group,
      "priority": priority,
    });
  }

  /// Set expression by its ID (matches "Name" in model3.json Expressions).
  Future<void> live2dStartExpression(String expressionId) async {
    return _channel.invokeMethod('l2d_setExpression', {"id": expressionId});
  }

  /// Set a random expression.
  Future<void> live2dSetRandomExpression() async {
    return _channel.invokeMethod('l2d_setRandomExpression');
  }

  /// Notify native side of speaking state for motion control.
  Future<void> live2dSpeakMotion(bool isSpeaking) async {
    return _channel.invokeMethod('l2d_SpeakMotion', {"isSpeaking": isSpeaking});
  }

  /// Stop all currently playing motions.
  /// When [resetPose] is true, the model returns to its neutral loaded pose.
  Future<void> live2dStopMotions({bool resetPose = true}) async {
    return _channel.invokeMethod('l2d_stopMotions', {"resetPose": resetPose});
  }

  /// Set lip sync value (0.0 = mouth closed, 1.0 = mouth fully open).
  /// Drives the LipSync parameter group (e.g. ParamMouthOpenY).
  Future<void> live2dSetLipSync(double value) async {
    return _channel.invokeMethod('l2d_setLipSync', value.clamp(0.0, 1.0));
  }

  /// Set mouth form/shape value (-1.0 = rounded/narrow, 0.0 = neutral,
  /// 1.0 = wide/smile-like deformation).
  /// Drives the ParamMouthForm parameter for speech shape variety.
  Future<void> live2dSetMouthForm(double value) async {
    return _channel.invokeMethod('l2d_setMouthForm', value.clamp(-1.0, 1.0));
  }

  /// Set a specific model parameter by its ID.
  /// Used to force-override parameters like hiding wings (Param41 = 0).
  Future<void> live2dSetParameter(String paramId, double value) async {
    return _channel.invokeMethod('l2d_setParameter', {
      "id": paramId,
      "value": value,
    });
  }

  /// Add a persistent parameter override — forced every frame.
  /// Use this to permanently hide model parts (e.g., wings).
  Future<void> live2dSetParameterOverride(String paramId, double value) async {
    return _channel.invokeMethod('l2d_setParameterOverride', {
      "id": paramId,
      "value": value,
    });
  }

  /// Clear all persistent parameter overrides (call when switching models).
  Future<void> live2dClearParameterOverrides() async {
    return _channel.invokeMethod('l2d_clearParameterOverrides');
  }

  /// Force a model part's opacity every frame. 0.0 = hidden, 1.0 = visible.
  /// Use to hide entire model parts (e.g., wings Part34).
  Future<void> live2dSetPartOpacityOverride(
      String partId, double opacity) async {
    return _channel.invokeMethod('l2d_setPartOpacityOverride', {
      "id": partId,
      "opacity": opacity,
    });
  }

  /// Clear all part opacity overrides (call when switching models).
  Future<void> live2dClearPartOpacityOverrides() async {
    return _channel.invokeMethod('l2d_clearPartOpacityOverrides');
  }

  /// Set model position offset and scale.
  /// Called when switching companion models to match the desired layout.
  Future<void> live2dSetModelTransform({
    required double offsetX,
    required double offsetY,
    required double scale,
  }) async {
    return _channel.invokeMethod('l2d_setModelTransform', {
      "offsetX": offsetX,
      "offsetY": offsetY,
      "scale": scale,
    });
  }

  /// Hide the native GL surface and pause rendering.
  /// Call this BEFORE removing the PlatformView widget from the tree
  /// to prevent the GL surface from bleeding through during route transitions.
  Future<void> hideView() async {
    return _channel.invokeMethod('l2d_hide');
  }

  /// Show the native GL surface and resume rendering.
  Future<void> showView() async {
    return _channel.invokeMethod('l2d_show');
  }
}
