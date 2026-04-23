import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/reminder_models.dart';
import '../services/reminder_service.dart';
import '../services/supabase_service.dart';

const Color _kBgDark = Color(0xFF060608);
const Color _kSurfaceCard = Color(0xFF0F1014);
const Color _kSurfaceElevated = Color(0xFF161820);
const Color _kAccentViolet = Color(0xFF6C5CE7);
const Color _kAccentCyan = Color(0xFF7DD3FC);
const Color _kAccentPink = Color(0xFFFF4E8E);
const Color _kAccentGreen = Color(0xFF66FFAA);
const Color _kTextPrimary = Color(0xFFF2F2F7);
const Color _kTextSecondary = Color(0xFF8E8EA0);
const Color _kTextMuted = Color(0xFF55556A);
const Color _kBorderSubtle = Color(0xFF1C1C28);

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.onBack,
  });

  final VoidCallback onBack;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<List<ReminderItem>>? _subscription;
  List<ReminderItem> _reminders = const [];
  final Set<String> _deletingReminderIds = <String>{};
  bool _isLoading = true;
  late final AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    unawaited(_bindReminders());
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _bindReminders() async {
    if (!SupabaseService.isLoggedIn) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final reminders = await SupabaseService.getReminders();
      if (!mounted) return;
      setState(() {
        _reminders = reminders;
        _isLoading = false;
      });
      _staggerController.forward();
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    _subscription = SupabaseService.watchReminders().listen(
      (reminders) {
        if (!mounted) return;
        setState(() {
          _reminders = reminders;
          _isLoading = false;
        });
      },
      onError: (_) async {
        if (!mounted) return;
        try {
          final reminders = await SupabaseService.getReminders();
          if (!mounted) return;
          setState(() {
            _reminders = reminders;
            _isLoading = false;
          });
        } catch (_) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      },
    );
  }

  List<ReminderItem> get _upcomingReminders {
    final now = DateTime.now();
    final items = _reminders
        .where(
          (reminder) =>
              !reminder.isTriggered &&
              reminder.scheduledAt
                  .isAfter(now.subtract(const Duration(minutes: 1))),
        )
        .toList(growable: false);
    items.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return items;
  }

  List<ReminderItem> get _pastReminders {
    final now = DateTime.now();
    final items = _reminders
        .where(
          (reminder) =>
              reminder.isTriggered ||
              !reminder.scheduledAt
                  .isAfter(now.subtract(const Duration(minutes: 1))),
        )
        .toList(growable: false);
    items.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _kBgDark,
      body: Column(
        children: [
          SizedBox(height: topPad),
          _buildAppBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kSurfaceElevated,
                border: Border.all(color: _kBorderSubtle, width: 0.8),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _kTextPrimary,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Reminders',
            style: GoogleFonts.plusJakartaSans(
              color: _kTextPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          if (_upcomingReminders.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _kAccentViolet.withValues(alpha: 0.12),
                border: Border.all(
                  color: _kAccentViolet.withValues(alpha: 0.2),
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    color: _kAccentViolet,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_upcomingReminders.length}',
                    style: GoogleFonts.manrope(
                      color: _kAccentViolet,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: _kAccentViolet.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    if (_reminders.isEmpty) {
      return _buildEmptyState();
    }

    final upcoming = _upcomingReminders;
    final past = _pastReminders;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildHeroCard(upcoming.length, past.length),
        const SizedBox(height: 28),
        if (upcoming.isNotEmpty) ...[
          _buildSectionHeader(
            'Upcoming',
            Icons.schedule_rounded,
            _kAccentCyan,
          ),
          const SizedBox(height: 14),
          ...List.generate(upcoming.length, (i) {
            return _buildAnimatedCard(
              child: _buildUpcomingCard(upcoming[i]),
              index: i,
            );
          }),
          const SizedBox(height: 24),
        ],
        if (past.isNotEmpty) ...[
          _buildSectionHeader(
            'Completed',
            Icons.check_circle_outline_rounded,
            _kTextMuted,
          ),
          const SizedBox(height: 14),
          ...List.generate(past.length, (i) {
            return _buildAnimatedCard(
              child: _buildPastCard(past[i]),
              index: i + upcoming.length,
            );
          }),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _kAccentViolet.withValues(alpha: 0.18),
                    _kAccentPink.withValues(alpha: 0.1),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kAccentViolet.withValues(alpha: 0.15),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                color: _kAccentViolet.withValues(alpha: 0.7),
                size: 34,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No reminders yet',
              style: GoogleFonts.plusJakartaSans(
                color: _kTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Say "remind me..." in Talk\nor type a reminder in Chat to create one.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: _kTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(int upcomingCount, int pastCount) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _kAccentViolet.withValues(alpha: 0.12),
                _kAccentPink.withValues(alpha: 0.06),
                _kSurfaceCard.withValues(alpha: 0.8),
              ],
            ),
            border: Border.all(
              color: _kAccentViolet.withValues(alpha: 0.18),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _kAccentViolet.withValues(alpha: 0.08),
                blurRadius: 40,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_kAccentViolet, _kAccentPink],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _kAccentViolet.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.alarm_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reminder Center',
                          style: GoogleFonts.plusJakartaSans(
                            color: _kTextPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          upcomingCount == 0
                              ? 'You\'re all caught up!'
                              : '$upcomingCount upcoming - $pastCount completed',
                          style: GoogleFonts.manrope(
                            color: _kTextSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (upcomingCount > 0) ...[
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pastCount / (upcomingCount + pastCount),
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _kAccentViolet.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$pastCount completed',
                      style: GoogleFonts.manrope(
                        color: _kTextMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${upcomingCount + pastCount} total',
                      style: GoogleFonts.manrope(
                        color: _kTextMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.manrope(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 0.6,
            color: color.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedCard({required Widget child, required int index}) {
    final delay = (index * 0.08).clamp(0.0, 0.6);
    final end = (delay + 0.4).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, childWidget) {
        final progress = CurvedAnimation(
          parent: _staggerController,
          curve: Interval(delay, end, curve: Curves.easeOutCubic),
        ).value;

        return Transform.translate(
          offset: Offset(0, 20 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: childWidget,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildUpcomingCard(ReminderItem reminder) {
    final timeUntil = _timeUntilText(reminder.scheduledAt);

    return _wrapReminderCard(
      reminder: reminder,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kSurfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _kAccentViolet.withValues(alpha: 0.12),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3.5,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_kAccentViolet, _kAccentPink],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        style: GoogleFonts.plusJakartaSans(
                          color: _kTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      if (reminder.details != null &&
                          reminder.details!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          reminder.displayDetails,
                          style: GoogleFonts.manrope(
                            color: _kTextSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _buildSourceChip(reminder),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 0.5,
              color: _kBorderSubtle,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 15,
                  color: _kAccentCyan.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _formatReminderTime(reminder.scheduledAt),
                    style: GoogleFonts.manrope(
                      color: _kTextPrimary.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: _kAccentGreen.withValues(alpha: 0.1),
                    border: Border.all(
                      color: _kAccentGreen.withValues(alpha: 0.2),
                      width: 0.6,
                    ),
                  ),
                  child: Text(
                    timeUntil,
                    style: GoogleFonts.manrope(
                      color: _kAccentGreen,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPastCard(ReminderItem reminder) {
    return _wrapReminderCard(
      reminder: reminder,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurfaceCard.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _kBorderSubtle,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kTextMuted.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.check_rounded,
                color: _kTextMuted.withValues(alpha: 0.7),
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    style: GoogleFonts.plusJakartaSans(
                      color: _kTextSecondary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: _kTextMuted.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatReminderTime(reminder.scheduledAt),
                    style: GoogleFonts.manrope(
                      color: _kTextMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildSourceChip(reminder, muted: true),
          ],
        ),
      ),
    );
  }

  Widget _wrapReminderCard({
    required ReminderItem reminder,
    required Widget child,
  }) {
    final isDeleting = _deletingReminderIds.contains(reminder.id);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isDeleting ? 0.5 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress:
            isDeleting ? null : () => unawaited(_showReminderActions(reminder)),
        child: child,
      ),
    );
  }

  Future<void> _showReminderActions(ReminderItem reminder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Text(
                  reminder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reminder.isTriggered
                      ? 'Completed reminder'
                      : 'Scheduled for ${_formatReminderTime(reminder.scheduledAt)}',
                  style: GoogleFonts.manrope(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFFF8A80),
                  ),
                  title: Text(
                    'Delete reminder',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFFFF8A80),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Remove this task and cancel its notification.',
                    style: GoogleFonts.manrope(
                      color: Colors.white.withValues(alpha: 0.42),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == 'delete') {
      await _confirmDeleteReminder(reminder);
    }
  }

  Future<void> _confirmDeleteReminder(ReminderItem reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17171A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Delete reminder?',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'This will permanently delete "${reminder.title}" and remove its notification.',
            style: GoogleFonts.manrope(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Delete',
                style: GoogleFonts.manrope(
                  color: const Color(0xFFFF8A80),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _deletingReminderIds.add(reminder.id);
    });

    try {
      await ReminderService.instance.deleteReminder(reminder);
      if (!mounted) {
        return;
      }

      setState(() {
        _deletingReminderIds.remove(reminder.id);
        _reminders = _reminders
            .where((item) => item.id != reminder.id)
            .toList(growable: false);
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Reminder deleted.')),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _deletingReminderIds.remove(reminder.id);
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not delete reminder. Please try again.'),
          ),
        );
    }
  }

  Widget _buildSourceChip(ReminderItem reminder, {bool muted = false}) {
    final isTalk = reminder.isTalk;
    final Color accent;
    if (muted) {
      accent = _kTextMuted;
    } else {
      accent = isTalk ? _kAccentCyan : _kAccentViolet;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: muted ? 0.06 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: muted ? 0.1 : 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isTalk ? Icons.mic_rounded : Icons.chat_bubble_outline_rounded,
            color: accent,
            size: 11,
          ),
          const SizedBox(width: 4),
          Text(
            reminder.sourceLabel,
            style: GoogleFonts.manrope(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  String _timeUntilText(DateTime scheduledAt) {
    final diff = scheduledAt.difference(DateTime.now());
    if (diff.isNegative) return 'Due now';
    if (diff.inDays > 0) {
      return 'in ${diff.inDays}d ${diff.inHours.remainder(24)}h';
    }
    if (diff.inHours > 0) {
      return 'in ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    if (diff.inMinutes > 0) {
      return 'in ${diff.inMinutes}m';
    }
    return 'in <1m';
  }

  String _formatReminderTime(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final isToday = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = tomorrow.year == local.year &&
        tomorrow.month == local.month &&
        tomorrow.day == local.day;

    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';

    final datePrefix = isToday
        ? 'Today'
        : isTomorrow
            ? 'Tomorrow'
            : '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    return '$datePrefix - $hour:$minute $meridiem';
  }
}
