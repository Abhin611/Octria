import 'dart:typed_data';

import '../data/models.dart';
import '../ofy/app_guide.dart';
import 'ai.dart';
import 'split.dart';

/// Ofy without a model: believable questions and drafts for each kind of
/// task, so tests, the demo and runs without Firebase work the same way.
class SampleAi implements Ai {
  SampleAi({this.delay = const Duration(milliseconds: 500)});

  /// A short pause, so the screens show their waiting state as they would.
  final Duration delay;

  @override
  Future<OfyAnswer> chat(OfyQuestion q) async {
    await Future<void>.delayed(delay);
    final said = q.text.trim();
    if (q.picture case final bytes?) {
      return OfyAnswer(
        'I can see the picture you attached (${(bytes.length / 1024).ceil()} '
        'KB). This is the sample Ofy, so I can’t read it; the real one '
        'explains what it shows.',
      );
    }
    final text = said.toLowerCase();
    bool can(String id) => q.actions.any((a) => a.$1 == id);
    RegExpMatch? match(String pattern) =>
        RegExp(pattern, caseSensitive: false).firstMatch(said);

    // Things to do.
    final done = match(r'mark (.+?) (?:as )?(?:done|finished|complete)');
    if (done != null && can('mark-done')) {
      final step = done.group(1)!.replaceAll(RegExp(r'^(the|my) '), '');
      return OfyAnswer(
        'I can mark “$step” done for you.',
        action: 'mark-done',
        args: {'step': step},
      );
    }
    final add = match(r'add (?:a )?(?:new )?step (?:called |named |to )?(.+)');
    if (add != null && can('add-step')) {
      final title = add.group(1)!.trim();
      return OfyAnswer(
        'I can add a step called “$title” for you.',
        action: 'add-step',
        args: {'title': title},
      );
    }
    if ((text.contains('draft') ||
            text.contains('make a plan') ||
            text.contains('plan for me')) &&
        can('draft-plan')) {
      return const OfyAnswer(
        'Let’s draft it together: I’ll ask a few questions first.',
        action: 'draft-plan',
      );
    }
    final open = match(
      r'^(?:please )?(?:open|go to|show me|take me to) (?:the )?(.+)$',
    );
    if (open != null) {
      final what = open
          .group(1)!
          .toLowerCase()
          .replaceAll(RegExp(r'[.?!]'), '')
          .trim();
      for (final tab in const [
        'dashboard',
        'activity',
        'kanvas',
        'timeline',
        'profile',
      ]) {
        if (what.startsWith(tab) && can('switch-tab')) {
          return OfyAnswer(
            'Opening $tab.',
            action: 'switch-tab',
            args: {'tab': tab},
          );
        }
      }
      for (final item in const [
        'files',
        'class chat',
        'private chats',
        'practice',
        'handovers',
        'important',
        'phases',
        'settings',
        'activity',
        'shared boards',
        'members and invite code',
      ]) {
        if (what.startsWith(item) && can('open-menu')) {
          return OfyAnswer(
            'Opening ${item[0].toUpperCase()}${item.substring(1)}.',
            action: 'open-menu',
            args: {'item': item},
          );
        }
      }
      if (can('open-classroom')) {
        return OfyAnswer(
          'Opening $what.',
          action: 'open-classroom',
          args: {'name': what},
        );
      }
    }
    if ((text.contains('dark') || text.contains('light')) &&
        (text.contains('switch') ||
            text.contains('turn') ||
            text.contains('mode')) &&
        can('toggle-theme')) {
      return const OfyAnswer(
        'Switching the background.',
        action: 'toggle-theme',
      );
    }

    // Questions about their work.
    if (text.contains('next') &&
        (text.contains('what') ||
            text.contains('do') ||
            text.contains('should'))) {
      final line = q.context
          .split('\n')
          .where((l) => l.startsWith('Your next step:'))
          .firstOrNull;
      return OfyAnswer(
        line == null
            ? 'Open a classroom and I’ll tell you your next step there.'
            : '${line.replaceFirst('Your next step:', 'Your next step is')} '
                  'It’s the one marked Next on the map.',
      );
    }

    // How things work.
    final howTo = guessHowTo(said);
    if (howTo != null) {
      final room = match(r'\b(?:in|for|of) (?:the |my )?(.+?) classroom\b');
      return OfyAnswer(
        howTo.answer,
        howTo: howTo.steps.isEmpty ? null : howTo.id,
        args: {if (room != null) 'classroom': room.group(1)!.trim()},
      );
    }
    return const OfyAnswer(
      'I can explain how anything in Octria works, show you where it is on '
      'screen, and do things for you, like adding a step or marking one '
      'done. Try “How do I add a file to a step?” or “What should I do '
      'next?”',
    );
  }

