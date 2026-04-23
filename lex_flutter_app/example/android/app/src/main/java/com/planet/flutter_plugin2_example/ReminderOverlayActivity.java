package com.planet.flutter_plugin2_example;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode;
import io.flutter.embedding.engine.FlutterEngine;

/**
 * Lightweight overlay activity that shows the reminder popup as a floating
 * card over whatever is currently on screen. It runs in its own task
 * (taskAffinity="") so the main Lex app is never brought to the foreground.
 */
public class ReminderOverlayActivity extends FlutterActivity {
  private static final String EXTRA_ROUTE = "extra_route";
  private static final String EXTRA_REMINDER_ID = "extra_reminder_id";
  private static final String EXTRA_REMINDER_JSON = "extra_reminder_json";

  public static Intent createIntent(
      @NonNull Context context,
      @NonNull String route,
      @NonNull String reminderId,
      @NonNull String reminderJson
  ) {
    Intent intent = new Intent(context, ReminderOverlayActivity.class);
    intent.putExtra(EXTRA_ROUTE, route);
    intent.putExtra(EXTRA_REMINDER_ID, reminderId);
    intent.putExtra(EXTRA_REMINDER_JSON, reminderJson);
    intent.addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK
            | Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
            | Intent.FLAG_ACTIVITY_NO_ANIMATION
    );
    return intent;
  }

  @Nullable
  @Override
  public String getInitialRoute() {
    String route = getIntent().getStringExtra(EXTRA_ROUTE);
    return route == null || route.trim().isEmpty() ? "/" : route;
  }

  @NonNull
  @Override
  public BackgroundMode getBackgroundMode() {
    return BackgroundMode.transparent;
  }

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    ReminderAlarmBridge.register(flutterEngine, this);
  }

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setShowWhenLocked(true);
    setTurnScreenOn(true);

    // Make the window truly floating / overlay-like:
    // - Not focusable prevents stealing focus from other apps
    // - Not touch modal allows touches outside the popup to pass through
    getWindow().addFlags(
        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
    );
  }

  @Override
  public void onBackPressed() {
    // Dismiss the overlay cleanly on back press
    finishAndRemoveTask();
  }
}
