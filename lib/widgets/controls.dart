import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

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
            boxShadow: [
              BoxShadow(
                color: p.shadow,
                blurRadius: blur,
                offset: Offset(0, drop),
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
                      inner: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
          Offset(0, size.height * 0.6),
          [light, light.withValues(alpha: 0)],
        ),
    );
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
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) =>
      old.radius != radius || old.top != top || old.bottom != bottom;
}

/// The still, soft colour the whole app sits on. It never moves, so it costs
/// nothing after the first frame and can't distract.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final plain = MediaQuery.highContrastOf(context);
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        child: CustomPaint(
          key: ValueKey(p.brightness),
          size: Size.infinite,
          painter: _AmbientPainter(p, plain),
        ),
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
    final reach = size.longestSide * 0.72;
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
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.p != p || old.plain != plain;
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

    return Semantics(
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
            duration: _down ? Duration.zero : const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: Container(
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
