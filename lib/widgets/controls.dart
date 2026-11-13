import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'hover_hint.dart';

/// How much of a glass pane is material. Thin for controls over the map, regular
/// for bars and cards, thick for anything read at length.
enum GlassWeight { thin, regular, thick }

/// Watches how long frames take to draw and turns real blur off for the rest of
/// the session if this device can't keep up. Smoothness outranks the material.
abstract final class GlassBudget {
  static final ValueNotifier<bool> lite = ValueNotifier(false);
  static const _window = 120;
  static const _slowRaster = Duration(milliseconds: 22);
  static var _watching = false;
  static var _frames = 0;
  static var _slow = 0;

  static void watch() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<ui.FrameTiming> timings) {
    if (lite.value) return;
    for (final t in timings) {
      _frames++;
      if (t.rasterDuration > _slowRaster) _slow++;
    }
    if (_frames < _window) return;
    if (_slow > _frames / 3) lite.value = true;
    _frames = 0;
    _slow = 0;
  }
}

/// A translucent floating surface: frosted, with light along its top edge. Goes
/// solid with a defined edge when the person has asked for more contrast, and
/// frosted without blur on a device that can't afford it.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding = EdgeInsets.zero,
    this.weight = GlassWeight.regular,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final GlassWeight weight;

  // Blur alone greys out what's behind; a lift in saturation keeps its colour.
  static const List<double> _saturate = [
    1.42, -0.36, -0.06, 0, 0, //
    -0.14, 1.20, -0.06, 0, 0, //
    -0.14, -0.36, 1.50, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final solid = MediaQuery.highContrastOf(context);
    final shape = BorderRadius.circular(radius);
    final fill = switch (weight) {
      GlassWeight.thin => p.glassThin,
      GlassWeight.regular => p.glassRegular,
      GlassWeight.thick => p.glassThick,
    };
    // Bigger, thicker surfaces sit further off the page.
    final (blur, drop) = switch (weight) {
      GlassWeight.thin => (12.0, 4.0),
      GlassWeight.regular => (20.0, 6.0),
      GlassWeight.thick => (28.0, 10.0),
    };
    // Clearer glass needs more blur behind it to stay readable.
    final sigma = switch (weight) {
      GlassWeight.thin => 16.0,
      GlassWeight.regular => 22.0,
      GlassWeight.thick => 30.0,
    };
    return ValueListenableBuilder<bool>(
      valueListenable: GlassBudget.lite,
      child: child,
      builder: (context, lite, child) {
        final body = CustomPaint(
          painter: _GlassBodyPainter(
            radius: radius,
            fill: solid
                ? p.raised
                : (lite ? Color.lerp(fill, p.raised, 0.7)! : fill),
            sheen: solid ? null : p.sheen,
          ),
          foregroundPainter: _GlassRimPainter(
            radius: radius,
            top: solid ? p.ink : p.rimTop,
            bottom: solid ? p.ink : p.rimBottom,
          ),
          child: Padding(padding: padding, child: child),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            // A tight shadow where the pane meets what's under it, and a
            // wide soft one for how far it floats.
            boxShadow: [
              BoxShadow(
                color: p.shadow.withValues(alpha: p.shadow.a * 0.45),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: p.shadow.withValues(alpha: p.shadow.a * 0.8),
                blurRadius: blur * 1.5,
                spreadRadius: -2,
                offset: Offset(0, drop * 1.4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: solid || lite
                ? body
                : BackdropFilter.grouped(
                    filter: ui.ImageFilter.compose(
                      outer: const ui.ColorFilter.matrix(_saturate),
                      inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    ),
                    child: body,
                  ),
          ),
        );
      },
    );
  }
}

class _GlassBodyPainter extends CustomPainter {
  const _GlassBodyPainter({
    required this.radius,
    required this.fill,
    required this.sheen,
  });

  final double radius;
  final Color fill;
  final Color? sheen;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(shape, Paint()..color = fill);
    final light = sheen;
    if (light == null) return;
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          Offset(0, math.min(size.height * 0.6, 220)),
          [light, light.withValues(alpha: 0)],
        ),
    );
    // Light pooling in the top-left corner, as on a curved pane.
    final reach = math.min(size.longestSide * 0.7, 420.0);
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawCircle(
      rect.topLeft,
      reach,
      Paint()
        ..shader = ui.Gradient.radial(rect.topLeft, reach, [
          light.withValues(alpha: light.a * 0.9),
          light.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassBodyPainter old) =>
      old.radius != radius || old.fill != fill || old.sheen != sheen;
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({
    required this.radius,
    required this.top,
    required this.bottom,
  });

  final double radius;
  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius - 0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          top,
          bottom,
        ]),
    );
    // Light caught on the inside of the edge, brightest at the top corners,
    // like the lip of a curved pane.
    final inner = rect.deflate(1.2);
    if (inner.height < 6) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(radius - 1.7)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          inner.topLeft,
          inner.bottomRight,
          [
            top.withValues(alpha: top.a * 0.55),
            top.withValues(alpha: 0),
            top.withValues(alpha: 0),
            top.withValues(alpha: top.a * 0.25),
          ],
          const [0, 0.35, 0.7, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) =>
      old.radius != radius || old.top != top || old.bottom != bottom;
}

