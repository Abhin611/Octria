/// Ofy's planning: a task in, a few short questions out, then a draft plan of
/// phases and steps for people to edit. Every AI feature goes through [Ai], so
/// the model behind it can be changed in one place.
library;

import 'dart:typed_data';

import '../data/models.dart';
import 'split.dart';

/// How many times one person may ask Ofy for something in a day. Gemini's free
/// tier is shared by everyone, so each person gets a fair share.
const int kAiCallsPerDay = 40;

/// What Ofy is asked to plan.
class TaskBrief {
  const TaskBrief({
    required this.title,
    required this.taskType,
    this.description = '',
    this.constraints = '',
    this.deadline,
    this.hoursPerWeek,
    this.individual = true,
    this.today,
    this.existing = const [],
    this.newPhasesAllowed = true,
    this.request = '',
    this.people = const [],
    this.linked = false,
    this.steps = const [],
    this.syllabus = '',
  });

  /// The official syllabus the plan must follow, as found on the web.
  final String syllabus;

  /// What the person asked Ofy for, in their own words: the plan they want,
  /// or what to add to the plan there is.
  final String request;

  /// Everyone in a group classroom, with what each does, such as
  /// ("Amy", "Back end"). Empty when it's just one person.
  final List<(String name, String role)> people;

  /// Whether the group works together: each takes a part, then teaches the
  /// others, so that together they all know all of it.
  final bool linked;

  /// The plan's steps as they are, so Ofy can see what's there, what's
  /// covered already, and where something new belongs.
  final List<ExistingStep> steps;

  /// The plan so far: each phase's title and its steps' titles. When it isn't
  /// empty, Ofy adds what's missing rather than starting again.
  final List<(String phase, List<String> steps)> existing;

  /// Whether Ofy may add phases, or only steps to the phases there are. Only
  /// masters and co-masters can add phases.
  final bool newPhasesAllowed;

  final String title;
  final String description;

  /// What the plan must respect, in the person's own words.
  final String constraints;
  final TaskType taskType;
  final DateTime? deadline;
  final double? hoursPerWeek;
  final bool individual;
  final DateTime? today;
}

/// A step already in the classroom, as Ofy is shown it. [ref] is a short id
/// such as e3, which new steps use to say where they fit.
class ExistingStep {
  const ExistingStep({
    required this.ref,
    required this.phase,
    required this.title,
    this.done = false,
    this.owner = '',
    this.needs = const [],
  });

  final String ref;
  final String phase;
  final String title;
  final bool done;
  final String owner;

  /// Refs of the steps it needs first.
  final List<String> needs;
}

/// Something asked for that the plan already has: [ref] is that step.
class Covered {
  const Covered(this.what, this.ref);

  final String what;
  final String ref;
}

/// A short question Ofy asks before planning, with answers to tap.
class FollowUp {
  const FollowUp(this.question, {this.choices = const []});

  final String question;

  /// Suggested answers. The person can always write their own.
  final List<String> choices;
}

/// One step in a draft. [key] links steps together before they have ids.
class DraftStep {
  const DraftStep({
    required this.key,
    required this.title,
    required this.hours,
    this.description = '',
    this.needs = const [],
    this.checklist = const [],
    this.skills = const [],
    this.owner = '',
    this.neededBy = const [],
  });

  /// Who does it, by name. Empty for whoever is drafting; `everyone` for a
  /// step the whole group does together, which becomes one step each.
  final String owner;

  /// Steps already in the plan that should now wait for this one, by ref.
  final List<String> neededBy;

  DraftStep copyWith({
    String? key,
    String? title,
    List<String>? needs,
    String? owner,
    List<String>? neededBy,
  }) => DraftStep(
    key: key ?? this.key,
    title: title ?? this.title,
    hours: hours,
    description: description,
    needs: needs ?? this.needs,
    checklist: checklist,
    skills: skills,
    owner: owner ?? this.owner,
    neededBy: neededBy ?? this.neededBy,
  );

  final String key;
  final String title;
  final String description;

  /// Estimated hours of work.
  final double hours;

