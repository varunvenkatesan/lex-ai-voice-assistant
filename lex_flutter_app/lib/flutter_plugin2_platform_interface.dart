import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_plugin2_method_channel.dart';

abstract class FlutterPlugin2Platform extends PlatformInterface {
  /// Constructs a FlutterPlugin2Platform.
  FlutterPlugin2Platform() : super(token: _token);

  static final Object _token = Object();

  static FlutterPlugin2Platform _instance = MethodChannelFlutterPlugin2();

  /// The default instance of [FlutterPlugin2Platform] to use.
  ///
  /// Defaults to [MethodChannelFlutterPlugin2].
  static FlutterPlugin2Platform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterPlugin2Platform] when
  /// they register themselves.
  static set instance(FlutterPlugin2Platform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
