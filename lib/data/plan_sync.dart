import 'dart:async';

import 'package:flutter/foundation.dart';

import '../graph/plan_controller.dart';
import '../model/plan.dart';
import 'backend.dart';
import 'models.dart';

/// Turns a stored classroom into the plan the graph draws.
Plan planFrom(ClassroomState state, String meId, DateTime today) => Plan(
  title: state.classroom.title,
  members: [for (final m in state.members) Member(id: m.uid, name: m.name)],
  phases: [for (final p in state.phases) Phase(id: p.id, title: p.title)],
  // A step whose owner has left still needs a lane to sit in.
  steps: [
    for (final s in state.steps)
      state.members.any((m) => m.uid == s.ownerId)
          ? s
          : s.copyWith(ownerId: state.classroom.masterUid),
  ],
  meId: meId,
  today: today,
);

/// What this person should hear about on returning: others' changes to their
/// work, and steps of theirs that something finishing has now unblocked.
List<ActivityEntry> awayNews(
  List<ActivityEntry> entries,
  String me,
  Iterable<PlanStep> steps,
) {
  final mineNeed = {
    for (final s in steps)
      if (s.ownerId == me) ...s.dependsOn,
  };
  return entries.where((e) {
    if (e.actorUid == me) return false;
    if (e.affectsUid == me) return true;
    final finished =
        e.kind == ActivityKind.stepFinished ||
        e.kind == ActivityKind.stepApproved;
    return finished && mineNeed.contains(e.targetId);
  }).toList();
}

/// Keeps one open classroom and its stored copy the same. Edits made on screen
/// go through the same [PlanController] as before; this notices what changed,
/// saves it and logs it, and brings other people's changes in.
class PlanSync {
  PlanSync({
    required this.backend,
    required this.classroomId,
    required this.controller,
    required this.onRefused,
    required this.onState,
  }) {
    controller.addListener(_onLocalChange);
    _subscription = backend
        .watchClassroom(classroomId)
        .listen(_onStored, onError: (Object e) => onRefused('$e'));
  }

  final Backend backend;
  final String classroomId;
  final PlanController controller;

  /// A change didn't go through, and the plan has gone back to the stored copy.
  final ValueChanged<String> onRefused;
  final ValueChanged<ClassroomState> onState;

  late final StreamSubscription<ClassroomState> _subscription;
  ClassroomState? _state;
  Map<String, PlanStep> _stored = const {};
  var _applying = false;
  var _disposed = false;
  Set<String> _changed = const {};

  /// Marks steps with a badge until the classroom is next opened.
  void showChanged(Set<String> ids) {
    _changed = ids;
    final state = _state;
    if (state == null) return;
    _applying = true;
    controller.adopt(_planFor(state));
    _applying = false;
  }

  Plan _planFor(ClassroomState state) {
    final plan = planFrom(state, _me, DateTime.now());
    if (_changed.isEmpty) return plan;
    return plan.withSteps(
      plan.steps.values.map(
        (s) =>
            _changed.contains(s.id) ? s.copyWith(changedSinceVisit: true) : s,
      ),
    );
  }

  Classroom? get classroom => _state?.classroom;
  ClassroomState? get state => _state;
  String get _me => backend.currentUser?.uid ?? '';

  void _onStored(ClassroomState state) {
    if (_disposed) return;
    final first = _state == null;
    _state = state;
    _stored = {for (final s in state.steps) s.id: s};
    final next = _planFor(state);
    _applying = true;
    if (first) {
      controller.replacePlan(next);
    } else {
      controller.adopt(next);
    }
    _applying = false;
    onState(state);
  }

  /// Anything in the plan that differs from what's stored was just edited here.
  void _onLocalChange() {
    if (_applying || _state == null) return;
    final plan = controller.plan;
    for (final step in plan.steps.values) {
      final before = _stored[step.id];
      if (before != null && before.storedSameAs(step)) continue;
      // A step whose owner left is shown under the master, but isn't an edit.
      if (before != null && !_shownOnlyDiffers(before, step)) {
        _send(step, before);
      } else if (before == null) {
        _send(step, null);
      }
    }
    for (final id in _stored.keys.toList()) {
      if (!plan.steps.containsKey(id)) _remove(_stored[id]!);
    }
  }

  bool _shownOnlyDiffers(PlanStep before, PlanStep shown) {
    final state = _state!;
    final ownerGone = !state.members.any((m) => m.uid == before.ownerId);
    return ownerGone &&
        shown.ownerId == state.classroom.masterUid &&
        before.copyWith(ownerId: shown.ownerId).storedSameAs(shown);
  }

