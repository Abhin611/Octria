import 'dart:ui';

import '../model/plan.dart';

const double kCellWidth = 280;
const double kRowHeight = 168;
const double kGutterWidth = 176;
const double kHeaderHeight = 76;
const double kEndPadding = 72;

/// Which way the plan flows across the screen.
enum GraphDirection { leftToRight, topToBottom }

/// How a plan is spread out in the world. [cellWidth] and [rowHeight] are always
/// horizontal and vertical spacing, whichever way the plan flows.
class LayoutOptions {
  const LayoutOptions({
    this.direction = GraphDirection.leftToRight,
    this.cellWidth = kCellWidth,
    this.rowHeight = kRowHeight,
  });

  final GraphDirection direction;
  final double cellWidth;
  final double rowHeight;

  bool get vertical => direction == GraphDirection.topToBottom;
}

/// How one dependency arrow runs, so arrows don't merge: its own exit and entry
/// point on the rectangles, and its own vertical track in the gap before the
/// target's column.
class EdgeRoute {
  const EdgeRoute({this.startDy = 0, this.endDy = 0, this.track = 0.5});

  /// Offsets from the rectangle's centre, in world units at full node height.
  final double startDy;
  final double endDy;

  /// Where the vertical run sits across the gap: 0 at the target, 1 at the far
  /// side.
  final double track;
}

class GraphLayout {
  const GraphLayout({
    required this.options,
    required this.edgeRoutes,
    required this.positions,
    required this.phaseBands,
    required this.laneBands,
    required this.size,
  });

  final LayoutOptions options;

  bool get vertical => options.vertical;

  /// Keyed by "from>to" step ids.
  final Map<String, EdgeRoute> edgeRoutes;

  /// Node centres in world space.
  final Map<String, Offset> positions;
  final Map<String, Rect> phaseBands;
  final Map<String, Rect> laneBands;
  final Size size;

  /// The nearest phase and lane for a world point, used when a step is dropped.
  (String phaseId, String memberId)? cellAt(Offset world) {
    String? phaseId;
    String? memberId;
    for (final e in phaseBands.entries) {
      if (e.value.contains(world)) phaseId = e.key;
    }
    for (final e in laneBands.entries) {
      if (e.value.contains(world)) memberId = e.key;
    }
    if (phaseId == null || memberId == null) return null;
    return (phaseId, memberId);
  }
}

/// Layered layout: phases are fixed columns, members are fixed lanes, and
/// dependencies decide the sub-column within a phase. Steps stacked in one cell
/// are ordered by the average height of their neighbours to reduce crossings.
GraphLayout computeLayout(
  Plan plan, {
  LayoutOptions options = const LayoutOptions(),
}) {
  final vertical = options.vertical;
  final cellWidth = options.cellWidth;
  final rowHeight = options.rowHeight;
  final steps = plan.steps;
  final phaseIndex = {
    for (var i = 0; i < plan.phases.length; i++) plan.phases[i].id: i,
  };

  // The viewer's steps in one phase also run in due order, so their route never
  // doubles back along their lane. Only the viewer has a route.
  final previousOnRoute = <String, PlanStep>{};
  final lastInPhase = <String, PlanStep>{};
  for (final s in plan.routeFor(plan.meId)) {
    final before = lastInPhase[s.phaseId];
    if (before != null) previousOnRoute[s.id] = before;
    lastInPhase[s.phaseId] = s;
  }

  // Sub-column within each phase: one past the deepest same-phase dependency.
  final subColumn = <String, int>{};
  int columnOf(PlanStep s) {
    final known = subColumn[s.id];
    if (known != null) return known;
    subColumn[s.id] = 0; // Guards against bad data; cycles are refused on edit.
    var column = 0;
    for (final id in s.dependsOn) {
      final dep = steps[id];
      if (dep != null && dep.phaseId == s.phaseId) {
        final next = columnOf(dep) + 1;
        if (next > column) column = next;
      }
    }
    final previous = previousOnRoute[s.id];
    if (previous != null) {
      final next = columnOf(previous) + 1;
      if (next > column) column = next;
    }
    return subColumn[s.id] = column;
  }

  final columnsInPhase = List<int>.filled(plan.phases.length, 1);
  for (final s in steps.values) {
    final index = phaseIndex[s.phaseId]!;
    final count = columnOf(s) + 1;
    if (count > columnsInPhase[index]) columnsInPhase[index] = count;
  }

  final firstColumn = List<int>.filled(plan.phases.length, 0);
  for (var i = 1; i < plan.phases.length; i++) {
    firstColumn[i] = firstColumn[i - 1] + columnsInPhase[i - 1];
  }
  int globalColumn(PlanStep s) =>
      firstColumn[phaseIndex[s.phaseId]!] + subColumn[s.id]!;

  // The viewer's lane sits on top; the rest keep their order.
  final lanes = [
    ...plan.members.where((m) => m.id == plan.meId),
    ...plan.members.where((m) => m.id != plan.meId),
  ];

  final cells = <(String, int), List<PlanStep>>{};
  for (final s in steps.values) {
    cells.putIfAbsent((s.ownerId, globalColumn(s)), () => []).add(s);
  }

  final laneRows = <String, int>{for (final m in lanes) m.id: 1};
  cells.forEach((key, list) {
    if (list.length > laneRows[key.$1]!) laneRows[key.$1] = list.length;
  });

  // Provisional row in each cell, refined by two barycentre sweeps.
  final rowOf = <String, double>{};
  void writeRows() {
    var laneTop = 0.0;
    for (final m in lanes) {
      final rows = laneRows[m.id]!;
      cells.forEach((key, list) {
        if (key.$1 != m.id) return;
        final inset = (rows - list.length) / 2;
        for (var i = 0; i < list.length; i++) {
          rowOf[list[i].id] = laneTop + inset + i;
        }
      });
      laneTop += rows;
    }
  }

  writeRows();
  for (var sweep = 0; sweep < 2; sweep++) {
    cells.forEach((key, list) {
      if (list.length < 2) return;
      double weight(PlanStep s) {
        final near = s.dependsOn.map((id) => rowOf[id]).whereType<double>();
        if (near.isEmpty) return rowOf[s.id]!;
        return near.reduce((a, b) => a + b) / near.length;
      }

      final weights = {for (final s in list) s.id: weight(s)};
      list.sort((a, b) => weights[a.id]!.compareTo(weights[b.id]!));
    });
    writeRows();
  }

  // Phases and sub-columns run along the flow; lanes run across it.
  final positions = <String, Offset>{
    for (final s in steps.values)
      s.id: vertical
          ? Offset(
              kGutterWidth + (rowOf[s.id]! + 0.5) * cellWidth,
              kHeaderHeight + (globalColumn(s) + 0.5) * rowHeight,
            )
          : Offset(
              kGutterWidth + (globalColumn(s) + 0.5) * cellWidth,
              kHeaderHeight + (rowOf[s.id]! + 0.5) * rowHeight,
            ),
  };

  final totalRows = laneRows.values.fold<int>(0, (a, b) => a + b);
  final totalColumns = columnsInPhase.fold<int>(0, (a, b) => a + b);
  final height =
      kHeaderHeight +
      (vertical ? totalColumns : totalRows) * rowHeight +
      kEndPadding;
  final width =
      kGutterWidth +
      (vertical ? totalRows : totalColumns) * cellWidth +
      kEndPadding;

  final phaseBands = <String, Rect>{};
  for (var i = 0; i < plan.phases.length; i++) {
    final isLast = i == plan.phases.length - 1;
    final end = isLast ? kEndPadding : 0.0;
    phaseBands[plan.phases[i].id] = vertical
        ? Rect.fromLTRB(
            0,
            kHeaderHeight + firstColumn[i] * rowHeight,
            width,
            kHeaderHeight +
                (firstColumn[i] + columnsInPhase[i]) * rowHeight +
                end,
          )
        : Rect.fromLTRB(
            kGutterWidth + firstColumn[i] * cellWidth,
            0,
            kGutterWidth +
                (firstColumn[i] + columnsInPhase[i]) * cellWidth +
                end,
            height,
          );
  }

  final laneBands = <String, Rect>{};
  var start = vertical ? kGutterWidth : kHeaderHeight;
  for (final m in lanes) {
    final extent = laneRows[m.id]! * (vertical ? cellWidth : rowHeight);
    laneBands[m.id] = vertical
        ? Rect.fromLTWH(start, 0, extent, height)
        : Rect.fromLTWH(0, start, width, extent);
    start += extent;
  }

  return GraphLayout(
    options: options,
    edgeRoutes: _routeEdges(plan, positions, globalColumn, vertical),
    positions: positions,
    phaseBands: phaseBands,
    laneBands: laneBands,
    size: Size(width, height),
  );
}

