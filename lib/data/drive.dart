/// Files kept in each person's own Google Drive. Octria stores only a link to
/// each one, so it pays for no storage.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// The largest file Octria will put in someone's Drive in one go.
const int kMaxUploadBytes = 25 * 1024 * 1024;

/// A file now in the person's Drive.
class DriveUpload {
  const DriveUpload({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.url,
  });

  final String id;
  final String name;
  final String mimeType;
  final int size;

  /// Where the file opens in Drive.
  final String url;
}

/// Something went wrong talking to Drive, said plainly.
class DriveFailure implements Exception {
  const DriveFailure(this.message, {this.cancelled = false});

  final String message;

  /// The person closed the Google window themselves: nothing to report.
  final bool cancelled;

  @override
  String toString() => message;
}

/// The person's own Google Drive, reached with the narrow `drive.file` scope:
/// Octria sees only the files it put there, never anything else.
abstract class DriveStore {
  /// Puts a file in the person's Drive, in an Octria folder named after the
  /// classroom. With [anyoneWithLink], whoever has the link can view it; the
  /// link is only ever shown inside the classroom.
  Future<DriveUpload> upload({
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required String folder,
    required bool anyoneWithLink,
  });

  /// Lets the file be opened with its link, or stops that. The file itself
  /// stays in the person's Drive either way.
  Future<void> setLinkSharing(String fileId, {required bool on});
}

/// A Drive that lives in memory, for the sample, the demo and the tests.
class MemoryDrive implements DriveStore {
  final Map<String, DriveUpload> files = {};
  final Set<String> linkShared = {};
  final _random = math.Random();

  @override
  Future<DriveUpload> upload({
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required String folder,
    required bool anyoneWithLink,
  }) async {
    if (bytes.length > kMaxUploadBytes) throw const DriveFailure(tooBig);
    final id = List.generate(
      24,
      (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)],
    ).join();
    final made = DriveUpload(
      id: id,
      name: name,
      mimeType: mimeType,
      size: bytes.length,
      url: 'https://drive.google.com/file/d/$id/view',
    );
    files[id] = made;
    if (anyoneWithLink) linkShared.add(id);
    return made;
  }

  @override
  Future<void> setLinkSharing(String fileId, {required bool on}) async {
    on ? linkShared.add(fileId) : linkShared.remove(fileId);
  }
}

const String tooBig =
    'That file is over 25 MB. Put it in Drive yourself and '
    'add its link as a study material instead.';

/// A best guess at a file's type from its name, for Drive and for the icon.
String mimeTypeFor(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return const {
        'pdf': 'application/pdf',
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'svg': 'image/svg+xml',
        'mp4': 'video/mp4',
        'mov': 'video/quicktime',
        'webm': 'video/webm',
        'mp3': 'audio/mpeg',
        'wav': 'audio/wav',
        'm4a': 'audio/mp4',
        'txt': 'text/plain',
        'md': 'text/markdown',
        'csv': 'text/csv',
        'json': 'application/json',
        'zip': 'application/zip',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      }[ext] ??
      'application/octet-stream';
}

/// What kind of thing a file is, for its icon and colour.
enum FileKind {
  pdf,
  image,
  video,
  audio,
  document,
  sheet,
  slides,
  archive,
  other,
}

FileKind fileKindOf(String mimeType) {
  if (mimeType == 'application/pdf') return FileKind.pdf;
  if (mimeType.startsWith('image/')) return FileKind.image;
  if (mimeType.startsWith('video/')) return FileKind.video;
  if (mimeType.startsWith('audio/')) return FileKind.audio;
  if (mimeType.contains('spreadsheet') ||
      mimeType.contains('excel') ||
      mimeType == 'text/csv') {
    return FileKind.sheet;
  }
  if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
    return FileKind.slides;
  }
  if (mimeType.contains('zip')) return FileKind.archive;
  if (mimeType.startsWith('text/') ||
      mimeType.contains('word') ||
      mimeType.contains('document')) {
    return FileKind.document;
  }
  return FileKind.other;
}

/// "2.4 MB", "830 KB".
String sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}

/// The body of a Drive multipart upload: the file's details, then its bytes.
({String boundary, Uint8List body}) multipartBody(
  Map<String, Object?> metadata,
  String mimeType,
  Uint8List bytes,
) {
  final boundary = 'octria${DateTime.now().microsecondsSinceEpoch}';
  final head = utf8.encode(
    '--$boundary\r\n'
    'Content-Type: application/json; charset=UTF-8\r\n\r\n'
    '${jsonEncode(metadata)}\r\n'
    '--$boundary\r\n'
    'Content-Type: $mimeType\r\n\r\n',
  );
  final tail = utf8.encode('\r\n--$boundary--');
  final body = Uint8List(head.length + bytes.length + tail.length)
    ..setRange(0, head.length, head)
    ..setRange(head.length, head.length + bytes.length, bytes)
    ..setRange(
      head.length + bytes.length,
      head.length + bytes.length + tail.length,
      tail,
    );
  return (boundary: boundary, body: body);
}
