import '../model/plan.dart';
import 'backend.dart';
import 'models.dart';
import 'plan_sync.dart';
import 'user_stats.dart';

/// One classroom as the dashboard shows it.
class RoomSummary {
  const RoomSummary({required this.state, required this.progress});

  final ClassroomState state;

  /// The share of its steps that are finished, from 0 to 1.
  final double progress;

  Classroom get classroom => state.classroom;
}

/// One of the person's own steps, and the classroom it's in.
class MyStep {
  const MyStep({
    required this.step,
    required this.standing,
    required this.room,
  });

  final PlanStep step;
  final Standing standing;
  final Classroom room;
}

/// One thing the person did, and the classroom it was in.
class MyAction {
  const MyAction({required this.entry, required this.room});

  final ActivityEntry entry;
  final Classroom room;
}

/// Everything the home tabs show, across all of someone's classrooms.
class Overview {
  const Overview({
    required this.rooms,
    required this.steps,
    required this.actions,
    required this.stats,
    required this.next,
  });

  final List<RoomSummary> rooms;

  /// Soonest due first.
  final List<MyStep> steps;

  /// Newest first.
  final List<MyAction> actions;
  final UserStats stats;

  /// The most pressing step they could work on now, in any classroom.
  final MyStep? next;

  int dueWithin(DateTime now, int days) {
    final limit = DateTime(now.year, now.month, now.day + days + 1);
    return steps
        .where(
          (s) => s.step.status != StepStatus.done && s.step.due.isBefore(limit),
        )
        .length;
  }
}

Future<Overview> loadOverview(Backend backend) async {
  final me = backend.currentUser?.uid ?? '';
  final now = DateTime.now();
  final classrooms = await backend.classrooms().first;
  final states = await Future.wait([
    for (final room in classrooms) backend.watchClassroom(room.id).first,
  ]);
  final logs = await Future.wait([
    for (final room in classrooms) backend.activity(room.id, limit: 500),
  ]);

  final rooms = <RoomSummary>[];
  final steps = <MyStep>[];
  MyStep? next;
  for (final state in states) {
    final plan = planFrom(state, me, now);
    rooms.add(
      RoomSummary(
        state: state,
        progress: state.steps.isEmpty
            ? 0
            : state.steps.where((s) => s.status == StepStatus.done).length /
                  state.steps.length,
      ),
    );
    for (final step in state.steps) {
      if (step.ownerId != me) continue;
      steps.add(
        MyStep(
          step: step,
          standing: plan.standing(plan.steps[step.id] ?? step),
          room: state.classroom,
        ),
      );
    }
    final candidate = plan.nextStepFor(me);
    if (candidate != null &&
        (next == null || candidate.due.isBefore(next.step.due))) {
      next = MyStep(
        step: candidate,
        standing: plan.standing(candidate),
        room: state.classroom,
      );
    }
  }
  steps.sort((a, b) => a.step.due.compareTo(b.step.due));

  final actions = [
    for (var i = 0; i < logs.length; i++)
      for (final entry in logs[i])
        if (entry.actorUid == me) MyAction(entry: entry, room: classrooms[i]),
  ]..sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));

  return Overview(
    rooms: rooms,
    steps: steps,
    actions: actions,
    next: next,
    stats: summariseUser(
      me: me,
      now: now,
      rooms: states,
      activity: [for (final log in logs) ...log],
    ),
  );
}
