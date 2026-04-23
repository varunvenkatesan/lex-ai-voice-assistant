class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.userId,
    required this.title,
    required this.rawTitle,
    required this.conversationKind,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessagePreview,
  });

  static const String chatKind = 'chat';
  static const String talkKind = 'talk';
  static const String _chatPrefix = '[chat] ';
  static const String _talkPrefix = '[talk] ';

  final String id;
  final String userId;
  final String title;
  final String rawTitle;
  final String conversationKind;
  final String? lastMessagePreview;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTalk => conversationKind == talkKind;

  bool get isChat => !isTalk;

  String get kindLabel => isTalk ? 'Talk' : 'Chat';

  String get previewText {
    final preview = lastMessagePreview?.trim();
    if (preview == null || preview.isEmpty) {
      return 'No messages yet';
    }
    return preview;
  }

  factory ChatConversation.fromMap(Map<String, dynamic> map) {
    final rawTitle = (map['title'] as String?)?.trim() ?? 'New Chat';
    final conversationKind = _normalizeKind(
      map['conversation_kind'] as String?,
      fallbackTitle: rawTitle,
    );

    return ChatConversation(
      id: map['id'] as String,
      userId: map['user_id'] as String? ?? '',
      title: _displayTitle(rawTitle),
      rawTitle: rawTitle,
      conversationKind: conversationKind,
      lastMessagePreview: map['last_message_preview'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': rawTitle,
      'conversation_kind': conversationKind,
      'last_message_preview': lastMessagePreview,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static String buildStoredTitle(
    String title, {
    String kind = chatKind,
  }) {
    final normalized =
        _displayTitle(title.trim()).replaceAll(RegExp(r'\s+'), ' ').trim();
    final visibleTitle = normalized.isEmpty ? 'New Chat' : normalized;
    final prefix = kind == talkKind ? _talkPrefix : _chatPrefix;
    return '$prefix$visibleTitle';
  }

  static String _normalizeKind(
    String? value, {
    required String fallbackTitle,
  }) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == talkKind) {
      return talkKind;
    }
    if (normalized == chatKind) {
      return chatKind;
    }
    return fallbackTitle.trim().toLowerCase().startsWith(_talkPrefix)
        ? talkKind
        : chatKind;
  }

  static String _displayTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.toLowerCase().startsWith(_talkPrefix)) {
      final visible = trimmed.substring(_talkPrefix.length).trim();
      return visible.isEmpty ? 'New Chat' : visible;
    }
    if (trimmed.toLowerCase().startsWith(_chatPrefix)) {
      final visible = trimmed.substring(_chatPrefix.length).trim();
      return visible.isEmpty ? 'New Chat' : visible;
    }
    return trimmed.isEmpty ? 'New Chat' : trimmed;
  }
}

class ChatConversationMessage {
  const ChatConversationMessage({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.role,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String userId;
  final String role;
  final String message;
  final DateTime createdAt;

  factory ChatConversationMessage.fromMap(Map<String, dynamic> map) {
    return ChatConversationMessage(
      id: map['id'] as String,
      sessionId: map['session_id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      role: map['role'] as String? ?? 'assistant',
      message: map['message'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'role': role,
      'message': message,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
