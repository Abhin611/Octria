import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/ai/sample_ai.dart';
import 'package:octria/ai/split.dart';
import 'package:octria/data/local_backend.dart';

const _amy = Person(
  id: 'amy',
  name: 'Amy',
  role: 'Back end',
  skills: ['Firebase', 'Dart', 'Testing'],
);
const _ben = Person(
  id: 'ben',
  name: 'Ben',
  skills: ['UI design', 'Flutter', 'Figma'],
);

void main() {
  group('skills are tidied', () {
    test('trimmed, once each whatever the capitals, capped', () {
      expect(cleanSkills([' Flutter ', 'flutter', '', 'Dart', 'DART']), [
        'Flutter',
        'Dart',
      ]);
      expect(
        cleanSkills([for (var i = 0; i < 40; i++) 'Skill $i']),
        hasLength(25),
      );
      expect(cleanSkills(['x' * 80]).single, hasLength(40));
    });

    test('typed as a line, they split at commas, semicolons and lines', () {
      expect(skillsFromText('Flutter, design; public speaking\nPython ,'), [
        'Flutter',
        'design',
        'public speaking',
        'Python',
      ]);
      expect(skillsFromText('  '), isEmpty);
    });
  });

  group('who suits a step', () {
    test('by the skills the step asks for', () {
      const step = SplitStep(
        id: 's',
        title: 'Build the sign-in screen',
        hours: 4,
        skills: ['Flutter', 'UI'],
      );
      expect(skillsThatFit(step, _ben), ['Flutter']);
      expect(skillsThatFit(step, _amy), isEmpty);
    });

    test('by the words in its title, as whole words only', () {
      const step = SplitStep(id: 's', title: 'Set up Firebase rules', hours: 2);
      expect(skillsThatFit(step, _amy), ['Firebase']);
      // "UI" is inside "build", but not as a word.
      const build = SplitStep(id: 'b', title: 'Build the thing', hours: 2);
      const ui = Person(id: 'u', name: 'Uma', skills: ['UI']);
      expect(skillsThatFit(build, ui), isEmpty);
    });

    test('a role counts like a skill', () {
      const step = SplitStep(id: 's', title: 'Write the back end', hours: 2);
      expect(skillsThatFit(step, _amy), ['Back end']);
    });
  });

  group('sharing steps out', () {
    test('a better fit of skills wins', () {
      final out = matchBySkills(
        const [
          SplitStep(
            id: 'a',
            title: 'Design the screens',
            hours: 3,
            skills: ['Figma'],
          ),
          SplitStep(
            id: 'b',
            title: 'Write the rules',
            hours: 3,
            skills: ['Firebase'],
          ),
        ],
        [_amy, _ben],
      );
      expect({for (final a in out) a.stepId: a.toId}, {'a': 'ben', 'b': 'amy'});
      expect(out.first.why, contains('Figma'));
    });

    test('with nothing to choose between, hours are kept even', () {
      final out = matchBySkills(
        [
          for (var i = 0; i < 6; i++)
            SplitStep(id: 's$i', title: 'Chore $i', hours: 2, ownerId: 'amy'),
        ],
        [_amy, _ben],
      );
      final each = <String, int>{};
      for (final a in out) {
        each[a.toId] = (each[a.toId] ?? 0) + 1;
      }
      expect(each, {'amy': 3, 'ben': 3});
      // The first stays where it was: equal hours, and Amy has it already.
      expect(out.first.toId, 'amy');
      expect(out.first.why, contains('stays'));
    });

    test('hours someone already has under way count against them', () {
      final out = matchBySkills(
        const [SplitStep(id: 'a', title: 'Chore', hours: 2, ownerId: 'amy')],
        [_amy, _ben],
        load: {'amy': 10},
      );
      expect(out.single.toId, 'ben');
      expect(out.single.why, contains('fewest hours'));
    });

    test('with nobody, nothing is given out', () {
      expect(
        matchBySkills(const [
          SplitStep(id: 'a', title: 'x', hours: 1),
        ], const []),
        isEmpty,
      );
    });
  });

  group('Ofy’s split', () {
    const brief = SplitBrief(
      subject: 'App',
      people: [_amy, _ben],
      steps: [
        SplitStep(id: 'id1', title: 'Rules', hours: 2),
        SplitStep(id: 'id2', title: 'Screens', hours: 3),
      ],
    );

    test('keeps only real steps and real people, each step once', () {
      final got = brief.read({
        'assignments': [
          {'step': 's1', 'person': 'amy', 'why': 'Knows Firebase'},
          {'step': 's2', 'person': 'Ben', 'why': 'Designs'},
          {'step': 's2', 'person': 'Amy', 'why': 'Again'},
          {'step': 's9', 'person': 'Amy', 'why': 'No such step'},
          {'step': 's1', 'person': 'Zed', 'why': 'No such person'},
          'nonsense',
        ],
      });
      expect(got.map((a) => (a.stepId, a.toId)), [
        ('id1', 'amy'),
        ('id2', 'ben'),
      ]);
      expect(got.first.why, 'Knows Firebase');
      expect(brief.read(const {}), isEmpty);
    });

    test('the sample model shares out by the same matching', () async {
      final got = await SampleAi(delay: Duration.zero).splitBySkills(brief);
      expect(got, hasLength(2));
    });
  });

  group('skills on a profile', () {
    test('are saved tidy, and stay when not given', () async {
      final b = LocalBackend();
      await b.registerWithEmail('Mina', 'mina@test.dev', 'secret1');
      await b.saveProfile(
        name: 'Mina',
        bio: 'Hi',
        skills: ['Flutter', ' flutter', 'Design'],
      );
      expect(b.currentUser?.skills, ['Flutter', 'Design']);
      await b.saveProfile(name: 'Mina R', bio: 'Hi');
      expect(b.currentUser?.skills, ['Flutter', 'Design']);
      final seen = await b.profileOf(b.currentUser!.uid);
      expect(seen?.skills, ['Flutter', 'Design']);
      await b.saveProfile(name: 'Mina R', bio: 'Hi', skills: const []);
      expect(b.currentUser?.skills, isEmpty);
    });

    test('the sample model reads known skills out of a resume', () async {
      final skills = await SampleAi(delay: Duration.zero).readSkills(
        text: 'Built apps with Flutter and Firebase. Enjoys public speaking.',
      );
      expect(skills, ['Flutter', 'Firebase', 'Public speaking']);
    });
  });
}
