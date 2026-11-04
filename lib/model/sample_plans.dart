import 'dart:math';

import 'plan.dart';

/// Fake plans for the graph prototype. Nothing here is real user data, and the
/// study materials are placeholders rather than real files or links.
final _today = DateTime(2026, 11, 17);

DateTime _d(int offset) => _today.add(Duration(days: offset));

const _file = ResourceType.file;
const _link = ResourceType.link;
const _video = ResourceType.video;
const _note = ResourceType.note;

StepResource _r(ResourceType type, String title, String detail) =>
    StepResource(type: type, title: title, detail: detail);

/// A checklist with its first [done] items ticked.
List<ChecklistItem> _check(int done, List<String> titles) => [
  for (var i = 0; i < titles.length; i++)
    ChecklistItem(title: titles[i], done: i < done),
];

Plan campusEventsPlan() {
  const members = [
    Member(id: 'me', name: 'You'),
    Member(id: 'asha', name: 'Asha'),
    Member(id: 'ben', name: 'Ben'),
    Member(id: 'chen', name: 'Chen'),
  ];
  const phases = [
    Phase(id: 'research', title: 'Research'),
    Phase(id: 'design', title: 'Design'),
    Phase(id: 'build', title: 'Build'),
    Phase(id: 'launch', title: 'Launch'),
  ];
  PlanStep s(
    String id,
    String phase,
    String owner,
    String title,
    StepStatus status,
    List<String> deps,
    double hours,
    int start,
    int due, {
    required String description,
    List<ChecklistItem> checklist = const [],
    List<StepResource> resources = const [],
    List<String> skills = const [],
    int comments = 0,
    int newSuggestions = 0,
    int newComments = 0,
    bool changed = false,
  }) => PlanStep(
    id: id,
    phaseId: phase,
    ownerId: owner,
    title: title,
    description: description,
    status: status,
    dependsOn: deps,
    estimateHours: hours,
    start: _d(start),
    due: _d(due),
    checklist: checklist,
    resources: resources,
    skills: skills,
    comments: comments,
    newSuggestions: newSuggestions,
    newComments: newComments,
    changedSinceVisit: changed,
  );

  const done = StepStatus.done;
  const doing = StepStatus.doing;
  const todo = StepStatus.todo;

  return Plan(
    title: 'Campus Events App',
    members: members,
    phases: phases,
    meId: 'me',
    today: _today,
    steps: [
      s(
        'interview',
        'research',
        'me',
        'Interview 5 students',
        done,
        [],
        6,
        -24,
        -20,
        description: 'Ask how they find out about campus events today.',
        checklist: _check(3, [
          'Write the questions',
          'Book five students',
          'Share the takeaways',
        ]),
        resources: [
          _r(_file, 'Interview questions', 'Twelve questions, one page'),
          _r(_note, 'Takeaways', 'Most students hear about events too late'),
        ],
        skills: ['User research'],
        comments: 3,
      ),
      s(
        'survey',
        'research',
        'asha',
        'Survey existing apps',
        done,
        [],
        4,
        -24,
        -21,
        description: 'Compare what other campus apps do well and badly.',
        resources: [_r(_file, 'App comparison', 'Six apps, side by side')],
        skills: ['Research'],
        comments: 1,
      ),
      s(
        'brief',
        'research',
        'asha',
        'Write the brief',
        done,
        ['survey', 'interview'],
        3,
        -20,
        -17,
        description: 'One page on who this is for and what it must do first.',
        resources: [_r(_file, 'Project brief', 'One page, agreed by the team')],
        skills: ['Writing'],
      ),
      s(
        'flows',
        'design',
        'me',
        'Sketch main flows',
        done,
        ['brief'],
        5,
        -17,
        -12,
        description: 'Find an event, read about it, say you are going.',
        checklist: _check(2, ['Paper sketches', 'Review with the team']),
        resources: [_r(_file, 'Flow sketches', 'Three flows, photographed')],
        skills: ['UX design'],
        comments: 2,
      ),
      s(
        'card',
        'design',
        'ben',
        'Design event card',
        doing,
        ['flows'],
        8,
        -10,
        3,
        description: 'Date, venue and club at a glance. Works in dark mode.',
        checklist: _check(2, [
          'Layout options',
          'Pick one with the team',
          'Dark mode version',
          'Long title cases',
          'Hand over to Build',
        ]),
        resources: [
          _r(_file, 'Card drafts', 'Three options to compare'),
          _r(_link, 'Type scale guide', 'Sizes for dense layouts'),
        ],
        skills: ['Visual design'],
        comments: 4,
        newComments: 2,
      ),
      s(
        'firebase',
        'build',
        'chen',
        'Set up Firebase',
        done,
        ['brief'],
        4,
        -12,
        -3,
        description: 'Project, database and security rules, ready to build on.',
        resources: [_r(_link, 'Setup guide', 'Steps for a new project')],
        skills: ['Firebase'],
        comments: 1,
      ),
      s(
        'list',
        'build',
        'me',
        'Build event list',
        todo,
        ['firebase', 'flows'],
        10,
        0,
        2,
        description: 'Scrollable list of upcoming events from Firestore.',
        checklist: _check(0, [
          'Read events from Firestore',
          'Build the list screen',
          'Add loading and empty states',
          'Test with 100 events',
        ]),
        resources: [
          _r(_link, 'Reading data guide', 'Queries and live updates'),
          _r(_video, 'Scrolling lists walkthrough', '14 min'),
          _r(_note, 'Sample event data', 'Twenty events to test with'),
        ],
        skills: ['Flutter', 'Firestore'],
        comments: 2,
        newSuggestions: 1,
      ),
      s(
        'signin',
        'build',
        'asha',
        'Add sign-in',
        doing,
        ['firebase'],
        6,
        -3,
        4,
        description: 'Google sign-in, with a clear way to sign out again.',
        checklist: _check(1, [
          'Turn on Google sign-in',
          'Sign-in screen',
          'Sign-out and errors',
        ]),
        resources: [_r(_link, 'Sign-in guide', 'Google sign-in steps')],
        skills: ['Flutter', 'Firebase'],
        comments: 1,
      ),
      s(
        'detail',
        'build',
        'ben',
        'Build event page',
        todo,
        ['card', 'list'],
        8,
        3,
        9,
        description: 'Everything about one event, reached from the list.',
        checklist: _check(0, [
          'Page layout',
          'Map to the venue',
          'Share button',
        ]),
        resources: [_r(_file, 'Page mock-up', 'One screen, two states')],
        skills: ['Flutter'],
        changed: true,
      ),
      s(
        'rsvp',
        'build',
        'chen',
        'Add RSVP',
        todo,
        ['signin', 'list'],
        6,
        4,
        10,
        description: 'Say you are going, and see how many others are.',
        resources: [
          _r(_note, 'RSVP rules', 'What happens when an event fills'),
        ],
        skills: ['Flutter', 'Firestore'],
        comments: 1,
      ),
      s(
        'test',
        'launch',
        'me',
        'Test with 10 friends',
        todo,
        ['detail', 'rsvp'],
        5,
        11,
        15,
        description: 'Watch people use it, and note where they get stuck.',
        checklist: _check(0, ['Book ten friends', 'Write up what broke']),
        resources: [_r(_file, 'Test script', 'Five tasks to try')],
        skills: ['User research'],
      ),
      s(
        'listing',
        'launch',
        'ben',
        'Write store listing',
        todo,
        ['detail'],
        3,
        11,
        14,
        description: 'Name, description and screenshots for the store page.',
        resources: [_r(_link, 'Listing checklist', 'What the store asks for')],
        skills: ['Writing'],
      ),
      s(
        'publish',
        'launch',
        'chen',
        'Publish to Play Store',
        todo,
        ['test', 'listing'],
        2,
        16,
        18,
        description: 'Send the first release for review.',
        resources: [_r(_link, 'Release guide', 'From build to review')],
        skills: ['Android'],
      ),
    ],
  );
}

