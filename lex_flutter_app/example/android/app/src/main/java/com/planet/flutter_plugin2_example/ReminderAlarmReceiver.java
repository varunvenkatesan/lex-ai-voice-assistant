package com.planet.flutter_plugin2_example;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;

import org.json.JSONObject;

public class ReminderAlarmReceiver extends BroadcastReceiver {
  private static final String CHANNEL_ID = "lex_reminder_fullscreen";
  private static final String CHANNEL_NAME = "LEX Reminder Alerts";

  @Override
  public void onReceive(Context context, Intent intent) {
    String reminderId = intent.getStringExtra(ReminderAlarmScheduler.EXTRA_REMINDER_ID);
    String reminderJson = intent.getStringExtra(ReminderAlarmScheduler.EXTRA_REMINDER_JSON);
    String route = intent.getStringExtra(ReminderAlarmScheduler.EXTRA_REMINDER_ROUTE);

    if (reminderId == null || reminderJson == null || route == null) {
      return;
    }

    createNotificationChannel(context);

    Intent overlayIntent = ReminderOverlayActivity.createIntent(context, route, reminderId, reminderJson);
    PendingIntent fullScreenIntent = PendingIntent.getActivity(
        context,
        Math.abs(reminderId.hashCode()),
        overlayIntent,
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
    );

    String title = "Reminder alert";
    String description = "Open Lex to view this reminder.";
    try {
      JSONObject json = new JSONObject(reminderJson);
      String reminderTitle = json.optString("title", "").trim();
      String reminderDetails = json.optString("details", "").trim();
      if (!reminderTitle.isEmpty()) {
        title = reminderTitle;
      }
      if (!reminderDetails.isEmpty()) {
        description = reminderDetails;
      }
    } catch (Exception ignored) {
    }

    NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle(title)
        .setContentText(description)
        .setPriority(NotificationCompat.PRIORITY_MAX)
        .setCategory(NotificationCompat.CATEGORY_ALARM)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setAutoCancel(true)
        .setOngoing(true)
        .setFullScreenIntent(fullScreenIntent, true)
        .setContentIntent(fullScreenIntent)
        .setStyle(new NotificationCompat.BigTextStyle().bigText(description));

    NotificationManager notificationManager =
        (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
    if (notificationManager != null) {
      notificationManager.notify(Math.abs(reminderId.hashCode()), builder.build());
    }

    // Launch the overlay activity directly for immediate popup display.
    // The theme (no dim, transparent) + manifest (taskAffinity="", singleInstance)
    // ensure this appears as a clean floating overlay without bringing the main app.
    try {
      context.startActivity(overlayIntent);
    } catch (Exception ignored) {
    }
  }

  public static void dismissReminderAlert(@NonNull Context context, @NonNull String reminderId) {
    NotificationManager notificationManager =
        (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
    if (notificationManager != null) {
      notificationManager.cancel(Math.abs(reminderId.hashCode()));
    }
  }

  private void createNotificationChannel(@NonNull Context context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return;
    }

    NotificationManager notificationManager =
        (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
    if (notificationManager == null) {
      return;
    }

    NotificationChannel channel = new NotificationChannel(
        CHANNEL_ID,
        CHANNEL_NAME,
        NotificationManager.IMPORTANCE_HIGH
    );
    channel.setDescription("Full-screen reminder alerts from Lex");
    channel.setLockscreenVisibility(NotificationCompat.VISIBILITY_PUBLIC);
    notificationManager.createNotificationChannel(channel);
  }
}
