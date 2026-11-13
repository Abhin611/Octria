import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/ai/replan.dart';
import 'package:octria/ai/sample_ai.dart';
import 'package:octria/graph/plan_changes.dart';
import 'package:octria/model/plan.dart';

final _today = DateTime(2026, 11, 12);

PlanStep _step(
  String id, {
  double hours = 6,
  String owner = 'me',
  String phase = 'p1',
  DateTime? due,
  StepStatus status = StepStatus.todo,
  List<String> needs = const [],
  List<ChecklistItem> checklist = const [],
  StepKind kind = StepKind.work,
}) => PlanStep(
  id: id,
  phaseId: phase,
  ownerId: owner,
  title: 'Step $id',
  estimateHours: hours,
  start: (due ?? _today).subtract(const Duration(days: 3)),
  due: due ?? _today,
  status: status,
  dependsOn: needs,
  checklist: checklist,
  kind: kind,
  participants: kind == StepKind.work ? const [] : const ['me', 'you'],
);

Plan _plan(List<PlanStep> steps) => Plan(
  title: 'Physics',
  members: const [
    Member(id: 'me', name: 'Mina'),
    Member(id: 'you', name: 'Amy'),
  ],
  phases: const [
    Phase(id: 'p1', title: 'Basics'),
    Phase(id: 'p2', title: 'Revision'),
  ],
  steps: steps,
  meId: 'me',
  today: _today,
);