/// What the whole app sits on: warm glows that stay put, and a slow orange globe
/// turning in the middle. The globe holds still when someone has asked for less
/// motion or the device can't keep up, and goes away with more contrast.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({super.key});

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin {
  // One turn of the globe. Slow enough that a low frame rate can't be seen,
  // which keeps the glass above it cheap.
  static const _turn = Duration(seconds: 90);
  static const _frame = Duration(milliseconds: 42);

  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _drawn = Duration.zero;

  void _tick(Duration now) {
    if (now - _drawn < _frame) return;
    _drawn = now;
    _time.value = now.inMicroseconds / _turn.inMicroseconds % 1;
  }

  void _sync() {
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.highContrastOf(context) ||
        GlassBudget.lite.value;
    if (still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _drawn = Duration.zero;
      _ticker.start();
    }
  }

  void _onBudget() {
    if (mounted) _sync();
  }

  @override
  void initState() {
    super.initState();
    GlassBudget.watch();
    GlassBudget.lite.addListener(_onBudget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    GlassBudget.lite.removeListener(_onBudget);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final plain = MediaQuery.highContrastOf(context);
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      child: Stack(
        key: ValueKey(p.brightness),
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _AmbientPainter(p, plain)),
          ),
          if (!plain)
            RepaintBoundary(child: CustomPaint(painter: _HudPainter(p, _time))),
          if (!plain)
            RepaintBoundary(
              child: CustomPaint(painter: _GlobePainter(p, _time)),
            ),
        ],
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.p, this.plain);

  final Palette p;
  final bool plain;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = p.ground);
    if (plain) return;
    final reach = size.longestSide * 0.62;
    void glow(double x, double y, Color colour) {
      final c = Offset(size.width * x, size.height * y);
      canvas.drawCircle(
        c,
        reach,
        Paint()
          ..shader = ui.Gradient.radial(c, reach, [
            colour,
            colour.withValues(alpha: 0),
          ]),
      );
    }

    glow(0.12, 0.08, p.ambientA);
    glow(0.92, 0.28, p.ambientB);
    glow(0.38, 0.98, p.ambientC);
    // A fine grid of points, so large empty areas read as made, not missing.
    final dot = Paint()
      ..color = (p.brightness == Brightness.dark
          ? const Color(0x14FFB070)
          : const Color(0x142B1A0A))
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const step = 26.0;
    canvas.drawPoints(ui.PointMode.points, [
      for (var x = step / 2; x < size.width; x += step)
        for (var y = step / 2; y < size.height; y += step) Offset(x, y),
    ], dot);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.p != p || old.plain != plain;
}

