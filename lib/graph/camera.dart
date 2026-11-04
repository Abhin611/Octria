import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// One animated value driven by a spring, described the way Apple describes
/// them: damping ratio and response. Re-targeting keeps the current value and
/// velocity, so a moving value can be grabbed and redirected without a jump.
class Spring {
  Spring(this.value) : target = value;

  double value;
  double target;
  double velocity = 0;
  double dampingRatio = 1;
  double response = 0.38;

  bool get settled => (value - target).abs() < 0.002 && velocity.abs() < 0.02;

  void jumpTo(double next) {
    value = next;
    target = next;
    velocity = 0;
  }

  void step(double dt) {
    final omega = 2 * math.pi / response;
    final stiffness = omega * omega;
    final damping = 2 * dampingRatio * omega;
    velocity += (-stiffness * (value - target) - damping * velocity) * dt;
    value += velocity * dt;
    if (settled) jumpTo(target);
  }
}

/// Where a released flick would come to rest, using Apple's scroll projection.
double projectMomentum(double velocity, [double decelerationRate = 0.998]) =>
    (velocity / 1000) * decelerationRate / (1 - decelerationRate);

/// Progressive resistance past a bound.
double rubberBand(double overshoot, double dimension, [double c = 0.55]) =>
    (overshoot * dimension * c) / (dimension + c * overshoot.abs());

const double kMinScale = 0.16;
const double kMaxScale = 2.6;

/// Maps world space to screen space. X, Y and scale are independent springs.
class GraphCamera extends ChangeNotifier {
  GraphCamera(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  final Spring _x = Spring(0);
  final Spring _y = Spring(0);
  final Spring _scale = Spring(1);

  Size viewport = Size.zero;

  /// How much of each edge the floating bars cover. The plan runs underneath
  /// them, but it is framed, centred and bounded in the part they leave clear.
  EdgeInsets chrome = EdgeInsets.zero;

  /// The part of the viewport no floating bar covers.
  Rect get clear => chrome.deflateRect(Offset.zero & viewport);

  /// World spacing of the plan; set to match the layout.
  double cellWidth = 280;
  double rowHeight = 168;
  Size world = Size.zero;

  /// Respect the system's reduce-motion setting: arrive without travelling.
  bool reduceMotion = false;

  double get scale => _scale.value;
  Offset get pan => Offset(_x.value, _y.value);

  /// Zooms by [factor] about the screen centre, aiming from where the camera is
  /// heading so repeated presses add up.
  void zoomStep(double factor) {
    final focal = clear.center;
    final fromScale = _scale.target;
    final fromPan = Offset(_x.target, _y.target);
    final anchor = (focal - fromPan) / fromScale;
    final next = (fromScale * factor).clamp(kMinScale, kMaxScale);
    moveTo(focal - anchor * next, next);
  }

  Offset toScreen(Offset w) => w * scale + pan;
  Offset toWorld(Offset s) => (s - pan) / scale;

  Rect get visibleWorld =>
      Rect.fromPoints(toWorld(clear.topLeft), toWorld(clear.bottomRight));

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final elapsed = _last == Duration.zero
        ? 0.016
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    // Small fixed steps keep the spring stable through a dropped frame.
    var remaining = math.min(elapsed, 0.05);
    while (remaining > 0) {
      final dt = math.min(remaining, 1 / 240);
      _x.step(dt);
      _y.step(dt);
      _scale.step(dt);
      remaining -= dt;
    }
    if (_x.settled && _y.settled && _scale.settled) _ticker.stop();
    notifyListeners();
  }

  /// Follow the finger exactly while a gesture is live.
  void panBy(Offset delta) {
    final next = pan + delta;
    final bounded = _softBound(next, scale);
    _x.jumpTo(bounded.dx);
    _y.jumpTo(bounded.dy);
    notifyListeners();
  }

  void zoomAround(Offset focal, double factor) {
    final nextScale = _softScale(scale * factor);
    final anchor = toWorld(focal);
    final nextPan = focal - anchor * nextScale;
    _scale.jumpTo(nextScale);
    _x.jumpTo(nextPan.dx);
    _y.jumpTo(nextPan.dy);
    notifyListeners();
  }

