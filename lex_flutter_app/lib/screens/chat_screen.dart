import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import '../models/reminder_models.dart';
import '../services/network_config.dart';
import '../services/reminder_service.dart';
import '../services/supabase_service.dart';
import '../widgets/sidebar_drawer.dart';

class ChatMessage {
  ChatMessage({
    this.id,
    required this.role,
    required this.text,
    required this.time,
    this.isStreaming = false,
    this.isSynthetic = false,
  });

  final String? id;
  final String role;
  String text;
  final DateTime time;
  bool isStreaming;
  final bool isSynthetic;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.userName = 'Guest',
    required this.serverBase,
    required this.onBack,
    this.initialSessionId,
    this.onSessionChanged,
    this.onOpenReminders,
  });

  final String userName;
  final String serverBase;
  final VoidCallback onBack;
  final String? initialSessionId;
  final ValueChanged<String?>? onSessionChanged;
  final VoidCallback? onOpenReminders;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const String _lexLogoAsset =
      'packages/flutter_plugin2/assets/UI image/lex_logo.png';
  static const String _welcomeText =
       'I am Lex, your personal assistant.';
  static const List<_QuickActionData> _quickActions = [
    _QuickActionData(
      label: 'Set Reminder',
      icon: Icons.alarm_rounded,
      color: Color(0xFFFF3DBA),
      prompt: 'What would you like me to remind you about?',
    ),
    _QuickActionData(
      label: 'Help me learn',
      icon: Icons.menu_book_rounded,
      color: Color(0xFFB62BFF),
      prompt: 'What you would like to teach me about? It can be anything',
    ),
    _QuickActionData(
      label: 'Code',
      icon: Icons.code_rounded,
      color: Color(0xFF2E5BFF),
      prompt: 'What programming concept would you like to explore?',
    ),
  ];

  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  final GlobalKey<_ChatComposerState> _composerKey =
      GlobalKey<_ChatComposerState>();

  String? _currentSessionId;
  bool _isSending = false;
  StreamSubscription<String>? _streamSub;
  StreamSubscription<List<ChatConversationMessage>>? _messageSubscription;
  http.Client? _activeStreamClient;
  ChatMessage? _copiedMessage;
  Timer? _copiedMessageTimer;

  @override
  void initState() {
    super.initState();
    _showWelcomeMessage();
    final initialSessionId = widget.initialSessionId;
    if (initialSessionId != null &&
        initialSessionId.isNotEmpty &&
        SupabaseService.isLoggedIn) {
      unawaited(_loadSession(initialSessionId));
    }
  }

  @override
  void dispose() {
    _activeStreamClient?.close();
    _streamSub?.cancel();
    _messageSubscription?.cancel();
    _copiedMessageTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSession(String sessionId) async {
    await _cancelActiveReply();
    await _messageSubscription?.cancel();
    _messageSubscription = null;

    _setCurrentSessionId(sessionId);

    try {
      final messages = await SupabaseService.getConversationMessages(sessionId);
      if (!mounted) return;
      _applyPersistedMessages(messages);
      _subscribeToSession(sessionId);
    } catch (error) {
      debugPrint('[ChatScreen] Failed to load session: $error');
      _showPersistenceNotice(
        'Could not load saved chats. Please check Supabase setup.',
      );
    }
  }

  Future<void> _startNewChat() async {
    await _cancelActiveReply();
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    if (!mounted) return;

    _setCurrentSessionId(null);
    setState(() {
      _isSending = false;
      _messages
        ..clear()
        ..add(_buildWelcomeMessage());
    });
  }

  void _subscribeToSession(String sessionId) {
    _messageSubscription =
        SupabaseService.watchConversationMessages(sessionId).listen(
      (messages) {
        if (!mounted || _currentSessionId != sessionId) return;
        _applyPersistedMessages(messages);
      },
      onError: (error) {
        debugPrint('[ChatScreen] Realtime message sync failed: $error');
      },
    );
  }

  Future<String?> _ensureSessionForMessage(String text) async {
    if (!SupabaseService.isLoggedIn) {
      return null;
    }

    if (_currentSessionId != null) {
      return _currentSessionId;
    }

    final conversation = await SupabaseService.createConversation(
      title: SupabaseService.conversationTitleFromText(text),
      kind: ChatConversation.chatKind,
    );

    _setCurrentSessionId(conversation.id);
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    _subscribeToSession(conversation.id);
    return conversation.id;
  }

  Future<void> _sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _isSending) return;

    final history = _buildHistoryPayload();
    final reminderDraft = ReminderParser.parseVoiceCommand(
      text,
      source: ReminderItem.chatSource,
    );

    final optimisticUserMessage = ChatMessage(
      role: 'user',
      text: text,
      time: DateTime.now(),
    );

    setState(() {
      _messages.removeWhere((message) => message.isSynthetic);
      _messages.add(optimisticUserMessage);
      _isSending = true;
    });
    _scrollToBottom();

    String? sessionId = _currentSessionId;
    if (SupabaseService.isLoggedIn) {
      try {
        sessionId = await _ensureSessionForMessage(text);
        if (sessionId != null) {
          final storedUserMessage = await SupabaseService.insertMessage(
            sessionId: sessionId,
            role: 'user',
            message: text,
          );
          if (!mounted) return;
          _upsertPersistedMessage(
            _messageFromRecord(storedUserMessage),
            replacing: optimisticUserMessage,
          );
        }
      } catch (error) {
        debugPrint('[ChatScreen] Failed to persist user message: $error');
        _showPersistenceNotice(
          'Message was sent, but it could not be saved to chat history.',
        );
      }
    }

    if (reminderDraft != null) {
      try {
        final reminder =
            await ReminderService.instance.createAndScheduleReminder(reminderDraft);
        if (!mounted) return;
        _showPersistenceNotice(
          'Reminder set for ${_formatReminderTime(reminder.scheduledAt)}',
        );
        await _finishLocalReminderReply(
          reminder: reminder,
          sessionId: sessionId,
        );
        return;
      } catch (error) {
        debugPrint('[ChatScreen] Failed to create reminder: $error');
        _showPersistenceNotice(
          'I understood the reminder, but it could not be saved.',
        );
      }
    }

    final aiMessage = ChatMessage(
      role: 'assistant',
      text: '',
      time: DateTime.now(),
      isStreaming: true,
    );
    setState(() => _messages.add(aiMessage));
    _scrollToBottom();

    final client = http.Client();
    _activeStreamClient = client;

    try {
      final serverBase = NetworkConfig.normalizeBaseUrl(widget.serverBase);
      final uri = Uri.parse('$serverBase/chat/stream');

      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'message': text,
        'history': history,
        'memory_user_id': SupabaseService.currentUser?.id ?? widget.userName,
        'memory_user_name': widget.userName,
      });

      final response = await client.send(request);
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        await _showStreamingFailure(aiMessage, _parseErrorMessage(errorBody));
        return;
      }

      _streamSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!line.startsWith('data: ')) return;
          final data = line.substring(6);
          if (data == '[DONE]') {
            unawaited(_finishStreamingReply(aiMessage));
            return;
          }

          try {
            final chunk = jsonDecode(data) as Map<String, dynamic>;
            if (chunk.containsKey('text')) {
              setState(() {
                aiMessage.text += chunk['text'] as String;
              });
              _scrollToBottom();
              return;
            }

            if (chunk.containsKey('error')) {
              unawaited(
                _showStreamingFailure(
                  aiMessage,
                  _parseErrorMessage(chunk['error'].toString()),
                ),
              );
            }
          } catch (_) {}
        },
        onError: (error) {
          unawaited(
            _showStreamingFailure(
                aiMessage, _parseErrorMessage(error.toString())),
          );
        },
        onDone: () {
          if (aiMessage.isStreaming) {
            unawaited(_finishStreamingReply(aiMessage));
          }
        },
      );
    } catch (error) {
      await _showStreamingFailure(
          aiMessage, _parseErrorMessage(error.toString()));
    }
  }

  Future<void> _finishLocalReminderReply({
    required ReminderItem reminder,
    required String? sessionId,
  }) async {
    final assistantMessage = ChatMessage(
      role: 'assistant',
      text: _buildReminderConfirmation(reminder),
      time: DateTime.now(),
    );

    if (!mounted) return;
    setState(() {
      _messages.add(assistantMessage);
      _isSending = false;
    });
    _scrollToBottom();

    if (!SupabaseService.isLoggedIn ||
        sessionId == null ||
        assistantMessage.text.trim().isEmpty) {
      return;
    }

    try {
      final storedAssistantMessage = await SupabaseService.insertMessage(
        sessionId: sessionId,
        role: 'assistant',
        message: assistantMessage.text,
      );
      if (!mounted) return;
      _upsertPersistedMessage(
        _messageFromRecord(storedAssistantMessage),
        replacing: assistantMessage,
      );
    } catch (error) {
      debugPrint(
        '[ChatScreen] Failed to persist local reminder confirmation: $error',
      );
      _showPersistenceNotice(
        'Reminder was created, but the confirmation could not be saved to chat history.',
      );
    }
  }

  Future<void> _finishStreamingReply(ChatMessage aiMessage) async {
    await _streamSub?.cancel();
    _streamSub = null;
    _activeStreamClient?.close();
    _activeStreamClient = null;

    if (!mounted) return;

    setState(() {
      aiMessage.isStreaming = false;
      _isSending = false;
    });

    final responseText = aiMessage.text.trim();
    if (!SupabaseService.isLoggedIn ||
        _currentSessionId == null ||
        responseText.isEmpty) {
      return;
    }

    try {
      final storedAssistantMessage = await SupabaseService.insertMessage(
        sessionId: _currentSessionId!,
        role: 'assistant',
        message: responseText,
      );
      if (!mounted) return;
      _upsertPersistedMessage(
        _messageFromRecord(storedAssistantMessage),
        replacing: aiMessage,
      );
    } catch (error) {
      debugPrint('[ChatScreen] Failed to persist assistant message: $error');
      _showPersistenceNotice(
        'Reply was received, but it could not be saved to chat history.',
      );
    }
  }

  Future<void> _showStreamingFailure(
    ChatMessage aiMessage,
    String message,
  ) async {
    await _streamSub?.cancel();
    _streamSub = null;
    _activeStreamClient?.close();
    _activeStreamClient = null;

    if (!mounted) return;
    setState(() {
      aiMessage.text = message;
      aiMessage.isStreaming = false;
      _isSending = false;
    });
  }

  Future<void> _cancelActiveReply() async {
    _activeStreamClient?.close();
    _activeStreamClient = null;
    await _streamSub?.cancel();
    _streamSub = null;

    if (!mounted) return;
    setState(() {
      _isSending = false;
      _messages.removeWhere(
        (message) => message.isStreaming && message.text.trim().isEmpty,
      );
      for (final message in _messages.where((message) => message.isStreaming)) {
        message.isStreaming = false;
      }
    });
  }

  List<Map<String, String>> _buildHistoryPayload() {
    return _messages
        .where((message) => !message.isStreaming && !message.isSynthetic)
        .map((message) => {
              'role': message.role,
              'content': message.text,
            })
        .toList(growable: false);
  }

  void _applyPersistedMessages(List<ChatConversationMessage> records) {
    final streamingMessages = _messages
        .where((message) => message.isStreaming)
        .toList(growable: false);
    final persistedMessages =
        records.map(_messageFromRecord).toList(growable: false);
    final localOnlyMessages = _messages
        .where(
          (message) =>
              message.id == null &&
              !message.isStreaming &&
              !message.isSynthetic &&
              !persistedMessages.any(
                (persisted) =>
                    persisted.role == message.role &&
                    persisted.text == message.text,
              ),
        )
        .toList(growable: false);

    setState(() {
      _messages
        ..clear()
        ..addAll(persistedMessages)
        ..addAll(localOnlyMessages)
        ..addAll(streamingMessages);
      if (_messages.isEmpty) {
        _messages.add(_buildWelcomeMessage());
      }
    });
    _scrollToBottom();
  }

  void _upsertPersistedMessage(
    ChatMessage message, {
    ChatMessage? replacing,
  }) {
    setState(() {
      if (replacing != null) {
        final replacingIndex = _messages.indexOf(replacing);
        if (replacingIndex != -1) {
          _messages[replacingIndex] = message;
          return;
        }
      }

      final existingIndex = message.id == null
          ? -1
          : _messages.indexWhere((item) => item.id == message.id);
      if (existingIndex != -1) {
        _messages[existingIndex] = message;
        return;
      }

      final insertBeforeStreaming =
          _messages.indexWhere((item) => item.isStreaming);
      _messages.removeWhere((item) => item.isSynthetic);
      if (insertBeforeStreaming == -1) {
        _messages.add(message);
      } else {
        _messages.insert(insertBeforeStreaming, message);
      }
    });
    _scrollToBottom();
  }

  ChatMessage _messageFromRecord(ChatConversationMessage record) {
    return ChatMessage(
      id: record.id,
      role: record.role,
      text: record.message,
      time: record.createdAt,
    );
  }

  ChatMessage _buildWelcomeMessage() {
    return ChatMessage(
      role: 'assistant',
      text: _welcomeText,
      time: DateTime.now(),
      isSynthetic: true,
    );
  }

  void _showWelcomeMessage() {
    _messages
      ..clear()
      ..add(_buildWelcomeMessage());
  }

  void _handleQuickAction(_QuickActionData action) {
    setState(() {
      _messages.removeWhere((m) => m.isSynthetic);
      _messages.add(ChatMessage(
        role: 'assistant',
        text: action.prompt,
        time: DateTime.now(),
        isSynthetic: true,
      ));
    });
    _scrollToBottom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _composerKey.currentState?._focusNode.requestFocus();
    });
  }

  void _setCurrentSessionId(String? sessionId) {
    _currentSessionId = sessionId;
    widget.onSessionChanged?.call(sessionId);
  }

  bool get _isWelcomeState =>
      !_messages.any((message) => !message.isSynthetic);

  String _parseErrorMessage(String rawError) {
    final lower = rawError.toLowerCase();
    if (lower.contains('429') ||
        lower.contains('quota') ||
        lower.contains('rate')) {
      return 'Lex is currently busy. Please wait a moment and try again.';
    }
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('authentication') ||
        lower.contains('api key')) {
      return 'Gemini authentication error. Please check the server configuration.';
    }
    if (lower.contains('500') || lower.contains('internal')) {
      return 'Server error. Please try again later.';
    }
    if (lower.contains('not found') ||
        lower.contains('unsupported') ||
        lower.contains('not supported')) {
      return 'Gemini chat model is unavailable right now. Please try again.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }
    if (lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('socketexception')) {
      return 'Could not reach the chat server. Please check the server URL and your connection.';
    }
    return 'Something went wrong. Please try again.';
  }

  String _buildReminderConfirmation(ReminderItem reminder) {
    final details = reminder.details?.trim();
    final hasDetails = details != null && details.isNotEmpty;
    return 'Reminder set for ${_formatReminderTime(reminder.scheduledAt)}.\n\n'
        '${reminder.title}'
        '${hasDetails ? '\n$details' : ''}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _showPersistenceNotice(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 112),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _copyMessageText(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!mounted) return;

    _copiedMessageTimer?.cancel();
    setState(() => _copiedMessage = message);

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Copied to clipboard'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 112),
          duration: const Duration(milliseconds: 1400),
        ),
      );

    _copiedMessageTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted || !identical(_copiedMessage, message)) return;
      setState(() => _copiedMessage = null);
    });
  }

  Widget _buildCopyAction({
    required ChatMessage message,
    required bool alignRight,
  }) {
    final isCopied = identical(_copiedMessage, message);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionIcon(
              icon: isCopied ? Icons.check : Icons.copy_outlined,
              tooltip: isCopied ? 'Copied' : 'Copy',
              color: isCopied
                  ? const Color(0xFF8BD8FF)
                  : Colors.white.withValues(alpha: 0.38),
              onTap: () => _copyMessageText(message),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isCopied
                  ? Padding(
                      key: ValueKey(
                        message.id ?? message.time.microsecondsSinceEpoch,
                      ),
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        'Copied',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF8BD8FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeMarkdown(String text) {
    return text.replaceAll('\r\n', '\n').trim();
  }

  TextStyle _assistantBodyTextStyle() {
    return GoogleFonts.plusJakartaSans(
      color: Colors.white.withValues(alpha: 0.98),
      fontSize: 18,
      height: 1.72,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.05,
    );
  }

  MarkdownStyleSheet _assistantMarkdownStyleSheet(BuildContext context) {
    final body = _assistantBodyTextStyle();
    const headingColor = Colors.white;

    return MarkdownStyleSheet(
      p: body,
      pPadding: const EdgeInsets.only(bottom: 18),
      strong: body.copyWith(
        fontWeight: FontWeight.w800,
        color: headingColor,
      ),
      em: body.copyWith(
        fontStyle: FontStyle.italic,
        color: Colors.white.withValues(alpha: 0.96),
      ),
      h1: GoogleFonts.plusJakartaSans(
        color: headingColor,
        fontSize: 34,
        height: 1.18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      h1Padding: const EdgeInsets.only(top: 14, bottom: 18),
      h2: GoogleFonts.plusJakartaSans(
        color: headingColor,
        fontSize: 28,
        height: 1.22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.45,
      ),
      h2Padding: const EdgeInsets.only(top: 12, bottom: 16),
      h3: GoogleFonts.plusJakartaSans(
        color: headingColor,
        fontSize: 23,
        height: 1.28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      h3Padding: const EdgeInsets.only(top: 10, bottom: 14),
      blockquote: body.copyWith(
        color: Colors.white.withValues(alpha: 0.95),
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      blockquoteDecoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border(
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.22),
            width: 4,
          ),
        ),
      ),
      listBullet: body.copyWith(
        color: Colors.white.withValues(alpha: 0.92),
        fontWeight: FontWeight.w700,
      ),
      code: GoogleFonts.jetBrainsMono(
        color: const Color(0xFFE7F1FF),
        fontSize: 14.5,
        height: 1.65,
        fontWeight: FontWeight.w500,
      ),
      codeblockPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF101214),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      a: body.copyWith(
        color: const Color(0xFF8BD8FF),
        decoration: TextDecoration.underline,
        decorationColor: const Color(0xFF8BD8FF),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessageContent(ChatMessage message) {
    final text = _normalizeMarkdown(message.text);
    if (text.isEmpty) {
      return Text(
        '...',
        style: _assistantBodyTextStyle(),
      );
    }

    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      styleSheet: _assistantMarkdownStyleSheet(context),
    );
  }

  void _navigateToTalk() {
    widget.onBack();
  }

  Future<void> _openSidebar() async {
    final result = await openSidebarDrawer(
      context,
      userName: widget.userName,
      currentSessionId: _currentSessionId,
      onNewChat: () {
        unawaited(_startNewChat());
      },
      onSessionSelected: (sessionId) {
        unawaited(_loadSession(sessionId));
      },
      onSessionDeleted: (sessionId) {
        if (_currentSessionId == sessionId) {
          unawaited(_startNewChat());
        }
      },
    );

    if (result == 'profile' && mounted) {
      widget.onBack();
    } else if (result == 'reminders' && mounted) {
      widget.onOpenReminders?.call();
    }
  }

  String _formatReminderTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final sameDay = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    final prefix = sameDay
        ? 'today'
        : '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return '$prefix at $hour:$minute $meridiem';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _isWelcomeState
                    ? _buildWelcomeView()
                    : _buildMessagesList(),
              ),
            ),
            _buildInputBar(bottomPad),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          _GlassCircleButton(icon: Icons.menu, size: 40, onTap: _openSidebar),
          const Spacer(),
          _buildModeToggle(),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TogglePill(
            label: 'Talk',
            selected: false,
            onTap: _navigateToTalk,
          ),
          _TogglePill(
            label: 'Chat',
            selected: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    final visibleMessages = _messages
        .where((message) => !message.isSynthetic)
        .toList(growable: false);
    if (visibleMessages.isEmpty) {
      return Center(
        child: Text(
          'Start a conversation with Lex',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('chat-conversation-list'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      itemCount: visibleMessages.length,
      itemBuilder: (context, index) {
        final message = visibleMessages[index];
        if (message.role == 'user') {
          return _buildUserBubble(message);
        }
        return _buildAssistantBubble(message);
      },
    );
  }

  Widget _buildWelcomeView() {
    return Center(
      key: const ValueKey('chat-welcome-view'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                _lexLogoAsset,
                width: 88,
                height: 88,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF63E0FF), Color(0xFFCB28FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Hi ${_displayNameForGreeting()}',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w500,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'How can I help you?',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w700,
                height: 1.06,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: _quickActions
                  .map((action) => _buildQuickActionChip(action))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionChip(_QuickActionData action) {
    return GestureDetector(
      onTap: _isSending ? null : () => _handleQuickAction(action),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, color: action.color, size: 20),
            const SizedBox(width: 7),
            Text(
              action.label,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayNameForGreeting() {
    final trimmed = widget.userName.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'guest') {
      return 'there';
    }
    return trimmed;
  }

  Widget _buildAssistantBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    _lexLogoAsset,
                    width: 22,
                    height: 22,
                    errorBuilder: (_, __, ___) => Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C4DFF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Lex',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildAssistantMessageContent(message),
            if (message.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
            if (!message.isStreaming && message.text.isNotEmpty)
              _buildCopyAction(message: message, alignRight: false),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2B30),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SelectableText(
                  message.text,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.05,
                  ),
                ),
              ),
              if (message.text.isNotEmpty)
                _buildCopyAction(message: message, alignRight: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 8, bottomPad + 10),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: _ChatComposer(
                key: _composerKey,
                isSending: _isSending,
                onSendText: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isSending
                ? null
                : () => _composerKey.currentState?._handleSend(),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSending
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFF2A2A2A),
              ),
              child: _isSending
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : Icon(
                      Icons.send_rounded,
                      color: Colors.white.withValues(alpha: 0.8),
                      size: 22,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatComposer extends StatefulWidget {
  const _ChatComposer({
    super.key,
    required this.isSending,
    required this.onSendText,
  });

  final bool isSending;
  final Future<void> Function(String text) onSendText;

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  late final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isSending) {
      return;
    }

    _controller.clear();
    _focusNode.unfocus();
    await widget.onSendText(text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('chat-composer-field'),
            controller: _controller,
            focusNode: _focusNode,
            autocorrect: true,
            enableSuggestions: true,
            enableIMEPersonalizedLearning: true,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.text,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Reply to Assistant',
              hintStyle: GoogleFonts.plusJakartaSans(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _handleSend(),
          ),
        ),
        // GestureDetector(
        //   onTap: () {},
        //   child: Padding(
        //     padding: const EdgeInsets.symmetric(horizontal: 4),
        //     child: Icon(
        //       Icons.camera_alt_outlined,
        //       color: Colors.white.withValues(alpha: 0.4),
        //       size: 22,
        //     ),
        //   ),
        // ),
        // GestureDetector(
        //   onTap: () {},
        //   child: Padding(
        //     padding: const EdgeInsets.only(right: 8),
        //     child: Icon(
        //       Icons.mic_none,
        //       color: Colors.white.withValues(alpha: 0.4),
        //       size: 22,
        //     ),
        //   ),
        // ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconButton = SizedBox(
      width: 28,
      height: 28,
      child: Center(
        child: Icon(
          icon,
          color: color ?? Colors.white.withValues(alpha: 0.38),
          size: 18,
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: iconButton,
        ),
      );
    }

    return Tooltip(
      message: tooltip!,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: iconButton,
        ),
      ),
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.label,
    required this.icon,
    required this.color,
    required this.prompt,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String prompt;
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.55),
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
