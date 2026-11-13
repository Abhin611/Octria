/// Sharing work out by skill: each step that hasn't started goes to whoever's
/// skills fit it best, with the hours kept even between people.
library;

/// Someone work can go to.
class Person {
  const Person({
    required this.id,
    required this.name,
    this.role = '',
    this.skills = const [],
  });

  final String id;
  final String name;

  /// What they do in the group, such as "Front end".
  final String role;
  final List<String> skills;
}

/// A step to give to someone.
class SplitStep {
  const SplitStep({
    required this.id,
    required this.title,
    required this.hours,
    this.skills = const [],
    this.ownerId = '',
  });

  final String id;
  final String title;
  final double hours;

  /// What the step calls for.
  final List<String> skills;

  /// Who has it now.
  final String ownerId;
}

/// Who a step should go to, and why.
class Assignment {
  const Assignment({required this.stepId, required this.toId, this.why = ''});

  final String stepId;
  final String toId;
  final String why;
}

/// Tidies a list of skills: trimmed, no doubles whatever the capitals, none
/// too long, and no more than [most].
List<String> cleanSkills(Iterable<String> raw, {int most = 25}) {
  final seen = <String>{};
  return [
    for (final s in raw)
      if (s.trim().isNotEmpty && seen.add(s.trim().toLowerCase()))
        s.trim().length > 40 ? s.trim().substring(0, 40) : s.trim(),
  ].take(most).toList();
}

/// Skills typed as one line: split at commas, semicolons and new lines.
List<String> skillsFromText(String text) =>
    cleanSkills(text.split(RegExp(r'[,;\n]')));

final _word = RegExp(r'[a-z0-9+#.]+');

Set<String> _words(String text) => {
  for (final m in _word.allMatches(text.toLowerCase()))
    if (m.group(0)!.length >= 2) m.group(0)!,
};

/// The person's skills that [step] calls for: by its own skills first, then
/// by the words in its title. "Flutter" fits "Flutter widgets"; "UI" doesn't
/// fit "build".
List<String> skillsThatFit(SplitStep step, Person person) {
  final wanted = [for (final s in step.skills) s.toLowerCase().trim()];
  final title = _words(step.title);
  final fits = <String>[];
  for (final skill in [
    ...person.skills,
    if (person.role.isNotEmpty) person.role,
  ]) {
    final have = skill.toLowerCase().trim();
    if (have.isEmpty) continue;
    final parts = _words(have);
    final bySkill = wanted.any(
      (w) =>
          w == have ||
          (w.length >= 3 &&
              have.length >= 3 &&
              (_words(w).containsAll(parts) || parts.containsAll(_words(w)))),
    );
    // Every word of the skill appears in the title, as whole words.
    final byTitle = parts.isNotEmpty && title.containsAll(parts);
    if (bySkill || byTitle) fits.add(skill.trim());
  }
  return fits;
}

/// Gives each of [steps] to one of [people]. A better fit of skills wins;
/// between equal fits it goes to whoever has the fewest hours so far, and
/// then to whoever has it already. [load] is the hours each person carries
/// before these steps, by id.
List<Assignment> matchBySkills(
  List<SplitStep> steps,
  List<Person> people, {
  Map<String, double> load = const {},
}) {
  if (people.isEmpty) return const [];
  final hours = {for (final p in people) p.id: load[p.id] ?? 0.0};
  final out = <Assignment>[];
  for (final step in steps) {
    Person? best;
    var bestFit = const <String>[];
    for (final p in people) {
      final fit = skillsThatFit(step, p);
      final better =
          best == null ||
          fit.length > bestFit.length ||
          (fit.length == bestFit.length &&
              (hours[p.id]! < hours[best.id]! - 0.01 ||
                  ((hours[p.id]! - hours[best.id]!).abs() <= 0.01 &&
                      p.id == step.ownerId)));
      if (better) {
        best = p;
        bestFit = fit;
      }
    }
    hours[best!.id] = hours[best.id]! + step.hours;
    out.add(
      Assignment(
        stepId: step.id,
        toId: best.id,
        why: bestFit.isNotEmpty
            ? 'Fits ${bestFit.take(3).join(', ')}'
            : best.id == step.ownerId
            ? 'No skill stands out, so it stays where it is'
            : 'No skill stands out; ${best.name} has the fewest hours',
      ),
    );
  }
  return out;
}