  @override
  Future<Research?> research(TaskBrief brief) async {
    await Future<void>.delayed(delay);
    if (!namesASyllabus(brief.request)) return null;
    return const Research(
      syllabus:
          'Unit 1: Electrostatics. Unit 2: Current electricity. Unit 3: '
          'Magnetic effects of current. Unit 4: Optics. Unit 5: Modern physics.',
      sources: [
        ('CBSE curriculum', 'https://cbseacademic.nic.in/curriculum_2025.html'),
        ('NCERT textbooks', 'https://ncert.nic.in/textbook.php'),
      ],
    );
  }

  @override
  Future<BoardHelp> helpWithBoard(BoardBrief brief) async {
    await Future<void>.delayed(delay);
    final first = brief.lines.take(4).toList();
    return switch (brief.task) {
      BoardTask.summary => BoardHelp(
        summary:
            '“${brief.title}” has ${brief.lines.length} things written on '
            'it, starting with ${first.isEmpty ? 'nothing' : first.first}.',
        items: first,
      ),
      BoardTask.ideas => const BoardHelp(
        summary: 'It’s gathering ideas.',
        items: [
          'Who is this for?',
          'What has to happen first?',
          'What could go wrong?',
        ],
      ),
      BoardTask.steps => BoardHelp(
        summary: 'Doing these turns the board into something finished.',
        items: [for (final l in first) 'Do: $l'],
      ),
    };
  }

  @override
  Future<List<Assignment>> splitBySkills(SplitBrief brief) async {
    await Future<void>.delayed(delay);
    return matchBySkills(brief.steps, brief.people);
  }

  @override
  Future<List<String>> readSkills({
    String text = '',
    Uint8List? file,
    String mime = '',
  }) async {
    await Future<void>.delayed(delay);
    // Picks out well-known skills by name: enough to try the screens.
    const known = [
      'Flutter',
      'Dart',
      'Python',
      'JavaScript',
      'Firebase',
      'Design',
      'Writing',
      'Research',
      'Testing',
      'Physics',
      'Chemistry',
      'Maths',
      'Public speaking',
    ];
    final lower = text.toLowerCase();
    final found = [
      for (final k in known)
        if (lower.contains(k.toLowerCase())) k,
    ];
    return found.isEmpty && file != null ? ['Writing', 'Research'] : found;
  }

  @override
  Future<ReplanAdvice> advise(ReplanBrief brief) async {
    await Future<void>.delayed(delay);
    // Trims the longest steps that aren't shared points, a third each.
    final long = brief.steps.where((s) => !s.point && s.hours >= 2).toList()
      ..sort((a, b) => b.hours.compareTo(a.hours));
    return ReplanAdvice(
      note:
          'I kept every step and trimmed the longest ones, so nothing the '
          'task needs is lost.',
      cuts: [
        for (final s in long.take(3))
          Cut(
            ref: s.ref,
            hours: ((s.hours * 2 / 3) * 2).round() / 2,
            why: 'It’s the longest left, so it has the most room to give.',
          ),
      ],
    );
  }

