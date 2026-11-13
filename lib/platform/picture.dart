/// Pictures made small enough to show Ofy: a screenshot or photo, shrunk so
/// its longest side is no more than a set size, as a PNG.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The longest side of a picture sent to Ofy. Enough to read text on a
/// screen, small enough to send quickly.
const int kOfyPictureSide = 1280;

/// [bytes] as a PNG no longer than [side] on its longest side. Null if it
/// isn't a picture this device can read.
Future<Uint8List?> shrinkPicture(
  Uint8List bytes, {
  int side = kOfyPictureSide,
}) async {
  ui.Image? picture;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        if (math.max(width, height) <= side) return ui.TargetImageSize();
        return width >= height
            ? ui.TargetImageSize(width: side)
            : ui.TargetImageSize(height: side);
      },
    );
    picture = (await codec.getNextFrame()).image;
    codec.dispose();
    return await pngOf(picture);
  } on Object {
    return null;
  } finally {
    picture?.dispose();
  }
}

/// A picture already in memory, as PNG bytes. Null if it can't be written.
Future<Uint8List?> pngOf(ui.Image picture) async {
  try {
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } on Object {
    return null;
  }
}

/// How much to scale a capture of something [width] by [height] so its
/// longest side is no more than [side]. Never scales up.
double captureScale(double width, double height, {int side = kOfyPictureSide}) {
  final longest = math.max(width, height);
  if (longest <= 0) return 1;
  return math.min(1, side / longest);
}
