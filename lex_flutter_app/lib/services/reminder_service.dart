import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder_models.dart';
import 'supabase_service.dart';

const String _pendingTappedReminderKey = 'lex_pending_tapped_reminder_payload';

class ReminderParser {
  ReminderParser._();

  static const String _commandPrefixPattern =
      r'(?:remind me|need(?:\s+(?:a|an))?\s+reminder|want(?:\s+(?:a|an))?\s+reminder|'
      r'set(?:\s+(?:a|an))?\s+(?:reminder|alarm)|create(?:\s+(?:a|an))?\s+reminder|'
      r'notify me|alert me|reminder to|remember to)';

  static bool looksLikeReminderCommand(String rawText) {
    final normalized = _normalizeCommandText(rawText);
    if (normalized.isEmpty) {
      return false;
    }

    final hasReminderKeyword = RegExp(
      r'\b(remind|reminder|alarm|notify|alert|remember to)\b',
      caseSensitive: false,
    ).hasMatch(normalized);
    final hasTimeSignal = RegExp(
      r'\b(in\s+\d+\s+(?:minute|minutes|hour|hours)|(?:at|on)\s+\d{1,2}(?:[:.\s]\d{2})?\s*(?:am|pm)?|tomorrow)\b',
      caseSensitive: false,
    ).hasMatch(normalized);

    return hasReminderKeyword && hasTimeSignal;
  }