  /// A gesture has ended: hand its velocity to the springs and aim at where the
  /// flick is going, kept inside the bounds.
  void release(Offset velocity) {
    final scaleTarget = scale.clamp(kMinScale, kMaxScale);
    if (reduceMotion) {
      final p = _hardBound(pan, scaleTarget);
      _x.jumpTo(p.dx);
      _y.jumpTo(p.dy);
      _scale.jumpTo(scaleTarget);
      notifyListeners();
      return;
    }
    final projected =
        pan +
        Offset(projectMomentum(velocity.dx), projectMomentum(velocity.dy));
    final target = _hardBound(projected, scaleTarget);
    _x
      ..velocity = velocity.dx
      ..dampingRatio = 1
      ..response = 0.5
      ..target = target.dx;
    _y
      ..velocity = velocity.dy
      ..dampingRatio = 1
      ..response = 0.5
      ..target = target.dy;
    _scale
      ..dampingRatio = 1
      ..response = 0.38
      ..target = scaleTarget;
    _wake();
  }

  /// Glide to a view. Starts from wherever the camera is right now.
  void moveTo(Offset panTarget, double scaleTarget) {
    final s = scaleTarget.clamp(kMinScale, kMaxScale);
    final p = _hardBound(panTarget, s);
    if (reduceMotion) {
      _x.jumpTo(p.dx);
      _y.jumpTo(p.dy);
      _scale.jumpTo(s);
      notifyListeners();
      return;
    }
    for (final spring in [_x, _y, _scale]) {
      spring
        ..dampingRatio = 1
        ..response = 0.42;
    }
    _x.target = p.dx;
    _y.target = p.dy;
    _scale.target = s;
    _wake();
  }

  void jumpTo(Offset panTarget, double scaleTarget) {
    _x.jumpTo(panTarget.dx);
    _y.jumpTo(panTarget.dy);
    _scale.jumpTo(scaleTarget);
    notifyListeners();
  }

  void centreOn(Offset worldPoint, {double? atScale, Offset? bias}) {
    final s = (atScale ?? scale).clamp(kMinScale, kMaxScale);
    final centre = clear.center + (bias ?? Offset.zero);
    moveTo(centre - worldPoint * s, s);
  }

  double fitScale(EdgeInsets padding) {
    if (world.isEmpty || viewport.isEmpty) return 1;
    final w = clear.width - padding.horizontal;
    final h = clear.height - padding.vertical;
    return math
        .min(math.min(w / world.width, h / world.height), 1.0)
        .clamp(kMinScale, kMaxScale);
  }

  void fit(EdgeInsets padding, {bool animate = true}) {
    final s = fitScale(padding);
    final x =
        clear.left +
        padding.left +
        (clear.width - padding.horizontal - world.width * s) / 2;
    final y =
        clear.top +
        padding.top +
        (clear.height - padding.vertical - world.height * s) / 2;
    if (animate) {
      moveTo(Offset(x, y), s);
    } else {
      final p = _hardBound(Offset(x, y), s);
      jumpTo(p, s);
    }
  }

  double _softScale(double next) {
    if (next < kMinScale) {
      return kMinScale - rubberBand(kMinScale - next, kMinScale) * 0.5;
    }
    if (next > kMaxScale) {
      return kMaxScale + rubberBand(next - kMaxScale, kMaxScale) * 0.5;
    }
    return next;
  }

  (double, double) _panRange(
    double start,
    double end,
    double worldSide,
    double s,
  ) {
    final side = end - start;
    final content = worldSide * s;
    // Keep a margin of the plan on screen; centre it when it is smaller.
    if (content <= side) {
      final centred = start + (side - content) / 2;
      return (centred, centred);
    }
    return (end - content - 48, start + 48);
  }

  Offset _hardBound(Offset p, double s) {
    final (minX, maxX) = _panRange(clear.left, clear.right, world.width, s);
    final (minY, maxY) = _panRange(clear.top, clear.bottom, world.height, s);
    return Offset(p.dx.clamp(minX, maxX), p.dy.clamp(minY, maxY));
  }

  Offset _softBound(Offset p, double s) {
    final (minX, maxX) = _panRange(clear.left, clear.right, world.width, s);
    final (minY, maxY) = _panRange(clear.top, clear.bottom, world.height, s);
    double soft(double v, double lo, double hi, double side) {
      if (v < lo) return lo - rubberBand(lo - v, side);
      if (v > hi) return hi + rubberBand(v - hi, side);
      return v;
    }

    return Offset(
      soft(p.dx, minX, maxX, viewport.width),
      soft(p.dy, minY, maxY, viewport.height),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
