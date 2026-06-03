/// Ongoing workout notification (Android). Fleshed out in the notification
/// task; this placeholder keeps SessionManager compilable.
class WorkoutNotification {
  Future<void> showFor({
    required String name,
    required DateTime startedAt,
    DateTime? restStart,
    int restTotal = 0,
  }) async {}

  Future<void> cancel() async {}
}
