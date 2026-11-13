/// Dates for a plan, worked out from hours and dependencies rather than guessed
/// by a model: each person works through their steps in order, a step starts
/// once what it needs is finished, and hours turn into days at the pace the
/// person can give each week.
library;

import 'dart:math' as math;

import 'ai.dart';

/// What happens when nobody says how much time they have each week.
const double kDefaultHoursPerWeek = 6;

class StepDates {
  const StepDates(this.start, this.due);

  final DateTime start;
  final DateTime due;
}

class Schedule {
  const Schedule({
    required this.dates,
    required this.finish,
    required this.hoursPerWeek,
    required this.assumedHours,
    this.deadline,
  });

  /// By step key.
  final Map<String, StepDates> dates;

  /// When the last step is due.
  final DateTime finish;
  final double hoursPerWeek;

  /// Whether [hoursPerWeek] is the default, because none was given.
  final bool assumedHours;
  final DateTime? deadline;

  bool get fitsDeadline => deadline == null || !finish.isAfter(deadline!);

  /// Weeks from the first start to the finish, rounded up.
  int weeksFrom(DateTime today) =>
      math.max(1, (finish.difference(today).inDays / 7).ceil());
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// One piece of work to lay out in time.
class ScheduleItem {
  const ScheduleItem({
    required this.key,
    required this.hours,
    this.needs = const [],
    this.owner = '',
    this.done = false,
    this.rank = 0,
  });

  final String key;
  final double hours;
  final List<String> needs;
  final String owner;

  /// Already finished: it gets no dates, and what needs it can start now.
  final bool done;

  /// Which comes first when two could go next: lower is earlier.
  final double rank;
}

/// Lays [plan] out in time. [ownerOf] says who does each step; steps of one
/// person happen one after another, steps of different people can overlap.
Schedule schedulePlan(
  DraftPlan plan, {
  required DateTime today,
  double? hoursPerWeek,
  DateTime? deadline,
  String Function(DraftStep step)? ownerOf,
}) {
  var i = 0;
  return scheduleItems(
    [
      for (final s in plan.steps)
        ScheduleItem(
          key: s.key,
          hours: s.hours,
          needs: s.needs,
          owner: ownerOf?.call(s) ?? '',
          rank: (i++).toDouble(),
        ),
    ],
    today: today,
    hoursPerWeek: hoursPerWeek,
    deadline: deadline,
  );
}

/// Lays any mix of steps out in time: what each needs comes first, each
/// person does one thing at a time, in [ScheduleItem.rank] order where there's
/// a choice, at [hoursPerWeek] each. Finished steps keep out of the way.
Schedule scheduleItems(
  List<ScheduleItem> items, {
  required DateTime today,
  double? hoursPerWeek,
  DateTime? deadline,
}) {
  final pace = (hoursPerWeek ?? 0) > 0 ? hoursPerWeek! : kDefaultHoursPerWeek;
  final start = _day(today);
  DateTime at(double hours) =>
      start.add(Duration(minutes: (hours / pace * 7 * 24 * 60).round()));

  final byKey = {for (final s in items) s.key: s};
  final finishedAt = <String, double>{};
  final freeAt = <String, double>{};
  final dates = <String, StepDates>{};
  var last = 0.0;

  // What each step waits for, among the steps here.
  final waiting = {
    for (final s in items)
      s.key: {
        for (final n in s.needs)
          if (byKey.containsKey(n) && n != s.key) n,
      },
  };
  final left = [...items]..sort((a, b) => a.rank.compareTo(b.rank));
  while (left.isNotEmpty) {
    // The first in order with nothing left to wait for. A loop, should there
    // be one, is broken by taking the first in order.
    final next = left.firstWhere(
      (s) => waiting[s.key]!.every(finishedAt.containsKey),
      orElse: () => left.first,
    );
    left.remove(next);
    if (next.done) {
      finishedAt[next.key] = 0;
      continue;
    }
    var begin = freeAt[next.owner] ?? 0;
    for (final need in waiting[next.key]!) {
      begin = math.max(begin, finishedAt[need] ?? 0);
    }
    final end = begin + next.hours;
    finishedAt[next.key] = end;
    freeAt[next.owner] = end;
    last = math.max(last, end);
    final due = _day(at(end));
    final from = _day(at(begin));
    dates[next.key] = StepDates(from, due.isBefore(from) ? from : due);
  }
  return Schedule(
    dates: dates,
    finish: dates.isEmpty ? start : _day(at(last)),
    hoursPerWeek: pace,
    assumedHours: (hoursPerWeek ?? 0) <= 0,
    deadline: deadline == null ? null : _day(deadline),
  );
}
