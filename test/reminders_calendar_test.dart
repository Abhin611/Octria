import 'package:flutter_test/flutter_test.dart';
import 'package:octria/data/local_backend.dart';
import 'package:octria/data/models.dart';
import 'package:octria/model/calendar.dart';
import 'package:octria/model/plan.dart';
import 'package:octria/model/reminders.dart';
import 'package:octria/screens/calendar_sheet.dart';
import 'package:octria/screens/practice_points.dart';

PlanStep _step(
  String id,
  DateTime due, {
  String owner = 'me',
  StepStatus status = StepStatus.todo,
  String title = '',
  String description = '',
  StepKind kind = StepKind.work,
  List<String> participants = const [],
  List<String> doneBy = const [],
}) => PlanStep(
  id: id,
  phaseId: 'p1',
  ownerId: owner,
  title: title.isEmpty ? 'Step $id' : title,
  estimateHours: 2,
  start: due.subtract(const Duration(days: 2)),
  due: due,
  description: description,
  status: status,
  kind: kind,
  participants: participants,
  doneBy: doneBy,
);

void main() {
  group('reminders', () {
    final now = DateTime(2026, 11, 11, 9);

    test('a step gets the day before, the day, and the day after', () {
      final r = remindersFor(
        [(_step('a', DateTime(2026, 11, 20)), 'Physics')],
        now: now,
        hour: 8,
      );
      expect(r.map((x) => x.at), [
        DateTime(2026, 11, 19, 8),
        DateTime(2026, 11, 20, 8),
        DateTime(2026, 11, 21, 8),
      ]);
      expect(r[0].title, 'Due tomorrow: Step a');
      expect(r[1].title, 'Due today: Step a');
      expect(r[2].title, 'Overdue: Step a');
      expect(r[1].body, contains('Physics'));
    });

    test('moments already past are left out', () {
      // Due today, and 8 am has gone: only tomorrow's "overdue" is ahead.
      final r = remindersFor(
        [(_step('a', DateTime(2026, 11, 11)), '')],
        now: now,
        hour: 8,
      );
      expect(r, hasLength(1));
      expect(r.single.title, startsWith('Overdue'));
      // With a later hour, today's is still ahead.
      final later = remindersFor(
        [(_step('a', DateTime(2026, 11, 11)), '')],
        now: now,
        hour: 18,
      );
      expect(later.map((x) => x.title.split(':').first), [
        'Due today',
        'Overdue',
      ]);
    });

    test('soonest first, and never more than the limit', () {
      final steps = [
        for (var i = 0; i < 30; i++)
          (_step('s$i', DateTime(2026, 12, 30 - i)), ''),
      ];
      final r = remindersFor(steps, now: now, limit: 40);
      expect(r, hasLength(40));
      for (var i = 1; i < r.length; i++) {
        expect(r[i].at.isBefore(r[i - 1].at), isFalse);
      }
    });

    test('ids are steady and differ by step and kind', () {
      expect(reminderId('abc', 1), reminderId('abc', 1));
      expect(reminderId('abc', 1), isNot(reminderId('abc', 2)));
      expect(reminderId('abc', 1), isNot(reminderId('abd', 1)));
      expect(reminderId('a' * 200, 2), lessThan(1 << 31));
    });

    test('the summary sorts steps into overdue, today and tomorrow', () {
      final s = DueSummary([
        (_step('late', DateTime(2026, 11, 9)), ''),
        (_step('now', DateTime(2026, 11, 11, 23)), ''),
        (_step('next', DateTime(2026, 11, 12)), ''),
        (_step('far', DateTime(2026, 11, 30)), ''),
      ], now);
      expect(s.overdue.single.id, 'late');
      expect(s.today.single.id, 'now');
      expect(s.tomorrow.single.id, 'next');
      expect(s.headline, '1 due today, 1 overdue, 1 due tomorrow');
      expect(DueSummary(const [], now).nothing, isTrue);
    });
  });

  group('calendar', () {
    test('a file holds one all-day event per step', () {
      final ics = icsFor([
        eventForStep(
          _step('a', DateTime(2026, 11, 20), title: 'Revise; waves, optics'),
          room: 'Physics',
          phase: 'Basics',
        ),
        eventForStep(_step('b', DateTime(2026, 12, 31))),
      ], now: DateTime.utc(2026, 11, 11, 4, 5, 6));
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect('BEGIN:VEVENT'.allMatches(ics), hasLength(2));
      expect(ics, contains('DTSTART;VALUE=DATE:20261120'));
      expect(ics, contains('DTEND;VALUE=DATE:20261121'));
      // The last day of the year ends on the first of the next.
      expect(ics, contains('DTEND;VALUE=DATE:20270101'));
      expect(ics, contains('DTSTAMP:20261111T040506Z'));
      expect(ics, contains('UID:a@octria.app'));
      // Commas and semicolons would otherwise split the text.
      expect(ics, contains(r'SUMMARY:Revise\; waves\, optics (Physics)'));
      expect(ics, contains(r'Classroom: Physics\nPhase: Basics'));
    });

    test('long lines are folded, and unfold to what went in', () {
      final long = 'word ' * 60;
      final ics = icsFor([
        CalEvent(id: 'x', title: 'T', day: DateTime(2026, 1, 1), details: long),
      ], now: DateTime.utc(2026));
      for (final line in ics.split('\r\n')) {
        expect(line.length, lessThanOrEqualTo(75));
      }
      expect(ics.replaceAll('\r\n ', ''), contains('DESCRIPTION:$long'));
    });

    test('only unfinished steps, and only your own or your part', () {
      final steps = [
        _step('mine', DateTime(2026, 11, 20)),
        _step('done', DateTime(2026, 11, 18), status: StepStatus.done),
        _step('theirs', DateTime(2026, 11, 19), owner: 'you'),
        _step(
          'test',
          DateTime(2026, 11, 17),
          owner: 'you',
          kind: StepKind.test,
          participants: ['me', 'you'],
        ),
        _step(
          'ticked',
          DateTime(2026, 11, 16),
          owner: 'you',
          kind: StepKind.test,
          participants: ['me', 'you'],
          doneBy: ['me'],
        ),
      ];
      expect(stepsToSchedule(steps, owner: 'me').map((s) => s.id), [
        'test',
        'mine',
      ]);
      expect(stepsToSchedule(steps).map((s) => s.id), [
        'ticked',
        'test',
        'theirs',
        'mine',
      ]);
    });

    test('the Google Calendar link carries the day and the title', () {
      final link = googleCalendarLink(
        eventForStep(_step('a', DateTime(2026, 11, 20), title: 'Read & note')),
      );
      expect(link.host, 'calendar.google.com');
      expect(link.queryParameters['action'], 'TEMPLATE');
      expect(link.queryParameters['text'], 'Read & note');
      expect(link.queryParameters['dates'], '20261120/20261121');
    });

    test('file names are plain', () {
      expect(calendarFileName('Physics: Unit 2!'), 'octria-physics-unit-2.ics');
      expect(calendarFileName('  '), 'octria-steps.ics');
    });
  });

  group('test results', () {
    test('are kept newest first and belong to one person', () async {
      final backend = LocalBackend();
      await backend.registerWithEmail('Asha', 'asha@example.com', 'secret12');
      await backend.saveResult(
        TestResult(
          id: '',
          classroomId: 'c1',
          label: 'Practice: Waves',
          targetId: 's1',
          right: 3,
          total: 6,
          missed: const ['What is a wavelength?'],
          at: DateTime(2026),
        ),
      );
      await backend.saveResult(
        TestResult(
          id: '',
          classroomId: 'c1',
          label: 'Mock test',
          targetId: 'p1',
          right: 9,
          total: 10,
          mock: true,
          at: DateTime(2026),
        ),
      );
      final mine = await backend.results().first;
      expect(mine.map((r) => r.label), ['Mock test', 'Practice: Waves']);
      expect(mine.last.percent, 50);
      expect(missedBefore(mine, 's1'), ['What is a wavelength?']);
      expect(missedBefore(mine, 'nothing'), isEmpty);

      final sum = ResultSummary(mine);
      expect((sum.count, sum.average, sum.best), (2, 70, 90));

      await backend.deleteResult(mine.first.id);
      expect(await backend.results().first, hasLength(1));

      await backend.signOut();
      await backend.registerWithEmail('Ben', 'ben@example.com', 'secret12');
      expect(await backend.results().first, isEmpty);
    });

    test('a result that doesn’t add up is refused', () async {
      final backend = LocalBackend();
      await backend.registerWithEmail('Asha', 'asha@example.com', 'secret12');
      expect(
        () => backend.saveResult(
          TestResult(
            id: '',
            classroomId: 'c1',
            label: 'x',
            right: 7,
            total: 5,
            at: DateTime(2026),
          ),
        ),
        throwsA(isA<BackendFailure>()),
      );
    });
  });
}
