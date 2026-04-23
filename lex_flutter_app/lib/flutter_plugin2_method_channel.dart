import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_plugin2_platform_interface.dart';

/// An implementation of [FlutterPlugin2Platform] that uses method channels.
class MethodChannelFlutterPlugin2 extends FlutterPlugin2Platform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_plugin2');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
