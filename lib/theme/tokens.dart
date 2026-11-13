import 'package:flutter/cupertino.dart';

import '../model/plan.dart';

/// How things move. Entrances start fast and settle; nothing eases in, so the
/// interface never seems to hesitate.
abstract final class Motion {
  /// Arriving, leaving, and anything answering a press.
  static const Curve out = Cubic(0.23, 1, 0.32, 1);

  /// Moving from one place on screen to another.
  static const Curve inOut = Cubic(0.77, 0, 0.175, 1);

  /// Sheets and drawers, like the system's own.
  static const Curve sheet = Cubic(0.32, 0.72, 0, 1);

  static const Duration press = Duration(milliseconds: 150);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration page = Duration(milliseconds: 260);
}

/// Carries the palette in use, so light and dark can cross-fade.
class PaletteScope extends InheritedWidget {
  const PaletteScope({super.key, required this.palette, required super.child});

  final Palette palette;

  @override
  bool updateShouldNotify(PaletteScope old) => !identical(old.palette, palette);
}

/// Fades every colour from one background to the other when it's switched,
/// rather than snapping. Reduce Motion switches at once.
class PaletteFade extends StatefulWidget {
  const PaletteFade({super.key, required this.child});

  final Widget child;

  @override
  State<PaletteFade> createState() => _PaletteFadeState();
}

