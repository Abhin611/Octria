/// Image, PDF and video cards on a board. The files live in their owner's
/// Google Drive; an image also keeps a small picture with the board, so
/// everyone who can see the board sees it.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/backend.dart';
import '../data/drive.dart';
import 'kanvas_model.dart';

/// The longest side of a board picture, in pixels.
const int kPreviewSide = 720;

/// Whether a file card shows a picture of the file.
bool showsPicture(String mime) => fileKindOf(mime) == FileKind.image;

/// A small JPEG of [bytes], an image file, no more than [kPreviewSide] on its
/// longest side and small enough to keep with the board. Null if it isn't an
/// image this device can read.
Future<({Uint8List jpeg, int width, int height})?> makePreview(
  Uint8List bytes,
) async {
  ui.Image? picture;
  try {
    // Works on phones and in the browser alike: the size is chosen once the
    // image's own size is known.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final longest = math.max(width, height);
        if (longest <= kPreviewSide) return ui.TargetImageSize();
        return width >= height
            ? ui.TargetImageSize(width: kPreviewSide)
            : ui.TargetImageSize(height: kPreviewSide);
      },
    );
    picture = (await codec.getNextFrame()).image;
    codec.dispose();
    final raw = await picture.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return null;
    final frame = img.Image.fromBytes(
      width: picture.width,
      height: picture.height,
      bytes: raw.buffer,
      numChannels: 4,
    );
    // Lower the quality until it fits beside the board.
    for (final quality in const [78, 64, 50, 36]) {
      final jpeg = img.encodeJpg(frame, quality: quality);
      if (jpeg.length <= 200 * 1024) {
        return (jpeg: jpeg, width: picture.width, height: picture.height);
      }
    }
    return null;
  } on Object {
    return null;
  } finally {
    picture?.dispose();
  }
}

/// Where a new card sits and how big it is: a picture keeps its shape.
ui.Rect cardRect(ui.Offset at, String mime, {int? width, int? height}) {
  if (showsPicture(mime) && width != null && height != null && width > 0) {
    final w = 320.0;
    final h = (w * height / width).clamp(120.0, 520.0);
    return ui.Rect.fromLTWH(at.dx, at.dy, w, h);
  }
  return ui.Rect.fromLTWH(at.dx, at.dy, 280, 88);
}

/// The pictures of a board's image cards, fetched once each and ready to
/// paint.
class BoardPictures extends ChangeNotifier {
  BoardPictures(this._backend);

  final Backend _backend;
  final Map<String, ui.Image> _ready = {};
  final Set<String> _asked = {};
  var _disposed = false;

  /// The picture for a Drive file id, once it has arrived.
  ui.Image? operator [](String fileId) => _ready[fileId];

  /// Everything ready now, for the painter to compare.
  Map<String, ui.Image> get all => Map.unmodifiable(_ready);

  /// Asks for any picture on the board not yet fetched.
  void want(String ownerUid, String boardId, Iterable<KShape> shapes) {
    for (final s in shapes) {
      if (s.kind != ShapeKind.file || !showsPicture(s.mime)) continue;
      if (s.fileId.isEmpty || !_asked.add(s.fileId)) continue;
      unawaited(_fetch(ownerUid, boardId, s.fileId));
    }
  }

  /// Uses a picture just made on this device, without fetching it back.
  Future<void> put(String fileId, Uint8List jpeg) async {
    _asked.add(fileId);
    await _decode(fileId, jpeg);
  }

  Future<void> _fetch(String ownerUid, String boardId, String fileId) async {
    try {
      final jpeg = await _backend.boardPreview(ownerUid, boardId, fileId);
      if (jpeg != null) await _decode(fileId, jpeg);
    } on Object {
      // No picture: the card shows the file's icon and name instead.
    }
  }

  Future<void> _decode(String fileId, Uint8List jpeg) async {
    try {
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _ready[fileId]?.dispose();
      _ready[fileId] = frame.image;
      notifyListeners();
    } on Object {
      // Unreadable: the card shows the file's icon and name instead.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final i in _ready.values) {
      i.dispose();
    }
    _ready.clear();
    super.dispose();
  }
}