/// The rest of the screen, so no corner sits still: points of light drifting
/// and linking up when near each other, and a slow dial turning in each
/// corner, like instruments around the globe. Every motion loops once a turn
/// of the globe, so nothing jumps when it starts again.
class _HudPainter extends CustomPainter {
  _HudPainter(this.p, this.time) : super(repaint: time);

  final Palette p;
  final ValueListenable<double> time;

  static final List<(double, double, int, int, double)> _points = () {
    final random = math.Random(7);
    int speed() {
      final s = random.nextInt(5) - 2;
      return s == 0 ? 1 : s;
    }

    return [
      for (var i = 0; i < 46; i++)
        (
          random.nextDouble(),
          random.nextDouble(),
          speed(),
          speed(),
          0.9 + random.nextDouble() * 1.8,
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    // With no room yet, such as a window still opening, every distance is
    // nothing over nothing: there's nothing to draw.
    if (size.shortestSide < 1) return;
    final t = time.value;
    final dark = p.brightness == Brightness.dark;
    final full = math.pi * 2;
    final colour = p.orb;
    final strength = dark ? 0.8 : 0.6;

    // Drifting points, linked when close.
    final at = [
      for (final (x, y, sx, sy, r) in _points)
        (
          Offset(
            ((x + t * sx) % 1) * size.width,
            ((y + t * sy * 0.6) % 1) * size.height,
          ),
          r,
        ),
    ];
    final reach = size.shortestSide * 0.16;
    final link = Paint()..strokeWidth = 0.7;
    for (var i = 0; i < at.length; i++) {
      for (var j = i + 1; j < at.length; j++) {
        final d = (at[i].$1 - at[j].$1).distance;
        if (d > reach) continue;
        link.color = colour.withValues(
          alpha: strength * 0.35 * (1 - d / reach),
        );
        canvas.drawLine(at[i].$1, at[j].$1, link);
      }
    }
    final dot = Paint();
    for (final (o, r) in at) {
      dot.color = colour.withValues(alpha: strength * 0.75);
      canvas.drawCircle(o, r, dot);
    }

    // A dial in each corner: a broken ring with ticks, turning slowly.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final radius = (size.shortestSide * 0.2).clamp(70.0, 190.0);
    final corners = [
      (Offset.zero, 1.0),
      (Offset(size.width, 0), -1.0),
      (Offset(0, size.height), -1.0),
      (Offset(size.width, size.height), 1.0),
    ];
    for (final (corner, way) in corners) {
      final spin = way * t * full * 2;
      ring
        ..strokeWidth = 1.1
        ..color = colour.withValues(alpha: strength * 0.55);
      final outer = Rect.fromCircle(center: corner, radius: radius);
      for (var k = 0; k < 3; k++) {
        canvas.drawArc(outer, spin + k * full / 3, full / 5, false, ring);
      }
      ring
        ..strokeWidth = 0.8
        ..color = colour.withValues(alpha: strength * 0.35);
      final inner = Rect.fromCircle(center: corner, radius: radius * 0.72);
      for (var k = 0; k < 4; k++) {
        canvas.drawArc(
          inner,
          -spin * 1.5 + k * full / 4,
          full / 9,
          false,
          ring,
        );
      }
      // Ticks round the outside.
      final tick = Paint()
        ..strokeWidth = 1
        ..color = colour.withValues(alpha: strength * 0.4);
      for (var k = 0; k < 36; k++) {
        final a = spin * 0.5 + k * full / 36;
        final long = k % 3 == 0 ? 9.0 : 4.0;
        final from = corner + Offset(math.cos(a), math.sin(a)) * (radius + 6);
        final to =
            corner + Offset(math.cos(a), math.sin(a)) * (radius + 6 + long);
        canvas.drawLine(from, to, tick);
      }
      // A sweep, like a scanner, crossing the dial.
      final sweep = way * t * full * 4;
      canvas.drawArc(
        Rect.fromCircle(center: corner, radius: radius * 0.95),
        sweep,
        0.5,
        true,
        Paint()
          ..shader = ui.Gradient.sweep(
            corner,
            [
              colour.withValues(alpha: 0),
              colour.withValues(alpha: strength * 0.18),
            ],
            [0, 1],
            TileMode.clamp,
            sweep,
            sweep + 0.5,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_HudPainter old) => old.p != p;
}

/// A globe of fine orange lines with a soft light inside it, turning slowly.
class _GlobePainter extends CustomPainter {
  _GlobePainter(this.p, this.time) : super(repaint: time);

  final Palette p;
  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final dark = p.brightness == Brightness.dark;
    final radius = (size.shortestSide * 0.42).clamp(150.0, 400.0);
    final centre = Offset(size.width / 2, size.height * 0.48);
    final full = math.pi * 2;

    // The light inside, breathing once every 15 seconds.
    final breath = 0.5 + 0.5 * math.sin(t * full * 6);
    final lightReach = radius * (1.5 + 0.08 * breath);
    canvas.drawCircle(
      centre,
      lightReach,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          lightReach,
          [
            p.orb.withValues(alpha: (dark ? 0.15 : 0.22) + 0.06 * breath),
            p.orb.withValues(alpha: dark ? 0.05 : 0.09),
            p.orb.withValues(alpha: 0),
          ],
          [0, 0.45, 1],
        ),
    );

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dark ? 1 : 1.3;
    // In light the globe shines in full orange, with a soft glow round every
    // line, so it reads as strongly on white as it does on black.
    final strength = dark ? 0.22 : 0.42;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void shine(void Function(Paint paint) draw, Paint core) {
      if (!dark) {
        glow
          ..color = core.color.withValues(alpha: core.color.a * 0.14)
          ..strokeWidth = core.strokeWidth + 4;
        draw(glow);
      }
      draw(core);
    }

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(-0.38);

    // Lines of longitude, sliding round as the globe turns.
    const meridians = 9;
    for (var i = 0; i < meridians; i++) {
      final angle = t * full + i * math.pi / meridians;
      final across = math.cos(angle);
      line.color = p.orb.withValues(
        alpha: strength * (0.45 + 0.55 * across.abs()),
      );
      final oval = Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2 * across.abs(),
        height: radius * 2,
      );
      shine((paint) => canvas.drawOval(oval, paint), line);
    }

    // Lines of latitude, seen from a little above.
    line.color = p.orb.withValues(alpha: strength * 0.7);
    for (var i = -3; i <= 3; i++) {
      final lat = i * math.pi / 8;
      final across = math.cos(lat) * radius * 2;
      final oval = Rect.fromCenter(
        center: Offset(0, math.sin(lat) * radius),
        width: across,
        height: across * 0.26,
      );
      shine((paint) => canvas.drawOval(oval, paint), line);
    }
    canvas.restore();

    // Two broken rings around it, drifting opposite ways.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = p.orb.withValues(alpha: math.min(1, strength * 1.1));
    void arcs(double scale, double width, double start, List<double> sweeps) {
      ring.strokeWidth = width;
      final rect = Rect.fromCircle(center: centre, radius: radius * scale);
      var at = start * full;
      for (final sweep in sweeps) {
        final from = at;
        shine((paint) => canvas.drawArc(rect, from, sweep, false, paint), ring);
        at += full / sweeps.length;
      }
    }

    arcs(1.12, 1.6, t * 2, const [1.5, 0.7, 1.1]);
    arcs(1.2, 1, -t * 3, const [0.5, 1.2, 0.3, 0.9]);
  }

  @override
  bool shouldRepaint(_GlobePainter old) => old.p != p;
}

/// A button whose feedback lands on the press, not the release.
class PressButton extends StatefulWidget {
  const PressButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.prominent = false,
    this.selected = false,
    this.selectedColor,
    this.destructive = false,
    this.quiet = false,
    this.iconOnly = false,
    this.height = 36,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool prominent;
  final bool selected;
  final Color? selectedColor;
  final bool destructive;
  final bool quiet;
  final bool iconOnly;
  final double height;
  final bool expand;

  @override
  State<PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<PressButton> {
  bool _down = false;
  bool _focused = false;
  bool _hovered = false;

  void _activate() {
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = widget.onTap != null;
    // Touch targets never drop below 44.
    final touch = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => MediaQuery.sizeOf(context).width < 840,
    };
    final height = touch && widget.height < 44 ? 44.0 : widget.height;
    final active = widget.selected || widget.prominent;
    final activeColor = widget.selectedColor ?? p.ink;
    final Color background;
    final Color foreground;
    if (!enabled) {
      background = p.control.withValues(alpha: p.control.a * 0.5);
      foreground = p.inkFaint;
    } else if (active) {
      background = activeColor;
      foreground = activeColor == p.route ? p.onRoute : p.ground;
    } else if (widget.quiet) {
      background = _hovered ? p.control : const Color(0x00000000);
      foreground = widget.destructive ? p.blocked : p.ink;
    } else {
      background = _hovered ? p.hairline : p.control;
      foreground = widget.destructive ? p.blocked : p.ink;
    }

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) Icon(widget.icon, size: 17, color: foreground),
        if (widget.icon != null && !widget.iconOnly) const SizedBox(width: 7),
        if (!widget.iconOnly)
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeRamp.label(foreground),
            ),
          ),
      ],
    );

    final button = Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTap: enabled ? _activate : null,
          child: AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: _down ? Duration.zero : Motion.press,
            curve: Motion.out,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              curve: Curves.ease,
              height: height,
              width: widget.iconOnly ? height : null,
              padding: widget.iconOnly
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(height / 2),
                border: _focused ? Border.all(color: p.doing, width: 2) : null,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
    // A button that's only an icon says what it does when pointed at or held.
    return widget.iconOnly
        ? HoverHint(message: widget.label, child: button)
        : button;
  }
}

