/// The classroom plan: members, phases and the steps that link them.
library;

enum StepStatus { todo, doing, review, done }

/// What a step is. Most are work. A test or check point comes after a
/// phase: everyone in it takes their own mock test, or goes through their own
/// checklist, and marks only their own part done.
enum StepKind {
  work,
  test,
  check,
  both,

  /// The same work done by several people: one step between them, each
  /// marking their own part, done once everyone has.
  joint;

  static StepKind named(String? name) =>
      StepKind.values.firstWhere((k) => k.name == name, orElse: () => work);
}

/// What a step means to someone looking at it today, derived from its status,
/// its dependencies and the date.
enum Standing { done, review, doing, ready, waiting, blocked }

class Member {
  const Member({required this.id, required this.name});

  final String id;
  final String name;

  String get initials => name
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0])
      .take(2)
      .join()
      .toUpperCase();
}

class Phase {
  const Phase({required this.id, required this.title});

  final String id;
  final String title;
}

enum ResourceType { file, link, video, note }

/// A study material or working file attached to a step.
class StepResource {
  const StepResource({
    required this.type,
    required this.title,
    this.detail = '',
  });

  final ResourceType type;
  final String title;
  final String detail;
}

class ChecklistItem {
  const ChecklistItem({required this.title, this.done = false});

  final String title;
  final bool done;
}

class PlanStep {
  const PlanStep({
    required this.id,
    required this.phaseId,
    required this.ownerId,
    required this.title,
    required this.estimateHours,
    required this.start,
    required this.due,
    this.description = '',
    this.status = StepStatus.todo,
    this.dependsOn = const [],
    this.checklist = const [],
    this.resources = const [],
    this.skills = const [],
    this.comments = 0,
    this.newSuggestions = 0,
    this.newComments = 0,
    this.changedSinceVisit = false,
    this.order = 0,
    this.kind = StepKind.work,
    this.participants = const [],
    this.doneBy = const [],
    this.ticks = const {},
  });

  /// For a test or check point: what each person has ticked on their own
  /// checklist, by uid.
  final Map<String, List<String>> ticks;

  final StepKind kind;

  /// For a test or check point: the people who each have a part in it.
  final List<String> participants;

  /// Of [participants], those who have finished their part.
  final List<String> doneBy;

  /// A test or check point, or joint work: several people share it.
  bool get shared => kind != StepKind.work;

  /// A mock test or check point after a phase, rather than work.
  bool get isPoint =>
      kind == StepKind.test || kind == StepKind.check || kind == StepKind.both;

  bool doneFor(String uid) => doneBy.contains(uid);

  /// The status that matches who has finished their part.
  StepStatus get sharedStatus {
    final left = participants.where((u) => !doneBy.contains(u));
    if (participants.isNotEmpty && left.isEmpty) return StepStatus.done;
    return doneBy.isEmpty ? StepStatus.todo : StepStatus.doing;
  }

  final String id;
  final String phaseId;
  final String ownerId;
  final String title;
  final String description;
  final StepStatus status;
  final List<String> dependsOn;
  final double estimateHours;
  final DateTime start;
  final DateTime due;
  final List<ChecklistItem> checklist;
  final List<StepResource> resources;
  final List<String> skills;
  final int comments;
  final int newSuggestions;
  final int newComments;
  final bool changedSinceVisit;

  /// Where the step sits among its neighbours when the plan is loaded.
  final int order;

  int get badgeCount =>
      newSuggestions + newComments + (changedSinceVisit ? 1 : 0);

  int get checklistDone => checklist.where((c) => c.done).length;

  /// The first thing left to do in this step, if any.
  String? get nextChecklistItem {
    for (final item in checklist) {
      if (!item.done) return item.title;
    }
    return null;
  }

  PlanStep copyWith({
    String? phaseId,
    String? ownerId,
    String? title,
    String? description,
    StepStatus? status,
    List<String>? dependsOn,
    double? estimateHours,
    DateTime? start,
    DateTime? due,
    List<ChecklistItem>? checklist,
    List<String>? skills,
    int? newSuggestions,
    int? newComments,
    bool? changedSinceVisit,
    StepKind? kind,
    List<String>? participants,
    List<String>? doneBy,
    Map<String, List<String>>? ticks,
  }) {
    return PlanStep(
      id: id,
      phaseId: phaseId ?? this.phaseId,
      ownerId: ownerId ?? this.ownerId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      dependsOn: dependsOn ?? this.dependsOn,
      estimateHours: estimateHours ?? this.estimateHours,
      start: start ?? this.start,
      due: due ?? this.due,
      checklist: checklist ?? this.checklist,
      resources: resources,
      skills: skills ?? this.skills,
      comments: comments,
      newSuggestions: newSuggestions ?? this.newSuggestions,
      newComments: newComments ?? this.newComments,
      changedSinceVisit: changedSinceVisit ?? this.changedSinceVisit,
      order: order,
      kind: kind ?? this.kind,
      participants: participants ?? this.participants,
      doneBy: doneBy ?? this.doneBy,
      ticks: ticks ?? this.ticks,
    );
  }