  @override
  Future<Quiz> makeQuiz(QuizBrief brief) async {
    await Future<void>.delayed(delay);
    final topics = brief.topics.isEmpty ? [brief.subject] : brief.topics;
    return Quiz(
      title: '${brief.mock ? 'Mock test' : 'Practice'}: ${topics.first}',
      questions: [
        for (var i = 0; i < 4; i++)
          QuizQuestion(
            question:
                'Which best describes the main idea of '
                '“${topics[i % topics.length]}”?',
            choices: const [
              'The idea the step is about',
              'Something unrelated',
              'The opposite of it',
              'None of these',
            ],
            answer: 0,
            explain: 'The step is about exactly this.',
          ),
      ],
    );
  }

  @override
  Future<ResourceFind> findResources(ResourceBrief brief) async {
    await Future<void>.delayed(delay);
    final q = Uri.encodeQueryComponent(brief.step);
    return ResourceFind(
      resources: [
        FoundResource(
          title: 'Khan Academy: ${brief.step}',
          url: 'https://www.khanacademy.org/search?page_search_query=$q',
          why: 'Short lessons with practice, free.',
          confirmed: true,
        ),
        FoundResource(
          title: 'Videos on ${brief.step}',
          url: 'https://www.youtube.com/results?search_query=$q',
          video: true,
          why: 'Worked examples to watch.',
          confirmed: true,
        ),
        FoundResource(
          title: 'Wikipedia: ${brief.step}',
          url: 'https://en.wikipedia.org/w/index.php?search=$q',
          why: 'Background and further reading.',
        ),
      ].where((r) => !brief.have.contains(r.url)).toList(),
      searches: ['${brief.step} tutorial', '${brief.step} explained'],
    );
  }

  @override
  Future<Interview> makeInterview(QuizBrief brief) async {
    await Future<void>.delayed(delay);
    final topics = brief.topics.isEmpty ? [brief.subject] : brief.topics;
    return Interview(
      title: 'Mock interview: ${topics.first}',
      questions: [
        for (var i = 0; i < 3; i++)
          InterviewQuestion(
            question:
                'In your own words, explain “${topics[i % topics.length]}” '
                'and why it matters.',
            lookFor: 'What it is, how it’s done, and one thing to watch for.',
          ),
      ],
    );
  }

  @override
  Future<InterviewReview> reviewInterview(
    QuizBrief brief,
    List<(InterviewQuestion, String)> answers,
  ) async {
    await Future<void>.delayed(delay);
    // Marks by length alone: enough to try the screens.
    return InterviewReview(
      summary: 'A fair start. Say more about why, not only what.',
      answers: [
        for (final (_, a) in answers)
          a.trim().isEmpty
              ? const AnswerReview(score: 0, feedback: 'Skipped.')
              : AnswerReview(
                  score: (3 + a.trim().split(RegExp(r'\s+')).length ~/ 4).clamp(
                    3,
                    9,
                  ),
                  feedback:
                      'You covered the idea. Add an example and say what '
                      'could go wrong.',
                ),
      ],
    );
  }

  @override
  Future<List<FollowUp>> followUps(TaskBrief brief) async {
    await Future<void>.delayed(delay);
    final level = switch (brief.taskType) {
      TaskType.study => const FollowUp(
        'How well do you know the subject already?',
        choices: ['Just starting', 'Some of it', 'Revising'],
      ),
      TaskType.build => const FollowUp(
        'How much have you built like this before?',
        choices: ['Never', 'A little', 'Plenty'],
      ),
      _ => const FollowUp(
        'How much experience do you have with this?',
        choices: ['None yet', 'Some', 'A lot'],
      ),
    };
    return [
      level,
      FollowUp(
        'What does finished look like for “${brief.title}”?',
        choices: const ['Good enough to share', 'Polished', 'Just done'],
      ),
      if (brief.deadline == null)
        const FollowUp(
          'Is there a date it has to be done by?',
          choices: ['In a month', 'In three months', 'No fixed date'],
        ),
    ];
  }