  static ReminderDraft? parseVoiceCommand(
    String rawText, {
    DateTime? now,
    String source = ReminderItem.talkSource,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    final normalizedText = _normalizeCommandText(text);
    if (!looksLikeReminderCommand(normalizedText)) {
      return null;
    }

    final current = now ?? DateTime.now();

    final inDurationMatch = RegExp(
      r'(.+?)\s+in\s+(\d+)\s+(minute|minutes|hour|hours)\b',
      caseSensitive: false,
    ).firstMatch(normalizedText);
    if (inDurationMatch != null) {
      final title = _extractReminderTitle(inDurationMatch.group(1)!);
      final amount = int.tryParse(inDurationMatch.group(2) ?? '');
      final unit = (inDurationMatch.group(3) ?? '').toLowerCase();
      if (title.isEmpty || amount == null || amount <= 0) {
        return null;
      }

      final scheduledAt = unit.startsWith('hour')
          ? current.add(Duration(hours: amount))
          : current.add(Duration(minutes: amount));
      return _buildDraft(
        title,
        scheduledAt,
        source: source,
        rawText: text,
      );
    }

    final timeFirstMatch = RegExp(
      '$_commandPrefixPattern\\s+(?:at|on)\\s+(.+?)\\s+(?:for|to|about)\\s+(.+)\$',
      caseSensitive: false,
    ).firstMatch(normalizedText);
    if (timeFirstMatch != null) {
      final whenText = timeFirstMatch.group(1)!.trim();
      final title = _extractReminderTitle(timeFirstMatch.group(2)!);
      final scheduledAt = _parseDateTimePhrase(whenText, current);
      if (title.isNotEmpty && scheduledAt != null) {
        return _buildDraft(
          title,
          scheduledAt,
          source: source,
          rawText: text,
        );
      }
    }

    final suffixTimeMatch = RegExp(
      '$_commandPrefixPattern\\s+(?:to\\s+|for\\s+|about\\s+)?(.+?)\\s+(?:at|on)\\s+(.+)\$',
      caseSensitive: false,
    ).firstMatch(normalizedText);
    if (suffixTimeMatch != null) {
      final title = _extractReminderTitle(suffixTimeMatch.group(1)!);
      final whenText = suffixTimeMatch.group(2)!.trim();
      final scheduledAt = _parseDateTimePhrase(whenText, current);
      if (title.isNotEmpty && scheduledAt != null) {
        return _buildDraft(
          title,
          scheduledAt,
          source: source,
          rawText: text,
        );
      }
    }

    final prefixTimeMatch = RegExp(
      '$_commandPrefixPattern\\s+(?:for\\s+|about\\s+)?(.+?)\\s+to\\s+(.+)\$',
      caseSensitive: false,
    ).firstMatch(normalizedText);
    if (prefixTimeMatch != null) {
      final whenText = prefixTimeMatch.group(1)!.trim();
      final title = _extractReminderTitle(prefixTimeMatch.group(2)!);
      final scheduledAt = _parseDateTimePhrase(whenText, current);
      if (title.isNotEmpty && scheduledAt != null) {
        return _buildDraft(
          title,
          scheduledAt,
          source: source,
          rawText: text,
        );
      }
    }

    return null;
  }

  static bool looksLikeReminderAssistantReply(String rawText) {
    final normalized = _normalizeCommandText(rawText);
    if (normalized.isEmpty) {
      return false;
    }

    final hasReminderKeyword = RegExp(
      r'\b(reminder|alarm|remind)\b',
      caseSensitive: false,
    ).hasMatch(normalized);
    final hasConfirmationPhrase = RegExp(
      r"\b(set|scheduled|successfully scheduled)\b|i(?:'ll| will)\s+remind you\b|i(?:'ll| will)\s+set\s+(?:a\s+|the\s+)?(?:reminder|alarm)\b",
      caseSensitive: false,
    ).hasMatch(normalized);

    return hasReminderKeyword && hasConfirmationPhrase;
  }

  static ReminderDraft? parseAssistantReply(
    String rawText, {
    DateTime? now,
    ReminderDraft? fallbackDraft,
    String source = ReminderItem.talkSource,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    final normalizedText = _normalizeCommandText(text);
    if (!looksLikeReminderAssistantReply(normalizedText)) {
      return null;
    }

    final current = now ?? DateTime.now();
    final commandLikeText = _assistantReplyToCommandText(normalizedText);
    if (commandLikeText.isNotEmpty) {
      final parsedDraft = parseVoiceCommand(
        commandLikeText,
        now: current,
        source: source,
      );
      if (parsedDraft != null) {
        return _mergeAssistantDraft(
          parsedDraft,
          fallbackDraft: fallbackDraft,
          source: source,
        );
      }
    }

    final scheduledAt = _extractScheduledAtFromAssistantReply(
      normalizedText,
      current,
    );
    if (scheduledAt != null && fallbackDraft != null) {
      return ReminderDraft(
        title: fallbackDraft.title,
        details: fallbackDraft.details,
        scheduledAt: scheduledAt,
        source: source,
      );
    }

    if (fallbackDraft != null) {
      return ReminderDraft(
        title: fallbackDraft.title,
        details: fallbackDraft.details,
        scheduledAt: fallbackDraft.scheduledAt,
        source: source,
      );
    }

    if (scheduledAt != null) {
      return _buildDraft(
        'Reminder',
        scheduledAt,
        source: source,
        rawText: text,
      );
    }

    return null;
  }

  static String _normalizeCommandText(String rawText) {
    return rawText
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(r'\b(remain me|reminder me|remainder me|remaind me)\b'),
          'remind me',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _assistantReplyToCommandText(String normalizedText) {
    var commandText = normalizedText.replaceFirst(
      RegExp(
        r'^(okay|ok|sure|alright|great|done|perfect|certainly|absolutely|of course|no problem)\b[\s,!.]*',
        caseSensitive: false,
      ),
      '',
    );

    commandText = commandText.replaceFirst(
      RegExp(r"^i(?:'ll| will)\s+remind you\b", caseSensitive: false),
      'remind me',
    );
    commandText = commandText.replaceFirst(
      RegExp(
        r"^i(?:'ll| will)\s+set\s+(?:a\s+|the\s+)?(?:reminder|alarm)\b",
        caseSensitive: false,
      ),
      'remind me',
    );
    commandText = commandText.replaceFirst(
      RegExp(
        r'^(?:your\s+)?(?:reminder|alarm)\s+(?:has been\s+|is\s+)?(?:successfully\s+)?(?:scheduled|set)\b',
        caseSensitive: false,
      ),
      'remind me',
    );

    return commandText.trim();
  }

  static DateTime? _extractScheduledAtFromAssistantReply(
    String normalizedText,
    DateTime now,
  ) {
    final inDurationMatch = RegExp(
      r'\bin\s+(\d+)\s+(minute|minutes|hour|hours)\b',
      caseSensitive: false,
    ).firstMatch(normalizedText);
    if (inDurationMatch != null) {
      final amount = int.tryParse(inDurationMatch.group(1) ?? '');
      final unit = (inDurationMatch.group(2) ?? '').toLowerCase();
      if (amount != null && amount > 0) {
        return unit.startsWith('hour')
            ? now.add(Duration(hours: amount))
            : now.add(Duration(minutes: amount));
      }
    }

    final anchoredTimeMatch = RegExp(
      r'\b(?:at|for|on)\s+([^.!?]+)',
      caseSensitive: false,
    ).firstMatch(normalizedText);
    if (anchoredTimeMatch != null) {
      final scheduledAt = _parseDateTimePhrase(
        anchoredTimeMatch.group(1)!.trim(),
        now,
      );
      if (scheduledAt != null) {
        return scheduledAt;
      }
    }

    return _parseDateTimePhrase(normalizedText, now);
  }

  static ReminderDraft _mergeAssistantDraft(
    ReminderDraft parsedDraft, {
    ReminderDraft? fallbackDraft,
    required String source,
  }) {
    final parsedTitle = parsedDraft.title.trim();
    final fallbackTitle = fallbackDraft?.title.trim();
    final resolvedTitle = parsedTitle.isEmpty || parsedTitle == 'Reminder'
        ? (fallbackTitle == null || fallbackTitle.isEmpty
            ? parsedDraft.title
            : fallbackDraft!.title)
        : parsedDraft.title;

    return ReminderDraft(
      title: resolvedTitle,
      details: fallbackDraft?.details ?? parsedDraft.details,
      scheduledAt: parsedDraft.scheduledAt,
      source: source,
    );
  }

  static ReminderDraft _buildDraft(
    String title,
    DateTime scheduledAt, {
    required String source,
    required String rawText,
  }) {
    final normalized = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final prefix = source == ReminderItem.chatSource
        ? 'Created from chat'
        : 'Created from voice assistant';
    return ReminderDraft(
      title: title,
      details: '$prefix • $normalized',
      scheduledAt: scheduledAt,
      source: source,
    );
  }

  static String _extractReminderTitle(String raw) {
    final stripped = raw
        .replaceFirst(
          RegExp('^.*?$_commandPrefixPattern\\s*', caseSensitive: false),
          '',
        )
        .trim();
    return _cleanTitle(stripped.isEmpty ? raw : stripped);
  }

  static DateTime? _parseDateTimePhrase(String raw, DateTime now) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;

    final timeMatch = RegExp(
      r'(\d{1,2})(?:[:.\s](\d{2}))?\s*(am|pm)?',
      caseSensitive: false,
    ).firstMatch(text);

    if (timeMatch == null) return null;

    var hour = int.tryParse(timeMatch.group(1) ?? '');
    final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
    final meridiem = (timeMatch.group(3) ?? '').toLowerCase();
    if (hour == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }

    if (meridiem == 'pm' && hour < 12) {
      hour += 12;
    } else if (meridiem == 'am' && hour == 12) {
      hour = 0;
    }

    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (text.contains('tomorrow')) {
      scheduled = scheduled.add(const Duration(days: 1));
    } else if (scheduled.isBefore(now.add(const Duration(minutes: 1)))) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  static String _cleanTitle(String raw) {
    return raw
        .trim()
        .replaceAll(
          RegExp(r'^(that|me to|to|for|about)\s+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();
  static const String _channelId = 'lex_reminders';
  static const String _channelName = 'LEX Reminders';
  static const String _channelDescription =
      'High-priority reminder alarms scheduled through Lex';
  static const String _preferencesKey = 'lex_reminder_preferences_v2';
  static const MethodChannel _nativeReminderChannel =
      MethodChannel('lex.reminder_overlay');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<ReminderItem> _triggeredController =
      StreamController<ReminderItem>.broadcast();

  Timer? _foregroundReminderTimer;
  bool _initialized = false;
  ReminderItem? _pendingTriggeredReminder;

  Stream<ReminderItem> get triggeredReminders => _triggeredController.stream;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) async {
        await _handleTriggeredPayload(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: _notificationTapBackground,
    );

    await _requestPermissions();
    _initialized = true;
    await _restoreNotificationLaunchReminder();
    await _restoreTappedReminderIfAny();
    await _reschedulePendingReminders();
  }

  Future<ReminderNotificationPreferences> loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_preferencesKey);
    if (raw == null || raw.isEmpty) {
      return const ReminderNotificationPreferences.defaults();
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return ReminderNotificationPreferences.fromMap(decoded);
    } catch (_) {
      return ReminderNotificationPreferences.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    }
  }

  Future<void> saveNotificationPreferences(
    ReminderNotificationPreferences preferences,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _preferencesKey,
      jsonEncode(preferences.toMap()),
    );
  }

  Future<void> setPopupWithVoice(bool enabled) async {
    final current = await loadNotificationPreferences();
    await saveNotificationPreferences(
      current.copyWith(popupWithVoice: enabled),
    );
  }

  Future<void> setPopupWithText(bool enabled) async {
    final current = await loadNotificationPreferences();
    await saveNotificationPreferences(
      current.copyWith(popupWithText: enabled),
    );
  }

  Future<ReminderItem> createAndScheduleReminder(ReminderDraft draft) async {
    await initialize();
    final reminder = await SupabaseService.createReminder(draft: draft);
    await scheduleStoredReminder(reminder);
    return reminder;
  }

  Future<List<ReminderItem>> loadAllReminders() async {
    await initialize();
    try {
      return await SupabaseService.getReminders();
    } catch (error) {
      debugPrint('[ReminderService] Failed to load reminders: $error');
      return <ReminderItem>[];
    }
  }

  Future<List<ReminderItem>> loadPendingReminders() async {
    await initialize();
    try {
      return await SupabaseService.getPendingReminders();
    } catch (error) {
      debugPrint('[ReminderService] Failed to load pending reminders: $error');
      return <ReminderItem>[];
    }
  }

  Future<void> scheduleStoredReminder(ReminderItem reminder) async {
    await initialize();
    if (reminder.isTriggered || reminder.scheduledAt.isBefore(DateTime.now())) {
      return;
    }
    await _scheduleNotification(reminder);
    // Always arm the foreground timer — even on Android.
    // The native alarm provides background/lock-screen coverage,
    // while the Dart timer ensures a reliable in-app popup when
    // the app is in the foreground (Android 10+ restricts
    // background Activity starts, so the native overlay may not
    // launch from a BroadcastReceiver).
    await _armForegroundReminderTimer();
  }

  Future<void> markReminderTriggered(
    String reminderId, {
    DateTime? deliveredAt,
  }) async {
    try {
      await SupabaseService.markReminderTriggered(
        reminderId,
        deliveredAt: deliveredAt,
      );
    } catch (error) {
      debugPrint('[ReminderService] Failed to mark reminder triggered: $error');
    }
    await _cancelNativeReminderAlarm(reminderId);
    await _armForegroundReminderTimer();
  }

  Future<void> deleteReminder(ReminderItem reminder) async {
    await initialize();

    try {
      await SupabaseService.deleteReminder(reminder.id);
    } catch (error) {
      debugPrint('[ReminderService] Failed to delete reminder: $error');
      rethrow;
    }

    await _notifications.cancel(reminder.id.hashCode);
    await _dismissNativeReminderNotification(reminder.id);
    await _cancelNativeReminderAlarm(reminder.id);
    clearPendingTriggeredReminder(reminder.id);
    await _armForegroundReminderTimer();
  }

  ReminderItem? takePendingTriggeredReminder() {
    final reminder = _pendingTriggeredReminder;
    _pendingTriggeredReminder = null;
    return reminder;
  }

  void clearPendingTriggeredReminder(String reminderId) {
    if (_pendingTriggeredReminder?.id == reminderId) {
      _pendingTriggeredReminder = null;
    }
  }

  Future<void> _reschedulePendingReminders() async {
    final reminders = await loadPendingReminders();
    await _notifications.cancelAll();
    final now = DateTime.now();
    for (final reminder in reminders) {
      if (reminder.scheduledAt.isAfter(now)) {
        await _scheduleNotification(reminder);
      }
    }
    await _armForegroundReminderTimer();
  }

  Future<void> _scheduleNotification(ReminderItem reminder) async {
    if (_usesNativeReminderOverlay) {
      try {
        await _scheduleNativeReminderAlarm(reminder);
        return;
      } catch (error) {
        debugPrint(
            '[ReminderService] Native reminder overlay scheduling failed: $error');
      }
    }

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestExactAlarmsPermission();
    await androidPlugin?.requestFullScreenIntentPermission();

    final preferences = await loadNotificationPreferences();
    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        ticker: 'LEX reminder alarm',
        channelAction: AndroidNotificationChannelAction.update,
      ),
    );

    final body = preferences.popupWithText
        ? '${reminder.displayDetails} • ${_formatNotificationTime(reminder.scheduledAt)}'
        : 'Reminder due now. Open Lex to hear it.';

    await _notifications.zonedSchedule(
      reminder.id.hashCode,
      'LEX Reminder',
      body,
      tz.TZDateTime.from(reminder.scheduledAt, tz.local),
      notificationDetails,
      payload: jsonEncode(reminder.toMap()),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
    );
  }

