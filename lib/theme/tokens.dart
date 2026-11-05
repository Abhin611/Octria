import 'package:flutter/cupertino.dart';

import '../model/plan.dart';

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
    ground: Color(0xFFFBF7F2),
    raised: Color(0xFFFFFFFF),
    hairline: Color(0x1A2B1A0A),
    outline: Color(0xFFC4B8AC),
    ink: Color(0xFF1A1410),
    inkSoft: Color(0xFF4F453D),
    inkFaint: Color(0xFF665B52),
    control: Color(0x122B1A0A),
    route: Color(0xFFC2187A),
    onRoute: Color(0xFFFFFFFF),
    done: Color(0xFF047857),
    doing: Color(0xFF4338CA),
    review: Color(0xFFB45309),
    waiting: Color(0xFF7F766E),
    blocked: Color(0xFFDC2626),
    terrainA: Color(0x3DFFFFFF),
    terrainB: Color(0x1FFFFFFF),
    shadow: Color(0x1F3B2410),
    glassThin: Color(0x8CFFFFFF),
    glassRegular: Color(0xB3FFFFFF),
    glassThick: Color(0xE6FFFFFF),
    rimTop: Color(0xF2FFFFFF),
    rimBottom: Color(0x262B1A0A),
    sheen: Color(0x26FFFFFF),
    nodeTop: Color(0xF5FFFFFF),
    nodeBottom: Color(0xDEFFFFFF),
    nodeRim: Color(0x262B1A0A),
    ambientA: Color(0xFFFFE8D4),
    ambientB: Color(0xFFFFF2E4),
    ambientC: Color(0xFFFFF6EC),
    panel: Color(0xFFFFFFFF),
    accent: Color(0xFF4F46E5),
    accentViolet: Color(0xFF7C3AED),
    accentWarm: Color(0xFFB45309),
    accentTeal: Color(0xFF0F766E),
    orb: Color(0xFFEA7A1E),
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
    glassThin: Color(0x80181310),
    glassRegular: Color(0xA6181310),
    glassThick: Color(0xE0181310),
    rimTop: Color(0x33FFFFFF),
    rimBottom: Color(0x12FFFFFF),
    sheen: Color(0x0DFFFFFF),
    nodeTop: Color(0xF0292320),
    nodeBottom: Color(0xE01D1815),
    nodeRim: Color(0x1FFFFFFF),
    ambientA: Color(0xFF2A1406),
    ambientB: Color(0xFF1E0F05),
    ambientC: Color(0xFF170B04),
    panel: Color(0xFF17120F),
    accent: Color(0xFF8B8CFF),
    accentViolet: Color(0xFFB794FF),
    accentWarm: Color(0xFFFFC53D),
    accentTeal: Color(0xFF2DD4BF),
    orb: Color(0xFFFF8C2E),
  );

  static Palette of(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark ? dark : light;

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
