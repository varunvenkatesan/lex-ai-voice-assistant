package com.planet.flutter_plugin2_example;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;

import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class ReminderAlarmBridge {
  public static final String CHANNEL_NAME = "lex.reminder_overlay";

  private ReminderAlarmBridge() {}

  public static void register(@NonNull FlutterEngine flutterEngine, @NonNull Activity activity) {
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL_NAME)
        .setMethodCallHandler((call, result) -> handle(call, result, activity));
  }

  private static void handle(
      @NonNull MethodCall call,
      @NonNull MethodChannel.Result result,
      @NonNull Activity activity
  ) {
    switch (call.method) {
      case "scheduleReminderAlarm":
        Map<String, Object> reminder = call.arguments();
        if (reminder == null) {
          result.error("invalid_args", "Reminder payload is required.", null);
          return;
        }
        try {
          ReminderAlarmScheduler.scheduleReminderAlarm(activity.getApplicationContext(), reminder);
          result.success(true);
        } catch (Exception error) {
          result.error("schedule_failed", error.getMessage(), null);
        }
        return;
      case "cancelReminderAlarm":
        String reminderId = call.argument("reminderId");
        if (reminderId == null || reminderId.trim().isEmpty()) {
          result.error("invalid_args", "reminderId is required.", null);
          return;
        }
        ReminderAlarmScheduler.cancelReminderAlarm(activity.getApplicationContext(), reminderId);
        result.success(true);
        return;
      case "dismissReminderAlert":
        String activeReminderId = call.argument("reminderId");
        if (activeReminderId == null || activeReminderId.trim().isEmpty()) {
          result.error("invalid_args", "reminderId is required.", null);
          return;
        }
        ReminderAlarmReceiver.dismissReminderAlert(
            activity.getApplicationContext(),
            activeReminderId
        );
        result.success(true);
        return;
      case "openMainApp":
        openMainApp(activity.getApplicationContext(), activity);
        result.success(true);
        return;
      case "canDrawOverlays":
        result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(activity));
        return;
      case "openOverlayPermissionSettings":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          Intent intent = new Intent(
              Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
              Uri.parse("package:" + activity.getPackageName())
          );
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
          activity.startActivity(intent);
        }
        result.success(true);
        return;
      default:
        result.notImplemented();
    }
  }

  private static void openMainApp(@NonNull Context context, @NonNull Activity activity) {
    Intent launchIntent = new Intent(context, MainActivity.class);
    launchIntent.addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK
            | Intent.FLAG_ACTIVITY_CLEAR_TOP
            | Intent.FLAG_ACTIVITY_SINGLE_TOP
    );
    context.startActivity(launchIntent);
    activity.finish();
  }
}