  bool get _usesNativeReminderOverlay =>
      defaultTargetPlatform == TargetPlatform.android;

  Future<void> _scheduleNativeReminderAlarm(ReminderItem reminder) async {
    await _nativeReminderChannel.invokeMethod(
      'scheduleReminderAlarm',
      reminder.toMap(),
    );
  }

  Future<void> _cancelNativeReminderAlarm(String reminderId) async {
    if (!_usesNativeReminderOverlay) {
      return;
    }
    try {
      await _nativeReminderChannel.invokeMethod(
        'cancelReminderAlarm',
        {'reminderId': reminderId},
      );
    } catch (error) {
      debugPrint(
          '[ReminderService] Failed to cancel native reminder alarm: $error');
    }
  }

  /// Dismiss the notification posted by [ReminderAlarmReceiver] on the native
  /// side. Called when the foreground Dart timer fires first so the user
  /// doesn't see a duplicate heads-up notification alongside the in-app popup.
  Future<void> _dismissNativeReminderNotification(String reminderId) async {
    if (!_usesNativeReminderOverlay) return;
    try {
      await _nativeReminderChannel.invokeMethod(
        'dismissReminderAlert',
        {'reminderId': reminderId},
      );
    } catch (_) {
      // Best-effort — the notification may not exist yet if the native
      // alarm hasn't fired, or the channel might not be available.
    }
  }

