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

  static const light = Palette(
    brightness: Brightness.light,
    ground: Color(0xFFF2F5FA),
    raised: Color(0xFFFFFFFF),
    hairline: Color(0x1F1C2744),
    outline: Color(0xFFAAB2C4),
    ink: Color(0xFF1B1F27),
    inkSoft: Color(0xFF474E5C),
    inkFaint: Color(0xFF5C6372),
    control: Color(0x141C2744),
    route: Color(0xFFC2187A),
    onRoute: Color(0xFFFFFFFF),
    done: Color(0xFF1F7F4C),
    doing: Color(0xFF1A67AD),
    waiting: Color(0xFF7E8494),
    blocked: Color(0xFFCE2F26),
    terrainA: Color(0x38FFFFFF),
    terrainB: Color(0x1FFFFFFF),
    shadow: Color(0x261B2A4A),
    glassThin: Color(0x73FFFFFF),
    glassRegular: Color(0x94FFFFFF),
    glassThick: Color(0xD1FFFFFF),
    rimTop: Color(0xE6FFFFFF),
    rimBottom: Color(0x40FFFFFF),
    sheen: Color(0x33FFFFFF),
    nodeTop: Color(0xE6FFFFFF),
    nodeBottom: Color(0xB8FFFFFF),
    nodeRim: Color(0x331C2744),
    ambientA: Color(0xFFBFD9FF),
    ambientB: Color(0xFFFFD6EC),
    ambientC: Color(0xFFCFF3E6),
  );

  static const dark = Palette(
    brightness: Brightness.dark,
    ground: Color(0xFF0E1116),
    raised: Color(0xFF23272F),
    hairline: Color(0x1FFFFFFF),
    outline: Color(0xFF4C5462),
    ink: Color(0xFFF2F4F8),
    inkSoft: Color(0xFFC3C8D2),
    inkFaint: Color(0xFFA2A8B4),
    control: Color(0x1FFFFFFF),
    route: Color(0xFFF2589F),
    onRoute: Color(0xFF2A0518),
    done: Color(0xFF55BD84),
    doing: Color(0xFF6AB0EA),
    waiting: Color(0xFF8B919E),
    blocked: Color(0xFFF2675D),
    terrainA: Color(0x0DFFFFFF),
    terrainB: Color(0x08FFFFFF),
    shadow: Color(0x73000000),
    glassThin: Color(0x6B1C2028),
    glassRegular: Color(0x8C1C2028),
    glassThick: Color(0xD61C2028),
    rimTop: Color(0x47FFFFFF),
    rimBottom: Color(0x0FFFFFFF),
    sheen: Color(0x12FFFFFF),
    nodeTop: Color(0xD9333945),
    nodeBottom: Color(0xB8272C36),
    nodeRim: Color(0x1FFFFFFF),
    ambientA: Color(0xFF1B2F55),
    ambientB: Color(0xFF3A1C46),
    ambientC: Color(0xFF0F3A38),
  );

  static Palette of(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark ? dark : light;

  Color standing(Standing s) => switch (s) {
    Standing.done => done,
    Standing.review => doing,
    Standing.doing => doing,
    Standing.ready => ink,
    Standing.waiting => waiting,
    Standing.blocked => blocked,
  };
}

String standingLabel(Standing s) => switch (s) {
  Standing.done => 'Done',
  Standing.review => 'In review',
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
