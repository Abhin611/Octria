/// The classroom plan: members, phases and the steps that link them.
library;

enum StepStatus { todo, doing, review, done }

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
  });

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

  bool isOverdue(PlanStep step) =>
      step.status != StepStatus.done && step.due.isBefore(today);

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
            .where((d) => d.status != StepStatus.done);
        if (open.isEmpty) return Standing.ready;
        return open.any(isOverdue) ? Standing.blocked : Standing.waiting;
    }
  }

  /// Steps a soft lock should warn about: dependencies not yet done.
  List<PlanStep> openDependencies(PlanStep step) => step.dependsOn
      .map((id) => steps[id])
      .whereType<PlanStep>()
      .where((d) => d.status != StepStatus.done)
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
