/// A set of changes to a plan, played back on the graph one step after
/// another: a re-plan shows each step that moved with its old and new date,
/// and each step that was left out fading away.
library;

import 'dart:ui';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _number(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// What happened to one step.
class StepChange {
  const StepChange({
    required this.id,
    required this.title,
    this.fromDue,
    this.toDue,
    this.fromHours,
    this.toHours,
    this.dropped = false,
    this.at,
  });

  final String id;
  final String title;
  final DateTime? fromDue;
  final DateTime? toDue;
  final double? fromHours;
  final double? toHours;

  /// Left out of the plan altogether.
  final bool dropped;

  /// Where a dropped step sat on the map, since it's no longer in the plan.
  final Offset? at;

  /// Days later than before; negative when it came forward.
  int get days {
    final a = fromDue;
    final b = toDue;
    if (a == null || b == null) return 0;
    return DateTime(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime(a.year, a.month, a.day)).inDays;
  }

  /// The short line shown above the step: "15 Nov → 18 Nov", "6 → 4 h", or
  /// "Left out".
  String get label {
    if (dropped) return 'Left out';
    final parts = [
      if (days != 0) '${_day(fromDue!)} → ${_day(toDue!)}',
      if (fromHours != null && toHours != null && fromHours != toHours)
        '${_number(fromHours!)} → ${_number(toHours!)} h',
    ];
    return parts.isEmpty ? 'Re-planned' : parts.join(' · ');
  }
}

/// Changes to play back, in the order they're shown.
class PlanChanges {
  PlanChanges(List<StepChange> changes)
    : changes = List.unmodifiable(changes),
      _index = {for (final (i, c) in changes.indexed) c.id: i};

  final List<StepChange> changes;
  final Map<String, int> _index;

  /// How long one step's own moment lasts.
  static const Duration each = Duration(milliseconds: 1900);

  /// The gap between one step starting and the next: shorter with more steps,
  /// so a big re-plan doesn't drag on.
  Duration get gap => Duration(
    milliseconds: changes.length <= 1
        ? 0
        : (2600 / (changes.length - 1)).clamp(60, 260).round(),
  );

  /// The whole playback, from the first step starting to the last finishing.
  Duration get duration =>
      each + gap * (changes.isEmpty ? 0 : changes.length - 1);

  StepChange? of(String id) {
    final i = _index[id];
    return i == null ? null : changes[i];
  }

  /// Where [id] is in its own moment, from 0 to 1, when the whole playback
  /// is at [t] (0 to 1). Below 0 it hasn't started; above 1 it has finished.
  double progress(String id, double t) {
    final i = _index[id];
    if (i == null) return -1;
    final total = duration.inMilliseconds;
    if (total == 0) return 1;
    final now = t * total;
    return (now - i * gap.inMilliseconds) / each.inMilliseconds;
  }
}