  /// Whether two versions of a step would be stored the same.
  bool storedSameAs(PlanStep o) =>
      phaseId == o.phaseId &&
      ownerId == o.ownerId &&
      title == o.title &&
      description == o.description &&
      status == o.status &&
      estimateHours == o.estimateHours &&
      start == o.start &&
      due == o.due &&
      order == o.order &&
      _sameList(dependsOn, o.dependsOn) &&
      _sameList(skills, o.skills) &&
      kind == o.kind &&
      _sameList(participants, o.participants) &&
      _sameList(doneBy, o.doneBy) &&
      _sameTicks(ticks, o.ticks) &&
      _sameChecklist(checklist, o.checklist);
}

class Plan {
  Plan({
    required this.title,
    required this.members,
    required this.phases,
    required List<PlanStep> steps,
    required this.meId,
    required this.today,
  }) : steps = {for (final s in steps) s.id: s};

  final String title;
  final List<Member> members;
  final List<Phase> phases;
  final Map<String, PlanStep> steps;
  final String meId;
  final DateTime today;

  Member member(String id) => members.firstWhere((m) => m.id == id);
  Phase phase(String id) => phases.firstWhere((p) => p.id == id);

  Iterable<PlanStep> stepsIn(String phaseId) =>
      steps.values.where((s) => s.phaseId == phaseId);

  Plan withSteps(Iterable<PlanStep> next) => Plan(
    title: title,
    members: members,
    phases: phases,
    steps: next.toList(),
    meId: meId,
    today: today,
  );

  Plan replacing(PlanStep step) =>
      withSteps(steps.values.map((s) => s.id == step.id ? step : s));

  /// Late once its due day has passed. A step due today isn't late yet.
  bool isOverdue(PlanStep step) =>
      step.status != StepStatus.done &&
      step.due.isBefore(DateTime(today.year, today.month, today.day));

  /// Whether [need], which [step] comes after, still holds it back. A shared
  /// mock test or checklist holds someone back only until their own part is
  /// done: one person who hasn't taken the test doesn't stop everyone else.
  bool holdsBack(PlanStep step, PlanStep need) {
    if (need.status == StepStatus.done) return false;
    if (!need.isPoint) return true;
    final who = step.shared ? step.participants : [step.ownerId];
    return who.any((u) => need.participants.contains(u) && !need.doneFor(u));
  }

  Standing standing(PlanStep step) {
    switch (step.status) {
      case StepStatus.done:
        return Standing.done;
      case StepStatus.review:
        return Standing.review;
      case StepStatus.doing:
        return Standing.doing;
      case StepStatus.todo:
        final open = step.dependsOn
            .map((id) => steps[id])
            .whereType<PlanStep>()
            .where((d) => holdsBack(step, d));
        if (open.isEmpty) return Standing.ready;
        return open.any(isOverdue) ? Standing.blocked : Standing.waiting;
    }
  }

  /// Where [step] stands and why, in a sentence or two: what it waits for,
  /// what it came after, who is on it.
  String explain(PlanStep step) {
    String name(String uid) =>
        members.where((m) => m.id == uid).firstOrNull?.name ?? 'someone';
    String who(PlanStep s) => s.ownerId == meId ? 'you' : name(s.ownerId);
    String list(List<PlanStep> xs) {
      final named = [for (final x in xs.take(3)) '“${x.title}” (${who(x)})'];
      final more = xs.length > 3 ? ' and ${xs.length - 3} more' : '';
      if (named.length == 1) return '${named.single}$more';
      return '${named.sublist(0, named.length - 1).join(', ')} and '
          '${named.last}$more';
    }

    final needs = step.dependsOn.map((id) => steps[id]).whereType<PlanStep>();
    final open = needs.where((d) => holdsBack(step, d)).toList();
    final unblocks = dependents(step);
    final owner = step.ownerId == meId ? 'Yours' : '${name(step.ownerId)}’s';
    final String state = switch (standing(step)) {
      Standing.done =>
        needs.isEmpty
            ? 'Done.'
            : 'Done. It came after ${list(needs.toList())}.',
      Standing.review => 'Finished, and waiting for the master to approve it.',
      Standing.doing => 'In progress now.',
      Standing.ready =>
        needs.isEmpty
            ? 'Ready to start: it needs nothing first.'
            : needs.any((d) => d.status != StepStatus.done)
            // A shared test others are still taking: this person's part is in.
            ? 'Ready to start: ${step.ownerId == meId ? 'your' : 'their'} '
                  'part of ${list(needs.toList())} is done.'
            : 'Ready to start: ${list(needs.toList())} '
                  '${needs.length == 1 ? 'is' : 'are'} done.',
      Standing.waiting => 'Waiting for ${list(open)} to be finished first.',
      Standing.blocked =>
        'Held up: it needs ${list(open)}, and '
            '${open.length == 1 ? 'that is' : 'some are'} late.',
    };
    final part = step.shared && step.participants.isNotEmpty
        ? ' ${step.doneBy.length} of ${step.participants.length} have '
              'finished their part'
              '${step.participants.any((u) => !step.doneBy.contains(u)) ? ': waiting for ${[for (final u in step.participants)
                      if (!step.doneBy.contains(u)) u == meId ? 'you' : name(u)].join(', ')}' : ''}.'
        : '';
    final late = isOverdue(step) ? ' It’s past its due date.' : '';
    final next = step.status != StepStatus.done && unblocks.isNotEmpty
        ? ' Then ${list(unblocks)} can start.'
        : '';
    if (step.shared) {
      return '${state.replaceAll('In progress now.', 'Under way.')}$part$late$next'
          .trim();
    }
    return '$owner. $state$late$next';
  }