  @override
  Future<DraftPlan> draftPlan(
    TaskBrief brief,
    List<(String, String)> answers,
  ) async {
    await Future<void>.delayed(delay);
    final t = brief.title.trim().isEmpty ? 'the task' : brief.title.trim();
    final asked = brief.request.trim();
    // A plan with steps gets what was asked for, placed after its last step,
    // unless a step already covers it.
    if (brief.steps.isNotEmpty && asked.isNotEmpty) {
      Set<String> words(String s) => {
        for (final w in s.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
          if (w.length > 2) w,
      };
      final want = words(asked);
      for (final s in brief.steps) {
        final have = words(s.title);
        if (have.isNotEmpty &&
            have.intersection(want).length * 2 >= have.length) {
          return DraftPlan(
            summary: 'Your plan already has this.',
            phases: const [],
            covered: [Covered(asked, s.ref)],
          );
        }
      }
      final last = brief.steps.last;
      final title = asked.length > 60 ? asked.substring(0, 60) : asked;
      return DraftPlan(
        summary: 'One new step, after “${last.title}”.',
        phases: [
          DraftPhase(
            title: last.phase,
            steps: [
              DraftStep(
                key: 'n1',
                title: '${title[0].toUpperCase()}${title.substring(1)}',
                hours: 2,
                needs: [last.ref],
                checklist: const ['Do it', 'Check it'],
              ),
            ],
          ),
        ],
      );
    }
    // A plan already under way gets a few more steps, not a new plan.
    if (brief.existing.isNotEmpty) {
      final last = brief.existing.last.$1;
      return DraftPlan(
        summary: 'A few steps the plan doesn’t have yet, to finish $t well.',
        phases: [
          DraftPhase(
            title: last,
            steps: const [
              DraftStep(key: 'a1', title: 'Check the work so far', hours: 1),
              DraftStep(
                key: 'a2',
                title: 'Fix what the check found',
                hours: 3,
                needs: ['a1'],
              ),
            ],
          ),
          if (brief.newPhasesAllowed)
            const DraftPhase(
              title: 'Hand over',
              steps: [
                DraftStep(
                  key: 'a3',
                  title: 'Share the result',
                  hours: 1,
                  needs: ['a2'],
                ),
              ],
            ),
        ],
      );
    }
    final shape = switch (brief.taskType) {
      TaskType.build => [
        (
          'Plan',
          [
            ('Write down what $t must do', 2.0, <String>[], ['Product']),
            ('Sketch the main screens', 3.0, ['s1'], ['Design']),
          ],
        ),
        (
          'Build',
          [
            ('Set up the project', 2.0, ['s1'], ['Setup']),
            ('Build the core feature', 8.0, ['s2', 's3'], ['Coding']),
            ('Add sign-in and saving', 6.0, ['s3'], ['Coding']),
          ],
        ),
        (
          'Finish',
          [
            ('Test with three people', 3.0, ['s4', 's5'], ['Testing']),
            ('Fix what they found', 4.0, ['s6'], ['Coding']),
            ('Publish $t', 2.0, ['s7'], ['Release']),
          ],
        ),
      ],
      TaskType.study => [
        (
          'Understand',
          [
            ('List every topic in the syllabus', 1.0, <String>[], ['Planning']),
            ('Read through the first half', 6.0, ['s1'], ['Reading']),
            ('Read through the second half', 6.0, ['s2'], ['Reading']),
          ],
        ),
        (
          'Practise',
          [
            ('Make summary notes', 4.0, ['s3'], ['Notes']),
            ('Do past questions', 6.0, ['s3'], ['Practice']),
          ],
        ),
        (
          'Revise',
          [
            ('Go over weak topics', 4.0, ['s5'], ['Revision']),
            ('Take a timed mock paper', 3.0, ['s4', 's6'], ['Exam']),
          ],
        ),
      ],
      TaskType.research => [
        (
          'Frame',
          [
            ('Write the research question', 2.0, <String>[], ['Writing']),
            ('Find ten key sources', 5.0, ['s1'], ['Searching']),
          ],
        ),
        (
          'Investigate',
          [
            ('Read and take notes', 8.0, ['s2'], ['Reading']),
            ('Collect or analyse the data', 8.0, ['s1'], ['Analysis']),
          ],
        ),
        (
          'Write up',
          [
            ('Draft the findings', 6.0, ['s3', 's4'], ['Writing']),
            ('Get feedback and revise', 4.0, ['s5'], ['Editing']),
          ],
        ),
      ],
      TaskType.eventOrCreative => [
        (
          'Shape the idea',
          [
            ('Agree what $t is for', 1.0, <String>[], ['Planning']),
            ('Set the budget and date', 2.0, ['s1'], ['Budget']),
          ],
        ),
        (
          'Make it',
          [
            ('Book what you need', 3.0, ['s2'], ['Logistics']),
            ('Create the main pieces', 8.0, ['s1'], ['Creative']),
            ('Tell people about it', 3.0, ['s2'], ['Promotion']),
          ],
        ),
        (
          'Deliver',
          [
            ('Run a rehearsal', 2.0, ['s3', 's4'], ['Practice']),
            ('Hold the day', 4.0, ['s5', 's6'], ['Hosting']),
          ],
        ),
      ],
      TaskType.other => [
        (
          'Get ready',
          [
            ('Decide what done looks like', 1.0, <String>[], ['Planning']),
            ('Gather what you need', 2.0, ['s1'], ['Preparation']),
          ],
        ),
        (
          'Do the work',
          [
            ('Do the first part', 4.0, ['s2'], <String>[]),
            ('Do the rest', 4.0, ['s3'], <String>[]),
          ],
        ),
        (
          'Wrap up',
          [
            ('Check it against what done looks like', 1.0, ['s4'], ['Review']),
          ],
        ),
      ],
    };
    final people = [for (final (name, _) in brief.people) name];
    if (people.length > 1 && brief.linked) return _studyGroup(t, people);
    var n = 0;
    return DraftPlan(
      summary:
          'A plan in ${shape.length} phases, starting small and ending with '
          'a check that $t is really done.',
      phases: [
        for (final (title, steps) in shape)
          DraftPhase(
            title: title,
            steps: [
              for (final (name, hours, needs, skills) in steps)
                DraftStep(
                  key: 's${++n}',
                  title: name,
                  hours: hours,
                  needs: needs,
                  skills: skills,
                  checklist: const ['Decide how to start', 'Do it', 'Check it'],
                  // Shared out in turn when it's a group.
                  owner: people.length > 1 ? people[n % people.length] : '',
                ),
            ],
          ),
      ],
    );
  }

  /// Each phase: one part each, then a session where everyone teaches the
  /// others their part.
  DraftPlan _studyGroup(String t, List<String> people) {
    const parts = ['first', 'second', 'third'];
    var previous = <String>[];
    final phases = <DraftPhase>[];
    for (var ph = 0; ph < 3; ph++) {
      final study = [
        for (var i = 0; i < people.length; i++)
          DraftStep(
            key: 'p${ph}s$i',
            title: 'Learn part ${i + 1} of the ${parts[ph]} third',
            hours: 4,
            owner: people[i],
            needs: previous,
            skills: const ['Reading'],
          ),
      ];
      final teach = DraftStep(
        key: 'p${ph}t',
        title: 'Teach each other the ${parts[ph]} third',
        hours: 2,
        owner: 'everyone',
        needs: [for (final s in study) s.key],
        skills: const ['Group study'],
      );
      phases.add(
        DraftPhase(title: 'The ${parts[ph]} third', steps: [...study, teach]),
      );
      previous = [teach.key];
    }
    return DraftPlan(
      summary:
          '$t in three parts. In each, everyone learns a share, then teaches '
          'it to the others, so all of you know all of it.',
      phases: phases,
    );
  }
}
