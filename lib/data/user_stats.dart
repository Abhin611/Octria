import '../model/plan.dart';
import 'backend.dart';
import 'models.dart';

/// What the profile says about someone's work, across all their classrooms.
/// Worked out from the plans and activity logs, so nothing extra is stored.
class UserStats {
  const UserStats({
    required this.classrooms,
    required this.leading,
    required this.stepsTotal,
    required this.stepsDone,
    required this.stepsInProgress,
    required this.hoursDone,
    required this.actionsThisWeek,
    required this.weeks,
    required this.finishedPerWeek,
  });

  final int classrooms;

  /// How many of those they're the master of.
  final int leading;
  final int stepsTotal;
  final int stepsDone;
  final int stepsInProgress;

  /// Estimated hours of the steps they've finished, not tracked time.
  final double hoursDone;
  final int actionsThisWeek;

  /// The Monday starting each week, oldest first.
  final List<DateTime> weeks;

  /// Steps finished in each of [weeks].
  final List<int> finishedPerWeek;

  int get finishedThisWeek => finishedPerWeek.last;
  int get finishedLastWeek => finishedPerWeek[finishedPerWeek.length - 2];

  /// How this week's finished steps compare with last week's, in words short
  /// enough for a tile. A percentage means nothing with nothing to compare to.
  String get growth {
    final now = finishedThisWeek;
    final before = finishedLastWeek;
    if (before == 0) return now == 0 ? 'No change' : '+$now new';
    final change = ((now - before) / before * 100).round();
    return change > 0 ? '+$change%' : (change == 0 ? 'No change' : '$change%');
  }
}

DateTime _monday(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// The sums themselves, kept apart from loading so they can be tested.
UserStats summariseUser({
  required String me,
  required DateTime now,
  required List<ClassroomState> rooms,
  required List<ActivityEntry> activity,
  int weekCount = 8,
}) {
  final thisWeek = _monday(now);
  final weeks = [
    for (var i = weekCount - 1; i >= 0; i--)
      // Built by date, not by adding 7 days of hours, so clock changes are safe.
      DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * i),
  ];
  final finished = List.filled(weekCount, 0);
  var actions = 0;
  for (final e in activity) {
    final when = _monday(e.createdAt);
    final index = weeks.indexOf(when);
    if (e.actorUid == me && when == thisWeek) actions++;
    final mine =
        (e.kind == ActivityKind.stepFinished && e.actorUid == me) ||
        (e.kind == ActivityKind.stepApproved && e.affectsUid == me);
    if (mine && index >= 0) finished[index]++;
  }
  final steps = [
    for (final room in rooms)
      for (final s in room.steps)
        if (s.ownerId == me) s,
  ];
  final done = steps.where((s) => s.status == StepStatus.done);
  return UserStats(
    classrooms: rooms.length,
    leading: rooms.where((r) => r.classroom.masterUid == me).length,
    stepsTotal: steps.length,
    stepsDone: done.length,
    stepsInProgress: steps.where((s) => s.status == StepStatus.doing).length,
    hoursDone: done.fold(0, (sum, s) => sum + s.estimateHours),
    actionsThisWeek: actions,
    weeks: weeks,
    finishedPerWeek: finished,
  );
}

Future<UserStats> loadUserStats(Backend backend) async {
  final rooms = await backend.classrooms().first;
  final states = await Future.wait([
    for (final room in rooms) backend.watchClassroom(room.id).first,
  ]);
  final logs = await Future.wait([
    for (final room in rooms) backend.activity(room.id, limit: 500),
  ]);
  return summariseUser(
    me: backend.currentUser?.uid ?? '',
    now: DateTime.now(),
    rooms: states,
    activity: [for (final log in logs) ...log],
  );
}
