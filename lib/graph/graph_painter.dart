import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../model/plan.dart';
import '../theme/tokens.dart';
import 'camera.dart';
import 'layout.dart';
import 'plan_controller.dart';

double _smooth(double a, double b, double v) {
  final t = ((v - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// The one continuous zoom axis, shared by drawing and hit testing.
class ZoomLevels {
  ZoomLevels(double scale)
    : phases = 1 - _smooth(0.2, 0.32, scale),
      card = _smooth(1.2, 1.55, scale);

  /// 1 when phases are big cards, fading to 0 as steps appear.
  final double phases;

  /// 1 when each step is a full inline card.
  final double card;

  double get steps => 1 - phases;
}

const double kCardWidth = 180;
const double kCardHeight = 112;
const double kNodeWidth = 176;
const double kNodeHeight = 104;

/// A step's rectangle on screen at the middle zoom. It keeps a readable minimum
/// without ever crowding the next column or lane.
Size nodeSize(
  double scale, {
  double row = kRowHeight,
  double cell = kCellWidth,
}) => Size(
  math.min(math.max(kNodeWidth * scale, 104.0), cell * scale - 6),
  math.min(math.max(kNodeHeight * scale, 66.0), row * scale - 8),
);

/// The rectangle at any zoom, growing continuously into the full card.
Size nodeSizeAt(
  double scale, {
  double row = kRowHeight,
  double cell = kCellWidth,
}) {
  final t = ZoomLevels(scale).card;
  final mid = nodeSize(scale, row: row, cell: cell);
  return Size(
    _lerp(mid.width, kCardWidth * scale, t),
    _lerp(mid.height, kCardHeight * scale, t),
  );
}

/// The rectangle as the camera sees it right now.
Size cameraNodeSize(GraphCamera camera) =>
    nodeSizeAt(camera.scale, row: camera.rowHeight, cell: camera.cellWidth);

/// Where a step's add-a-dependency handle sits, in the direction of flow.
Offset handleOffset(Size node, bool vertical) =>
    vertical ? Offset(0, node.height / 2 + 16) : Offset(node.width / 2 + 16, 0);

/// A canvas with no room to spare on one side: a phone, either way up.
bool _tightCanvas(Size canvas) => canvas.width < 500 || canvas.height < 420;

/// Width of the sticky member column. On phones it shrinks to avatars alone.
double laneGutterFor(Size canvas) => _tightCanvas(canvas) ? 44 : 92;

/// Height of the sticky strip naming the phases.
double phaseStripFor(Size canvas) {
  if (canvas.height < 420) return 28;
  return canvas.width < 500 ? 34 : 44;
}

/// Space between floating panes.
const double kPaneGap = 6;

/// Where the sticky member or phase column ends on screen.
double gutterEndFor(GraphCamera camera) =>
    camera.chrome.left + laneGutterFor(camera.clear.size);

/// Where the sticky strip ends on screen.
double stripEndFor(GraphCamera camera) =>
    camera.chrome.top + phaseStripFor(camera.clear.size);

/// The glass pane behind the sticky strip.
Rect stripPaneFor(GraphCamera camera) => Rect.fromLTRB(
  camera.clear.left,
  camera.clear.top,
  camera.clear.right,
  stripEndFor(camera),
);

/// The glass pane behind the sticky column.
Rect gutterPaneFor(GraphCamera camera) => Rect.fromLTRB(
  camera.clear.left,
  stripEndFor(camera) + kPaneGap,
  gutterEndFor(camera),
  camera.clear.bottom,
);

/// Where one arrow runs on screen right now. Shared by drawing and tap testing,
/// so what you tap is exactly what you see.
class EdgeLine {
  const EdgeLine(this.start, this.end, this.track, {this.vertical = false});

  final Offset start;
  final Offset end;

  /// The position of the arrow's own run across the flow, along the flow axis.
  final double track;
  final bool vertical;

  double _along(Offset p) => vertical ? p.dy : p.dx;
  double _across(Offset p) => vertical ? p.dx : p.dy;
  Offset _at(double along, double across) =>
      vertical ? Offset(across, along) : Offset(along, across);

  bool get straight => (_across(end) - _across(start)).abs() < 1;
  bool get curved => track <= _along(start) + 2 || track >= _along(end) - 2;

  /// The arrow as connected points, close enough to the drawn path to tap.
  List<Offset> get points {
    if (straight) return [start, end];
    if (!curved) {
      return [start, _at(track, _across(start)), _at(track, _across(end)), end];
    }
    final handle = math.max((_along(end) - _along(start)).abs() * 0.5, 28.0);
    final c1 = _at(_along(start) + handle, _across(start));
    final c2 = _at(_along(end) - handle, _across(end));
    return [
      for (var i = 0; i <= 16; i++)
        () {
          final t = i / 16;
          final u = 1 - t;
          return start * (u * u * u) +
              c1 * (3 * u * u * t) +
              c2 * (3 * u * t * t) +
              end * (t * t * t);
        }(),
    ];
  }

  /// A run along the flow, one run across it on the arrow's own track, and a run
  /// into the target, with rounded corners.
  Path get path {
    if (straight) {
      return Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy);
    }
    if (curved) {
      final handle = math.max((_along(end) - _along(start)).abs() * 0.5, 28.0);
      final c1 = _at(_along(start) + handle, _across(start));
      final c2 = _at(_along(end) - handle, _across(end));
      return Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
    }
    final shift = _across(end) - _across(start);
    final r = math.min(
      8.0,
      math.min(
        shift.abs() / 2,
        math.min(track - _along(start), _along(end) - track),
      ),
    );
    final sign = shift > 0 ? 1.0 : -1.0;
    final a = _at(track - r, _across(start));
    final corner1 = _at(track, _across(start));
    final b = _at(track, _across(start) + sign * r);
    final c = _at(track, _across(end) - sign * r);
    final corner2 = _at(track, _across(end));
    final d = _at(track + r, _across(end));
    return Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(a.dx, a.dy)
      ..quadraticBezierTo(corner1.dx, corner1.dy, b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..quadraticBezierTo(corner2.dx, corner2.dy, d.dx, d.dy)
      ..lineTo(end.dx, end.dy);
  }
}

EdgeLine edgeLineFor(
  GraphLayout layout,
  GraphCamera camera,
  String fromId,
  String toId,
  Offset fromWorld,
  Offset toWorld,
) {
  final node = cameraNodeSize(camera);
  final route = layout.edgeRoutes['$fromId>$toId'] ?? const EdgeRoute();
  final a = camera.toScreen(fromWorld);
  final b = camera.toScreen(toWorld);
  if (layout.vertical) {
    final half = node.height / 2;
    final gap = math.max(camera.rowHeight * camera.scale - node.height, 8.0);
    final port = node.width / kNodeWidth;
    return EdgeLine(
      a + Offset(route.startDy * port, half),
      b + Offset(route.endDy * port, -half - 8),
      b.dy - half - gap * route.track,
      vertical: true,
    );
  }
  final half = node.width / 2;
  final gap = math.max(camera.cellWidth * camera.scale - node.width, 8.0);
  final port = node.height / kNodeHeight;
  return EdgeLine(
    a + Offset(half, route.startDy * port),
    b + Offset(-half - 8, route.endDy * port),
    b.dx - half - gap * route.track,
  );
}

/// Everything the painter needs for one frame.
class GraphScene {
  GraphScene({
    required this.controller,
    required this.camera,
    required this.palette,
    required this.filter,
    required this.focus,
    required this.selectedId,
    required this.selectedEdge,
    required this.hoveredId,
    required this.pressedId,
    required this.nextId,
    required this.celebrateId,
    required this.celebrateT,
    required this.movingId,
    required this.movingAt,
    required this.dropCell,
    required this.linkFromId,
    required this.linkTo,
    required this.linkTargetId,
    required this.texts,
    this.reveal = const AlwaysStoppedAnimation(1),
    this.flow = const AlwaysStoppedAnimation(0),
  });

  /// From 0 to 1 as the graph first arrives.
  final Animation<double> reveal;

  /// Loops from 0 to 1, moving work along the arrows.
  final Animation<double> flow;

  final PlanController controller;
  final GraphCamera camera;
  final Palette palette;
  final GraphFilter filter;
  final double focus;
  final String? selectedId;

  /// The arrow someone tapped, as (from, to) step ids.
  final (String, String)? selectedEdge;
  final String? hoveredId;
  final String? pressedId;
  final String? nextId;
  final String? celebrateId;
  final double celebrateT;
  final String? movingId;
  final Offset? movingAt;
  final (String, String)? dropCell;
  final String? linkFromId;
  final Offset? linkTo;
  final String? linkTargetId;
  final TextCache texts;
}

/// Keeps laid-out text between frames. Laying out text is the slow part of a
/// graph this size, and most labels don't change.
class TextCache {
  final Map<String, TextPainter> _cache = {};
  TextScaler _scaler = TextScaler.noScaling;

  /// Follows the system's text size setting.
  set scaler(TextScaler value) {
    if (value == _scaler) return;
    _scaler = value;
    _clear();
  }

  TextPainter get(
    String text,
    TextStyle style,
    double maxWidth, {
    int maxLines = 1,
    TextAlign align = TextAlign.left,
  }) {
    final width = (maxWidth / 8).ceil() * 8.0;
    final key =
        '$text|${style.color?.toARGB32()}|${style.fontSize}|${style.fontWeight?.value}|$width|$maxLines|${align.index}';
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 2400) _clear();
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
      textScaler: _scaler,
    )..layout(maxWidth: width);
    return _cache[key] = painter;
  }

  void _clear() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }

  void dispose() => _clear();
}

