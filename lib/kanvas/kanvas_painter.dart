import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/cupertino.dart';

import '../data/drive.dart';
import '../theme/tokens.dart';
import 'kanvas_files.dart';
import 'kanvas_model.dart';

/// Where the board is on screen. Unlike Flowspace, a board has no edges.
class KanvasCamera extends ChangeNotifier {
  Offset pan = Offset.zero;
  double scale = 1;

  static const minScale = 0.1;
  static const maxScale = 4.0;

  Offset toWorld(Offset s) => (s - pan) / scale;
  Offset toScreen(Offset w) => w * scale + pan;

  void panBy(Offset d) {
    pan += d;
    notifyListeners();
  }

  void zoomAround(Offset focal, double factor) {
    final next = (scale * factor).clamp(minScale, maxScale);
    final anchor = toWorld(focal);
    scale = next;
    pan = focal - anchor * next;
    notifyListeners();
  }

  /// Frames [world] inside [viewport], never zooming in past full size.
  void fit(Rect world, Size viewport, {EdgeInsets padding = EdgeInsets.zero}) {
    if (world.isEmpty || viewport.isEmpty) {
      scale = 1;
      pan = Offset(viewport.width / 2, viewport.height / 2);
      notifyListeners();
      return;
    }
    final w = viewport.width - padding.horizontal;
    final h = viewport.height - padding.vertical;
    scale = math
        .min(math.min(w / world.width, h / world.height), 1.0)
        .clamp(minScale, maxScale);
    pan =
        Offset(padding.left + w / 2, padding.top + h / 2) -
        world.center * scale;
    notifyListeners();
  }
}

/// A line colour, readable on the board's ground in light and dark.
Color inkOf(KColour c, Palette p) {
  final dark = p.brightness == Brightness.dark;
  return switch (c) {
    KColour.ink => p.ink,
    KColour.yellow => dark ? const Color(0xFFFFD43B) : const Color(0xFFB7791F),
    KColour.pink => dark ? const Color(0xFFF472B6) : const Color(0xFFDB2777),
    KColour.blue => dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
    KColour.green => dark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
    KColour.orange => dark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
    KColour.purple => dark ? const Color(0xFFC084FC) : const Color(0xFF7C3AED),
    KColour.red => dark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
  };
}

/// A sticky note's paper. Paper stays light in dark mode, like a real note.
Color paperOf(KColour c) => switch (c) {
  KColour.ink => const Color(0xFFF2F0EC),
  KColour.yellow => const Color(0xFFFFE58F),
  KColour.pink => const Color(0xFFFFC9DA),
  KColour.blue => const Color(0xFFC7DEFF),
  KColour.green => const Color(0xFFC8F2D0),
  KColour.orange => const Color(0xFFFFD3A8),
  KColour.purple => const Color(0xFFE0D4FF),
  KColour.red => const Color(0xFFFFC4C4),
};

const _paperInk = Color(0xFF2A2118);

/// What the canvas is in the middle of drawing, besides the shapes.
class KanvasOverlay {
  const KanvasOverlay({
    this.selected = const {},
    this.marquee,
    this.liveStroke,
    this.liveArrow,
    this.snapTarget,
    this.editingId,
  });

  final Set<String> selected;
  final Rect? marquee;
  final KShape? liveStroke;
  final KShape? liveArrow;

  /// The shape an arrow being drawn would join.
  final String? snapTarget;

  /// A shape whose text is being typed in a field over the board.
  final String? editingId;
}

class KanvasPainter extends CustomPainter {
  KanvasPainter({
    required this.shapes,
    required this.camera,
    required this.palette,
    this.overlay = const KanvasOverlay(),
    this.showGrid = true,
    this.pictures,
  }) : super(
         repaint: pictures == null
             ? camera
             : Listenable.merge([camera, pictures]),
       );

  final List<KShape> shapes;
  final KanvasCamera camera;

  /// The pictures of image cards, as they arrive.
  final BoardPictures? pictures;
  final Palette palette;
  final KanvasOverlay overlay;
  final bool showGrid;

  Palette get _p => palette;