  /// Keys of earlier steps this one needs first.
  final List<String> needs;
  final List<String> checklist;
  final List<String> skills;
}

class DraftPhase {
  const DraftPhase({required this.title, required this.steps, this.after});

  final String title;
  final List<DraftStep> steps;

  /// For a new phase in a plan that has phases: the existing phase it comes
  /// after, or the empty string to come first. Null puts it at the end.
  final String? after;
}

/// A whole draft, ready to look over and change before it's added.
class DraftPlan {
  const DraftPlan({
    required this.phases,
    this.summary = '',
    this.covered = const [],
  });

  final List<DraftPhase> phases;

  /// What was asked for that the plan already has.
  final List<Covered> covered;

  /// A step for `everyone` stays one joint step that sits between the people,
  /// each marking their own part. With [split], it becomes one step each
  /// instead, and steps that needed it need all of them.
  DraftPlan forPeople(List<String> names, {bool split = false}) {
    if (names.length < 2 || !split) return this;
    final copies = <String, List<String>>{};
    for (final s in steps) {
      if (s.owner.trim().toLowerCase() == 'everyone') {
        copies[s.key] = [for (var i = 0; i < names.length; i++) '${s.key}~$i'];
      }
    }
    if (copies.isEmpty) return this;
    List<String> needsOf(List<String> needs) => [
      for (final n in needs) ...(copies[n] ?? [n]),
    ];
    return DraftPlan(
      summary: summary,
      covered: covered,
      phases: [
        for (final ph in phases)
          DraftPhase(
            title: ph.title,
            after: ph.after,
            steps: [
              for (final s in ph.steps)
                if (copies[s.key] case final keys?)
                  for (var i = 0; i < names.length; i++)
                    s.copyWith(
                      key: keys[i],
                      owner: names[i],
                      needs: needsOf(s.needs),
                    )
                else
                  s.copyWith(needs: needsOf(s.needs)),
            ],
          ),
      ],
    );
  }

  /// A sentence or two on how the plan is shaped.
  final String summary;

  Iterable<DraftStep> get steps => phases.expand((p) => p.steps);
  double get hours => steps.fold(0, (sum, s) => sum + s.hours);

  /// Reads a draft from what a model returned, keeping it sane: limited in
  /// size, every estimate sensible, and every need pointing at an earlier
  /// step, so the plan can never loop.
  static DraftPlan fromJson(
    Map<String, Object?> json, {
    Set<String> existing = const {},
  }) {
    String text(Object? v, [int max = 200]) {
      final s = (v is String ? v : '').trim();
      return s.length > max ? s.substring(0, max) : s;
    }

    List<String> texts(Object? v, int count, [int max = 120]) => [
      for (final x in (v is List ? v : const []).take(count))
        if (text(x, max).isNotEmpty) text(x, max),
    ];

    final seen = <String>{};
    final phases = <DraftPhase>[];
    var n = 0;
    for (final raw
        in (json['phases'] is List ? json['phases'] as List : const []).take(
          8,
        )) {
      if (raw is! Map) continue;
      final title = text(raw['title'], 80);
      final steps = <DraftStep>[];
      for (final s
          in (raw['steps'] is List ? raw['steps'] as List : const []).take(
            12,
          )) {
        if (s is! Map || n >= 60) continue;
        final stepTitle = text(s['title']);
        if (stepTitle.isEmpty) continue;
        n++;
        var key = text(s['key'], 40);
        if (key.isEmpty || seen.contains(key) || existing.contains(key)) {
          key = 'n$n';
        }
        final hours = (s['hours'] as num?)?.toDouble() ?? 2;
        steps.add(
          DraftStep(
            key: key,
            title: stepTitle,
            description: text(s['description'], 1000),
            hours: hours.isFinite ? hours.clamp(0.5, 80).toDouble() : 2,
            needs: [
              for (final k in texts(s['needs'], 12, 40))
                if (seen.contains(k) || existing.contains(k)) k,
            ],
            checklist: texts(s['checklist'], 8),
            skills: texts(s['skills'], 6, 40),
            owner: text(s['owner'], 80),
            neededBy: [
              for (final k in texts(s['neededBy'], 12, 40))
                if (existing.contains(k)) k,
            ],
          ),
        );
        seen.add(key);
      }
      if (steps.isNotEmpty) {
        phases.add(
          DraftPhase(
            title: title.isEmpty ? 'Phase ${phases.length + 1}' : title,
            steps: steps,
            after: raw['after'] is String ? text(raw['after'], 80) : null,
          ),
        );
      }
    }
    final covered = json['covered'] is List
        ? json['covered'] as List
        : const [];
    return DraftPlan(
      phases: phases,
      summary: text(json['summary'], 400),
      covered: [
        for (final c in covered.take(12))
          if (c is Map && existing.contains(text(c['step'], 40)))
            Covered(text(c['what'], 200), text(c['step'], 40)),
      ],
    );
  }
}

