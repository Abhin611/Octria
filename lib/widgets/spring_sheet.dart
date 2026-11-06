import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../graph/camera.dart';

SpringDescription _spring(double response, double dampingRatio) {
  final omega = 2 * math.pi / response;
  return SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: omega * omega,
    ratio: dampingRatio,
  );
}

/// A panel that slides in from the right and leaves the same way. A spring from
/// the current value means it can reverse mid-flight without a jump.
class SidePanelHost extends StatefulWidget {
  const SidePanelHost({
    super.key,
    required this.open,
    required this.width,
    required this.child,
  });

  final bool open;
  final double width;
  final Widget child;

  @override
  State<SidePanelHost> createState() => _SidePanelHostState();
}

class _SidePanelHostState extends State<SidePanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.open ? 0 : 1,
  );

  @override
  void didUpdateWidget(SidePanelHost old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    final target = widget.open ? 0.0 : 1.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.animateTo(target, duration: const Duration(milliseconds: 160));
      return;
    }
    _c.animateWith(
      SpringSimulation(_spring(0.34, 1), _c.value, target, _c.velocity),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value.clamp(0.0, 1.0);
        if (t >= 1) return const SizedBox.shrink();
        return Opacity(
          opacity: 1 - t * t,
          child: Transform.translate(
            offset: Offset(reduce ? 0 : t * (widget.width + 24), 0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A bottom sheet that follows the finger, keeps its velocity on release and
/// aims at where the flick was going.
class BottomSheetHost extends StatefulWidget {
  const BottomSheetHost({
    super.key,
    required this.open,
    required this.height,
    required this.builder,
    required this.onDismissed,
    this.boxed = false,
  });

  final bool open;
  final double height;

  /// A box of glass that opens whole inside its frame, rather than a sheet
  /// that rests halfway up the screen; dragging down still closes it.
  final bool boxed;
  final Widget Function(BuildContext, Widget grabber) builder;
  final VoidCallback onDismissed;

  @override
  State<BottomSheetHost> createState() => _BottomSheetHostState();
}

class _BottomSheetHostState extends State<BottomSheetHost>
    with SingleTickerProviderStateMixin {
  // Distance the sheet's top sits below the available height's top.
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.height,
  );

  double get _medium => widget.boxed ? 0 : widget.height * 0.42;
  double get _large => widget.boxed ? 0 : widget.height * 0.08;
  double get _closed => widget.height;

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _settle(_medium, 0));
    }
  }

  @override
  void didUpdateWidget(BottomSheetHost old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) {
      _settle(widget.open ? _medium : _closed, _c.velocity);
    }
  }

  void _settle(double target, double velocity, {double dampingRatio = 1}) {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.animateTo(target, duration: const Duration(milliseconds: 160));
      return;
    }
    _c.animateWith(
      SpringSimulation(_spring(0.32, dampingRatio), _c.value, target, velocity),
    );
  }

  void _onDragUpdate(DragUpdateDetails d) {
    var next = _c.value + d.delta.dy;
    if (next < _large) {
      next = _large - rubberBand(_large - next, widget.height) * 0.5;
    }
    _c.value = next;
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    final projected = _c.value + projectMomentum(v);
    final snaps = [_large, _medium, _closed];
    snaps.sort(
      (a, b) => (a - projected).abs().compareTo((b - projected).abs()),
    );
    final target = snaps.first;
    if (target == _closed) {
      widget.onDismissed();
    } else {
      // A flick earns a little overshoot; a slow drag does not.
      _settle(target, v, dampingRatio: v.abs() > 500 ? 0.85 : 1);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grabber = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: const SizedBox(
        height: 28,
        width: double.infinity,
        child: Center(child: _GrabHandle()),
      ),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        if (_c.value >= _closed - 0.5 && !widget.open) {
          return const SizedBox.shrink();
        }
        return Transform.translate(offset: Offset(0, _c.value), child: child);
      },
      child: SizedBox(
        height: widget.height,
        child: widget.builder(context, grabber),
      ),
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0x668B8E82),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Slide to mark a step done. The thumb tracks the finger 1:1 and commits on
/// where the release was heading.
class SwipeToDone extends StatefulWidget {
  const SwipeToDone({
    super.key,
    required this.label,
    required this.trackColor,
    required this.thumbColor,
    required this.thumb,
    required this.textStyle,
    required this.onCommit,
  });

  final String label;
  final Color trackColor;
  final Color thumbColor;
  final Widget thumb;
  final TextStyle textStyle;
  final VoidCallback onCommit;

  @override
  State<SwipeToDone> createState() => _SwipeToDoneState();
}

class _SwipeToDoneState extends State<SwipeToDone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );
  double _max = 1;

  void _end(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dx;
    final commits = _c.value + projectMomentum(v, 0.99) > _max * 0.6;
    if (commits) widget.onCommit();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 0;
      return;
    }
    _c.animateWith(SpringSimulation(_spring(0.3, 1), _c.value, 0, v));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onCommit,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _max = constraints.maxWidth - size - 6;
          return Container(
            height: size + 6,
            decoration: BoxDecoration(
              color: widget.trackColor,
              borderRadius: BorderRadius.circular((size + 6) / 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(widget.label, style: widget.textStyle),
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => Positioned(
                    left: 3 + _c.value.clamp(0.0, _max),
                    child: child!,
                  ),
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) => _c.value += d.delta.dx,
                    onHorizontalDragEnd: _end,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: widget.thumbColor,
                        shape: BoxShape.circle,
                      ),
                      child: widget.thumb,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