/// A red number raised over the corner of something, like on a phone's app icon.
/// Shows nothing at zero.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -5,
          right: -5,
          child: IgnorePointer(child: _Count(count)),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE5262B),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      textScaler: TextScaler.noScaling,
      style: const TextStyle(
        fontFamily: TypeRamp.family,
        fontSize: 12,
        height: 1.1,
        fontWeight: FontWeight.w700,
        fontVariations: [FontVariation('wght', 700)],
        color: Color(0xFFFFFFFF),
        decoration: TextDecoration.none,
      ),
    ),
  );
}

/// A labelled text field that reads well on glass.
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines = 1,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.sentences,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final int minLines;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final field = Semantics(
      label: label,
      textField: true,
      child: CupertinoTextField(
        controller: controller,
        placeholder: label,
        obscureText: obscureText,
        keyboardType: keyboardType,
        maxLines: maxLines,
        minLines: minLines,
        autofillHints: autofillHints,
        textCapitalization: keyboardType == null && !obscureText
            ? textCapitalization
            : TextCapitalization.none,
        onSubmitted: onSubmitted,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        style: TypeRamp.body(p.ink),
        placeholderStyle: TypeRamp.body(p.inkFaint),
        cursorColor: p.ink,
        decoration: BoxDecoration(
          color: p.control,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.hairline),
        ),
      ),
    );
    // Once there's text the placeholder is gone, so the label moves above.
    return ListenableBuilder(
      listenable: controller,
      child: field,
      builder: (context, field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.text.isNotEmpty)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(left: 14, bottom: 4),
                child: Text(label, style: TypeRamp.caption(p.inkSoft)),
              ),
            ),
          field!,
        ],
      ),
    );
  }
}

/// A selectable filter chip.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressButton(
      label: label,
      selected: selected,
      height: 32,
      onTap: onTap,
    );
  }
}

/// A small pane of tinted glass for an icon or a selected item: colour inside,
/// light on the rim.
BoxDecoration glassTint(Palette p, Color colour, {double radius = 12}) {
  final dark = p.brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colour.withValues(alpha: dark ? 0.32 : 0.24),
        colour.withValues(alpha: dark ? 0.12 : 0.08),
      ],
    ),
    border: Border.all(
      color: dark ? const Color(0x33FFFFFF) : const Color(0xB3FFFFFF),
    ),
  );
}