Color _fade(Color c, double a) {
  // Quantised so cached text can be reused across a fade.
  final q = (a.clamp(0.0, 1.0) * 12).round() / 12;
  return c.withValues(alpha: c.a * q);
}

/// How a step shows its status across its whole rectangle: a fill of its colour,
/// a little brighter at the top, like the rest of the glass.
@immutable
class StatusFill {
  const StatusFill(this.top, this.bottom);

  final Color top;
  final Color bottom;

  Shader shader(Rect rect, double alpha) => ui.Gradient.linear(
    rect.topCenter,
    rect.bottomCenter,
    [_fade(top, alpha), _fade(bottom, alpha)],
  );
}

/// The fill for a status, or null for a step that can't start yet, which stays
/// plain. Mixed from an opaque base, so words on top keep their contrast.
StatusFill? statusFill(Palette p, Standing standing) {
  final dark = p.brightness == Brightness.dark;
  final base = dark ? const Color(0xFF1D1815) : const Color(0xFFFFFFFF);
  StatusFill mix(Color colour, {bool quiet = false}) {
    final top = quiet ? (dark ? 0.2 : 0.14) : (dark ? 0.32 : 0.5);
    final bottom = quiet ? (dark ? 0.14 : 0.1) : (dark ? 0.24 : 0.4);
    return StatusFill(
      Color.lerp(base, colour, top)!,
      Color.lerp(base, colour, bottom)!,
    );
  }

  return switch (standing) {
    Standing.done => mix(p.done),
    Standing.doing => mix(p.doing),
    Standing.review => mix(p.review),
    Standing.blocked => mix(p.blocked),
    Standing.ready => mix(p.inkFaint, quiet: true),
    Standing.waiting => null,
  };
}

class GraphPainter extends CustomPainter {
  GraphPainter(this.scene, {required Listenable repaint, this.headers = false})
    : super(repaint: repaint);

  final GraphScene scene;

  /// Paints only the sticky names, which sit on glass above the map. The map
  /// itself is painted by a second painter underneath that glass.
  final bool headers;

  Plan get _plan => scene.controller.plan;
  GraphCamera get _cam => scene.camera;
  Palette get _p => scene.palette;
  double get _stripEnd => stripEndFor(_cam);
  double get _gutterEnd => gutterEndFor(_cam);
  bool get _vertical => scene.controller.layout.vertical;

  double _emphasis(PlanStep step) {
    var a = 1.0;
    if (!scene.filter.matches(_plan, step)) a *= 0.14;
    if (step.ownerId != _plan.meId) a *= _lerp(1, 0.22, scene.focus);
    final edge = scene.selectedEdge;
    if (edge != null && step.id != edge.$1 && step.id != edge.$2) a *= 0.3;
    return a;
  }

  /// How far a step has arrived, 0 to 1. Steps come in along the flow of the
  /// plan, so opening a classroom reads from its beginning to its end.
  double _arrival(String id) {
    final reveal = scene.reveal.value;
    if (reveal >= 1) return 1;
    final at = scene.controller.layout.positions[id];
    final world = scene.controller.layout.size;
    if (at == null || world.isEmpty) return 1;
    final along = _vertical ? at.dy / world.height : at.dx / world.width;
    final t = ((reveal - along.clamp(0.0, 1.0) * 0.55) / 0.45).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(t).clamp(0.0, 1.2);
  }

  Offset _position(String id) {
    if (id == scene.movingId && scene.movingAt != null) return scene.movingAt!;
    return scene.controller.positions[id] ?? Offset.zero;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final levels = ZoomLevels(_cam.scale);
    _flowing.clear();
    if (headers) {
      if (_vertical) {
        _paintPhaseGutter(canvas);
        _paintMemberStrip(canvas);
      } else {
        _paintLaneGutter(canvas);
        _paintPhaseStrip(canvas);
      }
      return;
    }
    _paintTerrain(canvas, size);
    if (scene.dropCell != null) _paintDropCell(canvas);
    if (levels.steps > 0) _paintEdges(canvas, size, levels);
    _paintFlow(canvas);
    if (levels.steps > 0) _paintTeamOrder(canvas, levels);
    // The route holds through every zoom level: it is the point of the map.
    _paintRoute(canvas);
    _paintArrowHeads(canvas);
    if (levels.steps > 0) {
      _paintNodes(canvas, size, levels);
      _paintSelectedEdge(canvas, levels);
      _paintLink(canvas);
    }
    if (levels.phases > 0) {
      _paintFarMarks(canvas, levels);
      _paintPhaseCards(canvas, levels);
    }
  }