/// Something went wrong asking Ofy, said plainly.
class AiFailure implements Exception {
  const AiFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A question to Ofy in the chat, with what's on screen.
class OfyQuestion {
  const OfyQuestion({
    required this.text,
    this.screen = 'app',
    this.context = '',
    this.actions = const [],
    this.history = const [],
    this.voice = false,
    this.picture,
    this.pictureMime = 'image/png',
  });

  /// A screenshot or photo the person is asking about.
  final Uint8List? picture;
  final String pictureMime;

  final String text;

  /// Which screen it was asked from, such as `classroom`.
  final String screen;

  /// What's on that screen, in short lines.
  final String context;

  /// What Ofy can do there: id, what it does, what it needs.
  final List<(String id, String description, List<String> params)> actions;

  /// The last few messages, oldest first: (from the person, text).
  final List<(bool, String)> history;

  /// Asked by voice: a guide on screen is better than a long answer.
  final bool voice;
}

/// Ofy's reply in the chat.
class OfyAnswer {
  const OfyAnswer(this.answer, {this.howTo, this.action, this.args = const {}});

  final String answer;

  /// A guide from the app guide that shows how, by its id.
  final String? howTo;

  /// Something to do on this screen, by its id, with what it needs.
  final String? action;
  final Map<String, String> args;
}

/// The searches Google suggests alongside an answer it helped with, read
/// from the chips it sends. Google asks that these be shown with the answer.
List<String> searchSuggestions(String renderedHtml) {
  String plain(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', '\'')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
  final seen = <String>{};
  return [
    for (final m in RegExp(
      r'<a\b[^>]*class="[^"]*chip[^"]*"[^>]*>(.*?)</a>',
      dotAll: true,
    ).allMatches(renderedHtml))
      if (plain(m.group(1)!).isNotEmpty && seen.add(plain(m.group(1)!)))
        plain(m.group(1)!),
  ].take(6).toList();
}

/// Where a Google search for [query] lives.
Uri googleSearchLink(String query) =>
    Uri.https('www.google.com', '/search', {'q': query});

/// What Ofy is asked to find material for: one step.
class ResourceBrief {
  const ResourceBrief({
    required this.subject,
    required this.step,
    this.description = '',
    this.have = const [],
  });

  /// The classroom's task.
  final String subject;
  final String step;
  final String description;

  /// Links the step already has, so they aren't found again.
  final List<String> have;
}

/// One thing worth reading or watching for a step.
class FoundResource {
  const FoundResource({
    required this.title,
    required this.url,
    this.video = false,
    this.why = '',
    this.confirmed = false,
  });

  final String title;
  final String url;
  final bool video;

  /// Why it fits the step, in a sentence.
  final String why;

  /// Whether the site was among those the search really returned. A link
  /// that wasn't may not exist.
  final bool confirmed;
}

/// What Ofy found on the web for a step.
class ResourceFind {
  const ResourceFind({required this.resources, this.searches = const []});

  final List<FoundResource> resources;

  /// Google's suggested searches for the same thing.
  final List<String> searches;

  static String _site(String host) {
    final site = host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
    // YouTube's short links are YouTube.
    return site == 'youtu.be' ? 'youtube.com' : site;
  }