  Future<void> _armForegroundReminderTimer() async {
    _foregroundReminderTimer?.cancel();
    final reminders = await loadPendingReminders();
    if (reminders.isEmpty) return;

    final next = reminders.first;
    final delay = next.scheduledAt.difference(DateTime.now());
    if (delay.isNegative || delay.inSeconds <= 0) {
      await _triggerReminder(next);
      return;
    }

    _foregroundReminderTimer = Timer(delay, () async {
      await _triggerReminder(next);
    });
  }

  Future<void> _triggerReminder(ReminderItem reminder) async {
    final deliveredAt = DateTime.now();
    await _notifications.cancel(reminder.id.hashCode);
    // Dismiss any native overlay notification so the user doesn't
    // see a duplicate heads-up when the in-app popup is already shown.
    await _dismissNativeReminderNotification(reminder.id);
    await markReminderTriggered(reminder.id, deliveredAt: deliveredAt);
    _emitTriggeredReminder(
      reminder.copyWith(
        status: ReminderItem.triggeredStatus,
        deliveredAt: deliveredAt,
        updatedAt: deliveredAt,
      ),
    );
  }

  void _emitTriggeredReminder(ReminderItem reminder) {
    _pendingTriggeredReminder = reminder;
    if (!_triggeredController.isClosed) {
      _triggeredController.add(reminder);
    }
  }

