import 'dart:io';
import 'dart:ui'; // PlatformDispatcher

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notification id and channel id. Top-level so both the instance and the
/// background isolate (which constructs a fresh plugin) agree on them.
const _kNotifId = 1;
const _kChannelId = 'workout_session';

// Rest-state blob keys (written on rest, read by the background +30s handler
// and by SessionManager's foreground reconciliation).
const restBlobName = 'rest.name';
const restBlobStartedAt = 'rest.started_at'; // iso8601
const restBlobStartMs = 'rest.start_ms'; // epoch millis of restStart
const restBlobTotal = 'rest.total'; // seconds

// Notification body strings keyed by locale. The notification is built with no
// BuildContext (and the +30s revert path runs in a background isolate), so
// AppLocalizations is unreachable — this standalone map fills that gap.
const _notifStrings = <String, Map<String, String>>{
  'en': {'rest': 'Rest', 'inProgress': 'Workout in progress'},
  'it': {'rest': 'Recupero', 'inProgress': 'Allenamento in corso'},
  'de': {'rest': 'Pause', 'inProgress': 'Training läuft'},
  'es': {'rest': 'Descanso', 'inProgress': 'Entrenamiento en curso'},
};

/// Resolves a notification string for the active locale WITHOUT a BuildContext
/// (works in the background isolate). Order: persisted override → platform
/// locale → en. [prefs] is the already-loaded SharedPreferences.
String notifString(SharedPreferences prefs, String key) {
  final code = prefs.getString('settings.locale') ??
      PlatformDispatcher.instance.locale.languageCode;
  final table = _notifStrings[code] ?? _notifStrings['en']!;
  return table[key] ?? _notifStrings['en']![key]!;
}

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

/// Builds the Android details for the ongoing notification. Shared by both the
/// instance and the background isolate. [countdown] chooses chronometer
/// direction (true = rest countdown, false = elapsed); [when] anchors the
/// chronometer (rest end for countdown, session start for elapsed);
/// [withAction] adds the "+30s" action chip (only on the live rest countdown).
AndroidNotificationDetails buildWorkoutAndroidDetails({
  required bool countdown,
  required DateTime when,
  required bool withAction,
}) {
  return AndroidNotificationDetails(
    _kChannelId,
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
    actions: withAction
        ? const <AndroidNotificationAction>[
            AndroidNotificationAction('add_30s', '+30s',
                showsUserInterface: false, cancelNotification: false),
          ]
        : null,
  );
}

/// Background-isolate handler for the +30s action when the app is killed.
/// Reads the rest blob, extends it by 30s, rewrites it, and reschedules both
/// the live countdown and the OS revert alarm — without the live controller.
///
/// Runs in a fresh isolate, so it must initialize the binding, timezones, and
/// a brand-new plugin instance before scheduling. Compiles on all platforms
/// (referenced by name in [WorkoutNotification.init]) but only fires on Android.
@pragma('vm:entry-point')
Future<void> workoutNotificationBackground(NotificationResponse resp) async {
  if (resp.actionId != 'add_30s') return;
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // refresh in case the isolate/engine is reused across taps
  final startMs = prefs.getInt(restBlobStartMs);
  final total = prefs.getInt(restBlobTotal);
  final name = prefs.getString(restBlobName);
  final startedAtIso = prefs.getString(restBlobStartedAt);
  if (startMs == null ||
      total == null ||
      name == null ||
      startedAtIso == null) {
    return;
  }
  final newTotal = total + 30;
  await prefs.setInt(restBlobTotal, newTotal);
  final restStart = DateTime.fromMillisecondsSinceEpoch(startMs);
  final startedAt = DateTime.parse(startedAtIso);
  final end = restStart.add(Duration(seconds: newTotal));

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await plugin.show(
    id: _kNotifId,
    title: name,
    body: notifString(prefs, 'rest'),
    notificationDetails: NotificationDetails(
      android: buildWorkoutAndroidDetails(
          countdown: true, when: end, withAction: true),
    ),
  );
  if (end.isAfter(DateTime.now())) {
    await plugin.zonedSchedule(
      id: _kNotifId,
      title: name,
      body: notifString(prefs, 'inProgress'),
      scheduledDate: tz.TZDateTime.from(end, tz.UTC),
      notificationDetails: NotificationDetails(
        android: buildWorkoutAndroidDetails(
            countdown: false, when: startedAt, withAction: false),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}

/// Thin Android-only wrapper around flutter_local_notifications. All methods
/// are no-ops off-Android (Linux dev builds never initialize the plugin).
class WorkoutNotification {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;
  ({String title, bool countdown, DateTime when})? _lastShown;
  DateTime? _lastScheduledEnd;

  Future<void> init({void Function()? onTap, void Function()? onAdd30}) async {
    if (!Platform.isAndroid) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.actionId == 'add_30s') {
          onAdd30?.call();
        } else {
          onTap?.call();
        }
      },
      onDidReceiveBackgroundNotificationResponse: workoutNotificationBackground,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _kChannelId,
          'Workout session',
          importance: Importance.low,
          playSound: false,
        ));
    tzdata.initializeTimeZones();
    _ready = true;
  }

  /// Builds the Android details for the ongoing notification, delegating to the
  /// top-level [buildWorkoutAndroidDetails] shared with the background isolate.
  AndroidNotificationDetails _androidDetails({
    required bool countdown,
    required DateTime when,
    bool withAction = false,
  }) =>
      buildWorkoutAndroidDetails(
          countdown: countdown, when: when, withAction: withAction);

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
    // Persist/clear the rest blob (read by the background +30s handler and the
    // foreground reconciliation). The blob mirrors the live rest state.
    final prefs = await SharedPreferences.getInstance();
    if (restStart != null) {
      await prefs.setString(restBlobName, name);
      await prefs.setString(restBlobStartedAt, startedAt.toIso8601String());
      await prefs.setInt(restBlobStartMs, restStart.millisecondsSinceEpoch);
      await prefs.setInt(restBlobTotal, restTotal);
    } else {
      await prefs.remove(restBlobName);
      await prefs.remove(restBlobStartedAt);
      await prefs.remove(restBlobStartMs);
      await prefs.remove(restBlobTotal);
    }
    // The "+30s" action chip belongs only on the live rest countdown
    // (p.countdown true). Elapsed mode and the scheduled revert omit it.
    await _plugin.show(
      id: _kNotifId,
      title: p.title,
      body: notifString(prefs, p.countdown ? 'rest' : 'inProgress'),
      notificationDetails: NotificationDetails(
        android:
            _androidDetails(countdown: p.countdown, when: p.when, withAction: p.countdown),
      ),
    );
    // Schedule the OS alarm that reverts the countdown back to elapsed mode at
    // rest end — Dart timers are suspended while backgrounded, so without this
    // the chronometer counts into negatives. The scheduled notification reuses
    // id=_kNotifId, so the OS REPLACES the live countdown at restEnd.
    // Re-scheduling id=_kNotifId replaces any prior alarm.
    final end = restStart == null ? null : restRevertAt(restStart, restTotal);
    if (end != null && end.isAfter(DateTime.now())) {
      if (_lastScheduledEnd != end) {
        _lastScheduledEnd = end;
        await _plugin.zonedSchedule(
          id: _kNotifId,
          title: name,
          body: notifString(prefs, 'inProgress'),
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(restBlobName);
    await prefs.remove(restBlobStartedAt);
    await prefs.remove(restBlobStartMs);
    await prefs.remove(restBlobTotal);
    await _plugin.cancel(id: _kNotifId); // cancels the shown notification AND the pending alarm
  }
}
