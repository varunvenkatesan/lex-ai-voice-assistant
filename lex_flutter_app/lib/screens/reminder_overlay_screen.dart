import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/reminder_models.dart';

// QUICK MANUAL CUSTOMIZATION GUIDE
// Search these names to customize the overlay quickly:
// - `_kCharacterAsset` for the character image
// - `_kOuterTop` / `_kOuterBottom` for the glass card colors
// - `_kCardHeightFactor`, `_kCardMinHeight`, `_kCardMaxHeight` for popup size
// - `_kEntryDuration`, `_kPulseDuration` for motion timing
// - `_kSwipeCommitVelocity`, `_kSwipeCommitThreshold` for swipe sensitivity
// - `_kActionCenterSizeFactor`, `_kActionButtonHeightFactor` for the bottom row
// - `_kTaskContainerWidthFactor`, `_kTaskContainerHeightFactor`, `_kTaskContainerOffsetX`, `_kTaskContainerOffsetY` for the task box
// - `_kTaskTextBoxWidthFactor` / `_kTaskTextBoxMinWidth` for the task text box width

const MethodChannel _kOverlayChannel = MethodChannel('lex.reminder_overlay');

// Assets
const String _kCharacterAsset =
    'packages/flutter_plugin2/assets/UI image/start_character_image.png';

// Colors
const Color _kOuterTop = Color(0xDA17151C);
const Color _kOuterBottom = Color(0xD9100F14);
const Color _kOuterBorder = Color(0x26FFFFFF);
const Color _kInnerPanel = Color(0xFF1C1B23);
const Color _kInnerBorder = Color(0x14FFFFFF);
const Color _kButtonBg = Color(0xFF282637);
const Color _kTextPrimary = Color(0xFFF7F5FB);
const Color _kTextSecondary = Color(0xFFA6A2B4);
const Color _kTextMuted = Color(0xFF7A7788);
const Color _kPink = Color(0xFFFF4FA0);
const Color _kPinkDeep = Color(0xFFD93682);
const Color _kAccept = Color(0xFF74E7B5);
const Color _kDecline = Color(0xFFFF7A8C);

// Layout
const double _kCardHorizontalInset = 14.0;
const double _kCardBottomInset = 12.0;
const double _kCardTopSafetyInset = 24.0;
const double _kCardHeightFactor = 0.60;
const double _kCardMinHeight = 430.0;
const double _kCardMaxHeight = 560.0;
const double _kCardRadius = 34.0;
const double _kCardBlur = 22.0;
const double _kCardShadowBlur = 36.0;
const double _kCardShadowYOffset = 16.0;
const EdgeInsets _kCardPadding = EdgeInsets.fromLTRB(22, 20, 22, 20);
const double _kHeaderBottomGap = 18.0;
const double _kCompactLayoutBreakpoint = 320.0;
const double _kCompactActionGap = 10.0;
const double _kRegularActionGap = 18.0;
const double _kActionHeightFactor = 0.40;
const double _kMinActionHeight = 46.0;
const double _kCompactActionMaxHeight = 72.0;
const double _kRegularActionMaxHeight = 96.0;
const double _kInnerPanelRadius = 28.0;
const double _kActionButtonRadius = 60.0;
const double _kActionTrackHorizontalPadding = 24.0;
const double _kActionCenterSizeFactor = 0.72;
const double _kActionCenterMinSize = 42.0;
const double _kActionCenterMaxSize = 88.0;
const double _kActionButtonMinHeight = 38.0;
const double _kTrackMinExtent = 40.0;
const double _kTrackMaxExtent = 160.0;
const double _kCharacterMaxWidth = 99.0;
const double _kCharacterWidthFactor = 0.99;
const double _kCharacterHeightFactor = 99.0;
const double _kCharacterRightInset = -20.0;
const double _kCharacterBottomMin = 24.0;
const double _kCharacterBottomFactor = 0.99;
const double _kTaskContainerWidthFactor = 0.68;
const double _kTaskContainerHeightFactor = 0.9;
const double _kTaskContainerOffsetX = 10.0;
const double _kTaskContainerOffsetY = 20.0;
const double _kTaskContainerMinWidth = 250.0;
const double _kTaskContainerMinHeight = 120.0;
const double _kTaskTextBoxWidthFactor = 0.46;
const double _kTaskTextBoxMinWidth = 200.0;