/// Spreads arrows out: at each rectangle they fan across its side in the order
/// of where they lead, and each takes its own track through the gap.
Map<String, EdgeRoute> _routeEdges(
  Plan plan,
  Map<String, Offset> positions,
  int Function(PlanStep) columnOf,
  bool vertical,
) {
  // Across the flow, and along it.
  double across(Offset p) => vertical ? p.dx : p.dy;
  double along(Offset p) => vertical ? p.dy : p.dx;

  final edges = <(PlanStep, PlanStep)>[
    for (final to in plan.steps.values)
      for (final id in to.dependsOn)
        if (plan.steps[id] != null) (plan.steps[id]!, to),
  ];

  Map<String, double> fan(
    String Function((PlanStep, PlanStep)) owner,
    String Function((PlanStep, PlanStep)) other,
  ) {
    final groups = <String, List<(PlanStep, PlanStep)>>{};
    for (final e in edges) {
      groups.putIfAbsent(owner(e), () => []).add(e);
    }
    final offsets = <String, double>{};
    for (final group in groups.values) {
      group.sort((a, b) {
        final pa = positions[other(a)]!;
        final pb = positions[other(b)]!;
        final byAcross = across(pa).compareTo(across(pb));
        return byAcross != 0 ? byAcross : along(pa).compareTo(along(pb));
      });
      final spacing = group.length < 2
          ? 0.0
          : (72 / (group.length - 1)).clamp(0.0, 16.0);
      for (var i = 0; i < group.length; i++) {
        final e = group[i];
        offsets['${e.$1.id}>${e.$2.id}'] =
            (i - (group.length - 1) / 2) * spacing;
      }
    }
    return offsets;
  }

  final starts = fan((e) => e.$1.id, (e) => e.$2.id);
  final ends = fan((e) => e.$2.id, (e) => e.$1.id);

  final tracks = <int, List<(PlanStep, PlanStep)>>{};
  for (final e in edges) {
    tracks.putIfAbsent(columnOf(e.$2), () => []).add(e);
  }
  final routes = <String, EdgeRoute>{};
  for (final group in tracks.values) {
    group.sort((a, b) {
      final byEnd = across(positions[a.$2.id]!)
          .compareTo(across(positions[b.$2.id]!));
      return byEnd != 0
          ? byEnd
          : across(positions[a.$1.id]!).compareTo(across(positions[b.$1.id]!));
    });
    for (var i = 0; i < group.length; i++) {
      final key = '${group[i].$1.id}>${group[i].$2.id}';
      routes[key] = EdgeRoute(
        startDy: starts[key]!,
        endDy: ends[key]!,
        track: (i + 1) / (group.length + 1),
      );
    }
  }
  return routes;
}
