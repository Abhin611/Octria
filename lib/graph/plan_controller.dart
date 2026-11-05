import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../model/plan.dart';
import 'camera.dart';
import 'layout.dart';

/// Filters dim what doesn't match rather than removing it, so the shape of the
/// plan stays put while someone narrows their view.
@immutable
class GraphFilter {
  const GraphFilter({
    this.memberIds = const {},
    this.phaseIds = const {},
    this.standings = const {},
    this.overdueOnly = false,
  });

  final Set<String> memberIds;
  final Set<String> phaseIds;
  final Set<Standing> standings;
  final bool overdueOnly;

  bool get isActive =>
      memberIds.isNotEmpty ||
      phaseIds.isNotEmpty ||
      standings.isNotEmpty ||
      overdueOnly;

  int get count =>
      memberIds.length +
      phaseIds.length +
      standings.length +
      (overdueOnly ? 1 : 0);

  bool matches(Plan plan, PlanStep step) {
    if (memberIds.isNotEmpty && !memberIds.contains(step.ownerId)) return false;
    if (phaseIds.isNotEmpty && !phaseIds.contains(step.phaseId)) return false;
    if (standings.isNotEmpty && !standings.contains(plan.standing(step))) {
      return false;
    }
    if (overdueOnly && !plan.isOverdue(step)) return false;
    return true;
  }

  GraphFilter copyWith({
    Set<String>? memberIds,
    Set<String>? phaseIds,
    Set<Standing>? standings,
    bool? overdueOnly,
  }) => GraphFilter(
    memberIds: memberIds ?? this.memberIds,
    phaseIds: phaseIds ?? this.phaseIds,
    standings: standings ?? this.standings,
    overdueOnly: overdueOnly ?? this.overdueOnly,
  );
}

/// Why a dependency could not be added, in words the person can act on.
class DependencyRefused implements Exception {
  const DependencyRefused(this.message);
  final String message;
}

GraphLayout _layoutWith((Plan, LayoutOptions) input) =>
    computeLayout(input.$1, options: input.$2);

/// Holds the plan and its layout, and glides nodes to their new places.
class PlanController extends ChangeNotifier {
  PlanController(Plan initial, TickerProvider vsync) : _plan = initial {
    _ticker = vsync.createTicker(_tick);
    _layout = computeLayout(initial);
    _critical = initial.criticalPath();
    _shown = Map.of(_layout.positions);
  }

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  Plan _plan;
  late GraphLayout _layout;
  late Set<String> _critical;
  late Map<String, Offset> _shown;
  Map<String, Offset> _from = const {};
  final Spring _travel = Spring(1);
  int _layoutGeneration = 0;
  LayoutOptions _options = const LayoutOptions();

  LayoutOptions get options => _options;

  /// Re-lays the plan for a new direction or screen shape. With [animate], the
  /// steps glide to their new places.
  void setOptions(LayoutOptions options, {bool animate = false}) {
    _options = options;
    _layoutGeneration++;
    _layout = computeLayout(_plan, options: options);
    if (animate && !reduceMotion) {
      _from = _shown;
      _travel
        ..value = 0
        ..target = 1
        ..velocity = 0
        ..dampingRatio = 1
        ..response = 0.5;
      _last = Duration.zero;
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
      _shown = Map.of(_layout.positions);
    }
    notifyListeners();
  }

  bool reduceMotion = false;

  Plan get plan => _plan;
  GraphLayout get layout => _layout;
  Set<String> get critical => _critical;

  /// Where each node is right now, possibly on its way to a new place.
  Map<String, Offset> get positions => _shown;

  void replacePlan(Plan next) {
    _ticker.stop();
    _plan = next;
    _layout = computeLayout(next, options: _options);
    _critical = next.criticalPath();
    _shown = Map.of(_layout.positions);
    _layoutGeneration++;
    notifyListeners();
  }

  /// Takes in a newer copy of the plan, such as someone else's edit. Steps glide
  /// to any new places, and the camera stays put.
  void adopt(Plan next) => _apply(next);

