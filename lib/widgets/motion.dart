import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../theme/tokens.dart';

/// Rises into place as it first appears, a beat after whatever came before it.
class Rise extends StatelessWidget {
  const Rise({super.key, required this.child, this.index = 0});

  final Widget child;

  /// Its place in the sequence. Long lists stop adding delay after a few.
  final int index;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // Short and close together: a page is seen many times a day.
    final delay = math.min(index, 8) * 34;
    final total = 300 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Motion.out),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 10),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Gives way under the finger straight away. Under a mouse, light follows
/// the pointer across it, as it would across a pane of glass.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    required this.label,
    this.radius = 16,
  });

  final Widget child;
  final VoidCallback onTap;
  final String label;

  /// The corner radius of what's inside, so the light stays within it.
  final double radius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _down = false;
  var _over = false;

  /// Where the pointer is over it.
  final _at = ValueNotifier<Offset>(Offset.zero);

  @override
  void dispose() {
    _at.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (e) {
          _at.value = e.localPosition;
          setState(() => _over = true);
        },
        onHover: (e) => _at.value = e.localPosition,
        onExit: (_) => setState(() => _over = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.97 : 1.0,
            duration: _down ? Duration.zero : Motion.press,
            curve: Motion.out,
            child: Stack(
              children: [
                widget.child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _over ? 1 : 0,
                      duration: still ? Duration.zero : Motion.quick,
                      curve: Curves.ease,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _GlintPainter(
                            _at,
                            widget.radius,
                            p.brightness == Brightness.dark
                                ? const Color(0x1FFFFFFF)
                                : const Color(0x8CFFFFFF),
                            p.brightness == Brightness.dark
                                ? const Color(0x33FFFFFF)
                                : const Color(0xB3FFFFFF),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft pool of light under the pointer, and a brighter edge near it.
class _GlintPainter extends CustomPainter {
  _GlintPainter(this.at, this.radius, this.light, this.edge)
    : super(repaint: at);

  final ValueListenable<Offset> at;
  final double radius;
  final Color light;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final reach = math.max(120.0, size.shortestSide * 1.4);
    final none = light.withValues(alpha: 0);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = RadialGradient(colors: [light, none])
            .createShader(Rect.fromCircle(center: at.value, radius: reach)),
    );
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = RadialGradient(
          colors: [edge, edge.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: at.value, radius: reach * 0.8)),
    );
  }

  @override
  bool shouldRepaint(_GlintPainter old) =>
      old.radius != radius || old.light != light || old.edge != edge;
}

/// How much of something is done, filling as it appears, inside a fine ring of
/// tick marks.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 46});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final percent = (value * 100).round();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 700),
      curve: Motion.out,
      builder: (context, shown, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(shown, p.accent, p.accentViolet, p.hairline),
          child: Center(
            child: Text(
              '$percent',
              textScaler: TextScaler.noScaling,
              style: TypeRamp.caption(p.ink)
                  .weighted(FontWeight.w700)
                  .copyWith(fontSize: size * 0.27),
            ),
          ),
        ),
      ),
    );
  }
}

/// One measure in [ConcentricRings].
class RingValue {
  const RingValue(this.label, this.value, this.detail, this.colour);

  final String label;

  /// From 0 to 1.
  final double value;
  final String detail;
  final Color colour;
}

/// Several measures as rings inside each other, filling in turn, with a key
/// beside them so the colour is never the only way to read them.
class ConcentricRings extends StatelessWidget {
  const ConcentricRings({
    super.key,
    required this.values,
    required this.centre,
    required this.caption,
    this.size = 132,
  });

  final List<RingValue> values;
  final String centre;
  final String caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label:
          '$caption: $centre. '
          '${values.map((v) => '${v.label}: ${v.detail}').join('. ')}',
      excludeSemantics: true,
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 850),
            curve: Motion.out,
            builder: (context, t, _) => SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: _ConcentricPainter(values, t, p.hairline),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        centre,
                        textScaler: TextScaler.noScaling,
                        style: TypeRamp.title(p.ink).copyWith(fontSize: 20),
                      ),
                      Text(
                        caption,
                        textScaler: TextScaler.noScaling,
                        style: TypeRamp.caption(p.inkSoft)
                            .copyWith(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: v.colour,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            v.label,
                            style: TypeRamp.label(p.inkSoft),
                          ),
                        ),
                        Text(
                          v.detail,
                          style: TypeRamp.label(p.ink)
                              .weighted(FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcentricPainter extends CustomPainter {
  const _ConcentricPainter(this.values, this.t, this.track);

  final List<RingValue> values;
  final double t;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 8.0;
    const gap = 4.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < values.length; i++) {
      final inset = width / 2 + i * (width + gap);
      final rect = (Offset.zero & size).deflate(inset);
      paint.color = track;
      canvas.drawArc(rect, 0, math.pi * 2, false, paint);
      final sweep = values[i].value.clamp(0.0, 1.0) * t * math.pi * 2;
      if (sweep <= 0) continue;
      paint.color = values[i].colour;
      canvas.drawArc(rect, -math.pi / 2, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_ConcentricPainter old) => old.t != t;
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value, this.from, this.to, this.track);

  final double value;
  final Color from;
  final Color to;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 3.5;
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ticks = Paint()
      ..color = track
      ..strokeWidth = 1;
    // A fine dial around the outside.
    for (var i = 0; i < 40; i++) {
      final a = i / 40 * math.pi * 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(centre + d * (radius - 2.5), centre + d * radius, ticks);
    }
    final rect = Rect.fromCircle(center: centre, radius: radius - 6.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      paint
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [from, to],
          transform: const GradientRotation(0),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.from != from || old.track != track;
}
