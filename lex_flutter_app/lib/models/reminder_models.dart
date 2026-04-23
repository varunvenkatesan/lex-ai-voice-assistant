class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.userId,
    required this.title,
    required this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    this.details,
    this.source = talkSource,
    this.status = scheduledStatus,
    this.deliveredAt,
  });

  static const String talkSource = 'talk';
  static const String chatSource = 'chat';
  static const String scheduledStatus = 'scheduled';
  static const String triggeredStatus = 'triggered';

  final String id;
  final String userId;
  final String title;
  final String? details;
  final DateTime scheduledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String source;
  final String status;
  final DateTime? deliveredAt;

  bool get isTalk => source == talkSource;

  bool get isChat => source == chatSource;

  bool get isTriggered => status == triggeredStatus || deliveredAt != null;

  String get sourceLabel => isTalk ? 'Talk' : 'Chat';

  String get displayDetails {
    final trimmed = details?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return isTalk ? 'Created from the voice assistant' : 'Created from chat';
  }

  ReminderItem copyWith({
    String? id,
    String? userId,
    String? title,
    String? details,
    DateTime? scheduledAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? source,
    String? status,
    DateTime? deliveredAt,
    bool clearDeliveredAt = false,
  }) {
    return ReminderItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      details: details ?? this.details,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      status: status ?? this.status,
      deliveredAt:
          clearDeliveredAt ? null : deliveredAt ?? this.deliveredAt,
    );
  }

  factory ReminderItem.fromMap(Map<String, dynamic> map) {
    return ReminderItem(
      id: map['id'] as String,
      userId: map['user_id'] as String? ?? '',
      title: map['title'] as String? ?? 'Reminder',
      details: map['details'] as String?,
      scheduledAt: DateTime.tryParse(map['scheduled_at'] as String? ?? '') ??
          DateTime.now(),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
      source: (map['source'] as String?) == chatSource ? chatSource : talkSource,
      status: (map['status'] as String?) == triggeredStatus
          ? triggeredStatus
          : scheduledStatus,
      deliveredAt: DateTime.tryParse(map['delivered_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'details': details,
      'scheduled_at': scheduledAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'source': source,
      'status': status,
      'delivered_at': deliveredAt?.toIso8601String(),
    };
  }
}

class ReminderDraft {
  const ReminderDraft({
    required this.title,
    required this.scheduledAt,
    this.details,
    this.source = ReminderItem.talkSource,
  });

  final String title;
  final String? details;
  final DateTime scheduledAt;
  final String source;
}

class ReminderNotificationPreferences {
  const ReminderNotificationPreferences({
    required this.popupWithVoice,
    required this.popupWithText,
  });

  const ReminderNotificationPreferences.defaults()
      : popupWithVoice = true,
        popupWithText = true;

  final bool popupWithVoice;
  final bool popupWithText;

  ReminderNotificationPreferences copyWith({
    bool? popupWithVoice,
    bool? popupWithText,
  }) {
    return ReminderNotificationPreferences(
      popupWithVoice: popupWithVoice ?? this.popupWithVoice,
      popupWithText: popupWithText ?? this.popupWithText,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'popup_with_voice': popupWithVoice,
      'popup_with_text': popupWithText,
    };
  }

  factory ReminderNotificationPreferences.fromMap(Map<String, dynamic> map) {
    return ReminderNotificationPreferences(
      popupWithVoice: map['popup_with_voice'] as bool? ?? true,
      popupWithText: map['popup_with_text'] as bool? ?? true,
    );
  }
}
