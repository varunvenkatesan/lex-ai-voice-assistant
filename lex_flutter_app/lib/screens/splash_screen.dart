import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Splash Screen — Full-screen video splash
//
// Plays `assets/splash _screen/splash_screen.mp4` once (no loop),
// then cross-fades into the [destination] widget.
// The video fills the entire screen with a black background so the user
// sees nothing but the branded intro.
//
// The video asset is extracted to a temp file before playback to avoid
// URL-encoding issues with spaces in the asset directory name.
// ─────────────────────────────────────────────────────────────────────────────

const String _kSplashVideoAsset = 'assets/splash _screen/splash_screen.mp4';
const String _kPackageName = 'flutter_plugin2';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.destinationFuture,
  });

  /// The widget to navigate to once the splash video completes.
  final Future<Widget> destinationFuture;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  late AnimationController _fadeCtrl;
  bool _navigating = false;
  bool _videoInitialized = false;
  bool _videoFinished = false;
  bool _systemUiRestored = false;
  Timer? _safetyTimer;
  Widget? _destination;
  File? _tempVideoFile;

  @override
  void initState() {
    super.initState();

    // Immersive full-screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Fade-out animation for transition
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Safety timer — if video doesn't complete in 15s, navigate anyway
    _safetyTimer = Timer(const Duration(seconds: 15), () {
      debugPrint('SplashScreen: safety timer fired');
      if (mounted && !_navigating) _navigateToDestination();
    });

    unawaited(_resolveDestination());
    unawaited(_initVideo());
  }

  Future<void> _resolveDestination() async {
    try {
      final destination = await widget.destinationFuture;
      if (!mounted) return;
      _destination = destination;
      debugPrint('SplashScreen: destination resolved');
      if (_videoFinished) {
        _navigateToDestination();
      }
    } catch (e) {
      debugPrint('SplashScreen: destination init failed: $e');
      if (!mounted) return;
      _destination = const SizedBox.shrink();
      _navigateToDestination();
    }
  }

  /// Loads the splash video from the asset bundle, writes it to a temp file,
  /// then plays it via [VideoPlayerController.file].
  ///
  /// This two-step approach avoids the URL-encoding issue where
  /// [VideoPlayerController.asset] uses `Uri.encodeFull()` which converts
  /// spaces to `%20`, but the Android native AssetManager expects a literal
  /// space — causing a FileNotFoundException at the native layer.
  Future<void> _initVideo() async {
    try {
      // ── Step 1: Load asset bytes from the bundle ──
      // Try package-prefixed key first (correct for plugin assets),
      // then fall back to direct key.
      final assetKeys = [
        'packages/$_kPackageName/$_kSplashVideoAsset',
        _kSplashVideoAsset,
      ];

      ByteData? videoData;
      for (final key in assetKeys) {
        try {
          debugPrint('SplashScreen: trying asset key: $key');
          videoData = await rootBundle.load(key);
          debugPrint(
            'SplashScreen: loaded asset from key: $key '
            '(${videoData.lengthInBytes} bytes)',
          );
          break;
        } catch (e) {
          debugPrint('SplashScreen: asset key "$key" failed: $e');
        }
      }

      if (videoData == null) {
        throw Exception(
          'Splash video not found in asset bundle. '
          'Tried keys: $assetKeys',
        );
      }

      // ── Step 2: Write to temp file ──
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/lex_splash_video.mp4');
      await tempFile.writeAsBytes(
        videoData.buffer.asUint8List(
          videoData.offsetInBytes,
          videoData.lengthInBytes,
        ),
        flush: true,
      );
      _tempVideoFile = tempFile;
      debugPrint('SplashScreen: wrote video to ${tempFile.path}');

      // ── Step 3: Initialize and play from the temp file ──
      final controller = VideoPlayerController.file(tempFile);
      await controller.initialize();
      debugPrint(
        'SplashScreen: video initialized — '
        'size: ${controller.value.size}, '
        'duration: ${controller.value.duration}',
      );

      _videoController = controller;
      if (!mounted) {
        await controller.dispose();
        return;
      }

      await controller.setLooping(false);
      await controller.setVolume(1.0);
      await controller.seekTo(Duration.zero);
      controller.addListener(_onVideoTick);

      setState(() => _videoInitialized = true);
      await controller.play();
      debugPrint('SplashScreen: video playback started');
    } catch (e, st) {
      debugPrint('SplashScreen: video init failed: $e\n$st');
      if (!mounted) return;
      _videoFinished = true;
      _navigateToDestination();
    }
  }

  void _onVideoTick() {
    if (_navigating) return;
    final controller = _videoController;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;

    final position = controller.value.position;
    final duration = controller.value.duration;

    // Navigate once the video finishes (or gets very close)
    if (duration > Duration.zero &&
        position >= duration - const Duration(milliseconds: 150)) {
      debugPrint('SplashScreen: video finished (pos=$position, dur=$duration)');
      _videoFinished = true;
      _navigateToDestination();
    }
  }

  void _navigateToDestination() {
    if (_navigating || !mounted || _destination == null) return;
    _navigating = true;
    _safetyTimer?.cancel();
    debugPrint('SplashScreen: navigating to destination');

    _restoreSystemUi();

    // Fade out then swap the screen
    _fadeCtrl.forward().then((_) {
      if (!mounted) return;

      // Use pushAndRemoveUntil to reliably replace the initial route
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, animation, _) => _destination!,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
        (_) => false,
      );
    });
  }

  void _restoreSystemUi() {
    if (_systemUiRestored) return;
    _systemUiRestored = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    _restoreSystemUi();
    _safetyTimer?.cancel();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _fadeCtrl.dispose();
    // Clean up temp file
    _tempVideoFile?.delete().catchError((_) => File(''));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _fadeCtrl,
        builder: (context, child) {
          return Opacity(
            opacity: 1.0 - _fadeCtrl.value,
            child: child,
          );
        },
        child: _videoInitialized && _videoController != null
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size.width,
                    height: _videoController!.value.size.height,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}