// Motion
const Duration _kEntryDuration = Duration(milliseconds: 650);
const Duration _kPulseDuration = Duration(milliseconds: 2300);
const Duration _kVoiceStartDelay = Duration(milliseconds: 450);
const Duration _kOpenTransitionDuration = Duration(milliseconds: 260);
const Duration _kSwipeCommitDelay = Duration(milliseconds: 120);
const Duration _kSwipeSnapDuration = Duration(milliseconds: 180);
const double _kCardLiftStart = 42.0;

// Swipe
const double _kCardSwipeExtentFactor = 0.24;
const double _kSwipeCommitVelocity = 850.0;
const double _kSwipeCommitThreshold = 0.52;

class ReminderOverlayScreen extends StatefulWidget {
  const ReminderOverlayScreen({
    super.key,
    required this.reminder,
    required this.homeBuilder,
  });

  final ReminderItem reminder;
  final WidgetBuilder homeBuilder;

  static ReminderItem? reminderFromRoute(String routeName) {
    if (!routeName.startsWith('/reminder_overlay') &&
        !routeName.startsWith('/reminder-overlay')) {
      return null;
    }

    final uri = Uri.tryParse(routeName);
    if (uri == null) {
      return null;
    }

    final jsonData =
        uri.queryParameters['data'] ?? uri.queryParameters['payload'];
    if (jsonData == null || jsonData.isEmpty) {
      return null;
    }

    try {
      return ReminderItem.fromMap(
        Map<String, dynamic>.from(jsonDecode(jsonData) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  State<ReminderOverlayScreen> createState() => _ReminderOverlayScreenState();
}

class _ReminderOverlayScreenState extends State<ReminderOverlayScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  late final Animation<double> _cardOpacity;
  late final Animation<double> _cardScale;
  late final Animation<double> _cardLift;

  final FlutterTts _tts = FlutterTts();

  bool _actionLocked = false;
  bool _isDraggingHandle = false;
  double _dragX = 0;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: _kEntryDuration,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: _kPulseDuration,
    )..repeat(reverse: true);

    _cardOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _cardScale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _cardLift = Tween<double>(begin: _kCardLiftStart, end: 0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _entryController.forward();
    HapticFeedback.heavyImpact();
    unawaited(_startVoice());
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startVoice() async {
    try {
      await Future<void>.delayed(_kVoiceStartDelay);
      await _tts.awaitSpeakCompletion(false);
      await _tts.setQueueMode(0);
      await _tts.setSpeechRate(0.47);
      await _tts.setPitch(1.02);
      await _tts.setVolume(1.0);
      await _tts.speak(_buildSpokenText(widget.reminder), focus: true);
    } catch (_) {}
  }

  Future<void> _openApp() async {
    if (_actionLocked) return;
    _actionLocked = true;
    HapticFeedback.mediumImpact();
    await _stopVoice();
    await _dismissNative();

    final openedNatively = await _invokeNativeBool('openMainApp');
    if (!mounted || openedNatively) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (ctx, anim, _) => widget.homeBuilder(ctx),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: _kOpenTransitionDuration,
      ),
    );
  }

  Future<void> _decline() async {
    if (_actionLocked) return;
    _actionLocked = true;
    HapticFeedback.lightImpact();
    await _stopVoice();
    await _dismissNative();

    try {
      await _entryController.reverse();
    } catch (_) {}

    if (!mounted) return;
    SystemNavigator.pop();
  }

  Future<void> _stopVoice() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> _dismissNative() async {
    try {
      await _kOverlayChannel.invokeMethod<void>(
        'dismissReminderAlert',
        <String, dynamic>{'reminderId': widget.reminder.id},
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<bool> _invokeNativeBool(String method) async {
    try {
      return await _kOverlayChannel.invokeMethod<bool>(method) ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  void _handleHorizontalDragStart() {
    if (_actionLocked) return;
    setState(() {
      _isDraggingHandle = true;
    });
  }

  void _handleHorizontalDragUpdate(
    DragUpdateDetails details,
    double maxSwipe,
  ) {
    if (_actionLocked) return;
    setState(() {
      _dragX = (_dragX + details.delta.dx).clamp(-maxSwipe, maxSwipe);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details, double maxSwipe) {
    if (_actionLocked) return;

    final velocity = details.primaryVelocity ?? 0;
    final shouldCommit = velocity.abs() > _kSwipeCommitVelocity ||
        _dragX.abs() > maxSwipe * _kSwipeCommitThreshold;
    if (shouldCommit) {
      final swipedLeft = velocity == 0 ? _dragX < 0 : velocity < 0;
      setState(() {
        _isDraggingHandle = false;
        _dragX = swipedLeft ? -maxSwipe : maxSwipe;
      });
      Future<void>.delayed(_kSwipeCommitDelay, () {
        swipedLeft ? unawaited(_openApp()) : unawaited(_decline());
      });
      return;
    }

    setState(() {
      _isDraggingHandle = false;
      _dragX = 0;
    });
  }

  void _handleHorizontalDragCancel() {
    if (_actionLocked) return;
    setState(() {
      _isDraggingHandle = false;
      _dragX = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final cardWidth =
        math.min(screen.width - (_kCardHorizontalInset * 2), 700.0);
    final maxCardHeight = math.min(
        _kCardMaxHeight, screen.height - bottomPad - _kCardTopSafetyInset);
    final cardHeight = math.min(
        math.max(screen.height * _kCardHeightFactor, _kCardMinHeight),
        maxCardHeight);
    final maxSwipe = cardWidth * _kCardSwipeExtentFactor;
    final dragProgress = (_dragX.abs() / maxSwipe).clamp(0.0, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: Listenable.merge([
            _entryController,
            _pulseController,
          ]),
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.03),
                        Colors.black.withValues(alpha: 0.14),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _decline,
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox.expand(),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      _kCardHorizontalInset,
                      0,
                      _kCardHorizontalInset,
                      bottomPad + _kCardBottomInset,
                    ),
                    child: Opacity(
                      opacity: _cardOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _cardLift.value),
                        child: Transform.scale(
                          scale: _cardScale.value,
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            width: cardWidth,
                            height: cardHeight,
                            child: _buildCard(cardWidth, dragProgress),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard(double cardWidth, double dragProgress) {
    final swipeTint = _dragX == 0
        ? Colors.transparent
        : (_dragX < 0 ? _kAccept : _kDecline)
            .withValues(alpha: 0.08 + (dragProgress * 0.08));

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kCardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _kCardBlur, sigmaY: _kCardBlur),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kCardRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(_kOuterTop, swipeTint, dragProgress) ?? _kOuterTop,
                Color.lerp(_kOuterBottom, swipeTint, dragProgress * 0.8) ??
                    _kOuterBottom,
              ],
            ),
            border: Border.all(
              color: Color.lerp(
                    _kOuterBorder,
                    Colors.white.withValues(alpha: 0.18),
                    dragProgress,
                  ) ??
                  _kOuterBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: _kCardShadowBlur,
                offset: const Offset(0, _kCardShadowYOffset),
              ),
            ],
          ),
          child: Padding(
            padding: _kCardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: _kHeaderBottomGap),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final availableHeight = constraints.maxHeight;
                      final compactLayout =
                          availableHeight < _kCompactLayoutBreakpoint;
                      final actionGap = compactLayout
                          ? _kCompactActionGap
                          : _kRegularActionGap;
                      final usableHeight =
                          math.max(0.0, availableHeight - actionGap);
                      final actionHeight = math.max(
                        _kMinActionHeight,
                        math.min(
                          compactLayout
                              ? _kCompactActionMaxHeight
                              : _kRegularActionMaxHeight,
                          usableHeight * _kActionHeightFactor,
                        ),
                      );
                      final panelHeight = math.max(
                        0.0,
                        usableHeight - actionHeight,
                      );

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            children: [
                              _buildInnerPanel(cardWidth, panelHeight),
                              SizedBox(height: actionGap),
                              _buildActionRow(actionHeight),
                            ],
                          ),
                          _buildCharacter(cardWidth, actionHeight),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          Icons.access_time_rounded,
          color: _kTextPrimary.withValues(alpha: 0.92),
          size: 34,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reminder alert',
                style: GoogleFonts.plusJakartaSans(
                  color: _kTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(widget.reminder.scheduledAt),
                style: GoogleFonts.manrope(
                  color: _kTextSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _decline,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.close_rounded,
              color: Colors.white.withValues(alpha: 0.62),
              size: 34,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInnerPanel(double cardWidth, double panelHeight) {
    final taskContainerWidth = math.min(
      cardWidth,
      math.max(_kTaskContainerMinWidth, cardWidth * _kTaskContainerWidthFactor),
    );
    final taskContainerHeight = math.min(
      panelHeight,
      math.max(
        _kTaskContainerMinHeight,
        panelHeight * _kTaskContainerHeightFactor,
      ),
    );
    final verticalPadding = taskContainerHeight < 170 ? 14.0 : 18.0;
    final horizontalPadding = taskContainerHeight < 170 ? 16.0 : 18.0;

    return SizedBox(
      height: panelHeight,
      width: double.infinity,
      child: Transform.translate(
        offset: const Offset(_kTaskContainerOffsetX, _kTaskContainerOffsetY),
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: taskContainerWidth,
            height: taskContainerHeight,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              verticalPadding,
              horizontalPadding,
              verticalPadding,
            ),
            decoration: BoxDecoration(
              color: _kInnerPanel,
              borderRadius: BorderRadius.circular(_kInnerPanelRadius),
              border: Border.all(color: _kInnerBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTaskTextBox(
                  containerWidth: taskContainerWidth,
                  panelHeight: taskContainerHeight,
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MANUAL EDIT:
  // Change `_kTaskContainerWidthFactor`, `_kTaskContainerHeightFactor`,
  // `_kTaskContainerOffsetX`, `_kTaskContainerOffsetY`,
  // `_kTaskTextBoxWidthFactor`, or `_kTaskTextBoxMinWidth` above
  // to resize and reposition the task detail box manually.
  Widget _buildTaskTextBox({
    required double containerWidth,
    required double panelHeight,
  }) {
    final textWidth = math.max(
      _kTaskTextBoxMinWidth,
      containerWidth * _kTaskTextBoxWidthFactor,
    );
    final titleFontSize = panelHeight < 140
        ? 22.0
        : panelHeight < 200
            ? 26.0
            : panelHeight < 260
                ? 30.0
                : 34.0;
    final descriptionFontSize = panelHeight < 140
        ? 12.0
        : panelHeight < 220
            ? 14.0
            : 15.0;
    final titleGap = panelHeight < 140
        ? 10.0
        : panelHeight < 220
            ? 14.0
            : 18.0;
    final chipGap = panelHeight < 160
        ? 14.0
        : panelHeight < 240
            ? 20.0
            : 28.0;
    final descriptionLines = panelHeight < 180 ? 4 : 5;
    final descriptionHeight = panelHeight < 220 ? 1.35 : 1.45;
    final resolvedTitleFontSize = containerWidth < 370 && titleFontSize > 30.0
        ? 30.0
        : containerWidth < 370 && titleFontSize > 26.0
            ? 26.0
            : titleFontSize;

    return SizedBox(
      width: textWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTaskChip(),
          SizedBox(height: chipGap),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.reminder.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: _kTextPrimary,
                      fontSize: resolvedTitleFontSize,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -1.0,
                    ),
                  ),
                  SizedBox(height: titleGap),
                  Text(
                    _descriptionText(widget.reminder),
                    maxLines: descriptionLines,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: _kTextMuted,
                      fontSize: descriptionFontSize,
                      fontWeight: FontWeight.w600,
                      height: descriptionHeight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskChip() {
    final label = widget.reminder.isTalk ? 'Voice' : 'Task';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPink, _kPinkDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: _kPink.withValues(alpha: 0.34),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildActionRow(double actionHeight) {
    final centerSize = math.min(
      math.max(actionHeight * _kActionCenterSizeFactor, _kActionCenterMinSize),
      math.min(_kActionCenterMaxSize, actionHeight),
    );

    return SizedBox(
      height: actionHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableTrackWidth = math.max(
            centerSize,
            constraints.maxWidth - (_kActionTrackHorizontalPadding * 2),
          );
          final trackHeight = math.max(
            _kActionButtonMinHeight,
            math.min(actionHeight, centerSize + 14.0),
          );
          final trackExtent = ((availableTrackWidth - centerSize) / 2).clamp(
            _kTrackMinExtent,
            _kTrackMaxExtent,
          );
          final dragProgress = (_dragX.abs() / trackExtent).clamp(0.0, 1.0);
          final acceptActive = _dragX < 0;
          final declineActive = _dragX > 0;
          final activeAccent = acceptActive
              ? _kAccept
              : declineActive
                  ? _kDecline
                  : Colors.white;

          return Container(
            height: trackHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kActionButtonRadius),
              color: Color.lerp(
                    _kButtonBg,
                    activeAccent.withValues(alpha: 0.12),
                    dragProgress,
                  ) ??
                  _kButtonBg,
              border: Border.all(
                color: acceptActive
                    ? _kAccept.withValues(alpha: 0.34)
                    : declineActive
                        ? _kDecline.withValues(alpha: 0.34)
                        : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kActionTrackHorizontalPadding,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SwipeActionLabel(
                          label: 'Set\nReminder',
                          accent: _kAccept,
                          active: acceptActive,
                          progress: dragProgress,
                        ),
                        _SwipeActionLabel(
                          label: 'Decline',
                          accent: _kDecline,
                          active: declineActive,
                          progress: dragProgress,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration:
                      _isDraggingHandle ? Duration.zero : _kSwipeSnapDuration,
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(_dragX, 0, 0),
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (_) {
                        _handleHorizontalDragStart();
                      },
                      onHorizontalDragUpdate: (details) {
                        _handleHorizontalDragUpdate(details, trackExtent);
                      },
                      onHorizontalDragEnd: (details) {
                        _handleHorizontalDragEnd(details, trackExtent);
                      },
                      onHorizontalDragCancel: _handleHorizontalDragCancel,
                      child: _buildCenterAlarm(dragProgress, centerSize),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenterAlarm(double dragProgress, double size) {
    final glow = 0.25 + (_pulseController.value * 0.22);
    final glowColor = _dragX < 0
        ? _kAccept
        : _dragX > 0
            ? _kDecline
            : _kPink;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPink, _kPinkDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: glow + (dragProgress * 0.1)),
            blurRadius: 28,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        Icons.alarm_rounded,
        color: Colors.white,
        size: size * 0.41,
      ),
    );
  }

  Widget _buildCharacter(double cardWidth, double actionHeight) {
    final characterWidth =
        math.min(_kCharacterMaxWidth, cardWidth * _kCharacterWidthFactor);

    return Positioned(
      right: _kCharacterRightInset,
      bottom: math.max(
          _kCharacterBottomMin, actionHeight * _kCharacterBottomFactor),
      child: IgnorePointer(
        child: Image.asset(
          _kCharacterAsset,
          width: characterWidth,
          height: characterWidth * _kCharacterHeightFactor,
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  String _buildSpokenText(ReminderItem reminder) {
    return 'Hey, your reminder is ready. ${reminder.title}. ${_descriptionText(reminder)}';
  }

  String _descriptionText(ReminderItem reminder) {
    final raw = reminder.displayDetails.trim();
    final segments = raw
        .split('•')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (segments.length > 1) {
      return segments.skip(1).join(' • ');
    }

    return raw;
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final isToday = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    final prefix = isToday ? 'today' : '${local.day}/${local.month}';
    return '$prefix  at  $hour:$minute $meridiem';
  }
}

class _SwipeActionLabel extends StatelessWidget {
  const _SwipeActionLabel({
    required this.label,
    required this.accent,
    required this.active,
    required this.progress,
  });

  final String label;
  final Color accent;
  final bool active;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: _kSwipeSnapDuration,
      curve: Curves.easeOutCubic,
      style: GoogleFonts.manrope(
        color: active
            ? Color.lerp(_kTextPrimary, accent, progress * 0.85) ??
                _kTextPrimary
            : _kTextPrimary.withValues(alpha: 0.88),
        fontSize: 15,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
      ),
    );
  }
}