  void _send(PlanStep step, PlanStep? before) {
    _stored = {..._stored, step.id: step};
    _guard(backend.saveStep(classroomId, step));
    final entry = describeChange(
      before: before,
      after: step,
      actorUid: _me,
      nameOf: _nameOf,
      id: backend.newId(),
    );
    if (entry != null) _guard(backend.logActivity(classroomId, entry));
  }

  void _remove(PlanStep step) {
    _stored = {..._stored}..remove(step.id);
    _guard(backend.deleteStep(classroomId, step.id));
    _guard(
      backend.logActivity(
        classroomId,
        ActivityEntry(
          id: backend.newId(),
          actorUid: _me,
          kind: ActivityKind.stepRemoved,
          summary: '${_nameOf(_me)} deleted “${step.title}”',
          targetId: step.id,
          affectsUid: step.ownerId == _me ? '' : step.ownerId,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  String _nameOf(String uid) {
    final members = _state?.members ?? const <ClassroomMember>[];
    for (final m in members) {
      if (m.uid == uid) return m.name;
    }
    return 'Someone';
  }

  // Saving offline only finishes once back online, so nothing waits on this.
  void _guard(Future<void> write) {
    unawaited(
      write.catchError((Object e) {
        if (_disposed) return;
        final state = _state;
        if (state != null) _onStored(state);
        onRefused(
          e is BackendFailure ? e.message : 'That change wasn’t saved.',
        );
      }),
    );
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_onLocalChange);
    unawaited(_subscription.cancel());
  }
}

/// The activity entry for one edit, or null if it isn't worth anyone's notice.
@visibleForTesting
ActivityEntry? describeChange({
  required PlanStep? before,
  required PlanStep after,
  required String actorUid,
  required String Function(String uid) nameOf,
  required String id,
}) {
  final actor = nameOf(actorUid);
  final title = '“${after.title}”';
  final owner = before?.ownerId ?? after.ownerId;
  final affects = owner == actorUid ? '' : owner;

  ActivityEntry entry(
    ActivityKind kind,
    String summary, {
    String? affectsUid,
  }) => ActivityEntry(
    id: id,
    actorUid: actorUid,
    kind: kind,
    summary: summary,
    targetId: after.id,
    affectsUid: affectsUid ?? affects,
    createdAt: DateTime.now(),
  );

  if (before == null) {
    final assigned = after.ownerId == actorUid
        ? ''
        : ' for ${nameOf(after.ownerId)}';
    return entry(ActivityKind.stepAdded, '$actor added $title$assigned');
  }
  if (before.ownerId != after.ownerId) {
    return entry(
      ActivityKind.stepHandedOver,
      '$actor handed $title to ${nameOf(after.ownerId)}',
      affectsUid: after.ownerId == actorUid ? before.ownerId : after.ownerId,
    );
  }
  if (before.status != after.status) {
    return switch ((before.status, after.status)) {
      (StepStatus.review, StepStatus.done) => entry(
        ActivityKind.stepApproved,
        '$actor approved $title',
      ),
      (StepStatus.review, _) => entry(
        ActivityKind.stepSentBack,
        '$actor sent $title back',
      ),
      (_, StepStatus.review) => entry(
        ActivityKind.stepSentForApproval,
        '$actor sent $title for approval',
      ),
      (_, StepStatus.done) => entry(
        ActivityKind.stepFinished,
        '$actor finished $title',
      ),
      (StepStatus.done, _) => entry(
        ActivityKind.stepReopened,
        '$actor reopened $title',
      ),
      (_, StepStatus.doing) => entry(
        ActivityKind.stepStarted,
        '$actor started $title',
      ),
      _ => entry(ActivityKind.stepEdited, '$actor changed $title'),
    };
  }
  if (!_sameItems(before.dependsOn, after.dependsOn)) {
    return entry(
      ActivityKind.dependencyChanged,
      '$actor changed what $title depends on',
    );
  }
  // Ticking off your own checklist is progress, not news for anyone else.
  if (affects.isEmpty &&
      before.copyWith(checklist: after.checklist).storedSameAs(after)) {
    return null;
  }
  return entry(ActivityKind.stepEdited, '$actor edited $title');
}

bool _sameItems(List<String> a, List<String> b) =>
    a.length == b.length && a.toSet().containsAll(b);
