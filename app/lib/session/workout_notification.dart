import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    _ready = true;
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
        android: AndroidNotificationDetails(
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
          chronometerCountDown: p.countdown,
          when: p.when.millisecondsSinceEpoch,
          category: AndroidNotificationCategory.stopwatch,
        ),
      ),
    );
  }

  Future<void> cancel() async {
    if (!_ready) return;
    _lastShown = null;
    await _plugin.cancel(id: _id);
  }
}
