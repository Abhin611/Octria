/// Kanvas boards: a person's own infinite canvas of notes, drawings and
/// diagrams. Everything here is plain data, stored as JSON in Firestore.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

enum ShapeKind {
  stroke,
  sticky,
  text,
  checklist,
  box,
  ellipse,
  arrow,
  link,

  /// An image, PDF or video kept in its owner's Google Drive.
  file,
}

/// Colours by name, so a board looks right in light and dark.
enum KColour {
  ink,
  yellow,
  pink,
  blue,
  green,
  orange,
  purple,
  red;

  static KColour named(String? name) =>
      KColour.values.firstWhere((c) => c.name == name, orElse: () => ink);
}

class CheckItem {
  const CheckItem(this.text, {this.done = false});

  final String text;
  final bool done;

  Map<String, Object?> toJson() => {'t': text, if (done) 'd': true};

  static CheckItem fromJson(Map<String, Object?> j) =>
      CheckItem((j['t'] as String?) ?? '', done: j['d'] == true);
}

/// One thing on a board. Which fields matter depends on [kind]: strokes use
/// [points], arrows use their ends, and everything else is a rectangle.
class KShape {
  const KShape({
    required this.id,
    required this.kind,
    this.rect = Rect.zero,
    this.points = const [],
    this.width = 3,
    this.colour = KColour.ink,
    this.text = '',
    this.items = const [],
    this.url = '',
    this.fromId = '',
    this.toId = '',
    this.start = Offset.zero,
    this.end = Offset.zero,
    this.fileId = '',
    this.mime = '',
    this.bytes = 0,
  });

  final String id;
  final ShapeKind kind;

  /// Where a note, box or card sits, in board units.
  final Rect rect;

  /// A freehand line, in board units.
  final List<Offset> points;

  /// Line thickness for strokes, boxes and arrows.
  final double width;
  final KColour colour;
  final String text;
  final List<CheckItem> items;

  /// A link card's address.
  final String url;

  /// For an arrow: the shapes it joins. Empty means a free end at [start] or
  /// [end].
  final String fromId;
  final String toId;
  final Offset start;
  final Offset end;

  /// For a file card: the file's id in Drive, its type and its size. Its name
  /// is [text] and where it opens is [url].
  final String fileId;
  final String mime;
  final int bytes;

  /// Cards that open something when tapped twice.
  bool get opens => kind == ShapeKind.link || kind == ShapeKind.file;

  bool get isRect => kind != ShapeKind.stroke && kind != ShapeKind.arrow;

  /// Shapes text can be written in.
  bool get holdsText =>
      kind == ShapeKind.sticky ||
      kind == ShapeKind.text ||
      kind == ShapeKind.box ||
      kind == ShapeKind.ellipse ||
      kind == ShapeKind.checklist;

  KShape copyWith({
    Rect? rect,
    List<Offset>? points,
    KColour? colour,
    String? text,
    List<CheckItem>? items,
    String? url,
    String? fromId,
    String? toId,
    Offset? start,
    Offset? end,
    String? id,
  }) => KShape(
    id: id ?? this.id,
    kind: kind,
    rect: rect ?? this.rect,
    points: points ?? this.points,
    width: width,
    colour: colour ?? this.colour,
    text: text ?? this.text,
    items: items ?? this.items,
    url: url ?? this.url,
    fromId: fromId ?? this.fromId,
    toId: toId ?? this.toId,
    start: start ?? this.start,
    end: end ?? this.end,
    fileId: fileId,
    mime: mime,
    bytes: bytes,
  );

  /// Moves the shape by [d]. An arrow's joined ends follow their shapes.
  KShape moved(Offset d) => switch (kind) {
    ShapeKind.stroke => copyWith(points: [for (final p in points) p + d]),
    ShapeKind.arrow => copyWith(start: start + d, end: end + d),
    _ => copyWith(rect: rect.shift(d)),
  };

  static double _r(double v) => (v * 10).roundToDouble() / 10;