  @override
  void paint(Canvas canvas, Size size) {
    final viewWorld = Rect.fromPoints(
      camera.toWorld(Offset.zero),
      camera.toWorld(Offset(size.width, size.height)),
    ).inflate(40);
    if (showGrid) _paintGrid(canvas, size);
    canvas.save();
    canvas.translate(camera.pan.dx, camera.pan.dy);
    canvas.scale(camera.scale);
    final byId = {for (final s in shapes) s.id: s};
    for (final s in shapes) {
      if (!boundsOf(s, byId).overlaps(viewWorld)) continue;
      _paintShape(canvas, s, byId);
    }
    if (overlay.liveStroke != null) {
      _paintShape(canvas, overlay.liveStroke!, byId);
    }
    if (overlay.liveArrow != null) {
      _paintShape(canvas, overlay.liveArrow!, byId);
    }
    final hair = 1.5 / camera.scale;
    final selection = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hair
      ..color = _p.accent;
    for (final id in overlay.selected) {
      final s = byId[id];
      if (s == null) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          boundsOf(s, byId).inflate(4 / camera.scale),
          Radius.circular(6 / camera.scale),
        ),
        selection,
      );
    }
    // One shape selected: a handle to resize it.
    if (overlay.selected.length == 1) {
      final s = byId[overlay.selected.first];
      if (s != null && s.isRect) {
        final r = handleRect(s.rect, camera.scale);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(3 / camera.scale)),
          Paint()..color = _p.accent,
        );
      }
    }
    final snap = byId[overlay.snapTarget];
    if (snap != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          snap.rect.inflate(6 / camera.scale),
          Radius.circular(8 / camera.scale),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 / camera.scale
          ..color = _p.accent.withValues(alpha: 0.7),
      );
    }
    final m = overlay.marquee;
    if (m != null) {
      canvas.drawRect(m, Paint()..color = _p.accent.withValues(alpha: 0.08));
      canvas.drawRect(m, selection);
    }
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Size size) {
    // Dots every 40 board units, spaced out as you zoom out so they never
    // crowd.
    var step = 40.0 * camera.scale;
    while (step < 18) {
      step *= 2;
    }
    final dot = Paint()
      ..color = _p.inkFaint.withValues(alpha: 0.22)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final start = Offset(camera.pan.dx % step, camera.pan.dy % step);
    final points = <Offset>[
      for (var x = start.dx; x < size.width; x += step)
        for (var y = start.dy; y < size.height; y += step) Offset(x, y),
    ];
    canvas.drawPoints(PointMode.points, points, dot);
  }

  void _paintShape(Canvas canvas, KShape s, Map<String, KShape> byId) {
    if (s.id == overlay.editingId && s.kind != ShapeKind.checklist) {
      // The text is in a field on top; draw only the shape behind it.
      _paintBody(canvas, s, byId, withText: false);
      return;
    }
    _paintBody(canvas, s, byId, withText: true);
  }

  void _paintBody(
    Canvas canvas,
    KShape s,
    Map<String, KShape> byId, {
    required bool withText,
  }) {
    final ink = inkOf(s.colour, _p);
    switch (s.kind) {
      case ShapeKind.stroke:
        if (s.points.isEmpty) return;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ink;
        if (s.points.length == 1) {
          canvas.drawCircle(s.points.first, s.width / 2, Paint()..color = ink);
          return;
        }
        final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
        // Smooth through the midpoints, so a quick line isn't jagged.
        for (var i = 1; i < s.points.length - 1; i++) {
          final mid = Offset.lerp(s.points[i], s.points[i + 1], 0.5)!;
          path.quadraticBezierTo(
            s.points[i].dx,
            s.points[i].dy,
            mid.dx,
            mid.dy,
          );
        }
        path.lineTo(s.points.last.dx, s.points.last.dy);
        canvas.drawPath(path, paint);
      case ShapeKind.sticky:
        final r = RRect.fromRectAndRadius(s.rect, const Radius.circular(6));
        canvas.drawRRect(
          r.shift(const Offset(0, 3)),
          Paint()
            ..color = const Color(0x33000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawRRect(r, Paint()..color = paperOf(s.colour));
        if (withText) {
          _text(
            canvas,
            s.text.isEmpty ? 'Double-tap to write' : s.text,
            s.rect.deflate(12),
            s.text.isEmpty ? _paperInk.withValues(alpha: 0.4) : _paperInk,
            15,
          );
        }
      case ShapeKind.text:
        if (withText) {
          _text(
            canvas,
            s.text.isEmpty ? 'Text' : s.text,
            s.rect.deflate(4),
            s.text.isEmpty ? _p.inkFaint : ink,
            18,
            weight: FontWeight.w600,
          );
        }
      case ShapeKind.checklist:
        final r = RRect.fromRectAndRadius(s.rect, const Radius.circular(10));
        canvas.drawRRect(r, Paint()..color = _p.panel);
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = _p.hairline,
        );
        if (!withText) return;
        var y = s.rect.top + 12;
        for (final item in s.items) {
          if (y + 20 > s.rect.bottom) break;
          final box = Rect.fromLTWH(s.rect.left + 12, y + 2, 15, 15);
          final boxPaint = Paint()
            ..style = item.done ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = item.done ? _p.done : _p.inkSoft;
          canvas.drawRRect(
            RRect.fromRectAndRadius(box, const Radius.circular(3)),
            boxPaint,
          );
          if (item.done) {
            final tick = Path()
              ..moveTo(box.left + 3.5, box.center.dy)
              ..lineTo(box.left + 6.5, box.bottom - 4)
              ..lineTo(box.right - 3, box.top + 4);
            canvas.drawPath(
              tick,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.8
                ..color = _p.brightness == Brightness.dark
                    ? _p.ground
                    : const Color(0xFFFFFFFF),
            );
          }
          _text(
            canvas,
            item.text.isEmpty ? 'Item' : item.text,
            Rect.fromLTRB(box.right + 8, y, s.rect.right - 10, y + 22),
            item.done ? _p.inkFaint : _p.ink,
            14,
            maxLines: 1,
            strike: item.done,
          );
          y += checklistRow;
        }
      case ShapeKind.box || ShapeKind.ellipse:
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width
          ..color = ink;
        final fill = Paint()..color = ink.withValues(alpha: 0.07);
        if (s.kind == ShapeKind.box) {
          final r = RRect.fromRectAndRadius(s.rect, const Radius.circular(10));
          canvas.drawRRect(r, fill);
          canvas.drawRRect(r, paint);
        } else {
          canvas.drawOval(s.rect, fill);
          canvas.drawOval(s.rect, paint);
        }
        if (withText && s.text.isNotEmpty) {
          _text(canvas, s.text, s.rect.deflate(14), _p.ink, 15, centre: true);
        }
      case ShapeKind.arrow:
        final (a, b) = arrowEnds(s, byId);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width
          ..strokeCap = StrokeCap.round
          ..color = ink;
        canvas.drawLine(a, b, paint);
        final d = b - a;
        if (d.distance > 1) {
          final u = d / d.distance;
          final n = Offset(-u.dy, u.dx);
          final size = 8 + s.width * 1.5;
          canvas.drawPath(
            Path()
              ..moveTo(b.dx, b.dy)
              ..lineTo(
                (b - u * size + n * size * 0.55).dx,
                (b - u * size + n * size * 0.55).dy,
              )
              ..lineTo(
                (b - u * size - n * size * 0.55).dx,
                (b - u * size - n * size * 0.55).dy,
              )
              ..close(),
            Paint()..color = ink,
          );
        }
      case ShapeKind.file:
        _paintFile(canvas, s, withText: withText);
      case ShapeKind.link:
        final r = RRect.fromRectAndRadius(s.rect, const Radius.circular(12));
        canvas.drawRRect(r, Paint()..color = _p.panel);
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = _p.hairline,
        );
        final chip = Rect.fromLTWH(s.rect.left + 12, s.rect.top + 14, 34, 34);
        canvas.drawRRect(
          RRect.fromRectAndRadius(chip, const Radius.circular(9)),
          Paint()..color = _p.accent.withValues(alpha: 0.16),
        );
        _glyph(canvas, linkGlyph(s.url), chip, _p.accent);
        if (!withText) return;
        final host = Uri.tryParse(s.url)?.host.replaceFirst('www.', '') ?? '';
        _text(
          canvas,
          s.text.isEmpty ? host : s.text,
          Rect.fromLTRB(
            chip.right + 10,
            s.rect.top + 12,
            s.rect.right - 10,
            s.rect.top + 34,
          ),
          _p.ink,
          14,
          maxLines: 1,
          weight: FontWeight.w600,
        );
        _text(
          canvas,
          host,
          Rect.fromLTRB(
            chip.right + 10,
            s.rect.top + 33,
            s.rect.right - 10,
            s.rect.bottom - 6,
          ),
          _p.inkSoft,
          12,
          maxLines: 1,
        );
    }
  }

  Color _fileColour(FileKind kind) => switch (kind) {
    FileKind.pdf => _p.accentWarm,
    FileKind.image => _p.accentTeal,
    FileKind.video => _p.accentViolet,
    _ => _p.accent,
  };

  /// An image card shows its picture; a PDF, a video, or an image whose
  /// picture hasn't arrived shows a card with its icon, name and size.
  void _paintFile(Canvas canvas, KShape s, {required bool withText}) {
    final r = RRect.fromRectAndRadius(s.rect, const Radius.circular(12));
    final kind = fileKindOf(s.mime);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _p.hairline;
    final picture = pictures?[s.fileId];
    if (picture != null) {
      final whole = Size(picture.width.toDouble(), picture.height.toDouble());
      final fit = applyBoxFit(BoxFit.cover, whole, s.rect.size);
      final from = Alignment.center.inscribe(fit.source, Offset.zero & whole);
      canvas.save();
      canvas.clipRRect(r);
      canvas.drawImageRect(
        picture,
        from,
        s.rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      canvas.drawRRect(r, edge);
      return;
    }
    canvas.drawRRect(r, Paint()..color = _p.panel);
    canvas.drawRRect(r, edge);
    final colour = _fileColour(kind);
    final side = math.min(44.0, s.rect.height - 20).clamp(20.0, 44.0);
    final chip = Rect.fromLTWH(
      s.rect.left + 14,
      s.rect.center.dy - side / 2,
      side,
      side,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(10)),
      Paint()..color = colour.withValues(alpha: 0.16),
    );
    _glyph(canvas, fileGlyph(kind), chip, colour);
    final play = kind == FileKind.video;
    final right = s.rect.right - (play ? 52 : 12);
    if (play) {
      final disc = Rect.fromCircle(
        center: Offset(s.rect.right - 30, s.rect.center.dy),
        radius: 16,
      );
      canvas.drawOval(disc, Paint()..color = colour.withValues(alpha: 0.9));
      _glyph(
        canvas,
        CupertinoIcons.play_fill,
        disc.deflate(2),
        const Color(0xFFFFFFFF),
      );
    }
    if (!withText) return;
    final label = [
      switch (kind) {
        FileKind.pdf => 'PDF',
        FileKind.video => 'Video',
        FileKind.image => 'Image',
        FileKind.audio => 'Audio',
        _ => 'File',
      },
      if (s.bytes > 0) sizeLabel(s.bytes),
      'Drive',
    ].join(' · ');
    _text(
      canvas,
      s.text.isEmpty ? 'Untitled file' : s.text,
      Rect.fromLTRB(
        chip.right + 12,
        s.rect.center.dy - 20,
        right,
        s.rect.center.dy + 2,
      ),
      _p.ink,
      14,
      maxLines: 1,
      weight: FontWeight.w600,
    );
    _text(
      canvas,
      label,
      Rect.fromLTRB(
        chip.right + 12,
        s.rect.center.dy + 2,
        right,
        s.rect.center.dy + 22,
      ),
      _p.inkSoft,
      12,
      maxLines: 1,
    );
  }

  void _glyph(Canvas canvas, IconData icon, Rect box, Color colour) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: box.height * 0.55,
          color: colour,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, box.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _text(
    Canvas canvas,
    String text,
    Rect box,
    Color colour,
    double size, {
    int? maxLines,
    bool centre = false,
    bool strike = false,
    FontWeight weight = FontWeight.w400,
  }) {
    if (box.width <= 4 || box.height <= 4) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: TypeRamp.family,
          fontSize: size,
          height: 1.3,
          color: colour,
          fontVariations: [FontVariation('wght', weight.value.toDouble())],
          decoration: strike ? TextDecoration.lineThrough : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: centre ? TextAlign.center : TextAlign.left,
      maxLines: maxLines ?? math.max(1, (box.height / (size * 1.3)).floor()),
      ellipsis: '…',
    )..layout(maxWidth: box.width);
    final y = centre ? box.center.dy - tp.height / 2 : box.top;
    final x = centre ? box.center.dx - tp.width / 2 : box.left;
    canvas.save();
    canvas.clipRect(box.inflate(2));
    tp.paint(canvas, Offset(x, y));
    canvas.restore();
  }

  @override
  bool shouldRepaint(KanvasPainter old) =>
      old.shapes != shapes ||
      old.overlay != overlay ||
      old.palette != palette ||
      old.showGrid != showGrid ||
      old.pictures != pictures;
}

