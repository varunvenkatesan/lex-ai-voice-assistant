import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/chat_models.dart';
import '../models/reminder_models.dart';
import '../services/supabase_service.dart';

Future<String?> openSidebarDrawer(
  BuildContext context, {
  required String userName,
  required VoidCallback onNewChat,
  required void Function(String sessionId) onSessionSelected,
  required void Function(String sessionId) onSessionDeleted,
  String? currentSessionId,
  String? activeCompanionId,
}) {
  return showGeneralDialog<String?>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close sidebar',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => _SidebarDrawer(
      userName: userName,
      onNewChat: onNewChat,
      onSessionSelected: onSessionSelected,
      onSessionDeleted: onSessionDeleted,
      currentSessionId: currentSessionId,
      activeCompanionId: activeCompanionId,
    ),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _SidebarDrawer extends StatefulWidget {
  const _SidebarDrawer({
    required this.userName,
    required this.onNewChat,
    required this.onSessionSelected,
    required this.onSessionDeleted,
    this.currentSessionId,
    this.activeCompanionId,
  });

  final String userName;
  final VoidCallback onNewChat;
  final void Function(String sessionId) onSessionSelected;
  final void Function(String sessionId) onSessionDeleted;
  final String? currentSessionId;
  final String? activeCompanionId;

  @override
  State<_SidebarDrawer> createState() => _SidebarDrawerState();
}

