/// Steps as calendar events: one file any calendar can open, or a link that
/// starts a new event in Google Calendar.
library;

import 'plan.dart';

/// A whole day in someone's calendar.
class CalEvent {
  const CalEvent({
    required this.id,
    required this.title,
    required this.day,
    this.details = '',
  });

  /// The same every time for the same step, so adding it again updates the
  /// event in calendars that go by it.
  final String id;
  final String title;
  final DateTime day;
  final String details;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';

String _hours(double h) {
  final whole = h == h.roundToDouble();
  final n = whole ? h.round().toString() : h.toStringAsFixed(1);
  return 'About $n ${h == 1 ? 'hour' : 'hours'}';
}

/// A step on the day it's due.
CalEvent eventForStep(PlanStep step, {String room = '', String phase = ''}) {
  return CalEvent(
    id: step.id,
    title: room.isEmpty ? step.title : '${step.title} ($room)',
    day: step.due,
    details: [
      if (room.isNotEmpty) 'Classroom: $room',
      if (phase.isNotEmpty) 'Phase: $phase',
      if (step.estimateHours > 0) _hours(step.estimateHours),
      if (step.description.trim().isNotEmpty) '\n${step.description.trim()}',
      '\nFrom Octria.',
    ].join('\n'),
  );
}

/// The steps worth putting in a calendar: unfinished ones, soonest first.
/// With [owner], only that person's, and shared ones they're part of.
List<PlanStep> stepsToSchedule(Iterable<PlanStep> steps, {String? owner}) =>
    steps.where((s) {
      if (owner == null) return s.status != StepStatus.done;
      if (s.shared) {
        return s.participants.contains(owner) && !s.doneBy.contains(owner);
      }
      return s.ownerId == owner && s.status != StepStatus.done;
    }).toList()..sort((a, b) => a.due.compareTo(b.due));

String _escape(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n');

/// Calendar files keep lines to 75 characters; longer ones carry on, on a
/// line that starts with a space.
String _fold(String line) {
  if (line.length <= 74) return line;
  final out = StringBuffer(line.substring(0, 74));
  for (var i = 74; i < line.length; i += 73) {
    final end = i + 73 > line.length ? line.length : i + 73;
    out.write('\r\n ${line.substring(i, end)}');
  }
  return out.toString();
}

/// An .ics file with every event, each lasting its whole day.
String icsFor(Iterable<CalEvent> events, {required DateTime now}) {
  final utc = now.toUtc();
  final stamp =
      '${_date(utc)}T${_two(utc.hour)}${_two(utc.minute)}${_two(utc.second)}Z';
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Octria//Plan//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    for (final e in events) ...[
      'BEGIN:VEVENT',
      'UID:${e.id}@octria.app',
      'DTSTAMP:$stamp',
      'DTSTART;VALUE=DATE:${_date(e.day)}',
      'DTEND;VALUE=DATE:${_date(DateTime(e.day.year, e.day.month, e.day.day + 1))}',
      'SUMMARY:${_escape(e.title)}',
      if (e.details.isNotEmpty) 'DESCRIPTION:${_escape(e.details)}',
      'TRANSP:TRANSPARENT',
      'END:VEVENT',
    ],
    'END:VCALENDAR',
  ];
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

/// Opens Google Calendar on a new event, filled in and ready to save.
Uri googleCalendarLink(
  CalEvent e,
) => Uri.https('calendar.google.com', '/calendar/render', {
  'action': 'TEMPLATE',
  'text': e.title,
  'dates':
      '${_date(e.day)}/${_date(DateTime(e.day.year, e.day.month, e.day.day + 1))}',
  if (e.details.isNotEmpty) 'details': e.details,
});
