import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// True where the file is saved straight to Downloads.
const bool savesToDownloads = false;

/// Opens the share sheet with [text] as a file called [name], so it can go to
/// a calendar, Drive or mail. False if nothing could open.
Future<bool> saveTextFile(String name, String mime, String text) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(text)),
            mimeType: mime,
            name: name,
          ),
        ],
        fileNameOverrides: [name],
      ),
    );
    return result.status != ShareResultStatus.unavailable;
  } on Object {
    return false;
  }
}