class _SidebarDrawerState extends State<_SidebarDrawer> {
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<List<ChatConversation>>? _sessionSubscription;
  StreamSubscription<List<ReminderItem>>? _reminderSubscription;
  List<ChatConversation> _sessions = const [];
  List<ReminderItem> _reminders = const [];
  final Set<String> _deletingSessionIds = <String>{};
  bool _isLoading = true;
  bool _isLoadingReminders = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    unawaited(_bindSessions());
    unawaited(_bindReminders());
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _reminderSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bindSessions() async {
    if (!SupabaseService.isLoggedIn) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final sessions = await SupabaseService.getConversations();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    _sessionSubscription = SupabaseService.watchConversations().listen(
      (sessions) {
        if (!mounted) return;
        setState(() {
          _sessions = sessions;
          _isLoading = false;
        });
      },
      onError: (_) async {
        if (!mounted) return;
        try {
          final sessions = await SupabaseService.getConversations();
          if (!mounted) return;
          setState(() {
            _sessions = sessions;
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

  Future<void> _bindReminders() async {
    if (!SupabaseService.isLoggedIn) {
      setState(() => _isLoadingReminders = false);
      return;
    }

    try {
      final reminders = await SupabaseService.getReminders();
      if (!mounted) return;
      setState(() {
        _reminders = reminders;
        _isLoadingReminders = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingReminders = false);
      }
    }

    _reminderSubscription = SupabaseService.watchReminders().listen(
      (reminders) {
        if (!mounted) return;
        setState(() {
          _reminders = reminders;
          _isLoadingReminders = false;
        });
      },
      onError: (_) async {
        if (!mounted) return;
        try {
          final reminders = await SupabaseService.getReminders();
          if (!mounted) return;
          setState(() {
            _reminders = reminders;
            _isLoadingReminders = false;
          });
        } catch (_) {
          if (mounted) {
            setState(() => _isLoadingReminders = false);
          }
        }
      },
    );
  }

  List<ChatConversation> get _filteredSessions {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _sessions;
    }

    return _sessions.where((session) {
      return session.title.toLowerCase().contains(query) ||
          session.previewText.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  List<ChatConversation> get _filteredChatSessions => _filteredSessions
      .where((session) => session.isChat)
      .toList(growable: false);

  List<ChatConversation> get _filteredTalkSessions => _filteredSessions
      .where((session) => session.isTalk)
      .toList(growable: false);

  List<ReminderItem> get _upcomingReminders => _reminders
      .where(
        (reminder) =>
            !reminder.isTriggered &&
            reminder.scheduledAt.isAfter(DateTime.now().subtract(
              const Duration(minutes: 1),
            )),
      )
      .toList(growable: false)
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: screenWidth * 0.82,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: topPad + 12),
              _buildSearchBar(),
              const SizedBox(height: 20),
              _buildNewChatButton(),
              const SizedBox(height: 20),
              Expanded(child: _buildChatList()),
              _buildRemindersSection(),
              _buildCompanionSection(),
              _buildProfileSection(bottomPad),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search,
              color: Colors.white.withValues(alpha: 0.5),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: GoogleFonts.manrope(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.edit_square,
                color: Colors.white.withValues(alpha: 0.5),
                size: 20,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNewChat();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildNewChatButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          widget.onNewChat();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.add_box_outlined,
                color: Colors.white.withValues(alpha: 0.8),
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                'New chat',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.manrope(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    final chatSessions = _filteredChatSessions;
    final talkSessions = _filteredTalkSessions;

    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white24,
          ),
        ),
      );
    }

    if (chatSessions.isEmpty && talkSessions.isEmpty) {
      final message = _searchQuery.trim().isEmpty
          ? 'No conversations yet.\nTap "New chat" to start one!'
          : 'No conversations match your search.';

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      children: [
        _buildSectionHeader('CHAT HISTORY'),
        const SizedBox(height: 8),
        if (chatSessions.isEmpty)
          _buildEmptyKindState('No text chats yet.')
        else
          ...chatSessions.map(_buildHistoryTile),
        const SizedBox(height: 18),
        _buildSectionHeader('TALK HISTORY'),
        const SizedBox(height: 8),
        if (talkSessions.isEmpty)
          _buildEmptyKindState('No voice history yet.')
        else
          ...talkSessions.map(_buildHistoryTile),
      ],
    );
  }

  Widget _buildEmptyKindState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        message,
        style: GoogleFonts.manrope(
          color: Colors.white.withValues(alpha: 0.32),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildHistoryTile(ChatConversation session) {
    final isActive = session.id == widget.currentSessionId;
    final isDeleting = _deletingSessionIds.contains(session.id);

    return InkWell(
      onTap: isDeleting
          ? null
          : () {
        Navigator.of(context).pop();
        widget.onSessionSelected(session.id);
      },
      onLongPress: isDeleting ? null : () => unawaited(_showHistoryActions(session)),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isActive
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  session.isTalk
                      ? Icons.mic_none_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 14,
                  color: session.isTalk
                      ? const Color(0xFF8BD8FF)
                      : Colors.white.withValues(alpha: 0.58),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: isActive
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (isDeleting)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  )
                else
                  Text(
                    _formatTimestamp(session.updatedAt),
                    style: GoogleFonts.manrope(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              session.previewText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                color: Colors.white.withValues(alpha: 0.48),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHistoryActions(ChatConversation session) async {
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
                  session.title,
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
                  session.isTalk ? 'Voice conversation' : 'Text conversation',
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
                    'Delete history',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFFFF8A80),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Remove this conversation locally and from Supabase.',
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
      await _confirmDeleteSession(session);
    }
  }

  Future<void> _confirmDeleteSession(ChatConversation session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17171A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Delete history?',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'This will permanently delete "${session.title}" from the sidebar and Supabase.',
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
      _deletingSessionIds.add(session.id);
      _sessions = _sessions
          .where((conversation) => conversation.id != session.id)
          .toList(growable: false);
    });

    try {
      await SupabaseService.deleteConversation(session.id);
      if (!mounted) {
        return;
      }
      widget.onSessionDeleted(session.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = [..._sessions, session];
        _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not delete that history item. Please try again.',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      debugPrint('[SidebarDrawer] Failed to delete session ${session.id}: $error');
    } finally {
      if (mounted) {
        setState(() {
          _deletingSessionIds.remove(session.id);
        });
      }
    }
  }

  Widget _buildCompanionSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.emoji_emotions_outlined,
                color: Colors.white.withValues(alpha: 0.5),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Companions',
                style: GoogleFonts.manrope(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: Row(
              children: [
                _buildCompanionCard(
                  'packages/flutter_plugin2/assets/UI image/female companion.png',
                  companionId: 'march7th',
                ),
                const SizedBox(width: 10),
                _buildCompanionCard(
                  'packages/flutter_plugin2/assets/UI image/icegirl model2.png',
                  companionId: 'icegirl',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemindersSection() {
    final upcomingReminders = _upcomingReminders;
    final nextReminder =
        upcomingReminders.isEmpty ? null : upcomingReminders.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              Navigator.of(context).pop('reminders');
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8BD8FF).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.alarm_rounded,
                      color: Color(0xFF8BD8FF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Reminders',
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (upcomingReminders.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8BD8FF)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${upcomingReminders.length}',
                                  style: GoogleFonts.manrope(
                                    color: const Color(0xFF8BD8FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_isLoadingReminders)
                          Text(
                            'Loading reminders...',
                            style: GoogleFonts.manrope(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        else if (nextReminder == null)
                          Text(
                            'No reminders yet. Reminder commands from Talk or Chat will appear here.',
                            style: GoogleFonts.manrope(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nextReminder.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Next at ${_formatTimestamp(nextReminder.scheduledAt)}',
                                style: GoogleFonts.manrope(
                                  color: Colors.white.withValues(alpha: 0.42),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.28),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanionCard(String assetPath, {required String companionId}) {
    final isActive = widget.activeCompanionId == companionId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).pop('companion:$companionId');
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(
                    color: const Color(0xFF7C4DFF),
                    width: 2.5,
                  )
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isActive ? 10 : 12),
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              height: 90,
              errorBuilder: (_, __, ___) => Container(
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.person,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 36,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection(double bottomPad) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop('profile');
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 16),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF7C4DFF),
              child: Text(
                _getInitials(widget.userName),
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.userName,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white.withValues(alpha: 0.4),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    final sameDay = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;

    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';

    if (sameDay) {
      return '$hour:$minute $suffix';
    }

    return '${local.day}/${local.month}';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
