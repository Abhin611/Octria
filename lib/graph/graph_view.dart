import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'camera.dart';
import 'graph_painter.dart';
import 'plan_controller.dart';

enum _Drag { none, pan, move, link }

/// The canvas: draws the graph and turns pointer, touch and keyboard input into
/// camera moves and edits.
class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.controller,
    required this.camera,
    required this.filter,
    required this.focus,
    required this.celebration,
    required this.celebrateId,
    required this.selectedId,
    required this.selectedEdge,
    required this.linkFromId,
    required this.onSelect,
    required this.onSelectEdge,
    required this.onContextMenu,
    required this.onLinked,
    required this.onMoved,
    required this.onToggleFocus,
    required this.onMarkDone,
    required this.onStartLink,
    required this.onViewportReady,
    required this.onFitPhase,
    required this.onToggleDirection,
  });

  final PlanController controller;
  final GraphCamera camera;
  final GraphFilter filter;
  final Animation<double> focus;
  final Animation<double> celebration;
  final String? celebrateId;
  final String? selectedId;
  final (String, String)? selectedEdge;
  final String? linkFromId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<(String, String)> onSelectEdge;
  final void Function(String id, Offset globalPosition) onContextMenu;

  /// [toId] now depends on [fromId].
  final void Function(String fromId, String toId) onLinked;
  final void Function(String id) onMoved;
  final VoidCallback onToggleFocus;
  final ValueChanged<String> onMarkDone;
  final ValueChanged<String> onStartLink;
  final VoidCallback onViewportReady;

  /// Frames one whole phase.
  final ValueChanged<String> onFitPhase;
  final VoidCallback onToggleDirection;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  final TextCache _texts = TextCache();
  final FocusNode _focusNode = FocusNode(debugLabel: 'graph');

  _Drag _drag = _Drag.none;
  double _lastScale = 1;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  bool _longPressMoved = false;
  Offset _downAt = Offset.zero;

  String? _hoveredId;
  bool _hoveringEdge = false;
  String? _pressedId;
  String? _movingId;
  Offset? _movingAt;
  Offset _grabOffset = Offset.zero;
  (String, String)? _dropCell;
  String? _linkId;
  Offset? _linkTo;
  String? _linkTargetId;
  Size _lastSize = Size.zero;

  GraphCamera get _camera => widget.camera;
  PlanController get _controller => widget.controller;

  @override
  void dispose() {
    _texts.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Hit testing ---------------------------------------------------------------

  String? _hitNode(Offset local) {
    if (local.dx < gutterEndFor(_camera) || local.dy < stripEndFor(_camera)) {
      return null;
    }
    final levels = ZoomLevels(_camera.scale);
    if (levels.steps < 0.5) return null;
    final reach = _kind == PointerDeviceKind.touch ? 6.0 : 2.0;
    final size = cameraNodeSize(_camera);
    for (final s in _controller.plan.steps.values) {
      final c = _camera.toScreen(_controller.positions[s.id] ?? Offset.zero);
      final rect = Rect.fromCenter(
        center: c,
        width: size.width,
        height: size.height,
      ).inflate(reach);
      if (rect.contains(local)) return s.id;
    }
    return null;
  }

  /// The nearest arrow to a point, as (from, to). Generous on touch, because a
  /// line is a thin thing to hit with a finger.
  (String, String)? _hitEdge(Offset local) {
    if (local.dx < gutterEndFor(_camera) ||
        local.dy < stripEndFor(_camera) ||
        ZoomLevels(_camera.scale).steps < 0.5) {
      return null;
    }
    var best = _kind == PointerDeviceKind.touch ? 18.0 : 8.0;
    (String, String)? hit;
    final positions = _controller.positions;
    for (final to in _controller.plan.steps.values) {
      for (final fromId in to.dependsOn) {
        final fromAt = positions[fromId];
        final toAt = positions[to.id];
        if (fromAt == null || toAt == null) continue;
        final points = edgeLineFor(
          _controller.layout,
          _camera,
          fromId,
          to.id,
          fromAt,
          toAt,
        ).points;
        for (var i = 0; i < points.length - 1; i++) {
          final d = _distanceToSegment(local, points[i], points[i + 1]);
          if (d < best) {
            best = d;
            hit = (fromId, to.id);
          }
        }
      }
    }
    return hit;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared)
        .clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  String? _hitHandle(Offset local) {
    final offset = handleOffset(
      cameraNodeSize(_camera),
      _controller.layout.vertical,
    );
    for (final id in {widget.selectedId, _hoveredId}) {
      if (id == null) continue;
      if (_controller.plan.steps[id] == null) continue;
      final c = _camera.toScreen(_controller.positions[id] ?? Offset.zero);
      final at = c + offset;
      if ((at - local).distance < 20) return id;
    }
    return null;
  }

  /// Frames the phase under a point, returning whether there was one.
  bool _fitPhaseAt(Offset local) {
    final world = _camera.toWorld(local);
    final vertical = _controller.layout.vertical;
    for (final band in _controller.layout.phaseBands.entries) {
      final inside = vertical
          ? world.dy >= band.value.top && world.dy < band.value.bottom
          : world.dx >= band.value.left && world.dx < band.value.right;
      if (inside) {
        widget.onFitPhase(band.key);
        return true;
      }
    }
    return false;
  }

  // Gestures ------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent e) {
    _kind = e.kind;
    _downAt = e.localPosition;
    _focusNode.requestFocus();
    // Feedback lands on the press, before the gesture is even recognised.
    setState(() => _pressedId = _hitNode(e.localPosition));
  }

  void _onPointerUp(PointerEvent e) {
    if (_pressedId != null) setState(() => _pressedId = null);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final scroll = event as PointerScrollEvent;
        final keys = HardwareKeyboard.instance;
        if (keys.isControlPressed || keys.isMetaPressed) {
          final factor = 1 - scroll.scrollDelta.dy * 0.0016;
          _camera.zoomAround(scroll.localPosition, factor.clamp(0.8, 1.25));
        } else {
          _camera.panBy(-scroll.scrollDelta);
        }
        _camera.release(Offset.zero);
      });
    } else if (e is PointerScaleEvent) {
      _camera.zoomAround(e.localPosition, e.scale);
      _camera.release(Offset.zero);
    }
  }

  void _onHover(PointerHoverEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    _kind = e.kind;
    final handle = _hitHandle(e.localPosition);
    final node = handle ?? _hitNode(e.localPosition);
    final overEdge = node == null && _hitEdge(e.localPosition) != null;
    if (node != _hoveredId || overEdge != _hoveringEdge) {
      setState(() {
        _hoveredId = node;
        _hoveringEdge = overEdge;
      });
    }
  }

  void _beginMove(String id, Offset local) {
    final centre = _camera.toScreen(_controller.positions[id] ?? Offset.zero);
    _grabOffset = local - centre; // Stay under the finger where it was grabbed.
    setState(() {
      _drag = _Drag.move;
      _movingId = id;
      _movingAt = _controller.positions[id];
      _pressedId = null;
    });
    HapticFeedback.selectionClick();
  }

  void _updateMove(Offset local) {
    final world = _camera.toWorld(local - _grabOffset);
    setState(() {
      _movingAt = world;
      _dropCell = _controller.layout.cellAt(world);
    });
  }

  void _endMove() {
    final id = _movingId;
    final at = _movingAt;
    final cell = _dropCell;
    setState(() {
      _drag = _Drag.none;
      _movingId = null;
      _movingAt = null;
      _dropCell = null;
    });
    if (id == null || at == null) return;
    final step = _controller.plan.steps[id];
    if (step == null) return;
    if (cell != null && (cell.$1 != step.phaseId || cell.$2 != step.ownerId)) {
      _controller.moveStep(
        id,
        phaseId: cell.$1,
        ownerId: cell.$2,
        droppedAt: at,
      );
      HapticFeedback.mediumImpact();
      widget.onMoved(id);
    } else {
      // Dropped where it started: return from the release point.
      _controller.settleFrom(id, at);
    }
  }

  void _updateLink(Offset local) {
    final target = _hitNode(local);
    setState(() {
      _linkTo = local;
      _linkTargetId = target == _linkId ? null : target;
    });
  }

  void _endLink() {
    final from = _linkId;
    final to = _linkTargetId;
    setState(() {
      _drag = _Drag.none;
      _linkId = null;
      _linkTo = null;
      _linkTargetId = null;
    });
    if (from != null && to != null) widget.onLinked(from, to);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastScale = 1;
    // Decide from where the press began; the finger has moved on by now.
    final handle = _hitHandle(_downAt);
    if (handle != null && d.pointerCount == 1) {
      setState(() {
        _drag = _Drag.link;
        _linkId = handle;
        _linkTo = d.localFocalPoint;
        _pressedId = null;
      });
      return;
    }
    if (_kind == PointerDeviceKind.mouse && d.pointerCount == 1) {
      final node = _hitNode(_downAt);
      if (node != null) {
        _beginMove(node, _downAt);
        return;
      }
    }
    _drag = _Drag.pan;
    if (_pressedId != null) setState(() => _pressedId = null);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    switch (_drag) {
      case _Drag.move:
        _updateMove(d.localFocalPoint);
      case _Drag.link:
        _updateLink(d.localFocalPoint);
      case _Drag.pan:
      case _Drag.none:
        _camera.panBy(d.focalPointDelta);
        if (d.scale != _lastScale && d.scale > 0) {
          _camera.zoomAround(d.localFocalPoint, d.scale / _lastScale);
          _lastScale = d.scale;
        }
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    switch (_drag) {
      case _Drag.move:
        _endMove();
      case _Drag.link:
        _endLink();
      case _Drag.pan:
      case _Drag.none:
        _camera.release(d.velocity.pixelsPerSecond);
        _drag = _Drag.none;
    }
  }

  void _onTapUp(TapUpDetails d) {
    _focusNode.requestFocus();
    final hit = _hitNode(d.localPosition);
    final linkFrom = widget.linkFromId;
    if (linkFrom != null) {
      if (hit != null && hit != linkFrom) widget.onLinked(linkFrom, hit);
      widget.onStartLink('');
      return;
    }
    // Tapping a phase's name, or its card when zoomed out, frames that phase.
    final inStrip = d.localPosition.dy < stripEndFor(_camera);
    final inGutter = d.localPosition.dx < gutterEndFor(_camera);
    final onPhaseName = _controller.layout.vertical
        ? inGutter && !inStrip
        : inStrip && !inGutter;
    if (onPhaseName && _fitPhaseAt(d.localPosition)) {
      return;
    }
    if (ZoomLevels(_camera.scale).phases > 0.5) {
      _fitPhaseAt(d.localPosition);
      return;
    }
    if (hit == null) {
      final edge = _hitEdge(d.localPosition);
      if (edge != null) {
        HapticFeedback.selectionClick();
        widget.onSelectEdge(edge);
        return;
      }
    }
    widget.onSelect(hit);
  }

  void _onSecondaryTapUp(TapUpDetails d) {
    final hit = _hitNode(d.localPosition);
    if (hit != null) widget.onContextMenu(hit, d.globalPosition);
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (_kind == PointerDeviceKind.mouse) return;
    final hit = _hitNode(d.localPosition);
    if (hit == null) return;
    _longPressMoved = false;
    _beginMove(hit, d.localPosition);
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_drag != _Drag.move) return;
    if (d.offsetFromOrigin.distance > 10) _longPressMoved = true;
    if (_longPressMoved) _updateMove(d.localPosition);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (_drag != _Drag.move) return;
    if (_longPressMoved) {
      _endMove();
      return;
    }
    final id = _movingId;
    setState(() {
      _drag = _Drag.none;
      _movingId = null;
      _movingAt = null;
      _dropCell = null;
    });
    if (id != null) widget.onContextMenu(id, d.globalPosition);
  }

  // Keyboard ------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    const step = 90.0;
    final selected = widget.selectedId;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _nudge(const Offset(step, 0));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _nudge(const Offset(-step, 0));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _nudge(const Offset(0, step));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _nudge(const Offset(0, -step));
    } else if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.25);
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(0.8);
    } else if (key == LogicalKeyboardKey.digit0) {
      _camera.fit(fitPadding);
    } else if (key == LogicalKeyboardKey.keyV) {
      widget.onToggleDirection();
    } else if (key == LogicalKeyboardKey.keyF) {
      widget.onToggleFocus();
    } else if (key == LogicalKeyboardKey.keyD && selected != null) {
      widget.onMarkDone(selected);
    } else if (key == LogicalKeyboardKey.keyL && selected != null) {
      widget.onStartLink(selected);
    } else if (key == LogicalKeyboardKey.escape) {
      if (widget.linkFromId != null) {
        widget.onStartLink('');
      } else {
        widget.onSelect(null);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _nudge(Offset delta) =>
      _camera.moveTo(_camera.pan + delta, _camera.scale);

  void _zoomBy(double factor) => _camera.zoomStep(factor);

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    _texts.scaler = MediaQuery.textScalerOf(context);
    _camera.reduceMotion = MediaQuery.disableAnimationsOf(context);
    _controller.reduceMotion = _camera.reduceMotion;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _camera.viewport = size;
        _camera.world = _controller.layout.size;
        if (size != _lastSize) {
          // Reframe on first layout and when the device is turned.
          final reframe =
              _lastSize == Size.zero ||
              (size.width > size.height) !=
                  (_lastSize.width > _lastSize.height);
          _lastSize = size;
          if (reframe) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onViewportReady();
            });
          }
        }
        return Semantics(
          label:
              'Plan graph for ${_controller.plan.title}. Switch to the List view '
              'for the same plan in a form that works with screen readers.',
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKey,
            child: MouseRegion(
              cursor: _cursor,
              onHover: _onHover,
              onExit: (_) {
                if (_hoveredId != null) setState(() => _hoveredId = null);
              },
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
                onPointerSignal: _onPointerSignal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onTapUp,
                  onSecondaryTapUp: _onSecondaryTapUp,
                  onLongPressStart: _onLongPressStart,
                  onLongPressMoveUpdate: _onLongPressMove,
                  onLongPressEnd: _onLongPressEnd,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      _controller,
                      widget.focus,
                      widget.celebration,
                    ]),
                    builder: (context, _) {
                      final plan = _controller.plan;
                      final scene = GraphScene(
                        controller: _controller,
                        camera: _camera,
                        palette: palette,
                        filter: widget.filter,
                        focus: widget.focus.value,
                        selectedId: widget.selectedId,
                        selectedEdge: widget.selectedEdge,
                        hoveredId: _hoveredId,
                        pressedId: _pressedId,
                        nextId: plan.nextStepFor(plan.meId)?.id,
                        celebrateId: widget.celebrateId,
                        celebrateT: widget.celebration.value,
                        movingId: _movingId,
                        movingAt: _movingAt,
                        dropCell: _dropCell,
                        linkFromId: _linkId,
                        linkTo: _linkTo,
                        linkTargetId: _linkTargetId,
                        texts: _texts,
                      );
                      final strip = stripPaneFor(_camera);
                      final gutter = gutterPaneFor(_camera);
                      // Map, then glass, then the names sitting on the glass.
                      return ClipRect(
                        child: Stack(
                          children: [
                            CustomPaint(
                              size: size,
                              isComplex: true,
                              painter: GraphPainter(scene, repaint: _camera),
                            ),
                            Positioned.fromRect(
                              rect: strip,
                              child: GlassPanel(
                                radius: strip.height / 2,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            Positioned.fromRect(
                              rect: gutter,
                              child: GlassPanel(
                                radius: gutter.width < 60 ? 22 : 20,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            CustomPaint(
                              size: size,
                              painter: GraphPainter(
                                scene,
                                repaint: _camera,
                                headers: true,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  MouseCursor get _cursor {
    if (_drag == _Drag.move || _drag == _Drag.link) {
      return SystemMouseCursors.grabbing;
    }
    if (widget.linkFromId != null) return SystemMouseCursors.precise;
    return _hoveredId != null || _hoveringEdge
        ? SystemMouseCursors.click
        : SystemMouseCursors.grab;
  }
}

/// Room around the plan when fitting it to the screen.
const EdgeInsets fitPadding = EdgeInsets.fromLTRB(28, 56, 16, 24);

/// Paints the plan's outline, the route and the current view.
class Minimap extends StatelessWidget {
  const Minimap({super.key, required this.controller, required this.camera});

  final PlanController controller;
  final GraphCamera camera;

  void _jump(Offset local, Size size) {
    final world = controller.layout.size;
    camera.centreOn(
      Offset(
        local.dx / size.width * world.width,
        local.dy / size.height * world.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const size = Size(176, 104);
    return Semantics(
      label: 'Minimap. Drag to move around the plan.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _jump(d.localPosition, size),
        onPanUpdate: (d) => _jump(d.localPosition, size),
        child: CustomPaint(
          size: size,
          painter: _MinimapPainter(controller, camera, Palette.of(context)),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.controller, this.camera, this.palette)
    : super(repaint: Listenable.merge([controller, camera]));

  final PlanController controller;
  final GraphCamera camera;
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final plan = controller.plan;
    // Each axis fills the panel, so very wide plans stay readable.
    final world = controller.layout.size;
    Offset map(Offset w) => Offset(
      w.dx / world.width * size.width,
      w.dy / world.height * size.height,
    );

    final dot = Paint();
    for (final s in plan.steps.values) {
      final p = controller.positions[s.id];
      if (p == null) continue;
      final mine = s.ownerId == plan.meId;
      dot.color = mine
          ? palette.route
          : palette.inkFaint.withValues(alpha: 0.6);
      canvas.drawCircle(map(p), mine ? 2.4 : 1.5, dot);
    }
    final view = camera.visibleWorld;
    final frame = Rect.fromPoints(map(view.topLeft), map(view.bottomRight));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        // Stays big enough to see even when zoomed far into a large plan.
        Rect.fromCenter(
          center: frame.center,
          width: frame.width < 16 ? 16 : frame.width,
          height: frame.height < 12 ? 12 : frame.height,
        ).intersect((Offset.zero & size).deflate(1)),
        const Radius.circular(4),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette.ink,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => old.palette != palette;
}