Plan physicsExamPlan() {
  const members = [Member(id: 'me', name: 'You')];
  const phases = [
    Phase(id: 'learn', title: 'Learn'),
    Phase(id: 'revise', title: 'Revise'),
    Phase(id: 'mock', title: 'Mock tests'),
  ];
  PlanStep s(
    int i,
    String phase,
    String title,
    StepStatus status,
    double hours,
    String description,
    List<ChecklistItem> checklist,
    List<StepResource> resources,
    List<String> skills,
  ) => PlanStep(
    id: 'p$i',
    phaseId: phase,
    ownerId: 'me',
    title: title,
    description: description,
    status: status,
    dependsOn: i == 0 ? const [] : ['p${i - 1}'],
    estimateHours: hours,
    start: _d(-8 + i * 3),
    due: _d(-5 + i * 3),
    checklist: checklist,
    resources: resources,
    skills: skills,
  );

  const done = StepStatus.done;
  const doing = StepStatus.doing;
  const todo = StepStatus.todo;

  return Plan(
    title: 'Exam prep: Physics',
    members: members,
    phases: phases,
    meId: 'me',
    today: _today,
    steps: [
      s(
        0,
        'learn',
        'Mechanics',
        done,
        8,
        'Forces, motion, energy and momentum.',
        _check(3, [
          'Read the chapters',
          'Work the examples',
          'Do the problems',
        ]),
        [
          _r(_file, 'Mechanics notes', 'Class notes, 18 pages'),
          _r(_video, 'Newton’s laws explained', '22 min'),
          _r(_file, 'Problem set 1', '20 problems with answers'),
        ],
        ['Mechanics'],
      ),
      s(
        1,
        'learn',
        'Waves and optics',
        done,
        6,
        'Wave behaviour, interference, reflection and lenses.',
        _check(3, ['Read the chapters', 'Ray diagrams', 'Do the problems']),
        [
          _r(_file, 'Waves and optics notes', 'Class notes, 14 pages'),
          _r(_video, 'Interference and diffraction', '18 min'),
          _r(_file, 'Problem set 2', '15 problems with answers'),
        ],
        ['Waves', 'Optics'],
      ),
      s(
        2,
        'learn',
        'Thermodynamics',
        doing,
        7,
        'Heat, work and the laws of thermodynamics, up to heat engines. '
            'Wave ideas come back in how heat moves as radiation.',
        _check(1, [
          'First and second laws',
          'Heat engines and efficiency',
          'Entropy problems',
          'Summarise on one page',
        ]),
        [
          _r(_file, 'Thermodynamics notes', 'Class notes, 16 pages'),
          _r(_video, 'Heat engines explained', '15 min'),
          _r(_link, 'Worked entropy examples', 'Eight solved problems'),
          _r(_note, 'My formula list', 'Your own notes for this topic'),
        ],
        ['Thermodynamics'],
      ),
      s(
        3,
        'learn',
        'Electromagnetism',
        todo,
        9,
        'Fields, circuits, induction and electromagnetic waves.',
        _check(0, ['Fields and forces', 'Circuits', 'Induction']),
        [
          _r(_file, 'Electromagnetism notes', 'Class notes, 22 pages'),
          _r(_video, 'Induction in ten minutes', '10 min'),
        ],
        ['Electromagnetism'],
      ),
      s(
        4,
        'revise',
        'Formula sheet',
        todo,
        3,
        'Every formula you need on two pages, in your own words.',
        _check(0, ['Collect from all topics', 'Test yourself from memory']),
        [_r(_note, 'Formula sheet draft', 'Start from your topic notes')],
        ['Revision'],
      ),
      s(
        5,
        'revise',
        'Past-paper topics',
        todo,
        5,
        'Find which topics come up most, and revise those first.',
        _check(0, ['Tally the last five papers', 'Revise the top three']),
        [_r(_file, 'Past papers', 'Last five years')],
        ['Revision'],
      ),
      s(
        6,
        'mock',
        'Mock test 1',
        todo,
        3,
        'A full paper, timed, with no notes.',
        _check(0, ['Sit the paper', 'Mark it']),
        [_r(_file, 'Mock paper A', 'Three hours, with mark scheme')],
        ['Exam technique'],
      ),
      s(
        7,
        'mock',
        'Review mistakes',
        todo,
        3,
        'Work out why each mark was lost, and redo those questions.',
        _check(0, ['List lost marks', 'Redo the questions']),
        [_r(_note, 'Mistake log', 'What went wrong, and the fix')],
        ['Exam technique'],
      ),
      s(
        8,
        'mock',
        'Mock test 2',
        todo,
        3,
        'A second timed paper, to check the gaps have closed.',
        _check(0, ['Sit the paper', 'Compare with test 1']),
        [_r(_file, 'Mock paper B', 'Three hours, with mark scheme')],
        ['Exam technique'],
      ),
    ],
  );
}