  Map<String, Object?> toJson() => {
    'id': id,
    'k': kind.name,
    if (isRect)
      'r': [_r(rect.left), _r(rect.top), _r(rect.width), _r(rect.height)],
    if (kind == ShapeKind.stroke)
      'p': [
        for (final p in points) ...[_r(p.dx), _r(p.dy)],
      ],
    if (width != 3) 'w': width,
    if (colour != KColour.ink) 'c': colour.name,
    if (text.isNotEmpty) 't': text,
    if (items.isNotEmpty) 'i': [for (final i in items) i.toJson()],
    if (url.isNotEmpty) 'u': url,
    if (fileId.isNotEmpty) 'd': fileId,
    if (mime.isNotEmpty) 'm': mime,
    if (bytes > 0) 'z': bytes,
    if (kind == ShapeKind.arrow) ...{
      if (fromId.isNotEmpty) 'f': fromId,
      if (toId.isNotEmpty) 'o': toId,
      'a': [_r(start.dx), _r(start.dy), _r(end.dx), _r(end.dy)],
    },
  };

  static KShape fromJson(Map<String, Object?> j) {
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;
    final r = (j['r'] as List?) ?? const [];
    final p = (j['p'] as List?) ?? const [];
    final a = (j['a'] as List?) ?? const [0, 0, 0, 0];
    return KShape(
      id: (j['id'] as String?) ?? '',
      kind: ShapeKind.values.firstWhere(
        (k) => k.name == j['k'],
        orElse: () => ShapeKind.sticky,
      ),
      rect: r.length == 4
          ? Rect.fromLTWH(n(r[0]), n(r[1]), n(r[2]), n(r[3]))
          : Rect.zero,
      points: [
        for (var i = 0; i + 1 < p.length; i += 2) Offset(n(p[i]), n(p[i + 1])),
      ],
      width: (j['w'] as num?)?.toDouble() ?? 3,
      colour: KColour.named(j['c'] as String?),
      text: (j['t'] as String?) ?? '',
      items: [
        for (final i in (j['i'] as List?) ?? const [])
          if (i is Map) CheckItem.fromJson(i.cast<String, Object?>()),
      ],
      url: (j['u'] as String?) ?? '',
      fromId: (j['f'] as String?) ?? '',
      toId: (j['o'] as String?) ?? '',
      start: a.length == 4 ? Offset(n(a[0]), n(a[1])) : Offset.zero,
      end: a.length == 4 ? Offset(n(a[2]), n(a[3])) : Offset.zero,
      fileId: (j['d'] as String?) ?? '',
      mime: (j['m'] as String?) ?? '',
      bytes: (j['z'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Who a board is shared with.
enum ShareMode { view, edit }

class KanvasBoard {
  const KanvasBoard({
    required this.id,
    required this.ownerUid,
    required this.title,
    this.folder = '',
    this.shapes = const [],
    this.updatedAt,
    this.updatedBy = '',
    this.classroomId = '',
    this.classroomMode = ShareMode.view,
    this.people = const {},
  });

  final String id;
  final String ownerUid;
  final String title;

  /// Empty for no folder.
  final String folder;
  final List<KShape> shapes;
  final DateTime? updatedAt;
  final String updatedBy;

  /// The classroom it's shared with, or empty. Everyone in it can see the
  /// board; with [classroomMode] edit, they can change it too.
  final String classroomId;
  final ShareMode classroomMode;

  /// People it's shared with, by uid.
  final Map<String, ShareMode> people;

  bool canEdit(String uid, {bool inClassroom = false}) =>
      uid == ownerUid ||
      people[uid] == ShareMode.edit ||
      (inClassroom && classroomMode == ShareMode.edit);

  /// Words to search for: the title, folder and all the writing on it.
  String get searchText => [
    title,
    folder,
    for (final s in shapes) ...[s.text, for (final i in s.items) i.text],
  ].join(' ').toLowerCase();

  KanvasBoard copyWith({
    String? title,
    String? folder,
    List<KShape>? shapes,
    String? classroomId,
    ShareMode? classroomMode,
    Map<String, ShareMode>? people,
  }) => KanvasBoard(
    id: id,
    ownerUid: ownerUid,
    title: title ?? this.title,
    folder: folder ?? this.folder,
    shapes: shapes ?? this.shapes,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
    classroomId: classroomId ?? this.classroomId,
    classroomMode: classroomMode ?? this.classroomMode,
    people: people ?? this.people,
  );
}

/// A saved copy of a board's contents, to go back to.
class KanvasVersion {
  const KanvasVersion({
    required this.id,
    required this.shapes,
    required this.savedAt,
    required this.savedBy,
  });

  final String id;
  final List<KShape> shapes;
  final DateTime savedAt;
  final String savedBy;
}

/// A board pinned to a step, or shared with a classroom, as the classroom sees
/// it.
class ClassroomBoard {
  const ClassroomBoard({
    required this.boardId,
    required this.ownerUid,
    required this.title,
    this.stepId = '',
  });

  final String boardId;
  final String ownerUid;
  final String title;

  /// The step it's pinned to, or empty.
  final String stepId;
}

/// Shapes to and from the stored text.
String encodeShapes(List<KShape> shapes) =>
    jsonEncode([for (final s in shapes) s.toJson()]);

List<KShape> decodeShapes(String? text) {
  if (text == null || text.isEmpty) return const [];
  try {
    final list = jsonDecode(text);
    if (list is! List) return const [];
    return [
      for (final j in list)
        if (j is Map) KShape.fromJson(j.cast<String, Object?>()),
    ];
  } on FormatException {
    return const [];
  }
}

/// How much a board's contents can hold, safely under Firestore's 1 MB limit.
const int kMaxBoardBytes = 800 * 1024;

// Geometry ------------------------------------------------------------------

/// Drops points that add nothing, so a long line stays small to store.
List<Offset> simplify(List<Offset> points, [double tolerance = 0.8]) {
  if (points.length < 3) return points;
  double distance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len = ab.distanceSquared;
    if (len == 0) return (p - a).distance;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len;
    final c = a + ab * t.clamp(0.0, 1.0);
    return (p - c).distance;
  }

  List<Offset> run(int from, int to) {
    var far = 0.0;
    var index = from;
    for (var i = from + 1; i < to; i++) {
      final d = distance(points[i], points[from], points[to]);
      if (d > far) {
        far = d;
        index = i;
      }
    }
    if (far <= tolerance) return [points[from], points[to]];
    final left = run(from, index);
    final right = run(index, to);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  return run(0, points.length - 1);
}

/// The area a shape covers, for drawing only what's on screen and selecting.
Rect boundsOf(KShape s, Map<String, KShape> byId) {
  switch (s.kind) {
    case ShapeKind.stroke:
      if (s.points.isEmpty) return Rect.zero;
      var r = Rect.fromPoints(s.points.first, s.points.first);
      for (final p in s.points) {
        r = r.expandToInclude(Rect.fromPoints(p, p));
      }
      return r.inflate(s.width);
    case ShapeKind.arrow:
      final (a, b) = arrowEnds(s, byId);
      return Rect.fromPoints(a, b).inflate(8);
    default:
      return s.rect;
  }
}

/// Where an arrow starts and ends: on the edge of each shape it joins, or at
/// its free ends.
(Offset, Offset) arrowEnds(KShape arrow, Map<String, KShape> byId) {
  final from = byId[arrow.fromId];
  final to = byId[arrow.toId];
  final a0 = from != null && from.isRect ? from.rect.center : arrow.start;
  final b0 = to != null && to.isRect ? to.rect.center : arrow.end;
  final a = from != null && from.isRect ? edgePoint(from.rect, b0) : a0;
  final b = to != null && to.isRect ? edgePoint(to.rect, a0) : b0;
  return (a, b);
}

/// Where a line from the rectangle's centre towards [toward] leaves it.
Offset edgePoint(Rect r, Offset toward) {
  final c = r.center;
  final d = toward - c;
  if (d == Offset.zero) return c;
  final sx = d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs();
  final sy = d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs();
  final s = math.min(sx, sy);
  return c + d * math.min(s, 1.0);
}

/// Whether [p] touches the shape, within [slop] board units.
bool hits(KShape s, Offset p, Map<String, KShape> byId, {double slop = 6}) {
  switch (s.kind) {
    case ShapeKind.stroke:
      for (var i = 0; i + 1 < s.points.length; i++) {
        if (_nearSegment(p, s.points[i], s.points[i + 1], slop + s.width)) {
          return true;
        }
      }
      return s.points.length == 1 &&
          (s.points.first - p).distance <= slop + s.width;
    case ShapeKind.arrow:
      final (a, b) = arrowEnds(s, byId);
      return _nearSegment(p, a, b, slop + s.width);
    default:
      return s.rect.inflate(slop).contains(p);
  }
}

bool _nearSegment(Offset p, Offset a, Offset b, double within) {
  final ab = b - a;
  final len = ab.distanceSquared;
  final t = len == 0
      ? 0.0
      : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance <= within;
}

/// The topmost rectangle-like shape under [p], for joining arrows.
KShape? shapeAt(List<KShape> shapes, Offset p, {String except = ''}) {
  for (final s in shapes.reversed) {
    if (s.isRect && s.id != except && s.rect.inflate(4).contains(p)) return s;
  }
  return null;
}