  Future<void> _handleTriggeredPayload(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    try {
      final reminder =
          ReminderItem.fromMap(Map<String, dynamic>.from(jsonDecode(payload)));
      final deliveredAt = DateTime.now();
      await markReminderTriggered(reminder.id, deliveredAt: deliveredAt);
      _emitTriggeredReminder(
        reminder.copyWith(
          status: ReminderItem.triggeredStatus,
          deliveredAt: deliveredAt,
          updatedAt: deliveredAt,
        ),
      );
    } catch (error) {
      debugPrint(
        '[ReminderService] Failed to handle notification payload: $error',
      );
    }
  }

  Future<void> _restoreNotificationLaunchReminder() async {
    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      await _handleTriggeredPayload(
        launchDetails?.notificationResponse?.payload,
      );
    }
  }

  Future<void> _restoreTappedReminderIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_pendingTappedReminderKey);
    if (payload == null || payload.isEmpty) {
      return;
    }
    await prefs.remove(_pendingTappedReminderKey);
    await _handleTriggeredPayload(payload);
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
    await androidPlugin?.requestFullScreenIntentPermission();
  }

  String _formatNotificationTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $meridiem';
  }

  Future<void> dispose() async {
    _foregroundReminderTimer?.cancel();
    await _triggeredController.close();
  }
}

@pragma('vm:entry-point')
Future<void> _notificationTapBackground(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_pendingTappedReminderKey, payload);
}