  void _paintTerrain(Canvas canvas, Size size) {
    final layout = scene.controller.layout;
    var i = 0;
    for (final band in layout.phaseBands.values) {
      final rect = _vertical
          ? Rect.fromLTRB(
              0,
              _cam.toScreen(band.topLeft).dy,
              size.width,
              _cam.toScreen(band.bottomRight).dy,
            )
          : Rect.fromLTRB(
              _cam.toScreen(band.topLeft).dx,
              0,
              _cam.toScreen(band.bottomRight).dx,
              size.height,
            );
      if (i.isEven && rect.overlaps(Offset.zero & size)) {
        canvas.drawRect(
          rect,
          Paint()..color = i % 4 == 0 ? _p.terrainA : _p.terrainB,
        );
      }
      i++;
    }
    final line = Paint()
      ..color = _p.hairline
      ..strokeWidth = 1;
    for (final lane in layout.laneBands.values.skip(1)) {
      final at = _cam.toScreen(lane.topLeft);
      if (_vertical) {
        if (at.dx > 0 && at.dx < size.width) {
          canvas.drawLine(Offset(at.dx, 0), Offset(at.dx, size.height), line);
        }
      } else if (at.dy > 0 && at.dy < size.height) {
        canvas.drawLine(Offset(0, at.dy), Offset(size.width, at.dy), line);
      }
    }
  }