  /// Reads lines of `title | https link | kind | why`. Only https links are
  /// kept, each once, never ones in [have]. A link counts as confirmed when
  /// its site is among [grounded], the sites the search returned. Confirmed
  /// ones come first.
  static ResourceFind parse(
    String text, {
    Iterable<String> grounded = const [],
    Iterable<String> have = const [],
    List<String> searches = const [],
  }) {
    final sites = {for (final g in grounded) _site(g)}..remove('');
    final skip = {for (final h in have) h.trim().toLowerCase()};
    final seen = <String>{};
    final found = <FoundResource>[];
    for (final line in text.split('\n')) {
      final parts = line.split('|').map((p) => p.trim()).toList();
      if (parts.length < 2) continue;
      final at = parts.indexWhere((p) => p.startsWith('https://'));
      if (at < 1) continue;
      final url = parts[at].replaceAll(RegExp(r'[)\].,]+$'), '');
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasAuthority || !uri.host.contains('.')) continue;
      if (skip.contains(url.toLowerCase()) || !seen.add(url.toLowerCase())) {
        continue;
      }
      final title = parts[at - 1]
          .replaceFirst(RegExp(r'^[-*\d.\s]+'), '')
          .replaceAll('*', '')
          .trim();
      if (title.isEmpty) continue;
      final site = _site(uri.host);
      final kind = parts.length > at + 1 ? parts[at + 1].toLowerCase() : '';
      found.add(
        FoundResource(
          title: title.length > 120 ? title.substring(0, 120) : title,
          url: url,
          video:
              kind.contains('video') ||
              const ['youtube.com', 'youtu.be', 'vimeo.com'].contains(site),
          why: parts.length > at + 2
              ? parts.sublist(at + 2).join(' | ')
              : (parts.length > at + 1 &&
                        !kind.contains('video') &&
                        kind.length > 12
                    ? parts[at + 1]
                    : ''),
          confirmed: sites.any(
            (s) => site == s || site.endsWith('.$s') || s.endsWith('.$site'),
          ),
        ),
      );
    }
    final ordered = [
      ...found.where((r) => r.confirmed),
      ...found.where((r) => !r.confirmed),
    ];
    return ResourceFind(
      resources: ordered.take(6).toList(),
      searches: searches,
    );
  }
}

/// A published syllabus Ofy looked up, and where it came from.
class Research {
  const Research({
    required this.syllabus,
    this.sources = const [],
    this.searches = const [],
  });

  /// Google's suggested searches for the same thing.
  final List<String> searches;

  /// Its units and topics, in order.
  final String syllabus;

  /// Pages and files worth keeping: (title, https link).
  final List<(String, String)> sources;

  bool get isEmpty => syllabus.trim().isEmpty;
}

/// Whether what someone asked for names a published syllabus, course or
/// exam worth looking up.
bool namesASyllabus(String text) => RegExp(
  r'\b(syllabus|curriculum|cbse|icse|isc|ncert|igcse|gcse|a[- ]?levels?|'
  r'ib|ap|sat|act|jee|neet|upsc|gate|board exams?|course|module|exam '
  r'board|state board|class 1[0-2]|grade 1[0-2]|\+2|plus two|12th|11th|10th)\b',
  caseSensitive: false,
).hasMatch(text);

/// How hard a practice set, mock test or interview is.
enum QuizLevel {
  easy('Easier', 'easy'),
  standard('Standard', ''),
  hard('Harder', 'hard');

  const QuizLevel(this.label, this.stored);

  final String label;

  /// How it's kept with a result; empty for the usual level.
  final String stored;

  static QuizLevel of(String stored) =>
      values.where((l) => l.stored == stored).firstOrNull ?? standard;
}

/// An open question in a mock interview: answered in the person's own words.
class InterviewQuestion {
  const InterviewQuestion({required this.question, this.lookFor = ''});

  final String question;

  /// What a strong answer covers, shown after it's marked.
  final String lookFor;
}

/// A mock interview Ofy wrote: a few open questions.
class Interview {
  const Interview({required this.title, required this.questions});

  final String title;
  final List<InterviewQuestion> questions;