/// A large plan to prove the canvas stays smooth. Same seed, same plan.
Plan stressPlan({int stepCount = 600}) {
  final random = Random(7);
  final members = [
    const Member(id: 'me', name: 'You'),
    for (var i = 1; i < 10; i++) Member(id: 'm$i', name: 'Member $i'),
  ];
  final phases = [
    for (var i = 0; i < 10; i++) Phase(id: 'ph$i', title: 'Phase ${i + 1}'),
  ];
  final steps = <PlanStep>[];
  for (var i = 0; i < stepCount; i++) {
    final phaseIndex = (i * phases.length) ~/ stepCount;
    final deps = <String>[];
    if (i > 0) deps.add('s${max(0, i - 1 - random.nextInt(14))}');
    if (i > 20 && random.nextBool()) deps.add('s${i - 1 - random.nextInt(20)}');
    final progress = i / stepCount;
    steps.add(
      PlanStep(
        id: 's$i',
        phaseId: phases[phaseIndex].id,
        ownerId: members[random.nextInt(members.length)].id,
        title: 'Step ${i + 1}',
        estimateHours: 1.0 + random.nextInt(8),
        status: progress < 0.3
            ? StepStatus.done
            : (progress < 0.34 ? StepStatus.doing : StepStatus.todo),
        dependsOn: deps.toSet().toList(),
        start: _d(-60 + (progress * 180).round()),
        due: _d(-55 + (progress * 180).round()),
      ),
    );
  }
  return Plan(
    title: 'Stress test: $stepCount steps',
    members: members,
    phases: phases,
    steps: steps,
    meId: 'me',
    today: _today,
  );
}
