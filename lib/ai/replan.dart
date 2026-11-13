/// Working a plan out again from where it stands today: what's left is laid
/// out afresh from now, at the hours the person can give, to see whether it
/// still fits the deadline, and what would have to give if it doesn't.
library;

import '../model/plan.dart';
import 'schedule.dart';

/// A step whose dates change.
class StepMove {
  const StepMove(this.step, this.start, this.due, {this.hours});

  final PlanStep step;
  final DateTime start;
  final DateTime due;

  /// Its new estimate, when that changes too.
  final double? hours;

  /// Days later than before; negative when it comes forward.
  int get days => due.difference(_day(step.due)).inDays;
}

/// A plan laid out again from today.
class Replan {
  const Replan({
    required this.schedule,
    required this.moves,
    required this.dropped,
    required this.overdue,
    required this.left,
  });

  final Schedule schedule;

  /// Steps this person may change whose dates or hours change, soonest first.
  final List<StepMove> moves;

  /// Steps left out to make it fit.
  final List<PlanStep> dropped;

  /// How many unfinished steps were already past their date.
  final int overdue;

  /// How many steps are still to do.
  final int left;

  DateTime get finish => schedule.finish;
  bool get fits => schedule.fitsDeadline;

  /// Days past the deadline; zero when it fits or there's none.
  int get daysOver {
    final d = schedule.deadline;
    if (d == null || fits) return 0;
    return finish.difference(d).inDays;
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// What's left of a step: a started one with a checklist counts only what
/// isn't ticked yet.
double hoursLeft(PlanStep s, {double? hours}) {
  final all = hours ?? s.estimateHours;
  if (s.status != StepStatus.doing || s.checklist.isEmpty) return all;
  final open = s.checklist.where((c) => !c.done).length;
  // Never nothing: a started step still has its last stretch.
  final part = open / s.checklist.length;
  return all * (part < 0.15 ? 0.15 : part);
}

/// Lays the unfinished steps out again from [today]. Their order stays as it
/// is: phase by phase, then by date. [drop] leaves steps out; [hours] gives
/// some a new estimate. Only steps [canChange] allows are reported as moves.
Replan replan(
  Plan plan, {
  required DateTime today,
  double? hoursPerWeek,
  DateTime? deadline,
  Set<String> drop = const {},
  Map<String, double> hours = const {},
  bool Function(PlanStep step)? canChange,
}) {
  final phaseAt = {
    for (var i = 0; i < plan.phases.length; i++) plan.phases[i].id: i,
  };
  final ordered = plan.steps.values.where((s) => !drop.contains(s.id)).toList()
    ..sort((a, b) {
      final byPhase = (phaseAt[a.phaseId] ?? 0).compareTo(
        phaseAt[b.phaseId] ?? 0,
      );
      if (byPhase != 0) return byPhase;
      // What's under way goes on before what hasn't started.
      final byState = (a.status == StepStatus.doing ? 0 : 1).compareTo(
        b.status == StepStatus.doing ? 0 : 1,
      );
      if (byState != 0) return byState;
      final byDue = a.due.compareTo(b.due);
      return byDue != 0 ? byDue : a.order.compareTo(b.order);
    });
  bool finished(PlanStep s) => s.status == StepStatus.done;
  final schedule = scheduleItems(
    [
      for (final (i, s) in ordered.indexed)
        ScheduleItem(
          key: s.id,
          hours: hoursLeft(s, hours: hours[s.id]),
          // A step that waited for one now left out waits for nothing.
          needs: [
            for (final n in s.dependsOn)
              if (!drop.contains(n)) n,
          ],
          // A shared point takes no one person's time.
          owner: s.shared ? 'shared:${s.id}' : s.ownerId,
          done: finished(s),
          rank: i.toDouble(),
        ),
    ],
    today: today,
    hoursPerWeek: hoursPerWeek,
    deadline: deadline,
  );
  final now = _day(today);
  final moves = <StepMove>[
    for (final s in ordered)
      if (!finished(s) && (canChange?.call(s) ?? true))
        if (schedule.dates[s.id] case final d?)
          if (_day(d.start) != _day(s.start) ||
              _day(d.due) != _day(s.due) ||
              (hours[s.id] != null && hours[s.id] != s.estimateHours))
            StepMove(s, d.start, d.due, hours: hours[s.id]),
  ]..sort((a, b) => a.due.compareTo(b.due));
  return Replan(
    schedule: schedule,
    moves: moves,
    dropped: [
      for (final s in plan.steps.values)
        if (drop.contains(s.id)) s,
    ],
    overdue: plan.steps.values
        .where((s) => !finished(s) && _day(s.due).isBefore(now))
        .length,
    left: ordered.where((s) => !finished(s)).length,
  );
}

/// The fewest hours a week, to the nearest half, at which the plan fits its
/// deadline. Null when there's no deadline, it has passed, or even [most]
/// hours a week isn't enough.
double? hoursToFit(
  Plan plan, {
  required DateTime today,
  required DateTime? deadline,
  Set<String> drop = const {},
  Map<String, double> hours = const {},
  double most = 70,
}) {
  if (deadline == null || !_day(deadline).isAfter(_day(today))) return null;
  bool fits(double pace) => replan(
    plan,
    today: today,
    hoursPerWeek: pace,
    deadline: deadline,
    drop: drop,
    hours: hours,
  ).fits;
  if (!fits(most)) return null;
  var low = 0.5;
  var high = most;
  if (fits(low)) return low;
  // Fitting only gets easier with more hours, so halve the gap.
  while (high - low > 0.5) {
    final mid = (low + high) / 2;
    if (fits(mid)) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return (high * 2).ceil() / 2;
}