  static Interview fromJson(Map<String, Object?> json, String fallbackTitle) {
    String text(Object? v, int max) {
      final s = (v is String ? v : '').trim();
      return s.length > max ? s.substring(0, max) : s;
    }

    final title = text(json['title'], 80);
    return Interview(
      title: title.isEmpty ? fallbackTitle : title,
      questions: [
        // Five at most: each is marked out of ten, and a result holds fifty.
        for (final q
            in (json['questions'] is List
                    ? json['questions'] as List
                    : const [])
                .take(5))
          if (q is Map && text(q['question'], 600).isNotEmpty)
            InterviewQuestion(
              question: text(q['question'], 600),
              lookFor: text(q['lookFor'], 600),
            ),
      ],
    );
  }
}

/// How one interview answer went.
class AnswerReview {
  const AnswerReview({required this.score, this.feedback = ''});

  /// Out of ten.
  final int score;
  final String feedback;
}

/// Ofy's marking of a whole mock interview.
class InterviewReview {
  const InterviewReview({required this.answers, this.summary = ''});

  /// One for each question, in order.
  final List<AnswerReview> answers;
  final String summary;

  int get score => answers.fold(0, (sum, a) => sum + a.score);
  int get outOf => answers.length * 10;

  /// Exactly [count] reviews, whatever came back: a missing one scores
  /// nothing, and scores stay between nought and ten.
  static InterviewReview fromJson(Map<String, Object?> json, int count) {
    String text(Object? v, int max) {
      final s = (v is String ? v : '').trim();
      return s.length > max ? s.substring(0, max) : s;
    }

    final got = json['answers'] is List ? json['answers'] as List : const [];
    return InterviewReview(
      summary: text(json['summary'], 500),
      answers: [
        for (var i = 0; i < count; i++)
          i < got.length && got[i] is Map
              ? AnswerReview(
                  score: (((got[i] as Map)['score'] as num?)?.round() ?? 0)
                      .clamp(0, 10),
                  feedback: text((got[i] as Map)['feedback'], 500),
                )
              : const AnswerReview(score: 0, feedback: 'Not marked.'),
      ],
    );
  }
}

/// One multiple-choice question.
class QuizQuestion {
  const QuizQuestion({
    required this.question,
    required this.choices,
    required this.answer,
    this.explain = '',
  });

  final String question;
  final List<String> choices;

  /// Which of [choices] is right.
  final int answer;
  final String explain;
}

/// A practice set or mock test that Ofy wrote.
class Quiz {
  const Quiz({required this.title, required this.questions});

  final String title;
  final List<QuizQuestion> questions;

  static Quiz fromJson(Map<String, Object?> json, String fallbackTitle) {
    String text(Object? v, int max) {
      final s = (v is String ? v : '').trim();
      return s.length > max ? s.substring(0, max) : s;
    }

    final questions = <QuizQuestion>[];
    for (final q
        in (json['questions'] is List ? json['questions'] as List : const [])
            .take(20)) {
      if (q is! Map) continue;
      final choices = [
        for (final x
            in (q['choices'] is List ? q['choices'] as List : const []).take(5))
          if (text(x, 300).isNotEmpty) text(x, 300),
      ];
      final answer = (q['answer'] as num?)?.toInt() ?? -1;
      if (text(q['question'], 600).isEmpty ||
          choices.length < 2 ||
          answer < 0 ||
          answer >= choices.length) {
        continue;
      }
      questions.add(
        QuizQuestion(
          question: text(q['question'], 600),
          choices: choices,
          answer: answer,
          explain: text(q['explain'], 600),
        ),
      );
    }
    final title = text(json['title'], 120);
    return Quiz(
      title: title.isEmpty ? fallbackTitle : title,
      questions: questions,
    );
  }
}

/// What a practice set or mock test covers.
class QuizBrief {
  const QuizBrief({
    required this.subject,
    required this.topics,
    this.mock = false,
    this.count = 8,
    this.syllabus = '',
    this.focus = const [],
    this.level = QuizLevel.standard,
  });

  /// How hard the questions are.
  final QuizLevel level;

