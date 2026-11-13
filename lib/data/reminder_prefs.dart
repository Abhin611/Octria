/// Whether this device reminds its owner about due steps, and at what hour.
/// Kept on the device: a phone and a browser can differ.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../model/reminders.dart';
import '../platform/reminders.dart';
import 'overview.dart';
import '../model/plan.dart';

class ReminderPrefs {
  const ReminderPrefs({this.on = false, this.hour = 8});

  final bool on;

  /// The hour of the day, 0 to 23.
  final int hour;

  static const _onKey = 'reminders.on';
  static const _hourKey = 'reminders.hour';

  static Future<ReminderPrefs> load() async {
    try {
      final store = await SharedPreferences.getInstance();
      return ReminderPrefs(
        on: store.getBool(_onKey) ?? false,
        hour: (store.getInt(_hourKey) ?? 8).clamp(0, 23),
      );
    } on Object {
      return const ReminderPrefs();
    }
  }

  Future<void> save() async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setBool(_onKey, on);
      await store.setInt(_hourKey, hour);
    } on Object {
      // Not kept this time; it still holds until the app closes.
    }
  }
}

/// This person's unfinished steps, and the shared ones still waiting on
/// their part, each with its classroom.
List<DueStep> dueSteps(Overview o) => [
  for (final s in o.steps)
    if (s.step.status != StepStatus.done) (s.step, s.room.title),
  for (final s in o.parts) (s.step, s.room.title),
];

String? _lastSet;

/// Brings the device's reminders in line with the plan as it stands. Cheap to
/// call often: it does nothing when nothing changed.
Future<void> syncReminders(
  Overview o, {
  DateTime? now,
  bool force = false,
}) async {
  final prefs = await ReminderPrefs.load();
  if (!prefs.on) {
    if (_lastSet != null || force) {
      _lastSet = null;
      await clearReminders();
    }
    return;
  }
  final at = now ?? DateTime.now();
  final steps = dueSteps(o);
  final upcoming = remindersFor(steps, now: at, hour: prefs.hour);
  final today = DueSummary(steps, at);
  final mark = [
    prefs.hour,
    today.headline,
    for (final r in upcoming)
      '${r.id}@${r.at.millisecondsSinceEpoch}:${r.title}',
  ].join('|');
  if (mark == _lastSet && !force) return;
  _lastSet = mark;
  await setReminders(
    upcoming,
    todayTitle: today.overdue.isEmpty && today.today.isEmpty
        ? ''
        : 'Octria: ${today.headline}',
    todayBody: today.names,
  );
}
