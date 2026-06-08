import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Pure payload mapping for the ongoing workout notification (testable, no
/// plugin types). Elapsed mode: `when` = session start, Android chronometer
/// counts up. Rest mode: `when` = rest END time, chronometer counts down.
({String title, String body, bool countdown, DateTime when})
    notificationPayloadFor({
  required String sessionName,
  required DateTime startedAt,
  DateTime? restStart,
  int restTotal = 0,
  required DateTime now,
}) {
  if (restStart != null) {
    final end = restStart.add(Duration(seconds: restTotal));
    if (end.isAfter(now)) {
      return (title: sessionName, body: 'Rest', countdown: true, when: end);
    }
  }
  return (
    title: sessionName,
    body: 'Workout in progress',
    countdown: false,
    when: startedAt,
  );
}

/// Absolute instant the rest countdown ends (used to schedule the OS-alarm
/// revert back to elapsed mode).
DateTime restRevertAt(DateTime restStart, int restTotal) =>
    restStart.add(Duration(seconds: restTotal));

/// Thin Android-only wrapper around flutter_local_notifications. All methods
/// are no-ops off-Android (Linux dev builds never initialize the plugin).
class WorkoutNotification {
  static const _id = 1;
  static const _channelId = 'workout_session';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;
  ({String title, bool countdown, DateTime when})? _lastShown;
  DateTime? _lastScheduledEnd;

  Future<void> init({void Function()? onTap}) async {
    if (!Platform.isAndroid) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) => onTap?.call(),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          'Workout session',
          importance: Importance.low,
          playSound: false,
        ));
    tzdata.initializeTimeZones();
    _ready = true;
  }

  /// Builds the Android details for the ongoing notification. [countdown]
  /// chooses chronometer direction (true = rest countdown, false = elapsed);
  /// [when] anchors the chronometer (rest end for countdown, session start for
  /// elapsed).
  AndroidNotificationDetails _androidDetails({
    required bool countdown,
    required DateTime when,
  }) {
    return AndroidNotificationDetails(
      _channelId,
      'Workout session',
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: true,
      usesChronometer: true,
      chronometerCountDown: countdown,
      when: when.millisecondsSinceEpoch,
      category: AndroidNotificationCategory.stopwatch,
    );
  }

  Future<void> showFor({
    required String name,
    required DateTime startedAt,
    DateTime? restStart,
    int restTotal = 0,
  }) async {
    if (!_ready) return;
    if (!_permissionAsked) {
      _permissionAsked = true;
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission(); // result ignored — degrades silently
    }
    final p = notificationPayloadFor(
      sessionName: name,
      startedAt: startedAt,
      restStart: restStart,
      restTotal: restTotal,
      now: DateTime.now(),
    );
    final key = (title: p.title, countdown: p.countdown, when: p.when);
    if (key == _lastShown) return; // unchanged → skip the re-show
    _lastShown = key;
    await _plugin.show(
      id: _id,
      title: p.title,
      body: p.body,
      notificationDetails: NotificationDetails(
        android: _androidDetails(countdown: p.countdown, when: p.when),
      ),
    );
    // Schedule the OS alarm that reverts the countdown back to elapsed mode at
    // rest end — Dart timers are suspended while backgrounded, so without this
    // the chronometer counts into negatives. The scheduled notification reuses
    // id=_id, so the OS REPLACES the live countdown at restEnd. Re-scheduling
    // id=_id replaces any prior alarm.
    final end = restStart == null ? null : restRevertAt(restStart, restTotal);
    if (end != null && end.isAfter(DateTime.now())) {
      if (_lastScheduledEnd != end) {
        _lastScheduledEnd = end;
        await _plugin.zonedSchedule(
          id: _id,
          title: name,
          body: 'Workout in progress',
          scheduledDate: tz.TZDateTime.from(end, tz.UTC),
          notificationDetails: NotificationDetails(
            android: _androidDetails(countdown: false, when: startedAt),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }
  }

  Future<void> cancel() async {
    if (!_ready) return;
    _lastShown = null;
    _lastScheduledEnd = null;
    await _plugin.cancel(id: _id); // cancels the shown notification AND the pending alarm
  }
}
