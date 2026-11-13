import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// True where the file is saved straight to Downloads.
const bool savesToDownloads = true;

/// Downloads [text] as a file called [name]. False if the browser refused.
Future<bool> saveTextFile(String name, String mime, String text) async {
  try {
    final blob = web.Blob(
      [text.toJS].toJS,
      web.BlobPropertyBag(type: '$mime;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body?.append(link);
    link.click();
    link.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } on Object {
    return false;
  }
}
