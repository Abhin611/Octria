import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/data/local_backend.dart';
import 'package:octria/data/models.dart';
import 'package:octria/graph/layout.dart';
import 'package:octria/model/plan.dart';

void main() {
  final day = DateTime(2026, 11, 10);
  PlanStep step(
    String id,
    String owner, {
    List<String> needs = const [],
    StepKind kind = StepKind.work,
    List<String> people = const [],
    List<String> doneBy = const [],
  }) => PlanStep(
    id: id,
    phaseId: 'ph',
    ownerId: owner,
    title: id,
    estimateHours: 1,
    start: day,
    due: day,
    dependsOn: needs,
    kind: kind,
    participants: people,
    doneBy: doneBy,
  );

  test('a shared point is done only when everyone’s part is', () {
    final point = step('t', 'amy', kind: StepKind.test, people: ['amy', 'ben']);
    expect(point.sharedStatus, StepStatus.todo);
    expect(point.copyWith(doneBy: ['ben']).sharedStatus, StepStatus.doing);
    expect(
      point.copyWith(doneBy: ['ben', 'amy']).sharedStatus,
      StepStatus.done,
    );
  });

  test('a shared point sits between its people’s lanes', () {
    final plan = Plan(
      title: 'Physics',
      members: const [
        Member(id: 'amy', name: 'Amy'),
        Member(id: 'ben', name: 'Ben'),
      ],
      phases: const [Phase(id: 'ph', title: 'One')],
      steps: [
        step('a', 'amy'),
        step('b', 'ben'),
        step(
          't',
          'amy',
          needs: ['a', 'b'],
          kind: StepKind.test,
          people: ['amy', 'ben'],
        ),
      ],
      meId: 'amy',
      today: day,
    );
    final layout = computeLayout(plan);
    final a = layout.positions['a']!;
    final b = layout.positions['b']!;
    final t = layout.positions['t']!;
    expect(t.dy, closeTo((a.dy + b.dy) / 2, 0.01));
    expect(t.dx, greaterThan(a.dx));
  });

  test('each person marks only their own part', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Amy', 'a@p.dev', 'secret1');
    final amy = b.currentUser!.uid;
    final room = await b.createClassroom(
      title: 'Physics',
      description: '',
      taskType: TaskType.study,
      individual: false,
    );
    final code = (await b.watchClassroom(room).first).classroom.inviteCode;
    await b.signOut();
    await b.registerWithEmail('Ben', 'b@p.dev', 'secret1');
    final ben = b.currentUser!.uid;
    await b.joinWithCode(code);
    await b.signOut();
    await b.signInWithEmail('a@p.dev', 'secret1');
    await b.savePhase(
      room,
      const PhaseRecord(id: 'ph', title: 'One', order: 1),
    );
    final point = step('t', amy, kind: StepKind.test, people: [amy, ben]);
    await b.saveStep(room, point);
    await b.signOut();
    await b.signInWithEmail('b@p.dev', 'secret1');
    // Ben can't tick Amy's part, or call the whole point done.
    await expectLater(
      b.saveStep(room, point.copyWith(doneBy: [amy], status: StepStatus.doing)),
      throwsA(isA<BackendFailure>()),
    );
    await expectLater(
      b.saveStep(room, point.copyWith(status: StepStatus.done)),
      throwsA(isA<BackendFailure>()),
    );
    await b.saveStep(
      room,
      point.copyWith(doneBy: [ben], status: StepStatus.doing),
    );
    final stored = (await b.watchClassroom(room).first).steps.single;
    expect(stored.doneBy, [ben]);
    expect(stored.status, StepStatus.doing);
  });

  test('a link that would cross a step goes round it', () {
    final plan = Plan(
      title: 'Physics',
      members: const [Member(id: 'amy', name: 'Amy')],
      phases: const [Phase(id: 'ph', title: 'One')],
      steps: [
        step('a', 'amy'),
        step('b', 'amy', needs: ['a']),
        step('c', 'amy', needs: ['b', 'a']),
      ],
      meId: 'amy',
      today: day,
    );
    final layout = computeLayout(plan);
    // a, b and c sit in one row; a to c would run straight through b.
    expect(layout.edgeRoutes['a>b']!.detour, isNull);
    final round = layout.edgeRoutes['a>c']!.detour;
    expect(round, isNotNull);
    expect(round, isNot(closeTo(layout.positions['b']!.dy, 60)));
  });

  test('ticks are kept, and only your own', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Amy', 'a@t.dev', 'secret1');
    final amy = b.currentUser!.uid;
    final room = await b.createClassroom(
      title: 'Physics',
      description: '',
      taskType: TaskType.study,
      individual: false,
    );
    final code = (await b.watchClassroom(room).first).classroom.inviteCode;
    await b.signOut();
    await b.registerWithEmail('Ben', 'b@t.dev', 'secret1');
    final ben = b.currentUser!.uid;
    await b.joinWithCode(code);
    await b.signOut();
    await b.signInWithEmail('a@t.dev', 'secret1');
    await b.savePhase(
      room,
      const PhaseRecord(id: 'ph', title: 'One', order: 1),
    );
    final point = step('t', amy, kind: StepKind.check, people: [amy, ben]);
    await b.saveStep(room, point);
    await b.signOut();
    await b.signInWithEmail('b@t.dev', 'secret1');
    await b.saveStep(
      room,
      point.copyWith(
        ticks: {
          ben: ['Electrostatics'],
        },
      ),
    );
    await expectLater(
      b.saveStep(
        room,
        point.copyWith(
          ticks: {
            ben: ['Electrostatics'],
            amy: ['Not hers to tick'],
          },
        ),
      ),
      throwsA(anything),
    );
    final stored = (await b.watchClassroom(room).first).steps.single;
    expect(stored.ticks[ben], ['Electrostatics']);
  });

  test('a syllabus is looked up only when one is named', () {
    expect(namesASyllabus('CBSE class 12 physics, theory only'), isTrue);
    expect(namesASyllabus('Plan a birthday party'), isFalse);
  });

  test('a model’s questions are kept sane', () {
    final quiz = Quiz.fromJson({
      'title': 'Electrostatics',
      'questions': [
        {
          'question': 'Unit of charge?',
          'choices': ['Coulomb', 'Volt'],
          'answer': 0,
        },
        {
          'question': 'Bad',
          'choices': ['Only one'],
          'answer': 0,
        },
        {
          'question': 'Out of range',
          'choices': ['a', 'b'],
          'answer': 5,
        },
      ],
    }, 'Practice');
    expect(quiz.questions, hasLength(1));
    expect(quiz.title, 'Electrostatics');
  });
}
