import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/ai/sample_ai.dart';
import 'package:octria/data/models.dart';
import 'package:octria/model/plan.dart';

final _today = DateTime(2026, 11, 12);

PlanStep _step(
  String id, {
  String owner = 'me',
  String phase = 'p1',
  StepStatus status = StepStatus.todo,
  List<String> needs = const [],
  StepKind kind = StepKind.work,
  List<String> participants = const [],
  List<String> doneBy = const [],
}) => PlanStep(
  id: id,
  phaseId: phase,
  ownerId: owner,
  title: 'Step $id',
  estimateHours: 2,
  start: _today,
  due: _today.add(const Duration(days: 3)),
  status: status,
  dependsOn: needs,
  kind: kind,
  participants: participants,
  doneBy: doneBy,
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
  group('a shared mock test holds back only those who haven’t taken it', () {
    PlanStep test_({List<String> doneBy = const []}) => _step(
      't',
      kind: StepKind.test,
      participants: const ['me', 'you'],
      doneBy: doneBy,
      status: doneBy.isEmpty ? StepStatus.todo : StepStatus.doing,
    );

    test('nobody has: both wait', () {
      final plan = _plan([
        test_(),
        _step('mine', owner: 'me', needs: ['t'], phase: 'p2'),
        _step('yours', owner: 'you', needs: ['t'], phase: 'p2'),
      ]);
      expect(plan.standing(plan.steps['mine']!), Standing.waiting);
      expect(plan.standing(plan.steps['yours']!), Standing.waiting);
    });

    test('one has: they go on, the other still waits', () {
      final plan = _plan([
        test_(doneBy: ['me']),
        _step('mine', owner: 'me', needs: ['t'], phase: 'p2'),
        _step('yours', owner: 'you', needs: ['t'], phase: 'p2'),
      ]);
      expect(plan.standing(plan.steps['mine']!), Standing.ready);
      expect(plan.standing(plan.steps['yours']!), Standing.waiting);
      expect(plan.openDependencies(plan.steps['mine']!), isEmpty);
      expect(plan.openDependencies(plan.steps['yours']!).single.id, 't');
      expect(plan.nextStepFor('me')?.id, 'mine');
      expect(plan.explain(plan.steps['mine']!), contains('your part of'));
    });

    test('ordinary work still waits for the whole step', () {
      final plan = _plan([
        _step('a', owner: 'you', status: StepStatus.doing),
        _step('b', owner: 'me', needs: ['a']),
      ]);
      expect(plan.standing(plan.steps['b']!), Standing.waiting);
    });

    test('joint work after a test waits for everyone in it', () {
      final plan = _plan([
        test_(doneBy: ['me']),
        _step(
          'together',
          kind: StepKind.joint,
          participants: const ['me', 'you'],
          needs: ['t'],
          phase: 'p2',
        ),
      ]);
      expect(plan.standing(plan.steps['together']!), Standing.waiting);
    });

    test('someone the test isn’t for isn’t held by it', () {
      final plan = _plan([
        _step('t', kind: StepKind.test, participants: const ['you']),
        _step('mine', owner: 'me', needs: ['t'], phase: 'p2'),
      ]);
      expect(plan.standing(plan.steps['mine']!), Standing.ready);
    });
  });

  group('mock interviews', () {
    test('questions are read and capped at five', () {
      final interview = Interview.fromJson({
        'title': '',
        'questions': [
          for (var i = 0; i < 8; i++)
            {'question': 'Explain $i', 'lookFor': 'What and why'},
          {'question': '   '},
          'nonsense',
        ],
      }, 'Mock interview');
      expect(interview.title, 'Mock interview');
      expect(interview.questions, hasLength(5));
      expect(interview.questions.first.lookFor, 'What and why');
    });

    test('marking always gives one review per question, 0 to 10', () {
      final review = InterviewReview.fromJson({
        'summary': 'Good.',
        'answers': [
          {'score': 7.6, 'feedback': 'Clear.'},
          {'score': 42, 'feedback': 'Too kind.'},
          {'score': -3},
          'nonsense',
        ],
      }, 5);
      expect(review.answers.map((a) => a.score), [8, 10, 0, 0, 0]);
      expect(review.answers.last.feedback, 'Not marked.');
      expect(review.score, 18);
      expect(review.outOf, 50);
      expect(InterviewReview.fromJson(const {}, 2).answers, hasLength(2));
    });

    test(
      'the sample model asks open questions and marks every answer',
      () async {
        final ai = SampleAi(delay: Duration.zero);
        const brief = QuizBrief(
          subject: 'Physics',
          topics: ['Waves', 'Optics'],
        );
        final interview = await ai.makeInterview(brief);
        expect(interview.questions, isNotEmpty);
        final review = await ai.reviewInterview(brief, [
          for (final (i, q) in interview.questions.indexed)
            (q, i == 0 ? '' : 'A wave carries energy without carrying matter.'),
        ]);
        expect(review.answers, hasLength(interview.questions.length));
        expect(review.answers.first.score, 0);
        expect(review.answers.last.score, greaterThan(0));
      },
    );
  });

  group('results', () {
    TestResult result({
      bool mock = false,
      bool interview = false,
      String level = '',
    }) => TestResult(
      id: 'r',
      classroomId: 'c',
      label: 'Waves',
      right: 3,
      total: 4,
      mock: mock,
      interview: interview,
      level: level,
      at: _today,
    );

    test('say what kind of test they were', () {
      expect(result().kindLabel, 'Practice');
      expect(result(mock: true, level: 'hard').kindLabel, 'Mock test, harder');
      expect(
        result(mock: true, interview: true, level: 'easy').kindLabel,
        'Mock interview, easier',
      );
    });

    test('levels are kept by a short word', () {
      expect(QuizLevel.of('hard'), QuizLevel.hard);
      expect(QuizLevel.of(''), QuizLevel.standard);
      expect(QuizLevel.of('nonsense'), QuizLevel.standard);
      expect(QuizLevel.easy.stored, 'easy');
    });
  });
}
