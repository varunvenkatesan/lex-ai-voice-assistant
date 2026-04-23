import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_plugin2/models/reminder_models.dart';
import 'package:flutter_plugin2/services/reminder_service.dart';

void main() {
  group('ReminderParser', () {
    test('keeps parsing direct chat reminder commands', () {
      final now = DateTime(2026, 3, 31, 10, 0);

      final draft = ReminderParser.parseVoiceCommand(
        'Remind me to drink water at 9 PM',
        now: now,
        source: ReminderItem.chatSource,
      );

      expect(draft, isNotNull);
      expect(draft!.title, 'drink water');
      expect(draft.source, ReminderItem.chatSource);
      expect(draft.scheduledAt, DateTime(2026, 3, 31, 21, 0));
    });

    test('parses assistant replies that include the reminder details', () {
      final now = DateTime(2026, 3, 31, 10, 0);

      final draft = ReminderParser.parseAssistantReply(
        "Sure, I'll remind you to drink water at 9 PM.",
        now: now,
        source: ReminderItem.talkSource,
      );

      expect(draft, isNotNull);
      expect(draft!.title, 'drink water');
      expect(draft.source, ReminderItem.talkSource);
      expect(draft.scheduledAt, DateTime(2026, 3, 31, 21, 0));
    });

    test('merges assistant-confirmed time with the queued voice intent', () {
      final now = DateTime(2026, 3, 31, 10, 0);
      final fallbackDraft = ReminderDraft(
        title: 'take medicine',
        details: 'Created from voice assistant',
        scheduledAt: DateTime(2026, 4, 1, 8, 0),
        source: ReminderItem.talkSource,
      );

      final draft = ReminderParser.parseAssistantReply(
        'Reminder set for 9:00 PM IST today.',
        now: now,
        source: ReminderItem.talkSource,
        fallbackDraft: fallbackDraft,
      );

      expect(draft, isNotNull);
      expect(draft!.title, 'take medicine');
      expect(draft.details, fallbackDraft.details);
      expect(draft.scheduledAt, DateTime(2026, 3, 31, 21, 0));
    });
  });
}
