package com.planet.flutter_plugin2_example;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;

import androidx.annotation.NonNull;

import org.json.JSONObject;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.Map;

public final class ReminderAlarmScheduler {
  public static final String ACTION_REMINDER_ALARM =
      "com.planet.flutter_plugin2_example.ACTION_REMINDER_ALARM";
  public static final String EXTRA_REMINDER_ID = "extra_reminder_id";
  public static final String EXTRA_REMINDER_JSON = "extra_reminder_json";
  public static final String EXTRA_REMINDER_ROUTE = "extra_reminder_route";

  private ReminderAlarmScheduler() {}

  public static void scheduleReminderAlarm(
      @NonNull Context context,
      @NonNull Map<String, Object> reminder
  ) throws Exception {
    String reminderId = String.valueOf(reminder.get("id"));
    String scheduledAt = String.valueOf(reminder.get("scheduled_at"));
    long triggerAtMillis = parseScheduledAtMillis(scheduledAt);
    String reminderJson = new JSONObject(reminder).toString();
    String route = "/reminder-overlay?payload=" + Uri.encode(reminderJson);

    Intent intent = new Intent(context, ReminderAlarmReceiver.class);
    intent.setAction(ACTION_REMINDER_ALARM);
    intent.putExtra(EXTRA_REMINDER_ID, reminderId);
    intent.putExtra(EXTRA_REMINDER_JSON, reminderJson);
    intent.putExtra(EXTRA_REMINDER_ROUTE, route);

    PendingIntent pendingIntent = PendingIntent.getBroadcast(
        context,
        requestCodeFor(reminderId),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
    );

    AlarmManager alarmManager =
        (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
    if (alarmManager == null) {
      throw new IllegalStateException("AlarmManager is unavailable.");
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      alarmManager.setExactAndAllowWhileIdle(
          AlarmManager.RTC_WAKEUP,
          triggerAtMillis,
          pendingIntent
      );
    } else {
      alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent);
    }
  }

  public static void cancelReminderAlarm(@NonNull Context context, @NonNull String reminderId) {
    Intent intent = new Intent(context, ReminderAlarmReceiver.class);
    intent.setAction(ACTION_REMINDER_ALARM);
    PendingIntent pendingIntent = PendingIntent.getBroadcast(
        context,
        requestCodeFor(reminderId),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
    );

    AlarmManager alarmManager =
        (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
    if (alarmManager != null) {
      alarmManager.cancel(pendingIntent);
    }
    pendingIntent.cancel();
  }

  private static int requestCodeFor(@NonNull String reminderId) {
    return Math.abs(reminderId.hashCode());
  }

  private static long parseScheduledAtMillis(@NonNull String scheduledAt) {
    try {
      return Instant.parse(scheduledAt).toEpochMilli();
    } catch (Exception ignored) {
    }

    try {
      return OffsetDateTime.parse(scheduledAt).toInstant().toEpochMilli();
    } catch (Exception ignored) {
    }

    return LocalDateTime.parse(scheduledAt)
        .atZone(ZoneId.systemDefault())
        .toInstant()
        .toEpochMilli();
  }
}