  void _paintDropCell(Canvas canvas) {
    final layout = scene.controller.layout;
    final (phaseId, memberId) = scene.dropCell!;
    final phase = layout.phaseBands[phaseId];
    final lane = layout.laneBands[memberId];
    if (phase == null || lane == null) return;
    final world = phase.intersect(lane);
    final rect = RRect.fromRectAndRadius(
      Rect.fromPoints(
        _cam.toScreen(world.topLeft),
        _cam.toScreen(world.bottomRight),
      ).deflate(4),
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = _p.ink.withValues(alpha: 0.05));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _p.inkFaint,
    );
  }

  Color _edgeColour(PlanStep from, PlanStep to) {
    final toStanding = _plan.standing(to);
    if (toStanding == Standing.blocked) return _p.blocked;
    return switch (from.status) {
      StepStatus.done => _p.done,
      StepStatus.doing || StepStatus.review => _p.doing,
      StepStatus.todo => _p.waiting,
    };
  }

  /// A smooth curve along the flow, for the route and for a link being drawn.
  Path _edgePath(Offset a, Offset b) {
    if (_vertical) {
      final handle = math.max((b.dy - a.dy).abs() * 0.5, 28.0);
      return Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, a.dy + handle, b.dx, b.dy - handle, b.dx, b.dy);
    }
    final handle = math.max((b.dx - a.dx).abs() * 0.5, 28.0);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(a.dx + handle, a.dy, b.dx - handle, b.dy, b.dx, b.dy);
  }

  void _paintEdges(Canvas canvas, Size size, ZoomLevels levels) {
    final viewport = (Offset.zero & size).inflate(80);
    final layout = scene.controller.layout;
    final critical = scene.controller.critical;
    final width = 1.6 * _cam.scale.clamp(0.8, 1.2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width + 1.8
      ..strokeCap = StrokeCap.round;
    // With a step in focus, its own arrows stand out and the rest step back.
    final edge = scene.selectedEdge;
    final focusId = edge != null ? null : scene.selectedId ?? scene.hoveredId;
    _heads.clear();

    for (final to in _plan.steps.values) {
      for (final fromId in to.dependsOn) {
        final from = _plan.steps[fromId];
        if (from == null) continue;
        final a = _cam.toScreen(_position(from.id));
        final b = _cam.toScreen(_position(to.id));
        final bounds = Rect.fromPoints(a, b);
        if (!bounds.overlaps(viewport)) continue;
        final line = edgeLineFor(
          layout,
          _cam,
          from.id,
          to.id,
          _position(from.id),
          _position(to.id),
        );
        final end = line.end;
        final path = line.path;
        final related = from.id == focusId || to.id == focusId;
        var alpha = levels.steps * math.min(_emphasis(from), _emphasis(to));
        final arrived = _arrival(to.id).clamp(0.0, 1.0);
        alpha *= arrived;
        if (edge != null) {
          // The tapped arrow is drawn on its own, above everything.
          if (edge == (from.id, to.id)) continue;
          alpha *= 0.4;
        } else if (focusId != null) {
          if (!related) alpha *= 0.28;
        } else if (from.status == StepStatus.done &&
            to.status == StepStatus.done) {
          // Finished work has nothing left to say about what happens next.
          alpha *= 0.3;
        }
        if (critical.contains(from.id) && critical.contains(to.id)) {
          // A cased line, like a main road: named in the map key.
          casing.color = _p.ink.withValues(alpha: 0.42 * alpha);
          canvas.drawPath(path, casing);
        }
        final colour = _edgeColour(from, to).withValues(alpha: alpha * 0.9);
        // Work moving along the arrows out of anything under way.
        if (from.status == StepStatus.doing &&
            to.status != StepStatus.done &&
            _flowing.length < 16 &&
            scene.flow.value > 0 &&
            _cam.scale > 0.3 &&
            alpha > 0.5 &&
            bounds.overlaps(Offset.zero & size)) {
          _flowing.add((path, colour));
        }
        stroke
          ..color = colour
          ..strokeWidth = related ? width + 1 : width;
        canvas.drawPath(path, stroke);
        if (_cam.scale > 0.3) _heads.add((end, colour));
        if (from.id == scene.celebrateId) {
          _paintUnlockSweep(canvas, path);
        }
      }
    }
  }

  final List<(Offset, Color)> _heads = [];
  final List<(Path, Color)> _flowing = [];

  /// A small light travelling along each active arrow. A few at most, so this
  /// costs little, and it stops altogether on a phone that can't keep up.
  void _paintFlow(Canvas canvas) {
    if (_flowing.isEmpty) return;
    final t = scene.flow.value;
    final dot = Paint();
    for (final (path, colour) in _flowing) {
      for (final metric in path.computeMetrics()) {
        final at = metric.getTangentForOffset(metric.length * t);
        if (at == null) continue;
        // Fades in and out at the ends, so it never pops.
        final fade = (math.min(t, 1 - t) * 6).clamp(0.0, 1.0);
        dot.color = colour.withValues(alpha: colour.a * 0.28 * fade);
        canvas.drawCircle(at.position, 6, dot);
        dot.color = colour.withValues(alpha: fade);
        canvas.drawCircle(at.position, 2.8, dot);
      }
    }
  }

  /// The tapped arrow, drawn over the steps so it can be followed end to end:
  /// a dot where it starts and a large arrowhead where it ends.
  void _paintSelectedEdge(Canvas canvas, ZoomLevels levels) {
    final edge = scene.selectedEdge;
    if (edge == null) return;
    final from = _plan.steps[edge.$1];
    final to = _plan.steps[edge.$2];
    if (from == null || to == null) return;
    final line = edgeLineFor(
      scene.controller.layout,
      _cam,
      from.id,
      to.id,
      _position(from.id),
      _position(to.id),
    );
    final path = line.path;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = _p.ground.withValues(alpha: 0.85),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round
        ..color = _p.ink,
    );
    final ink = Paint()..color = _p.ink;
    canvas.drawCircle(line.start, 5.5, ink);
    canvas.drawPath(_arrowShape(line.end, length: 8, back: 6, half: 8), ink);
  }

  /// Labels a step at either end of the tapped arrow.
  void _paintEndTag(Canvas canvas, Rect rect, String label) {
    final text = scene.texts.get(label, TypeRamp.caption(_p.ground), 48);
    final tag = Rect.fromLTWH(
      rect.left,
      rect.top - text.height - 9,
      text.width + 12,
      text.height + 5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tag, const Radius.circular(5)),
      Paint()..color = _p.ink,
    );
    text.paint(canvas, tag.topLeft + const Offset(6, 2.5));
  }

  /// Drawn after the route, so an arrow along your lane still shows its head.
  void _paintArrowHeads(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final (tip, colour) in _heads) {
      paint.color = colour;
      canvas.drawPath(_arrowHead(tip), paint);
    }
    _heads.clear();
  }

  void _paintUnlockSweep(Canvas canvas, Path path) {
    final t = Curves.easeOutCubic.transform(scene.celebrateT);
    final fade = 1 - _smooth(0.7, 1, scene.celebrateT);
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round
          ..color = _p.done.withValues(alpha: fade),
      );
    }
  }

  Path _arrowHead(Offset tip) =>
      _arrowShape(tip, length: 7, back: 3, half: 5.5);

  /// An arrowhead pointing along the flow.
  Path _arrowShape(
    Offset tip, {
    required double length,
    required double back,
    required double half,
  }) {
    if (_vertical) {
      return Path()
        ..moveTo(tip.dx, tip.dy + length)
        ..lineTo(tip.dx - half, tip.dy - back)
        ..lineTo(tip.dx + half, tip.dy - back)
        ..close();
    }
    return Path()
      ..moveTo(tip.dx + length, tip.dy)
      ..lineTo(tip.dx - back, tip.dy - half)
      ..lineTo(tip.dx - back, tip.dy + half)
      ..close();
  }

  /// Each teammate's order of work: a quiet dashed arrow from one step to the
  /// next along their lane, so their work reads as a line just as yours does.
  /// Steps with a real link already have that arrow, so they get no second one.
  void _paintTeamOrder(Canvas canvas, ZoomLevels levels) {
    final viewport = (Offset.zero & _cam.viewport).inflate(80);
    final node = cameraNodeSize(_cam);
    final width = _lerp(1.6, 2.2, _cam.scale.clamp(0.4, 1.0));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final half = _vertical
        ? Offset(0, node.height / 2)
        : Offset(node.width / 2, 0);
    final gap = _vertical ? const Offset(0, 8) : const Offset(8, 0);
    for (final member in _plan.members) {
      if (member.id == _plan.meId) continue;
      final order = _plan.routeFor(member.id);
      for (var i = 0; i < order.length - 1; i++) {
        final from = order[i];
        final to = order[i + 1];
        if (to.dependsOn.contains(from.id)) continue;
        final a = _cam.toScreen(_position(from.id));
        final b = _cam.toScreen(_position(to.id));
        if (!Rect.fromPoints(a, b).overlaps(viewport)) continue;
        final apart = _vertical ? b.dy - a.dy : b.dx - a.dx;
        if (apart <= (_vertical ? node.height : node.width)) continue;
        final colour = _p.inkSoft.withValues(
          alpha:
              0.7 *
              levels.steps *
              math.min(_emphasis(from), _emphasis(to)) *
              _arrival(to.id).clamp(0.0, 1.0),
        );
        stroke.color = colour;
        final tip = b - half - gap;
        canvas.drawPath(_dashes(_edgePath(a + half, tip), width), stroke);
        _heads.add((tip, colour));
      }
    }
  }

  /// The signature: the viewer's course, overprinted across everything. It's
  /// solid only where one step really depends on the next. Elsewhere it's just
  /// the order of their work, and dashes say so, with a head showing which way it
  /// runs, so it can't pass for a link.
  void _paintRoute(Canvas canvas) {
    final mine = _plan.routeFor(_plan.meId);
    if (mine.length < 2) return;
    final viewport = (Offset.zero & _cam.viewport).inflate(80);
    final node = cameraNodeSize(_cam);
    final width = _lerp(2.4, 3.6, _cam.scale.clamp(0.4, 1.0));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < mine.length - 1; i++) {
      final a = _cam.toScreen(_position(mine[i].id));
      final b = _cam.toScreen(_position(mine[i + 1].id));
      if (!Rect.fromPoints(a, b).overlaps(viewport)) continue;
      final finished =
          mine[i].status == StepStatus.done &&
          mine[i + 1].status == StepStatus.done;
      final linked = mine[i + 1].dependsOn.contains(mine[i].id);
      stroke.color = _p.route.withValues(
        alpha:
            (finished ? 0.45 : 1) *
            _lerp(0.85, 1, scene.focus) *
            (scene.selectedEdge != null ? 0.35 : 1) *
            _arrival(mine[i + 1].id).clamp(0.0, 1.0),
      );
      // From edge to edge, so the line never runs behind a step's words.
      final half = _vertical
          ? Offset(0, node.height / 2)
          : Offset(node.width / 2, 0);
      final apart = _vertical ? b.dy - a.dy : b.dx - a.dx;
      final clear = apart > (_vertical ? node.height : node.width);
      final gap = _vertical ? const Offset(0, 8) : const Offset(8, 0);
      final path = _edgePath(
        clear ? a + half : a,
        clear ? (linked ? b - half : b - half - gap) : b,
      );
      if (!linked && clear) _heads.add((b - half - gap, stroke.color));
      if (linked) {
        canvas.drawPath(path, stroke);
        // A thin bright core, so the line reads as lit from inside.
        core.color = const Color(0xFFFFFFFF)
            .withValues(alpha: stroke.color.a * 0.38);
        canvas.drawPath(path, core);
      } else {
        canvas.drawPath(_dashes(path, width), stroke);
      }
    }
  }

  Path _dashes(Path path, double width) {
    final dash = width * 2;
    final gap = width * 2.6;
    final out = Path();
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        out.addPath(metric.extractPath(d, d + dash), Offset.zero);
      }
    }
    return out;
  }

  /// When zoomed out, steps stay on the map as small marks, so the team and the
  /// route are still there under the phase cards.
  void _paintFarMarks(Canvas canvas, ZoomLevels levels) {
    final dot = Paint();
    for (final step in _plan.steps.values) {
      final c = _cam.toScreen(_position(step.id));
      final a = levels.phases * _emphasis(step);
      if (step.id == scene.nextId) {
        canvas.drawCircle(c, 5, Paint()..color = _fade(_p.ground, a));
        canvas.drawCircle(
          c,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = _fade(_p.route, a),
        );
      } else {
        dot.color = _fade(
          step.ownerId == _plan.meId
              ? _p.route
              : _p.standing(_plan.standing(step)),
          a,
        );
        canvas.drawCircle(c, step.ownerId == _plan.meId ? 3.4 : 2.6, dot);
      }
    }
  }

  void _paintNodes(Canvas canvas, Size size, ZoomLevels levels) {
    final viewport = (Offset.zero & size).inflate(240);
    PlanStep? lifted;
    for (final step in _plan.steps.values) {
      final c = _cam.toScreen(_position(step.id));
      if (!viewport.contains(c)) continue;
      if (step.id == scene.movingId) {
        lifted = step;
        continue;
      }
      _paintNode(canvas, step, c, levels);
    }
    if (lifted != null) {
      _paintNode(canvas, lifted, _cam.toScreen(_position(lifted.id)), levels);
    }
  }

  void _paintNode(Canvas canvas, PlanStep step, Offset c, ZoomLevels levels) {
    final arrived = _arrival(step.id);
    final alpha = levels.steps * _emphasis(step) * arrived.clamp(0.0, 1.0);
    if (alpha <= 0) return;
    final lift = step.id == scene.movingId
        ? 1.04
        : (step.id == scene.pressedId
              ? 0.97
              : (step.id == scene.hoveredId ? 1.025 : 1.0));
    final size = cameraNodeSize(_cam) * lift * _lerp(0.82, 1, arrived);
    final rect = Rect.fromCenter(
      center: c,
      width: size.width,
      height: size.height,
    );
    _paintPlate(canvas, step, rect, alpha, levels);
    // The short form hands over to the card quickly, so the two never overlap.
    final handover = 1 - _smooth(0, 0.4, levels.card);
    if (handover > 0) _paintPlateText(canvas, step, rect, alpha * handover);
    if (levels.card > 0.5) {
      _paintCardText(
        canvas,
        step,
        rect,
        alpha * _smooth(0.5, 0.9, levels.card),
      );
    }
    if (step.badgeCount > 0 && _cam.scale > 0.34) {
      _paintBadge(canvas, rect.topRight, step.badgeCount, alpha);
    }
    final edge = scene.selectedEdge;
    if (edge != null && step.id == edge.$1) {
      _paintEndTag(canvas, rect, 'From');
    } else if (edge != null && step.id == edge.$2) {
      _paintEndTag(canvas, rect, 'To');
    }
    if (step.id == scene.celebrateId) _paintRipple(canvas, rect);
    _paintUnlockedGlow(canvas, step, rect);
    if (step.id == scene.selectedId || step.id == scene.hoveredId) {
      _paintHandle(canvas, step, c, levels);
    }
  }

  /// The rectangle itself: your steps carry the route's colour, and the next
  /// one the heaviest edge, so it is still the one thing you can't miss.
  void _paintPlate(
    Canvas canvas,
    PlanStep step,
    Rect rect,
    double alpha,
    ZoomLevels levels,
  ) {
    final mine = step.ownerId == _plan.meId;
    final isNext = step.id == scene.nextId;
    final radius = Radius.circular(_lerp(11, 15, levels.card));
    final plate = RRect.fromRectAndRadius(rect, radius);
    final standing = _plan.standing(step);
    final rim = _statusRim(standing);
    // A step that can't start yet sits back, so what's lit stands out more.
    _paintGlassPlate(
      canvas,
      plate,
      standing == Standing.waiting ? alpha * 0.72 : alpha,
      fill: statusFill(_p, standing),
    );
    if (rim != null) {
      // Your magenta outline goes around this, so both can be read.
      canvas.drawRRect(
        mine ? plate.deflate(isNext ? 2.6 : 1.8) : plate,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _fade(rim, alpha),
      );
    }
    if (mine) {
      canvas.drawRRect(
        plate,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNext ? 3.4 : 2
          ..color = _fade(_p.route, alpha),
      );
    }
    final edge = scene.selectedEdge;
    if (step.id == scene.selectedId ||
        step.id == scene.linkTargetId ||
        (edge != null && (step.id == edge.$1 || step.id == edge.$2))) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(isNext ? 5 : 4), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _fade(_p.ink, alpha),
      );
    }
  }

  /// The edge of a step whose status has a strong colour. Steps not yet started
  /// have none.
  Color? _statusRim(Standing standing) => switch (standing) {
    Standing.doing => _p.doing,
    Standing.review => _p.review,
    Standing.blocked => _p.blocked,
    Standing.done => _p.done,
    Standing.ready || Standing.waiting => null,
  };

  /// A pane of glass drawn by hand. Real blur for every step would cost far too
  /// much in a big plan, so depth comes from a lit gradient, a rim and a shadow.
  void _paintGlassPlate(
    Canvas canvas,
    RRect plate,
    double alpha, {
    StatusFill? fill,
  }) {
    final rect = plate.outerRect;
    if (_cam.scale > 0.34) {
      final shadow = Paint()..color = _fade(_p.shadow, alpha * 0.5);
      canvas.drawRRect(plate.shift(const Offset(0, 4)).inflate(1), shadow);
      canvas.drawRRect(plate.shift(const Offset(0, 1.5)), shadow);
      canvas.drawRRect(
        plate,
        Paint()
          ..shader =
              fill?.shader(rect, alpha) ??
              ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
                _fade(_p.nodeTop, alpha),
                _fade(_p.nodeBottom, alpha),
              ]),
      );
      canvas.drawRRect(
        plate.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
            _fade(_p.rimTop, alpha),
            _fade(_p.nodeRim, alpha),
          ]),
      );
      return;
    }
    // Far out there are too many to light, and too small to tell.
    canvas.drawRRect(
      plate,
      Paint()..color = _fade(fill?.top ?? _p.nodeTop, alpha),
    );
  }

  /// Text widths are cached in steps of 8, so ask for a width that fits.
  double _fitWidth(double width) => (width / 8).floorToDouble() * 8;

  void _paintPlateText(Canvas canvas, PlanStep step, Rect rect, double alpha) {
    final mine = step.ownerId == _plan.meId;
    final standing = _plan.standing(step);
    final filled = statusFill(_p, standing) != null;
    final weight = mine || filled ? FontWeight.w600 : FontWeight.w500;
    // Too far out for words: the colour and the mark.
    if (_cam.scale <= 0.34) {
      _paintNodeMark(canvas, rect.center, 7, standing, alpha);
      return;
    }
    final word = scene.texts.get(
      standingWord(standing),
      TypeRamp.caption(_fade(filled ? _p.ink : _p.inkSoft, alpha))
          .weighted(FontWeight.w600)
          .copyWith(fontSize: 11),
      rect.width - 16,
    );
    final compact = rect.height < 60 || rect.width < 124;
    if (compact) {
      _paintNodeMark(
        canvas,
        Offset(rect.left + 15, rect.center.dy),
        7,
        standing,
        alpha,
      );
      final title = scene.texts.get(
        step.title,
        TypeRamp.label(_fade(_p.ink, alpha))
            .weighted(weight)
            .copyWith(fontSize: 12),
        // Up to two lines, leaving room for the status under the name.
        rect.width - 34,
        maxLines: rect.height >= 62 ? 2 : 1,
      );
      final shown = title.height + word.height + 1 <= rect.height - 6;
      final total = title.height + (shown ? word.height + 1 : 0);
      final x = rect.left + 28;
      final y = rect.center.dy - total / 2;
      title.paint(canvas, Offset(x, y));
      if (shown && word.width <= rect.width - 34) {
        word.paint(canvas, Offset(x, y + title.height + 1));
      }
      return;
    }
    final inner = rect.deflate(8);
    _paintNodeMark(
      canvas,
      Offset(inner.left + 7, inner.top + 7),
      7,
      standing,
      alpha,
    );
    final overdue = _plan.isOverdue(step);
    // Red and soft grey don't hold up on a coloured fill, so a late date says it in words.
    final due = scene.texts.get(
      overdue && filled ? 'Late · ${shortDate(step.due)}' : shortDate(step.due),
      TypeRamp.caption(
        _fade(filled ? _p.ink : (overdue ? _p.blocked : _p.inkSoft), alpha),
      ),
      _fitWidth(inner.width - 20 - (!mine && rect.width >= 150 ? 20 : 0)),
    );
    due.paint(canvas, Offset(inner.left + 20, inner.top));
    if (!mine && rect.width >= 150) {
      _paintAvatar(
        canvas,
        Offset(inner.right - 8, inner.top + 7),
        _plan.member(step.ownerId),
        alpha,
      );
    }
    final titleTop = inner.top + 21;
    // Room for the name, once the status has its line at the bottom.
    final lineHeight = word.height * 1.08;
    final room = inner.bottom - titleTop - word.height - 2;
    final lines = (room / lineHeight).floor().clamp(1, 3);
    // A notch smaller on narrow plates, so long words stay whole.
    final title = scene.texts.get(
      step.title,
      TypeRamp.label(_fade(_p.ink, alpha))
          .weighted(weight)
          .copyWith(fontSize: inner.width < 120 ? 12 : 13),
      // The cache rounds this up by less than the rectangle's own padding.
      inner.width,
      maxLines: lines,
    );
    title.paint(canvas, Offset(inner.left, titleTop));
    if (titleTop + title.height + word.height + 1 <= inner.bottom + 3) {
      word.paint(canvas, Offset(inner.left, inner.bottom - word.height + 2));
    }
  }

  /// A status mark on a dark or light disc, so it stands out on a coloured fill.
  void _paintNodeMark(
    Canvas canvas,
    Offset c,
    double r,
    Standing standing,
    double alpha,
  ) {
    if (statusFill(_p, standing) != null) {
      canvas.drawCircle(c, r + 2, Paint()..color = _fade(_p.ground, alpha));
    }
    paintStandingMark(canvas, c, r, standing, _p, alpha: alpha);
  }

  void _paintCardText(
    Canvas canvas,
    PlanStep step,
    Rect rect,
    double textAlpha,
  ) {
    final pad = 12.0;
    final inner = rect.deflate(pad);
    final filled = statusFill(_p, _plan.standing(step)) != null;
    final soft = filled ? _p.ink : _p.inkSoft;
    final overdue = _plan.isOverdue(step);
    _paintNodeMark(
      canvas,
      Offset(inner.left + 8, inner.top + 8),
      8,
      _plan.standing(step),
      textAlpha,
    );
    final standing = scene.texts.get(
      standingLabel(_plan.standing(step)),
      TypeRamp.caption(_fade(soft, textAlpha)).weighted(FontWeight.w600),
      inner.width - 118,
    );
    standing.paint(canvas, Offset(inner.left + 22, inner.top + 1));
    final due = scene.texts.get(
      overdue && filled ? 'Late · ${shortDate(step.due)}' : shortDate(step.due),
      TypeRamp.caption(
        _fade(
          filled ? _p.ink : (overdue ? _p.blocked : _p.inkFaint),
          textAlpha,
        ),
      ),
      90,
      align: TextAlign.right,
    );
    due.paint(canvas, Offset(inner.right - due.width, inner.top + 1));

    var y = inner.top + 24;
    final title = scene.texts.get(
      step.title,
      TypeRamp.heading(_fade(_p.ink, textAlpha)),
      inner.width,
      maxLines: 2,
    );
    title.paint(canvas, Offset(inner.left, y));
    y += title.height + 4;

    final footerTop = inner.bottom - 16;
    if (step.description.isNotEmpty && y + 18 < footerTop) {
      final lines = ((footerTop - y - 4) / 18).floor().clamp(1, 4);
      final body = scene.texts.get(
        step.description,
        TypeRamp.label(_fade(soft, textAlpha)),
        inner.width,
        maxLines: lines,
      );
      body.paint(canvas, Offset(inner.left, y));
      y += body.height + 6;
    }
    final nextItem = step.nextChecklistItem;
    if (nextItem != null &&
        step.status != StepStatus.done &&
        y + 16 < footerTop) {
      final next = scene.texts.get(
        'Next: $nextItem',
        TypeRamp.label(_fade(_p.ink, textAlpha)),
        inner.width,
      );
      next.paint(canvas, Offset(inner.left, y));
    }

    final parts = <String>[
      if (step.checklist.isNotEmpty)
        '${step.checklistDone}/${step.checklist.length} checked',
      if (step.resources.isNotEmpty) _count(step.resources.length, 'material'),
      if (step.comments > 0) _count(step.comments, 'comment'),
      if (step.newSuggestions > 0) _count(step.newSuggestions, 'suggestion'),
    ];
    if (parts.isNotEmpty) {
      final footer = scene.texts.get(
        parts.join(' · '),
        TypeRamp.caption(_fade(filled ? _p.ink : _p.inkFaint, textAlpha)),
        inner.width,
      );
      footer.paint(canvas, Offset(inner.left, footerTop));
    }
  }

  String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  void _paintBadge(Canvas canvas, Offset c, int count, double alpha) {
    final text = scene.texts.get(
      '$count',
      TypeRamp.caption(_fade(_p.ground, alpha)).copyWith(fontSize: 11),
      24,
    );
    final w = math.max(16.0, text.width + 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: w, height: 16),
        const Radius.circular(8),
      ),
      Paint()..color = _fade(_p.ink, alpha),
    );
    text.paint(canvas, c - Offset(text.width / 2, text.height / 2));
  }

  void _paintAvatar(Canvas canvas, Offset c, Member member, double alpha) {
    canvas.drawCircle(c, 10, Paint()..color = _fade(_p.control, alpha));
    final text = scene.texts.get(
      member.initials,
      TypeRamp.caption(_fade(_p.inkSoft, alpha)).copyWith(fontSize: 11),
      20,
    );
    text.paint(canvas, c - Offset(text.width / 2, text.height / 2));
  }

  void _paintRipple(Canvas canvas, Rect rect) {
    final t = Curves.easeOutCubic.transform(scene.celebrateT);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(28 * t), const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = _p.done.withValues(alpha: (1 - scene.celebrateT) * 0.8),
    );
  }

  void _paintUnlockedGlow(Canvas canvas, PlanStep step, Rect rect) {
    final id = scene.celebrateId;
    if (id == null || !step.dependsOn.contains(id)) return;
    final t = _smooth(0.45, 1, scene.celebrateT);
    if (t <= 0 || t >= 1) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(4 + 12 * t),
        const Radius.circular(10),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = _p.done.withValues(alpha: (1 - t) * 0.9),
    );
  }

  void _paintHandle(Canvas canvas, PlanStep step, Offset c, ZoomLevels levels) {
    final at = c + handleOffset(cameraNodeSize(_cam), _vertical);
    canvas.drawCircle(at, 10, Paint()..color = _p.raised);
    canvas.drawCircle(
      at,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _p.inkSoft,
    );
    final plus = Paint()
      ..color = _p.ink
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(at - const Offset(4, 0), at + const Offset(4, 0), plus);
    canvas.drawLine(at - const Offset(0, 4), at + const Offset(0, 4), plus);
  }

  void _paintLink(Canvas canvas) {
    final fromId = scene.linkFromId;
    final to = scene.linkTo;
    if (fromId == null || to == null) return;
    final a = _cam.toScreen(_position(fromId));
    final path = _edgePath(a, to);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = _p.ink,
    );
    canvas.drawCircle(to, 5, Paint()..color = _p.ink);
  }

  void _paintPhaseCards(Canvas canvas, ZoomLevels levels) {
    final layout = scene.controller.layout;
    final a = levels.phases;
    final nextPhase = _plan.steps[scene.nextId]?.phaseId;
    for (final phase in _plan.phases) {
      final band = layout.phaseBands[phase.id];
      if (band == null) continue;
      if (_vertical) {
        _paintSidePhaseCard(canvas, phase, band, a, phase.id == nextPhase);
        continue;
      }
      final left = _cam.toScreen(band.topLeft).dx;
      final right = _cam.toScreen(band.bottomRight).dx;
      final top = _stripEnd + 24.0;
      final width = right - left - 8;
      if (width < 40) continue;
      final rect = Rect.fromLTWH(left + 4, top, width, 116);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
      _paintGlassPlate(canvas, rrect, a);
      if (phase.id == nextPhase) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = _fade(_p.route, a),
        );
      }
      // A quiet measure of progress, not a reward: one ink, thin, no end caps.
      final progress = _plan.phaseProgress(phase.id);
      final ring = rect.topLeft + const Offset(26, 26);
      canvas.drawCircle(
        ring,
        13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _fade(_p.control, a),
      );
      canvas.drawArc(
        Rect.fromCircle(center: ring, radius: 13),
        -math.pi / 2,
        progress * math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _fade(_p.inkSoft, a),
      );
      final title = scene.texts.get(
        phase.title,
        TypeRamp.label(_fade(_p.ink, a)).weighted(FontWeight.w600),
        rect.width - 20,
      );
      title.paint(canvas, Offset(rect.left + 12, rect.top + 50));
      final steps = _plan.stepsIn(phase.id);
      final finished = steps.where((s) => s.status == StepStatus.done).length;
      final caption = scene.texts.get(
        '$finished of ${steps.length} done',
        TypeRamp.caption(_fade(_p.inkSoft, a)),
        rect.width - 20,
        maxLines: 2,
      );
      caption.paint(
        canvas,
        Offset(rect.left + 12, rect.top + 50 + title.height + 3),
      );
    }
  }

  /// A phase card at the far zoom when phases run down the screen.
  void _paintSidePhaseCard(
    Canvas canvas,
    Phase phase,
    Rect band,
    double a,
    bool holdsNext,
  ) {
    final top = _cam.toScreen(band.topLeft).dy;
    final bottom = _cam.toScreen(band.bottomLeft).dy;
    final height = math.min(bottom - top - 8, 72.0);
    if (height < 34) return;
    final rect = Rect.fromLTWH(
      _gutterEnd + 6,
      top + (bottom - top - height) / 2,
      156,
      height,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    _paintGlassPlate(canvas, rrect, a);
    if (holdsNext) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _fade(_p.route, a),
      );
    }
    final progress = _plan.phaseProgress(phase.id);
    final ring = Offset(rect.left + 20, rect.center.dy);
    canvas.drawCircle(
      ring,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _fade(_p.control, a),
    );
    canvas.drawArc(
      Rect.fromCircle(center: ring, radius: 10),
      -math.pi / 2,
      progress * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _fade(_p.inkSoft, a),
    );
    final steps = _plan.stepsIn(phase.id);
    final finished = steps.where((s) => s.status == StepStatus.done).length;
    final title = scene.texts.get(
      phase.title,
      TypeRamp.label(_fade(_p.ink, a)).weighted(FontWeight.w600),
      rect.width - 48,
    );
    final caption = scene.texts.get(
      '$finished of ${steps.length} done',
      TypeRamp.caption(_fade(_p.inkSoft, a)),
      rect.width - 48,
    );
    final textTop = rect.center.dy - (title.height + caption.height + 2) / 2;
    title.paint(canvas, Offset(rect.left + 38, textTop));
    caption.paint(canvas, Offset(rect.left + 38, textTop + title.height + 2));
  }

  /// Phase names stay at the left edge when phases run down the screen. On a
  /// phone's slim column they turn on their side to fit.
  void _paintPhaseGutter(Canvas canvas) {
    final pane = gutterPaneFor(_cam);
    final layout = scene.controller.layout;
    final style = TypeRamp.label(_p.ink).weighted(FontWeight.w600);
    canvas.save();
    canvas.clipRect(pane);
    for (final phase in _plan.phases) {
      final band = layout.phaseBands[phase.id];
      if (band == null) continue;
      final top = math.max(_cam.toScreen(band.topLeft).dy, pane.top);
      final bottom = math.min(_cam.toScreen(band.bottomLeft).dy, pane.bottom);
      final room = bottom - top;
      if (room < 28) continue;
      final y = (top + bottom) / 2;
      if (pane.width < 60) {
        final title = scene.texts.get(phase.title, style, room - 8);
        canvas.save();
        canvas.translate(pane.center.dx, y);
        canvas.rotate(-math.pi / 2);
        title.paint(canvas, Offset(-title.width / 2, -title.height / 2));
        canvas.restore();
      } else {
        final title = scene.texts.get(
          phase.title,
          style,
          pane.width - 12,
          maxLines: 3,
          align: TextAlign.center,
        );
        title.paint(
          canvas,
          Offset(pane.center.dx - title.width / 2, y - title.height / 2),
        );
      }
    }
    canvas.restore();
  }

  /// Members stay along the top when lanes run down the screen.
  void _paintMemberStrip(Canvas canvas) {
    final pane = stripPaneFor(_cam);
    final layout = scene.controller.layout;
    canvas.save();
    canvas.clipRect(pane);
    for (final member in _plan.members) {
      final lane = layout.laneBands[member.id];
      if (lane == null) continue;
      final left = math.max(_cam.toScreen(lane.topLeft).dx, _gutterEnd);
      final right = math.min(_cam.toScreen(lane.topRight).dx, pane.right);
      if (right - left < 26) continue;
      final mine = member.id == _plan.meId;
      final alpha = mine ? 1.0 : _lerp(1, 0.4, scene.focus);
      final radius = math.min(pane.height / 2 - 3, 13.0);
      final name = scene.texts.get(
        member.name,
        TypeRamp.caption(_fade(mine ? _p.ink : _p.inkSoft, alpha)),
        math.max(right - left - radius * 2 - 14, 8),
      );
      final showName = right - left > radius * 2 + 44;
      final total = radius * 2 + (showName ? name.width + 6 : 0);
      final x = (left + right - total) / 2;
      final c = Offset(x + radius, pane.center.dy);
      canvas.drawCircle(
        c,
        radius,
        Paint()..color = _fade(mine ? _p.route : _p.control, alpha),
      );
      final letter = scene.texts.get(
        member.initials,
        TypeRamp.caption(_fade(mine ? _p.onRoute : _p.inkSoft, alpha))
            .copyWith(fontSize: 11),
        radius * 2,
      );
      letter.paint(canvas, c - Offset(letter.width / 2, letter.height / 2));
      if (showName) {
        name.paint(canvas, Offset(c.dx + radius + 6, c.dy - name.height / 2));
      }
    }
    canvas.restore();
  }

  void _paintLaneGutter(Canvas canvas) {
    final pane = gutterPaneFor(_cam);
    final layout = scene.controller.layout;
    canvas.save();
    canvas.clipRect(pane);
    final mid = pane.center.dx;
    for (final member in _plan.members) {
      final lane = layout.laneBands[member.id];
      if (lane == null) continue;
      final top = _cam.toScreen(lane.topLeft).dy;
      final bottom = _cam.toScreen(lane.bottomLeft).dy;
      if (bottom < pane.top || top > pane.bottom) continue;
      final visibleTop = math.max(top, pane.top);
      final y = (visibleTop + math.min(bottom, pane.bottom)) / 2;
      final mine = member.id == _plan.meId;
      final height = bottom - top;
      final alpha = mine ? 1.0 : _lerp(1, 0.4, scene.focus);
      if (pane.width < 60 && height >= 30) {
        final c = Offset(mid, y);
        canvas.drawCircle(
          c,
          14,
          Paint()..color = _fade(mine ? _p.route : _p.control, alpha),
        );
        final letter = scene.texts.get(
          member.initials,
          TypeRamp.caption(_fade(mine ? _p.onRoute : _p.inkSoft, alpha))
              .copyWith(fontSize: 11),
          28,
        );
        letter.paint(canvas, c - Offset(letter.width / 2, letter.height / 2));
        continue;
      }
      if (height < 56) {
        final name = scene.texts.get(
          member.initials,
          TypeRamp.caption(_fade(mine ? _p.route : _p.inkSoft, alpha)),
          pane.width - 12,
          align: TextAlign.center,
        );
        name.paint(canvas, Offset(mid - name.width / 2, y - name.height / 2));
        continue;
      }
      final c = Offset(mid, y - 10);
      canvas.drawCircle(
        c,
        14,
        Paint()..color = _fade(mine ? _p.route : _p.control, alpha),
      );
      final initials = scene.texts.get(
        member.initials,
        TypeRamp.caption(_fade(mine ? _p.onRoute : _p.inkSoft, alpha))
            .copyWith(fontSize: 11),
        28,
      );
      initials.paint(
        canvas,
        c - Offset(initials.width / 2, initials.height / 2),
      );
      final name = scene.texts.get(
        member.name,
        TypeRamp.caption(_fade(mine ? _p.ink : _p.inkSoft, alpha)),
        pane.width - 10,
        align: TextAlign.center,
      );
      name.paint(canvas, Offset(mid - name.width / 2, y + 7));
    }
    canvas.restore();
  }

  void _paintPhaseStrip(Canvas canvas) {
    final pane = stripPaneFor(_cam);
    final layout = scene.controller.layout;
    canvas.save();
    canvas.clipRect(pane);
    for (final phase in _plan.phases) {
      final band = layout.phaseBands[phase.id];
      if (band == null) continue;
      final left = _cam.toScreen(band.topLeft).dx;
      final right = _cam.toScreen(band.bottomRight).dx;
      if (right < _gutterEnd || left > pane.right) continue;
      final room = right - math.max(left, _gutterEnd) - 24;
      if (room < 28) continue;
      final title = scene.texts.get(
        phase.title,
        (pane.height < 44
            ? TypeRamp.label(_p.ink).weighted(FontWeight.w600)
            : TypeRamp.heading(_p.ink)),
        room,
      );
      final x = math.max(left + 14, _gutterEnd + 14).toDouble();
      title.paint(canvas, Offset(x, pane.center.dy - title.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GraphPainter old) => old.scene != scene;
}

/// A status drawn as a mark first and a colour second, so the graph still reads
/// in greyscale and for people who can't tell the colours apart.
void paintStandingMark(
  Canvas canvas,
  Offset c,
  double r,
  Standing standing,
  Palette p, {
  double alpha = 1,
}) {
  final colour = _fade(p.standing(standing), alpha);
  final fill = Paint()..color = colour;
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.6, r * 0.22)
    ..color = colour;
  final ground = Paint()..color = _fade(p.ground, alpha);
  switch (standing) {
    case Standing.done:
      canvas.drawCircle(c, r, fill);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.42, c.dy + r * 0.02)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.34)
          ..lineTo(c.dx + r * 0.46, c.dy - r * 0.32),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, r * 0.2)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _fade(p.ground, alpha),
      );
    case Standing.doing:
      canvas.drawCircle(c, r, ground);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        math.pi,
        true,
        fill,
      );
      canvas.drawCircle(c, r, ring);
    case Standing.review:
      canvas.drawCircle(c, r, ground);
      canvas.drawCircle(c, r * 0.5, fill);
      canvas.drawCircle(c, r, ring);
    case Standing.ready:
      canvas.drawCircle(c, r, ground);
      canvas.drawCircle(c, r, ring);
    case Standing.waiting:
      canvas.drawCircle(c, r, ground);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, r * 0.12)
          ..color = colour,
      );
      canvas.drawCircle(c, math.max(1.4, r * 0.16), fill);
    case Standing.blocked:
      canvas.drawCircle(c, r, ground);
      canvas.drawCircle(c, r, ring);
      canvas.drawLine(
        c + Offset(-r * 0.68, -r * 0.68),
        c + Offset(r * 0.68, r * 0.68),
        ring,
      );
  }
}

/// A small sample of a status's colour, for the map key. It carries the drawn
/// mark too, because lists and panels use the marks.
class StatusSwatch extends StatelessWidget {
  const StatusSwatch(this.standing, {super.key});

  final Standing standing;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(34, 20),
      painter: _SwatchPainter(standing, Palette.of(context)),
      child: SizedBox(
        width: 34,
        height: 20,
        child: Center(child: StandingMark(standing, size: 14)),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.standing, this.palette);
  final Standing standing;
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    final status = statusFill(palette, standing);
    final fill = Paint();
    if (status == null) {
      fill.color = palette.nodeBottom;
    } else {
      fill.shader = status.shader(Offset.zero & size, 1);
    }
    canvas.drawRRect(shape, fill);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = palette.nodeRim,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.standing != standing || old.palette != palette;
}

/// Stand-alone painter for marks in lists and panels.
class StandingMark extends StatelessWidget {
  const StandingMark(this.standing, {super.key, this.size = 18});

  final Standing standing;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(standing, Palette.of(context)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.standing, this.palette);
  final Standing standing;
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) => paintStandingMark(
    canvas,
    size.center(Offset.zero),
    size.width / 2 - 1,
    standing,
    palette,
  );

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.standing != standing || old.palette != palette;
}
