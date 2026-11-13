/// When to remind someone about their steps: the day before one is due, the
/// morning it's due, and the day after if it slipped.
library;

import 'plan.dart';

/// One nudge, at one moment.
class Reminder {
  const Reminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  /// The same for the same step and kind of nudge, so setting them again
  /// replaces rather than doubles.
  final int id;
  final DateTime at;
  final String title;
  final String body;
}

/// A step to be reminded of, and the classroom it's in.
typedef DueStep = (PlanStep step, String room);

/// A steady number from a step's id and which nudge it is. Dart's own hash
/// changes between runs.
int reminderId(String stepId, int kind) {
  var h = 17;
  for (final c in stepId.codeUnits) {
    h = (h * 31 + c) & 0x0FFFFFFF;
  }
  return h * 4 + kind;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The nudges still ahead of [now] for these unfinished steps, soonest first,
/// each at [hour] o'clock. No more than [limit]: phones cap how many an app
/// may hold.
List<Reminder> remindersFor(
  Iterable<DueStep> steps, {
  required DateTime now,
  int hour = 8,
  int limit = 40,
}) {
  final out = <Reminder>[];
  for (final (step, room) in steps) {
    final due = _day(step.due);
    DateTime at(int days) =>
        DateTime(due.year, due.month, due.day + days, hour);
    final where = room.isEmpty ? '' : ' in $room';
    for (final (kind, days, title, body) in [
      (0, -1, 'Due tomorrow: ${step.title}', 'One day left$where.'),
      (1, 0, 'Due today: ${step.title}', 'It’s due today$where.'),
      (2, 1, 'Overdue: ${step.title}', 'It was due yesterday$where.'),
    ]) {
      final when = at(days);
      if (!when.isAfter(now)) continue;
      out.add(
        Reminder(
          id: reminderId(step.id, kind),
          at: when,
          title: title,
          body: body,
        ),
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// What's pressing today, for the dashboard and for a browser, which can't
/// hold a reminder for later.
class DueSummary {
  DueSummary(Iterable<DueStep> steps, DateTime now)
    : overdue = [
        for (final (s, _) in steps)
          if (_day(s.due).isBefore(_day(now))) s,
      ],
      today = [
        for (final (s, _) in steps)
          if (_day(s.due) == _day(now)) s,
      ],
      tomorrow = [
        for (final (s, _) in steps)
          if (_day(s.due) == _day(DateTime(now.year, now.month, now.day + 1)))
            s,
      ];

  final List<PlanStep> overdue;
  final List<PlanStep> today;
  final List<PlanStep> tomorrow;

  bool get nothing => overdue.isEmpty && today.isEmpty && tomorrow.isEmpty;

  /// "2 due today, 1 overdue", or empty when nothing presses.
  String get headline => [
    if (today.isNotEmpty) '${today.length} due today',
    if (overdue.isNotEmpty) '${overdue.length} overdue',
    if (tomorrow.isNotEmpty) '${tomorrow.length} due tomorrow',
  ].join(', ');

  /// The first few by name.
  String get names {
    final all = [...overdue, ...today, ...tomorrow];
    final shown = all.take(3).map((s) => s.title).join(', ');
    return all.length > 3 ? '$shown and ${all.length - 3} more' : shown;
  }
}