  /// Steps a soft lock should warn about: dependencies not yet done.
  List<PlanStep> openDependencies(PlanStep step) => step.dependsOn
      .map((id) => steps[id])
      .whereType<PlanStep>()
      .where((d) => holdsBack(step, d))
      .toList();

  /// Steps that became workable because [step] finished.
  List<PlanStep> dependents(PlanStep step) =>
      steps.values.where((s) => s.dependsOn.contains(step.id)).toList();

  /// The viewer's next available step: work in progress first, then whatever
  /// on the critical path is ready, then the earliest due.
  PlanStep? nextStepFor(String memberId) {
    final critical = criticalPath();
    final mine = steps.values.where((s) {
      if (s.ownerId != memberId) return false;
      // Their part of a shared step is in: the rest is for the others.
      if (s.shared && s.doneFor(memberId)) return false;
      final st = standing(s);
      return st == Standing.doing || st == Standing.ready;
    }).toList();
    if (mine.isEmpty) return null;
    int rank(PlanStep s) {
      if (s.status == StepStatus.doing) return 0;
      return critical.contains(s.id) ? 1 : 2;
    }

    mine.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.due.compareTo(b.due);
    });
    return mine.first;
  }

  /// A member's steps in the order they fall due: the course they walk.
  List<PlanStep> routeFor(String memberId) =>
      steps.values.where((s) => s.ownerId == memberId).toList()..sort((a, b) {
        final byDue = a.due.compareTo(b.due);
        return byDue != 0 ? byDue : a.start.compareTo(b.start);
      });

  /// The chain of unfinished steps with the most remaining hours: the one that
  /// decides the deadline.
  Set<String> criticalPath() {
    final memo = <String, double>{};
    final via = <String, String?>{};

    double remaining(PlanStep s) {
      final known = memo[s.id];
      if (known != null) return known;
      var best = 0.0;
      String? bestId;
      for (final id in s.dependsOn) {
        final dep = steps[id];
        if (dep == null || dep.status == StepStatus.done) continue;
        final hours = remaining(dep);
        if (hours > best) {
          best = hours;
          bestId = id;
        }
      }
      via[s.id] = bestId;
      return memo[s.id] = best + s.estimateHours;
    }

    PlanStep? end;
    var longest = 0.0;
    for (final s in steps.values) {
      if (s.status == StepStatus.done) continue;
      final hours = remaining(s);
      if (hours > longest) {
        longest = hours;
        end = s;
      }
    }

    final path = <String>{};
    String? cursor = end?.id;
    while (cursor != null) {
      path.add(cursor);
      cursor = via[cursor];
    }
    return path;
  }

  /// Whether making [stepId] depend on [dependencyId] would close a loop.
  bool wouldCycle(String stepId, String dependencyId) {
    if (stepId == dependencyId) return true;
    final seen = <String>{};
    final stack = [dependencyId];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (id == stepId) return true;
      if (seen.add(id)) stack.addAll(steps[id]?.dependsOn ?? const []);
    }
    return false;
  }

  double phaseProgress(String phaseId) {
    final inPhase = stepsIn(phaseId).toList();
    if (inPhase.isEmpty) return 0;
    return inPhase.where((s) => s.status == StepStatus.done).length /
        inPhase.length;
  }
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameChecklist(List<ChecklistItem> a, List<ChecklistItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].title != b[i].title || a[i].done != b[i].done) return false;
  }
  return true;
}

bool _sameTicks(Map<String, List<String>> a, Map<String, List<String>> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    final other = b[e.key];
    if (other == null || !_sameList(e.value, other)) return false;
  }
  return true;
}
