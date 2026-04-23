import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_models.dart';
import '../models/reminder_models.dart';

class SupabaseService {
  SupabaseService._();

  static const String _supabaseUrl = 'https://gukampydgtgpbuxffwic.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd1a2FtcHlkZ3RncGJ1eGZmd2ljIiwi'
      'cm9sZSI6ImFub24iLCJpYXQiOjE3NzI4Nzc5NzUsImV4cCI6MjA4ODQ1Mzk3NX0.'
      '0cA8mPvdh7PlnxNqsQiVeA87ktxFKetRV0xTlxgzC9U';

  static const Uuid _uuid = Uuid();

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  static bool get isLoggedIn => currentUser != null;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  static Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    return client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static Future<String> currentUserFullName() async {
    final user = currentUser;
    if (user == null) return 'User';

    try {
      final data = await client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .single();
      return (data['full_name'] as String?) ?? 'User';
    } catch (_) {
      return user.userMetadata?['full_name'] as String? ?? 'User';
    }
  }

  static String conversationTitleFromText(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return 'New Chat';
    }
    if (normalized.length <= 60) {
      return normalized;
    }
    return '${normalized.substring(0, 57)}...';
  }

  static Future<ChatConversation> createConversation({
    String title = 'New Chat',
    String kind = ChatConversation.chatKind,
  }) async {
    final userId = _requireUserId();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'user_id': userId,
      'title': ChatConversation.buildStoredTitle(title, kind: kind),
      'last_message_preview': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    final conversation = ChatConversation.fromMap(row);

    await _cacheConversation(conversation);

    try {
      await client.from('chat_sessions').insert(row);
    } catch (error) {
      debugPrint('[SupabaseService] Failed to sync conversation: $error');
    }

    return conversation;
  }

  static Future<void> updateConversationTitle(
    String sessionId,
    String title, [
    String? kind,
  ]) async {
    final trimmedTitle = title.trim().isEmpty ? 'New Chat' : title.trim();
    final userId = _requireUserId();
    final conversations = await _readCachedConversations(userId);
    final index = conversations
        .indexWhere((conversation) => conversation.id == sessionId);
    if (index >= 0) {
      final current = conversations[index];
      final storedTitle = kind == null
          ? trimmedTitle
          : ChatConversation.buildStoredTitle(trimmedTitle, kind: kind);
      conversations[index] = ChatConversation.fromMap({
        'id': current.id,
        'user_id': current.userId,
        'title': storedTitle,
        'last_message_preview': current.lastMessagePreview,
        'created_at': current.createdAt.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _writeCachedConversations(userId, conversations);
    }

    try {
      await client.from('chat_sessions').update({
        'title': kind == null
            ? trimmedTitle
            : ChatConversation.buildStoredTitle(trimmedTitle, kind: kind),
      }).eq('id', sessionId);
    } catch (error) {
      debugPrint('[SupabaseService] Failed to sync title update: $error');
    }
  }

  static Future<List<ChatConversation>> getConversations() async {
    final userId = _requireUserId();
    final cached = await _readCachedConversations(userId);

    try {
      final rows = await client
          .from('chat_sessions')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);
      final remote = rows
          .map<ChatConversation>((row) => ChatConversation.fromMap(row))
          .toList(growable: false);
      final merged = _mergeConversations(remote, cached);
      await _writeCachedConversations(userId, merged);
      return merged;
    } catch (error) {
      debugPrint(
        '[SupabaseService] Falling back to cached conversations: $error',
      );
      return cached;
    }
  }

  static Stream<List<ChatConversation>> watchConversations() async* {
    if (!isLoggedIn) {
      yield const <ChatConversation>[];
      return;
    }

    final userId = _requireUserId();
    yield await getConversations();

    yield* client
        .from('chat_sessions')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .asyncMap((rows) async {
          final remote = rows
              .map<ChatConversation>((row) => ChatConversation.fromMap(row))
              .toList(growable: false);
          final cached = await _readCachedConversations(userId);
          final merged = _mergeConversations(remote, cached);
          await _writeCachedConversations(userId, merged);
          return merged;
        });
  }

  static Future<void> deleteConversation(String sessionId) async {
    final userId = _requireUserId();
    final conversations = await _readCachedConversations(userId);
    final cachedMessages = await _readCachedMessages(userId, sessionId);
    final updatedConversations = conversations
        .where((conversation) => conversation.id != sessionId)
        .toList(growable: true);
    await _writeCachedConversations(userId, updatedConversations);
    await _removeCachedMessages(userId, sessionId);

    try {
      await client.from('chat_sessions').delete().eq('id', sessionId);
    } catch (error) {
      await _writeCachedConversations(userId, conversations);
      await _writeCachedMessages(userId, sessionId, cachedMessages);
      debugPrint(
        '[SupabaseService] Failed to sync conversation delete: $error',
      );
      rethrow;
    }
  }

  static Future<ChatConversationMessage> insertMessage({
    required String sessionId,
    required String role,
    required String message,
  }) async {
    final userId = _requireUserId();
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'session_id': sessionId,
      'user_id': userId,
      'role': role,
      'message': message,
      'created_at': now.toIso8601String(),
    };
    final record = ChatConversationMessage.fromMap(row);

    await _cacheMessage(record);

    try {
      await client.from('chat_messages').insert(row);
    } catch (error) {
      debugPrint('[SupabaseService] Failed to sync message: $error');
    }

    return record;
  }

  static Future<List<ChatConversationMessage>> getConversationMessages(
    String sessionId,
  ) async {
    final userId = _requireUserId();
    final cached = await _readCachedMessages(userId, sessionId);

    try {
      final rows = await client
          .from('chat_messages')
          .select()
          .eq('session_id', sessionId)
          .eq('user_id', userId)
          .order('created_at', ascending: true);
      final remote = rows
          .map<ChatConversationMessage>(
            (row) => ChatConversationMessage.fromMap(row),
          )
          .toList(growable: false);
      final merged = _mergeMessages(remote, cached);
      await _writeCachedMessages(userId, sessionId, merged);
      return merged;
    } catch (error) {
      debugPrint('[SupabaseService] Falling back to cached messages: $error');
      return cached;
    }
  }

  static Stream<List<ChatConversationMessage>> watchConversationMessages(
    String sessionId,
  ) async* {
    if (!isLoggedIn) {
      yield const <ChatConversationMessage>[];
      return;
    }

    final userId = _requireUserId();
    yield await getConversationMessages(sessionId);

    yield* client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .asyncMap((rows) async {
          final remote = rows
              .map<ChatConversationMessage>(
                (row) => ChatConversationMessage.fromMap(row),
              )
              .toList(growable: false);
          final cached = await _readCachedMessages(userId, sessionId);
          final merged = _mergeMessages(remote, cached);
          await _writeCachedMessages(userId, sessionId, merged);
          return merged;
        });
  }

  static Future<String> createSession({
    String title = 'New Chat',
    String kind = ChatConversation.chatKind,
  }) async {
    final conversation = await createConversation(title: title, kind: kind);
    return conversation.id;
  }

  static Future<void> updateSessionTitle(String sessionId, String title) async {
    await updateConversationTitle(sessionId, title);
  }

  static Future<List<Map<String, dynamic>>> getSessions() async {
    final conversations = await getConversations();
    return conversations.map((conversation) => conversation.toMap()).toList();
  }

  static Future<void> deleteSession(String sessionId) async {
    await deleteConversation(sessionId);
  }

  static Future<void> saveMessage({
    required String sessionId,
    required String role,
    required String message,
  }) async {
    await insertMessage(
      sessionId: sessionId,
      role: role,
      message: message,
    );
  }

  static Future<List<Map<String, dynamic>>> getMessages(
    String sessionId,
  ) async {
    final messages = await getConversationMessages(sessionId);
    return messages.map((message) => message.toMap()).toList();
  }

  static Future<ReminderItem> createReminder({
    required ReminderDraft draft,
  }) async {
    final userId = _requireUserId();
    final now = DateTime.now().toUtc();
    final normalizedDetails = draft.details?.trim();
    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'user_id': userId,
      'title': draft.title.trim().isEmpty ? 'Reminder' : draft.title.trim(),
      'details': normalizedDetails == null || normalizedDetails.isEmpty
          ? null
          : normalizedDetails,
      'scheduled_at': draft.scheduledAt.toUtc().toIso8601String(),
      'source': draft.source == ReminderItem.chatSource
          ? ReminderItem.chatSource
          : ReminderItem.talkSource,
      'status': ReminderItem.scheduledStatus,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'delivered_at': null,
    };
    final reminder = ReminderItem.fromMap(row);

    await _cacheReminder(reminder);

    try {
      await client.from('reminders').insert(row);
    } catch (error) {
      debugPrint('[SupabaseService] Failed to sync reminder: $error');
    }

    return reminder;
  }

  static Future<void> markReminderTriggered(
    String reminderId, {
    DateTime? deliveredAt,
  }) async {
    final userId = _requireUserId();
    final now = (deliveredAt ?? DateTime.now()).toUtc();
    final reminders = await _readCachedReminders(userId);
    final index = reminders.indexWhere((reminder) => reminder.id == reminderId);
    if (index >= 0) {
      reminders[index] = reminders[index].copyWith(
        status: ReminderItem.triggeredStatus,
        deliveredAt: now,
        updatedAt: now,
      );
      await _writeCachedReminders(userId, _sortReminders(reminders));
    }

    try {
      await client.from('reminders').update({
        'status': ReminderItem.triggeredStatus,
        'delivered_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).eq('id', reminderId);
    } catch (error) {
      debugPrint('[SupabaseService] Failed to sync reminder trigger: $error');
    }
  }

  static Future<void> deleteReminder(String reminderId) async {
    final userId = _requireUserId();
    final reminders = await _readCachedReminders(userId);
    final updatedReminders = reminders
        .where((reminder) => reminder.id != reminderId)
        .toList(growable: true);
    await _writeCachedReminders(userId, _sortReminders(updatedReminders));

    try {
      await client.from('reminders').delete().eq('id', reminderId);
    } catch (error) {
      await _writeCachedReminders(userId, reminders);
      debugPrint('[SupabaseService] Failed to sync reminder delete: $error');
      rethrow;
    }
  }

  static Future<List<ReminderItem>> getReminders() async {
    final userId = _requireUserId();
    final cached = await _readCachedReminders(userId);

    try {
      final rows = await client
          .from('reminders')
          .select()
          .eq('user_id', userId)
          .order('scheduled_at', ascending: true);
      final remote = rows
          .map<ReminderItem>((row) => ReminderItem.fromMap(row))
          .toList(growable: false);
      final merged = _mergeReminders(remote, cached);
      await _writeCachedReminders(userId, merged);
      return merged;
    } catch (error) {
      debugPrint('[SupabaseService] Falling back to cached reminders: $error');
      return cached;
    }
  }

  static Future<List<ReminderItem>> getPendingReminders() async {
    final reminders = await getReminders();
    return reminders
        .where((reminder) => !reminder.isTriggered)
        .toList(growable: false);
  }

  static Stream<List<ReminderItem>> watchReminders() async* {
    if (!isLoggedIn) {
      yield const <ReminderItem>[];
      return;
    }

    final userId = _requireUserId();
    yield await getReminders();

    yield* client
        .from('reminders')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .asyncMap((rows) async {
          final remote = rows
              .map<ReminderItem>((row) => ReminderItem.fromMap(row))
              .toList(growable: false);
          final cached = await _readCachedReminders(userId);
          final merged = _mergeReminders(remote, cached);
          await _writeCachedReminders(userId, merged);
          return merged;
        });
  }

  static Future<void> _cacheConversation(ChatConversation conversation) async {
    final conversations = await _readCachedConversations(conversation.userId);
    final index =
        conversations.indexWhere((item) => item.id == conversation.id);
    if (index >= 0) {
      conversations[index] = conversation;
    } else {
      conversations.add(conversation);
    }
    await _writeCachedConversations(
      conversation.userId,
      _sortConversations(conversations),
    );
  }

  static Future<void> _cacheMessage(ChatConversationMessage message) async {
    final messages =
        await _readCachedMessages(message.userId, message.sessionId);
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      messages[index] = message;
    } else {
      messages.add(message);
    }
    await _writeCachedMessages(
      message.userId,
      message.sessionId,
      _sortMessages(messages),
    );

    final conversations = await _readCachedConversations(message.userId);
    final indexConversation = conversations
        .indexWhere((conversation) => conversation.id == message.sessionId);
    if (indexConversation >= 0) {
      final current = conversations[indexConversation];
      conversations[indexConversation] = ChatConversation.fromMap({
        'id': current.id,
        'user_id': current.userId,
        'title': current.rawTitle,
        'last_message_preview': message.message,
        'created_at': current.createdAt.toIso8601String(),
        'updated_at': message.createdAt.toIso8601String(),
      });
      await _writeCachedConversations(
        message.userId,
        _sortConversations(conversations),
      );
    }
  }

  static Future<void> _cacheReminder(ReminderItem reminder) async {
    final reminders = await _readCachedReminders(reminder.userId);
    final index = reminders.indexWhere((item) => item.id == reminder.id);
    if (index >= 0) {
      reminders[index] = reminder;
    } else {
      reminders.add(reminder);
    }
    await _writeCachedReminders(reminder.userId, _sortReminders(reminders));
  }

  static Future<List<ChatConversation>> _readCachedConversations(
    String userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationCacheKey(userId));
    if (raw == null || raw.isEmpty) {
      return <ChatConversation>[];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatConversation.fromMap)
          .toList(growable: true);
    } catch (_) {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(ChatConversation.fromMap)
          .toList(growable: true);
    }
  }

  static Future<void> _writeCachedConversations(
    String userId,
    List<ChatConversation> conversations,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _conversationCacheKey(userId),
      jsonEncode(
        conversations.map((conversation) => conversation.toMap()).toList(),
      ),
    );
  }

  static Future<List<ChatConversationMessage>> _readCachedMessages(
    String userId,
    String sessionId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_messageCacheKey(userId, sessionId));
    if (raw == null || raw.isEmpty) {
      return <ChatConversationMessage>[];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatConversationMessage.fromMap)
          .toList(growable: true);
    } catch (_) {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(ChatConversationMessage.fromMap)
          .toList(growable: true);
    }
  }

  static Future<void> _writeCachedMessages(
    String userId,
    String sessionId,
    List<ChatConversationMessage> messages,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _messageCacheKey(userId, sessionId),
      jsonEncode(messages.map((message) => message.toMap()).toList()),
    );
  }

  static Future<void> _removeCachedMessages(
    String userId,
    String sessionId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messageCacheKey(userId, sessionId));
  }

  static Future<List<ReminderItem>> _readCachedReminders(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reminderCacheKey(userId));
    if (raw == null || raw.isEmpty) {
      return <ReminderItem>[];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ReminderItem.fromMap)
          .toList(growable: true);
    } catch (_) {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(ReminderItem.fromMap)
          .toList(growable: true);
    }
  }

  static Future<void> _writeCachedReminders(
    String userId,
    List<ReminderItem> reminders,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _reminderCacheKey(userId),
      jsonEncode(reminders.map((reminder) => reminder.toMap()).toList()),
    );
  }

  static List<ChatConversation> _mergeConversations(
    List<ChatConversation> primary,
    List<ChatConversation> secondary,
  ) {
    final merged = <String, ChatConversation>{};
    for (final conversation in [...secondary, ...primary]) {
      final existing = merged[conversation.id];
      if (existing == null ||
          conversation.updatedAt.isAfter(existing.updatedAt)) {
        merged[conversation.id] = conversation;
      }
    }
    return _sortConversations(merged.values.toList(growable: false));
  }

  static List<ChatConversationMessage> _mergeMessages(
    List<ChatConversationMessage> primary,
    List<ChatConversationMessage> secondary,
  ) {
    final merged = <String, ChatConversationMessage>{};
    for (final message in [...secondary, ...primary]) {
      final existing = merged[message.id];
      if (existing == null || message.createdAt.isAfter(existing.createdAt)) {
        merged[message.id] = message;
      }
    }
    return _sortMessages(merged.values.toList(growable: false));
  }

  static List<ReminderItem> _mergeReminders(
    List<ReminderItem> primary,
    List<ReminderItem> secondary,
  ) {
    final merged = <String, ReminderItem>{};
    for (final reminder in [...secondary, ...primary]) {
      final existing = merged[reminder.id];
      if (existing == null || reminder.updatedAt.isAfter(existing.updatedAt)) {
        merged[reminder.id] = reminder;
      }
    }
    return _sortReminders(merged.values.toList(growable: false));
  }

  static List<ChatConversation> _sortConversations(
    List<ChatConversation> conversations,
  ) {
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  static List<ChatConversationMessage> _sortMessages(
    List<ChatConversationMessage> messages,
  ) {
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  static List<ReminderItem> _sortReminders(List<ReminderItem> reminders) {
    reminders.sort((a, b) {
      if (a.isTriggered != b.isTriggered) {
        return a.isTriggered ? 1 : -1;
      }
      return a.scheduledAt.compareTo(b.scheduledAt);
    });
    return reminders;
  }

  static String _conversationCacheKey(String userId) =>
      'cached_chat_conversations_$userId';

  static String _messageCacheKey(String userId, String sessionId) =>
      'cached_chat_messages_${userId}_$sessionId';

  static String _reminderCacheKey(String userId) => 'cached_reminders_$userId';

  static String _requireUserId() {
    final userId = currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw StateError('Supabase user is not authenticated.');
    }
    return userId;
  }
}
