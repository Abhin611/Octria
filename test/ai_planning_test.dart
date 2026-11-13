import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/ai/sample_ai.dart';
import 'package:octria/ai/schedule.dart';
import 'package:octria/data/local_backend.dart';
import 'package:octria/data/models.dart';
import 'package:octria/data/plan_sync.dart';
import 'package:octria/screens/plan_draft_sheet.dart';

DraftPlan _plan(List<(String, double, List<String>)> steps) => DraftPlan(
  phases: [
    DraftPhase(
      title: 'One',
      steps: [
        for (final (k, h, n) in steps)
          DraftStep(key: k, title: 'Step $k', hours: h, needs: n),
      ],
    ),
  ],
);

void main() {
  final monday = DateTime(2026, 11, 9);

  group('dates are worked out, not guessed', () {
    test('hours become days at the weekly pace, in order', () {
      final s = schedulePlan(
        _plan([
          ('a', 7, []),
          ('b', 7, ['a']),
        ]),
        today: monday,
        hoursPerWeek: 7,
      );
      // 7 hours at 7 a week is one week each.
      expect(s.dates['a']!.start, monday);
      expect(s.dates['a']!.due, DateTime(2026, 11, 16));
      expect(s.dates['b']!.start, DateTime(2026, 11, 16));
      expect(s.dates['b']!.due, DateTime(2026, 11, 23));
      expect(s.finish, DateTime(2026, 11, 23));
      expect(s.assumedHours, isFalse);
    });

    test('different people work at the same time; a need waits', () {
      final s = schedulePlan(
        _plan([
          ('a', 7, []),
          ('b', 7, []),
          ('c', 7, ['a', 'b']),
        ]),
        today: monday,
        hoursPerWeek: 7,
        ownerOf: (step) => step.key == 'b' ? 'amy' : 'me',
      );
      expect(s.dates['b']!.start, monday);
      expect(s.dates['c']!.start, DateTime(2026, 11, 16));
    });

    test('no hours given uses a default, and the deadline is checked', () {
      final s = schedulePlan(
        _plan([('a', 12, [])]),
        today: monday,
        deadline: DateTime(2026, 11, 12),
      );
      expect(s.hoursPerWeek, kDefaultHoursPerWeek);
      expect(s.assumedHours, isTrue);
      expect(s.fitsDeadline, isFalse);
    });
  });

  test('a model’s answer is kept sane', () {
    final plan = DraftPlan.fromJson({
      'summary': 'Short.',
      'phases': [
        {
          'title': '',
          'steps': [
            {
              'key': 'x',
              'title': 'First',
              'hours': 900,
              'needs': ['y'],
            },
            {
              'key': 'x',
              'title': 'Second',
              'hours': 0,
              'needs': ['x', 'nope'],
            },
            {'key': 'z', 'title': '  ', 'hours': 3},
          ],
        },
        {'title': 'Empty', 'steps': []},
      ],
    });
    expect(plan.phases, hasLength(1));
    expect(plan.phases.single.title, 'Phase 1');
    final [a, b] = plan.phases.single.steps;
    expect(a.hours, 80);
    // A need on a later or unknown step is dropped, so nothing can loop.
    expect(a.needs, isEmpty);
    expect(b.key, isNot('x'));
    expect(b.hours, 0.5);
    expect(b.needs, ['x']);
  });

  test('Ofy has a fair daily share for each person', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Mina', 'm@ai.dev', 'secret1');
    for (var i = 0; i < kAiCallsPerDay; i++) {
      await b.spendAiCall();
    }
    await expectLater(b.spendAiCall(), throwsA(isA<BackendFailure>()));
    await b.signOut();
    await b.registerWithEmail('Amy', 'a@ai.dev', 'secret1');
    await b.spendAiCall();
  });

  testWidgets('Ofy asks, drafts, and the kept steps are added with dates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = LocalBackend()..ai = SampleAi(delay: Duration.zero);
    late String room;
    late Classroom classroom;
    await tester.runAsync(() async {
      await b.registerWithEmail('Mina', 'm@draft.dev', 'secret1');
      room = await b.createClassroom(
        title: 'Launch app',
        description: '',
        taskType: TaskType.build,
        individual: true,
        hoursPerWeek: 10,
      );
      classroom = (await b.watchClassroom(room).first).classroom;
    });
    final state = await tester.runAsync(() => b.watchClassroom(room).first);
    final plan = planFrom(state!, b.currentUser!.uid, monday);
    bool? result;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            child: const Text('open'),
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(
                CupertinoPageRoute(
                  builder: (_) => CupertinoPageScaffold(
                    child: SingleChildScrollView(
                      child: PlanDraftSheet(
                        backend: b,
                        classroom: classroom,
                        plan: plan,
                        today: monday,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Plan with Ofy'), findsOneWidget);
    // A description is needed; the questions are optional.
    await tester.tap(find.text('Draft my plan'));
    await tester.pumpAndSettle();
    expect(find.text('Your draft plan'), findsNothing);
    await tester.tap(find.text('Nothing'));
    await tester.pump();
    await tester.tap(find.text('Let Ofy ask a few questions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never'));
    await tester.enterText(
      find.byType(CupertinoTextField).first,
      'A small app to track habits',
    );
    await tester.pump();
    await tester.tap(find.text('Draft my plan'));
    await tester.pumpAndSettle();
    expect(find.text('Your draft plan'), findsOneWidget);
    // Leave the last step out.
    await tester.tap(find.textContaining('8. Publish'));
    await tester.pump();
    await tester.tap(find.textContaining('Add 3 phases and 7 steps'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    final saved = await tester.runAsync(() => b.watchClassroom(room).first);
    expect(saved!.phases.map((p) => p.title), ['Plan', 'Build', 'Finish']);
    expect(saved.steps, hasLength(7));
    final byTitle = {for (final s in saved.steps) s.title: s};
    final core = byTitle['Build the core feature']!;
    expect(core.dependsOn, hasLength(2));
    expect(core.estimateHours, 8);
    expect(core.start.isBefore(core.due) || core.start == core.due, isTrue);
    expect(byTitle.keys.any((t) => t.startsWith('Publish')), isFalse);
  });

  test('a study group splits each phase and teaches each other', () {
    final plan = DraftPlan(
      phases: [
        DraftPhase(
          title: 'Mechanics',
          steps: const [
            DraftStep(
              key: 'a',
              title: 'Learn kinematics',
              hours: 3,
              owner: 'Amy',
            ),
            DraftStep(key: 'b', title: 'Learn forces', hours: 3, owner: 'Ben'),
            DraftStep(
              key: 't',
              title: 'Teach each other',
              hours: 1,
              owner: 'everyone',
              needs: ['a', 'b'],
            ),
            DraftStep(key: 'n', title: 'Next part', hours: 2, needs: ['t']),
          ],
        ),
      ],
    ).forPeople(['Amy', 'Ben'], split: true);
    final steps = plan.steps.toList();
    final teach = steps.where((s) => s.title == 'Teach each other').toList();
    expect(teach.map((s) => s.owner), ['Amy', 'Ben']);
    expect(teach.every((s) => s.needs.length == 2), isTrue);
    expect(steps.last.needs, hasLength(2));
  });

  test('work for everyone stays one joint step by default', () {
    final plan = DraftPlan(
      phases: [
        DraftPhase(
          title: 'One',
          steps: const [
            DraftStep(
              key: 'a',
              title: 'Align syllabus scope',
              hours: 2,
              owner: 'everyone',
            ),
            DraftStep(key: 'n', title: 'Next', hours: 1, needs: ['a']),
          ],
        ),
      ],
    ).forPeople(['Amy', 'Ben']);
    expect(plan.steps, hasLength(2));
    expect(plan.steps.first.owner, 'everyone');
    expect(plan.steps.last.needs, ['a']);
  });

  test('new steps fit among the old ones, and the rest move along', () {
    final s = scheduleItems(
      const [
        ScheduleItem(key: 'e1', hours: 7, owner: 'me', rank: 0),
        ScheduleItem(
          key: 'e2',
          hours: 7,
          owner: 'me',
          needs: ['e1', 'n1'],
          rank: 1,
        ),
        ScheduleItem(
          key: 'n1',
          hours: 7,
          owner: 'me',
          needs: ['e1'],
          rank: 0.5,
        ),
      ],
      today: monday,
      hoursPerWeek: 7,
    );
    expect(s.dates['n1']!.start, DateTime(2026, 11, 16));
    // e2 now waits for the new step, a week later than before.
    expect(s.dates['e2']!.start, DateTime(2026, 11, 23));
  });

  test('a draft that repeats a step says which step has it', () async {
    final draft = await SampleAi(delay: Duration.zero).draftPlan(
      const TaskBrief(
        title: 'Physics',
        taskType: TaskType.study,
        request: 'do past papers',
        steps: [
          ExistingStep(ref: 'e1', phase: 'Practise', title: 'Do past papers'),
        ],
      ),
      const [],
    );
    expect(draft.steps, isEmpty);
    expect(draft.covered.single.ref, 'e1');
  });
}