  /// Questions this person got wrong before on the same thing, so the new
  /// set comes back to those ideas.
  final List<String> focus;

  /// The classroom's task.
  final String subject;

  /// The steps it covers: titles, with descriptions where there are some.
  final List<String> topics;

  /// A mock test: exam style and a little harder, rather than practice.
  final bool mock;
  final int count;
  final String syllabus;
}

/// What Ofy does with a Kanvas board.
enum BoardTask {
  summary('Summarise the board', 'Ofy is reading the board…'),
  ideas('Suggest what’s missing', 'Ofy is thinking about what’s missing…'),
  steps('Turn it into steps', 'Ofy is working out the steps…');

  const BoardTask(this.label, this.waiting);

  final String label;
  final String waiting;
}

/// A board for Ofy to help with: what's written on it.
class BoardBrief {
  const BoardBrief({
    required this.title,
    required this.lines,
    required this.task,
  });

  final String title;

  /// The board's words, one thing per line.
  final List<String> lines;
  final BoardTask task;
}

/// Ofy's help with a board: a short summary, and key points, ideas or steps
/// depending on what was asked.
class BoardHelp {
  const BoardHelp({this.summary = '', this.items = const []});

  final String summary;
  final List<String> items;

  bool get isEmpty => summary.trim().isEmpty && items.isEmpty;

  static BoardHelp fromJson(Map<String, Object?> json) {
    String text(Object? v, int max) {
      final s = (v is String ? v : '').trim();
      return s.length > max ? s.substring(0, max) : s;
    }

    final seen = <String>{};
    return BoardHelp(
      summary: text(json['summary'], 600),
      items: [
        for (final i
            in (json['items'] is List ? json['items'] as List : const []).take(
              12,
            ))
          if (text(i, 160).isNotEmpty && seen.add(text(i, 160).toLowerCase()))
            text(i, 160),
      ],
    );
  }
}

/// Work to share out between people, for Ofy to say who should take what.
class SplitBrief {
  const SplitBrief({
    required this.subject,
    required this.people,
    required this.steps,
  });

  /// The classroom's task.
  final String subject;
  final List<Person> people;

  /// The steps that haven't started.
  final List<SplitStep> steps;

  /// Keeps only assignments of steps there are to people there are, each
  /// step once. People are matched by name, whatever the capitals.
  List<Assignment> read(Map<String, Object?> json) {
    String text(Object? v, int max) {
      final s = (v is String ? v : '').trim();
      return s.length > max ? s.substring(0, max) : s;
    }

    final byName = {for (final p in people) p.name.toLowerCase(): p};
    final refs = {for (final (i, s) in steps.indexed) 's${i + 1}': s};
    final seen = <String>{};
    return [
      for (final a
          in (json['assignments'] is List
                  ? json['assignments'] as List
                  : const [])
              .take(200))
        if (a is Map)
          if (refs[text(a['step'], 20)] case final step?)
            if (byName[text(a['person'], 80).toLowerCase()] case final who?)
              if (seen.add(step.id))
                Assignment(
                  stepId: step.id,
                  toId: who.id,
                  why: text(a['why'], 200),
                ),
    ];
  }
}

/// A plan that no longer fits its deadline, for Ofy to say what should give.
class ReplanBrief {
  const ReplanBrief({
    required this.subject,
    required this.daysOver,
    required this.hoursPerWeek,
    required this.steps,
    this.deadline,
    this.constraints = '',
  });

  /// The classroom's task.
  final String subject;
  final DateTime? deadline;

  /// How many days past the deadline the plan now ends.
  final int daysOver;
  final double hoursPerWeek;
  final String constraints;

  /// What's still to do.
  final List<ReplanStep> steps;
}

/// One unfinished step, as Ofy is shown it.
class ReplanStep {
  const ReplanStep({
    required this.ref,
    required this.title,
    required this.phase,
    required this.hours,
    this.owner = '',
    this.started = false,
    this.neededBy = 0,
    this.point = false,
  });

  final String ref;
  final String title;
  final String phase;
  final double hours;
  final String owner;
  final bool started;

  /// How many other steps wait for this one.
  final int neededBy;