  /// Applies an edit. The layout runs off the main thread where the platform
  /// has one, so big plans don't freeze. [droppedAt] starts a dragged node from
  /// where the finger left it.
  Future<void> _apply(Plan next, {Map<String, Offset>? droppedAt}) async {
    _plan = next;
    _critical = next.criticalPath();
    notifyListeners();

    final generation = ++_layoutGeneration;
    final fresh = await compute(_layoutWith, (next, _options));
    if (generation != _layoutGeneration) return;

    _from = {..._shown, ...?droppedAt};
    _layout = fresh;
    if (reduceMotion) {
      _shown = Map.of(fresh.positions);
      notifyListeners();
      return;
    }
    _travel
      ..value = 0
      ..target = 1
      ..velocity = 0
      ..dampingRatio = 1
      ..response = 0.42;
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    notifyListeners();
  }

  void _tick(Duration now) {
    final elapsed = _last == Duration.zero
        ? 0.016
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    var remaining = elapsed.clamp(0.0, 0.05);
    while (remaining > 0) {
      final dt = remaining < 1 / 240 ? remaining : 1 / 240;
      _travel.step(dt);
      remaining -= dt;
    }
    final t = _travel.value;
    final target = _layout.positions;
    _shown = {
      for (final e in target.entries)
        e.key: Offset.lerp(_from[e.key] ?? e.value, e.value, t)!,
    };
    if (_travel.settled) {
      _shown = Map.of(target);
      _ticker.stop();
    }
    notifyListeners();
  }

  void setStatus(String id, StepStatus status) {
    final step = _plan.steps[id];
    if (step == null) return;
    _plan = _plan.replacing(step.copyWith(status: status));
    _critical = _plan.criticalPath();
    notifyListeners();
  }

  void toggleChecklist(String id, int index) {
    final step = _plan.steps[id];
    if (step == null) return;
    final next = [...step.checklist];
    final item = next[index];
    next[index] = ChecklistItem(title: item.title, done: !item.done);
    _plan = _plan.replacing(step.copyWith(checklist: next));
    notifyListeners();
  }

  /// Throws [DependencyRefused] rather than creating a loop.
  void addDependency(String stepId, String dependencyId) {
    final step = _plan.steps[stepId];
    final dep = _plan.steps[dependencyId];
    if (step == null || dep == null) return;
    if (step.dependsOn.contains(dependencyId)) {
      throw DependencyRefused(
        '“${step.title}” already depends on “${dep.title}”.',
      );
    }
    if (_plan.wouldCycle(stepId, dependencyId)) {
      throw DependencyRefused(
        'That would create a loop: “${dep.title}” already depends on '
        '“${step.title}”.',
      );
    }
    _apply(
      _plan.replacing(
        step.copyWith(dependsOn: [...step.dependsOn, dependencyId]),
      ),
    );
  }

  void removeDependency(String stepId, String dependencyId) {
    final step = _plan.steps[stepId];
    if (step == null) return;
    _apply(
      _plan.replacing(
        step.copyWith(
          dependsOn: step.dependsOn.where((d) => d != dependencyId).toList(),
        ),
      ),
    );
  }

  void moveStep(
    String id, {
    required String phaseId,
    required String ownerId,
    required Offset droppedAt,
  }) {
    final step = _plan.steps[id];
    if (step == null) return;
    _apply(
      _plan.replacing(step.copyWith(phaseId: phaseId, ownerId: ownerId)),
      droppedAt: {id: droppedAt},
    );
  }

  /// A drag that changed nothing: glide the node home from where it was let go.
  void settleFrom(String id, Offset droppedAt) {
    _from = {..._shown, id: droppedAt};
    if (reduceMotion) {
      notifyListeners();
      return;
    }
    _travel
      ..value = 0
      ..target = 1
      ..velocity = 0
      ..dampingRatio = 1
      ..response = 0.36;
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void handOver(String id, String ownerId) {
    final step = _plan.steps[id];
    if (step == null) return;
    _apply(_plan.replacing(step.copyWith(ownerId: ownerId)));
  }

  /// Returns the plan as it was, for undo.
  Plan deleteStep(String id) {
    final before = _plan;
    final remaining = _plan.steps.values
        .where((s) => s.id != id)
        .map(
          (s) => s.dependsOn.contains(id)
              ? s.copyWith(
                  dependsOn: s.dependsOn.where((d) => d != id).toList(),
                )
              : s,
        );
    _shown = Map.of(_shown)..remove(id);
    _apply(_plan.withSteps(remaining));
    return before;
  }

  void restore(Plan before) => _apply(before);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