class _PaletteFadeState extends State<PaletteFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: 1,
  );
  Palette? _from;
  Palette? _to;

  Palette get _now {
    final to = _to!;
    if (_fade.value >= 1 || _from == null) return to;
    return Palette.lerp(_from!, to, Curves.easeInOut.transform(_fade.value));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final target = CupertinoTheme.brightnessOf(context) == Brightness.dark
        ? Palette.dark
        : Palette.light;
    if (_to == null) {
      _to = target;
    } else if (!identical(target, _to)) {
      _from = _now;
      _to = target;
      if (MediaQuery.disableAnimationsOf(context)) {
        _fade.value = 1;
      } else {
        _fade.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    child: widget.child,
    builder: (context, child) => PaletteScope(palette: _now, child: child!),
  );
}

/// Octria's palette. Magenta is reserved for the viewer's own route.
@immutable
class Palette {
  const Palette({
    required this.brightness,
    required this.ground,
    required this.raised,
    required this.hairline,
    required this.outline,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.control,
    required this.route,
    required this.onRoute,
    required this.done,
    required this.doing,
    required this.review,
    required this.waiting,
    required this.blocked,
    required this.terrainA,
    required this.terrainB,
    required this.shadow,
    required this.glassThin,
    required this.glassRegular,
    required this.glassThick,
    required this.rimTop,
    required this.rimBottom,
    required this.sheen,
    required this.nodeTop,
    required this.nodeBottom,
    required this.nodeRim,
    required this.ambientA,
    required this.ambientB,
    required this.ambientC,
    required this.panel,
    required this.accent,
    required this.accentViolet,
    required this.accentWarm,
    required this.accentTeal,
    required this.orb,
  });

  final Brightness brightness;
  final Color ground;
  final Color raised;
  final Color hairline;
  final Color outline;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color control;
  final Color route;
  final Color onRoute;
  final Color done;
  final Color doing;
  final Color review;
  final Color waiting;
  final Color blocked;
  final Color terrainA;
  final Color terrainB;
  final Color shadow;

  /// How much of the surface a glass pane keeps. Thicker holds longer reading.
  final Color glassThin;
  final Color glassRegular;
  final Color glassThick;

  /// Light catching a pane's edge: bright along the top, faint along the bottom.
  final Color rimTop;
  final Color rimBottom;
  final Color sheen;

  /// A step on the canvas: glass to look at, solid enough to read.
  final Color nodeTop;
  final Color nodeBottom;
  final Color nodeRim;

  /// Soft colour behind everything, so the glass has something to pick up.
  final Color ambientA;
  final Color ambientB;
  final Color ambientC;

  /// A solid card on the home pages, with a fine edge rather than glass.
  final Color panel;

  /// Colours for telling kinds of things apart. They never mean status, and
  /// magenta stays the viewer's own.
  final Color accent;
  final Color accentViolet;
  final Color accentWarm;
  final Color accentTeal;

  /// The moving globe behind everything. Only ever used there.
  final Color orb;

  static const light = Palette(
    brightness: Brightness.light,
    // A soft warm grey rather than paper white, so light mode doesn't glare.
    ground: Color(0xFFEAE3DA),
    raised: Color(0xFFF7F3EE),
    hairline: Color(0x1A2B1A0A),
    outline: Color(0xFFC4B8AC),
    ink: Color(0xFF1A1410),
    inkSoft: Color(0xFF4F453D),
    inkFaint: Color(0xFF665B52),
    control: Color(0x1F2B1A0A),
    route: Color(0xFFC2187A),
    onRoute: Color(0xFFFFFFFF),
    done: Color(0xFF047857),
    doing: Color(0xFF4338CA),
    review: Color(0xFFB45309),
    waiting: Color(0xFF7F766E),
    blocked: Color(0xFFDC2626),
    terrainA: Color(0x3DFFFFFF),
    terrainB: Color(0x1FFFFFFF),
    shadow: Color(0x2B3B2410),
    glassThin: Color(0x59FCFAF7),
    glassRegular: Color(0x75FCFAF7),
    glassThick: Color(0xADFBF8F4),
    rimTop: Color(0xF2FFFFFF),
    rimBottom: Color(0x402B1A0A),
    sheen: Color(0x40FFFFFF),
    nodeTop: Color(0xF2F9F6F2),
    nodeBottom: Color(0xDEF1ECE6),
    nodeRim: Color(0x262B1A0A),
    ambientA: Color(0xFFEFC59C),
    ambientB: Color(0xFFE6CDB4),
    ambientC: Color(0xFFE2D5C6),
    panel: Color(0x8FFBF8F4),
    accent: Color(0xFF4F46E5),
    accentViolet: Color(0xFF7C3AED),
    accentWarm: Color(0xFFB45309),
    accentTeal: Color(0xFF0F766E),
    orb: Color(0xFFFF7A00),
  );

  static const dark = Palette(
    brightness: Brightness.dark,
    ground: Color(0xFF0E0B09),
    raised: Color(0xFF1F1A16),
    hairline: Color(0x1FFFFFFF),
    outline: Color(0xFF4E463F),
    ink: Color(0xFFF7F3EF),
    inkSoft: Color(0xFFC9C0B8),
    inkFaint: Color(0xFFA89E95),
    control: Color(0x1CFFFFFF),
    route: Color(0xFFF2589F),
    onRoute: Color(0xFF2A0518),
    done: Color(0xFF34D399),
    doing: Color(0xFF8B8CFF),
    review: Color(0xFFFFC53D),
    waiting: Color(0xFF8F867E),
    blocked: Color(0xFFF87171),
    terrainA: Color(0x0AFFFFFF),
    terrainB: Color(0x06FFFFFF),
    shadow: Color(0x80000000),
    glassThin: Color(0x4D181310),
    glassRegular: Color(0x66181310),
    glassThick: Color(0x8C181310),
    rimTop: Color(0x66FFFFFF),
    rimBottom: Color(0x1AFFFFFF),
    sheen: Color(0x1CFFFFFF),
    nodeTop: Color(0xF0292320),
    nodeBottom: Color(0xE01D1815),
    nodeRim: Color(0x1FFFFFFF),
    ambientA: Color(0xFF2A1406),
    ambientB: Color(0xFF1E0F05),
    ambientC: Color(0xFF170B04),
    panel: Color(0x73191410),
    accent: Color(0xFF8B8CFF),
    accentViolet: Color(0xFFB794FF),
    accentWarm: Color(0xFFFFC53D),
    accentTeal: Color(0xFF2DD4BF),
    orb: Color(0xFFFF8C2E),
  );

  /// Part of the way from [a] to [b], for the fade between backgrounds.
  static Palette lerp(Palette a, Palette b, double t) => Palette(
    brightness: t < 0.5 ? a.brightness : b.brightness,
    ground: Color.lerp(a.ground, b.ground, t)!,
    raised: Color.lerp(a.raised, b.raised, t)!,
    hairline: Color.lerp(a.hairline, b.hairline, t)!,
    outline: Color.lerp(a.outline, b.outline, t)!,
    ink: Color.lerp(a.ink, b.ink, t)!,
    inkSoft: Color.lerp(a.inkSoft, b.inkSoft, t)!,
    inkFaint: Color.lerp(a.inkFaint, b.inkFaint, t)!,
    control: Color.lerp(a.control, b.control, t)!,
    route: Color.lerp(a.route, b.route, t)!,
    onRoute: Color.lerp(a.onRoute, b.onRoute, t)!,
    done: Color.lerp(a.done, b.done, t)!,
    doing: Color.lerp(a.doing, b.doing, t)!,
    review: Color.lerp(a.review, b.review, t)!,
    waiting: Color.lerp(a.waiting, b.waiting, t)!,
    blocked: Color.lerp(a.blocked, b.blocked, t)!,
    terrainA: Color.lerp(a.terrainA, b.terrainA, t)!,
    terrainB: Color.lerp(a.terrainB, b.terrainB, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
    glassThin: Color.lerp(a.glassThin, b.glassThin, t)!,
    glassRegular: Color.lerp(a.glassRegular, b.glassRegular, t)!,
    glassThick: Color.lerp(a.glassThick, b.glassThick, t)!,
    rimTop: Color.lerp(a.rimTop, b.rimTop, t)!,
    rimBottom: Color.lerp(a.rimBottom, b.rimBottom, t)!,
    sheen: Color.lerp(a.sheen, b.sheen, t)!,
    nodeTop: Color.lerp(a.nodeTop, b.nodeTop, t)!,
    nodeBottom: Color.lerp(a.nodeBottom, b.nodeBottom, t)!,
    nodeRim: Color.lerp(a.nodeRim, b.nodeRim, t)!,
    ambientA: Color.lerp(a.ambientA, b.ambientA, t)!,
    ambientB: Color.lerp(a.ambientB, b.ambientB, t)!,
    ambientC: Color.lerp(a.ambientC, b.ambientC, t)!,
    panel: Color.lerp(a.panel, b.panel, t)!,
    accent: Color.lerp(a.accent, b.accent, t)!,
    accentViolet: Color.lerp(a.accentViolet, b.accentViolet, t)!,
    accentWarm: Color.lerp(a.accentWarm, b.accentWarm, t)!,
    accentTeal: Color.lerp(a.accentTeal, b.accentTeal, t)!,
    orb: Color.lerp(a.orb, b.orb, t)!,
  );

  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaletteScope>()?.palette ??
      (CupertinoTheme.brightnessOf(context) == Brightness.dark ? dark : light);

  Color standing(Standing s) => switch (s) {
    Standing.done => done,
    Standing.review => review,
    Standing.doing => doing,
    Standing.ready => ink,
    Standing.waiting => waiting,
    Standing.blocked => blocked,
  };
}

/// The short form that fits on a step in the graph.
String standingWord(Standing s) => switch (s) {
  Standing.done => 'Done',
  Standing.review => 'Waiting for approval',
  Standing.doing => 'In progress',
  Standing.ready => 'Ready',
  Standing.waiting => 'Waiting',
  Standing.blocked => 'Blocked',
};

String standingLabel(Standing s) => switch (s) {
  Standing.done => 'Done',
  Standing.review => 'Waiting for approval',
  Standing.doing => 'In progress',
  Standing.ready => 'Ready to start',
  Standing.waiting => 'Waiting on another step',
  Standing.blocked => 'Blocked by an overdue step',
};

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Short remarks run together as sentences: "Ben. Fits Flutter. 2 hours".
/// A remark that already ends in a full stop doesn't get a second one.
String sentences(Iterable<String> parts) => [
  for (final part in parts)
    if (part.trim().isNotEmpty) part.trim().replaceFirst(RegExp(r'\.+$'), ''),
].join('. ');

String shortDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// A moment to the second, in the person's own time: "Thu 5 Nov, 9:21:05 pm".
String exactTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${shortDate(d)}, $hour:${two(d.minute)}:${two(d.second)} '
      '${d.hour < 12 ? 'am' : 'pm'}';
}

String monthDay(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Type sizes. Tracking tightens as text grows; body stays near zero.
abstract final class TypeRamp {
  static const family = 'Inter';

  static TextStyle title(Color c) => TextStyle(
    fontFamily: family,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w700,
    fontVariations: const [FontVariation('wght', 700)],
    letterSpacing: -0.4,
    color: c,
    decoration: TextDecoration.none,
  );
  static TextStyle heading(Color c) => TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
    fontVariations: const [FontVariation('wght', 600)],
    letterSpacing: -0.2,
    color: c,
    decoration: TextDecoration.none,
  );
  static TextStyle body(Color c) => TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
    fontVariations: const [FontVariation('wght', 400)],
    letterSpacing: -0.05,
    color: c,
    decoration: TextDecoration.none,
  );
  static TextStyle label(Color c) => TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 1.25,
    fontWeight: FontWeight.w500,
    fontVariations: const [FontVariation('wght', 500)],
    letterSpacing: 0,
    color: c,
    decoration: TextDecoration.none,
  );
  static TextStyle caption(Color c) => TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w500,
    fontVariations: const [FontVariation('wght', 500)],
    letterSpacing: 0.05,
    color: c,
    fontFeatures: const [FontFeature.tabularFigures()],
    decoration: TextDecoration.none,
  );
}

/// Inter is a variable font, so the weight axis has to be set along with the
/// weight for the real cut to be used.
extension WeightedText on TextStyle {
  TextStyle weighted(FontWeight weight) => copyWith(
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
  );
}