  /// A shared mock test or checklist, which shouldn't be cut.
  final bool point;
}

/// One change Ofy suggests to make a plan fit: give a step fewer hours, or
/// leave it out.
class Cut {
  const Cut({required this.ref, required this.why, this.hours});

  final String ref;

  /// The step's new hours, or null to leave it out altogether.
  final double? hours;
  final String why;

  bool get drops => hours == null;
}

/// What Ofy would change so the plan fits.
class ReplanAdvice {
  const ReplanAdvice({required this.note, required this.cuts});

  /// A sentence or two on the thinking.
  final String note;
  final List<Cut> cuts;

  /// Keeps only what makes sense: steps that exist, shorter hours that really
  /// are shorter, and nothing that leaves a shared point or a step others
  /// wait for out of the plan.
  static ReplanAdvice fromJson(Map<String, Object?> json, ReplanBrief brief) {
    String text(Object? v, int max) {
      final s = (v is String ? v : '').trim();
      return s.length > max ? s.substring(0, max) : s;
    }

    final known = {for (final s in brief.steps) s.ref: s};
    final seen = <String>{};
    final cuts = <Cut>[];
    for (final c
        in (json['changes'] is List ? json['changes'] as List : const []).take(
          40,
        )) {
      if (c is! Map) continue;
      final step = known[text(c['step'], 40)];
      if (step == null || !seen.add(step.ref)) continue;
      final why = text(c['why'], 240);
      if (text(c['change'], 20).toLowerCase() == 'drop') {
        if (step.point || step.neededBy > 0 || step.started) continue;
        cuts.add(Cut(ref: step.ref, why: why));
        continue;
      }
      final hours = (c['hours'] as num?)?.toDouble();
      if (hours == null || step.point) continue;
      // To the nearest half hour, and never to nothing.
      final to = ((hours * 2).round() / 2).clamp(0.5, step.hours);
      if (to >= step.hours) continue;
      cuts.add(Cut(ref: step.ref, why: why, hours: to.toDouble()));
    }
    return ReplanAdvice(note: text(json['note'], 400), cuts: cuts);
  }
}

/// Ofy's model. [GeminiAi] in the real app; [SampleAi] for tests, the demo
/// and running without Firebase.
abstract class Ai {
  /// What to shorten or leave out so a late plan fits its deadline again.
  Future<ReplanAdvice> advise(ReplanBrief brief);

  /// Reads a Kanvas board and summarises it, suggests what's missing, or
  /// turns it into steps.
  Future<BoardHelp> helpWithBoard(BoardBrief brief);

  /// Who should take each step, going by everyone's skills and roles.
  Future<List<Assignment>> splitBySkills(SplitBrief brief);

  /// The skills a resume or a description of someone shows: from [text], or
  /// from a [file] such as a PDF, of type [mime].
  Future<List<String>> readSkills({
    String text = '',
    Uint8List? file,
    String mime = '',
  });

  /// Answers a question in Ofy's chat, and may offer a guide or an action.
  Future<OfyAnswer> chat(OfyQuestion question);

  /// Up to five short questions that would make the plan better.
  Future<List<FollowUp>> followUps(TaskBrief brief);

  /// A draft plan for [brief], using the answers to the questions.
  Future<DraftPlan> draftPlan(
    TaskBrief brief,
    List<(String question, String answer)> answers,
  );

  /// Looks up the published syllabus [brief] follows, on the web. Null when
  /// there isn't one to find.
  Future<Research?> research(TaskBrief brief);

  /// Searches the web for things worth reading or watching for one step.
  Future<ResourceFind> findResources(ResourceBrief brief);

  /// Writes a practice set or mock test.
  Future<Quiz> makeQuiz(QuizBrief brief);

  /// Writes a mock interview: a few open questions on the same topics.
  Future<Interview> makeInterview(QuizBrief brief);

  /// Marks the answers to a mock interview, each out of ten, with what
  /// would have made it stronger.
  Future<InterviewReview> reviewInterview(
    QuizBrief brief,
    List<(InterviewQuestion question, String answer)> answers,
  );
}