/// The height of one checklist line, in board units.
const double checklistRow = 26;

/// The square in a rectangle's corner that resizes it.
Rect handleRect(Rect r, double scale) {
  final side = 12 / scale;
  return Rect.fromCenter(center: r.bottomRight, width: side, height: side);
}

/// An icon for a kind of file.
IconData fileGlyph(FileKind kind) => switch (kind) {
  FileKind.pdf => CupertinoIcons.doc_richtext,
  FileKind.image => CupertinoIcons.photo,
  FileKind.video => CupertinoIcons.film,
  FileKind.audio => CupertinoIcons.music_note,
  FileKind.sheet => CupertinoIcons.table,
  FileKind.slides => CupertinoIcons.rectangle_on_rectangle,
  _ => CupertinoIcons.doc,
};

/// An icon for a link, from what it points at.
IconData linkGlyph(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.contains('youtube') ||
      host.contains('youtu.be') ||
      host.contains('vimeo')) {
    return CupertinoIcons.play_rectangle;
  }
  if (url.toLowerCase().endsWith('.pdf')) return CupertinoIcons.doc_text;
  if (host.contains('github') || host.contains('gitlab')) {
    return CupertinoIcons.chevron_left_slash_chevron_right;
  }
  return CupertinoIcons.link;
}