void main() {
  group('re-planning', () {
    test('what’s left starts again from today, in the same order', () {
      // Two overdue steps and one to come, 6 hours each, 6 hours a week.
      final plan = _plan([
        _step('a', due: DateTime(2026, 11, 1)),
        _step('b', due: DateTime(2026, 11, 5), needs: ['a']),
        _step('c', due: DateTime(2026, 11, 20), needs: ['b']),
      ]);
      final r = replan(plan, today: _today, hoursPerWeek: 6);
      expect(r.overdue, 2);
      expect(r.left, 3);
      expect(r.schedule.dates['a']!.due, DateTime(2026, 11, 19));
      expect(r.schedule.dates['b']!.due, DateTime(2026, 11, 26));
      expect(r.schedule.dates['c']!.due, DateTime(2026, 12, 3));
      expect(r.finish, DateTime(2026, 12, 3));
      expect(r.moves.map((m) => m.step.id), ['a', 'b', 'c']);
      expect(r.moves.first.days, 18);
    });

    test('finished steps stay put and cost no time', () {
      final plan = _plan([
        _step('a', due: DateTime(2026, 11, 1), status: StepStatus.done),
        _step('b', due: DateTime(2026, 11, 5), needs: ['a']),
      ]);
      final r = replan(plan, today: _today, hoursPerWeek: 6);
      expect(r.left, 1);
      expect(r.overdue, 1);
      expect(r.schedule.dates.containsKey('a'), isFalse);
      expect(r.schedule.dates['b']!.due, DateTime(2026, 11, 19));
    });

    test('a started step counts only what its checklist has left', () {
      final half = _step(
        'a',
        hours: 8,
        status: StepStatus.doing,
        checklist: const [
          ChecklistItem(title: 'x', done: true),
          ChecklistItem(title: 'y'),
        ],
      );
      expect(hoursLeft(half), 4);
      expect(hoursLeft(_step('b', hours: 8)), 8);
      // All ticked but not marked done: its last stretch is still to do.
      final nearly = _step(
        'c',
        hours: 10,
        status: StepStatus.doing,
        checklist: const [ChecklistItem(title: 'x', done: true)],
      );
      expect(hoursLeft(nearly), closeTo(1.5, 0.001));
    });

    test('two people work side by side; a shared point costs no one time', () {
      final plan = _plan([
        _step('a', owner: 'me'),
        _step('b', owner: 'you'),
        _step('t', kind: StepKind.test, needs: ['a', 'b'], owner: 'me'),
        _step('c', owner: 'me', needs: ['t'], phase: 'p2'),
      ]);
      final r = replan(plan, today: _today, hoursPerWeek: 6);
      // Both first steps end the same day, not one after the other.
      expect(r.schedule.dates['a']!.due, r.schedule.dates['b']!.due);
      // Mina's next step waits for the test, not for her own time on it.
      expect(r.schedule.dates['c']!.start, r.schedule.dates['t']!.due);
    });

    test('it says whether the deadline still holds, and by how much', () {
      final plan = _plan([
        _step('a'),
        _step('b', needs: ['a']),
      ]);
      final late = replan(
        plan,
        today: _today,
        hoursPerWeek: 6,
        deadline: DateTime(2026, 11, 20),
      );
      expect(late.fits, isFalse);
      expect(late.daysOver, 6);
      final fine = replan(
        plan,
        today: _today,
        hoursPerWeek: 12,
        deadline: DateTime(2026, 11, 20),
      );
      expect(fine.fits, isTrue);
      expect(fine.daysOver, 0);
    });

    test('the hours that would make it fit are found', () {
      final plan = _plan([
        _step('a'),
        _step('b', needs: ['a']),
      ]);
      final need = hoursToFit(
        plan,
        today: _today,
        deadline: DateTime(2026, 11, 20),
      );
      expect(need, isNotNull);
      // 12 hours by the end of the 20th, nearly 9 days away: 9.5 a week.
      expect(need!, 9.5);
      expect(
        replan(
          plan,
          today: _today,
          hoursPerWeek: need,
          deadline: DateTime(2026, 11, 20),
        ).fits,
        isTrue,
      );
      // No deadline, or one already gone, has no answer.
      expect(hoursToFit(plan, today: _today, deadline: null), isNull);
      expect(
        hoursToFit(plan, today: _today, deadline: DateTime(2026, 11, 1)),
        isNull,
      );
    });

    test('leaving a step out frees what waited for it', () {
      final plan = _plan([
        _step('a'),
        _step('b', needs: ['a']),
        _step('c', needs: ['b']),
      ]);
      final r = replan(
        plan,
        today: _today,
        hoursPerWeek: 6,
        drop: {'b'},
        hours: {'c': 3},
      );
      expect(r.dropped.single.id, 'b');
      expect(r.left, 2);
      expect(r.schedule.dates.containsKey('b'), isFalse);
      // a takes a week, then c takes half a week.
      expect(
        r.schedule.dates['c']!.due.isBefore(DateTime(2026, 11, 24)),
        isTrue,
      );
      expect(r.moves.firstWhere((m) => m.step.id == 'c').hours, 3);
    });

    test('a member’s re-plan only reports their own steps', () {
      final plan = _plan([
        _step('a', owner: 'me', due: DateTime(2026, 11, 1)),
        _step('b', owner: 'you', due: DateTime(2026, 11, 1)),
      ]);
      final r = replan(
        plan,
        today: _today,
        hoursPerWeek: 6,
        canChange: (s) => s.ownerId == 'me',
      );
      expect(r.moves.map((m) => m.step.id), ['a']);
    });
  });

  group('Ofy’s advice', () {
    const brief = ReplanBrief(
      subject: 'Physics',
      daysOver: 6,
      hoursPerWeek: 6,
      steps: [
        ReplanStep(ref: 's1', title: 'Read', phase: 'Basics', hours: 6),
        ReplanStep(
          ref: 's2',
          title: 'Notes',
          phase: 'Basics',
          hours: 4,
          neededBy: 2,
        ),
        ReplanStep(
          ref: 's3',
          title: 'Mock test',
          phase: 'Basics',
          hours: 2,
          point: true,
        ),
        ReplanStep(
          ref: 's4',
          title: 'Extra reading',
          phase: 'Revision',
          hours: 3,
        ),
        ReplanStep(
          ref: 's5',
          title: 'Problems',
          phase: 'Revision',
          hours: 5,
          started: true,
        ),
      ],
    );

    test('keeps only changes that make sense', () {
      final advice = ReplanAdvice.fromJson({
        'note': 'Protected the mock test.',
        'changes': [
          {'step': 's1', 'change': 'shorten', 'hours': 3.7, 'why': 'Skim it.'},
          // Longer is not shorter.
          {'step': 's2', 'change': 'shorten', 'hours': 9, 'why': 'x'},
          // Others wait for it, so it can't be left out.
          {'step': 's2', 'change': 'drop', 'why': 'x'},
          // A shared point is never changed.
          {'step': 's3', 'change': 'shorten', 'hours': 1, 'why': 'x'},
          {'step': 's4', 'change': 'drop', 'why': 'Optional.'},
          // Already started: not dropped.
          {'step': 's5', 'change': 'drop', 'why': 'x'},
          // Not a step at all.
          {'step': 's99', 'change': 'drop', 'why': 'x'},
          // Twice the same step: the first stands.
          {'step': 's1', 'change': 'drop', 'why': 'x'},
          'nonsense',
        ],
      }, brief);
      expect(advice.note, 'Protected the mock test.');
      expect(advice.cuts.map((c) => (c.ref, c.hours, c.drops)), [
        ('s1', 3.5, false),
        ('s4', null, true),
      ]);
    });

    test('an empty or broken answer gives no changes', () {
      expect(ReplanAdvice.fromJson(const {}, brief).cuts, isEmpty);
      expect(
        ReplanAdvice.fromJson(const {'changes': 'none'}, brief).cuts,
        isEmpty,
      );
    });

    test(
      'the sample model trims the longest steps and never a point',
      () async {
        final advice = await SampleAi(delay: Duration.zero).advise(brief);
        expect(advice.cuts, isNotEmpty);
        expect(advice.cuts.any((c) => c.ref == 's3'), isFalse);
        for (final c in advice.cuts) {
          final before = brief.steps.firstWhere((s) => s.ref == c.ref).hours;
          expect(c.hours, lessThan(before));
        }
      },
    );
  });
  group('playing a re-plan back on the graph', () {
    StepChange moved(String id, int from, int to, {double? h0, double? h1}) =>
        StepChange(
          id: id,
          title: 'Step $id',
          fromDue: DateTime(2026, 11, from),
          toDue: DateTime(2026, 11, to),
          fromHours: h0,
          toHours: h1,
        );

    test('each step says what changed', () {
      expect(moved('a', 15, 18).label, '15 Nov → 18 Nov');
      expect(moved('a', 15, 18).days, 3);
      expect(moved('a', 20, 14).days, -6);
      expect(moved('a', 15, 15, h0: 6, h1: 4).label, '6 → 4 h');
      expect(
        moved('a', 15, 18, h0: 6, h1: 4.5).label,
        '15 Nov → 18 Nov · 6 → 4.5 h',
      );
      expect(moved('a', 15, 15, h0: 6, h1: 6).label, 'Re-planned');
      expect(
        const StepChange(id: 'x', title: 'Gone', dropped: true).label,
        'Left out',
      );
    });

    test('steps take their turn, one after another', () {
      final play = PlanChanges([
        moved('a', 15, 18),
        moved('b', 16, 19),
        moved('c', 17, 20),
      ]);
      // At the very start only the first has begun.
      expect(play.progress('a', 0), 0);
      expect(play.progress('b', 0), lessThan(0));
      expect(play.progress('c', 0), lessThan(0));
      // At the very end the last has just finished, the rest already had.
      expect(play.progress('c', 1), closeTo(1, 0.001));
      expect(play.progress('a', 1), greaterThan(1));
      // Later ones are always behind earlier ones.
      for (final t in [0.2, 0.5, 0.8]) {
        expect(play.progress('a', t), greaterThan(play.progress('b', t)));
        expect(play.progress('b', t), greaterThan(play.progress('c', t)));
      }
      expect(play.progress('nobody', 0.5), -1);
      expect(play.of('b')?.title, 'Step b');
      expect(play.of('nobody'), isNull);
    });

    test('a big re-plan doesn’t drag on', () {
      final one = PlanChanges([moved('a', 15, 18)]);
      expect(one.duration, PlanChanges.each);
      final many = PlanChanges([
        for (var i = 0; i < 60; i++) moved('s$i', 1, 2),
      ]);
      expect(many.duration.inMilliseconds, lessThan(6000));
      expect(PlanChanges(const []).duration, PlanChanges.each);
    });
  });
}
