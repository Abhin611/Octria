/// Hands a small text file to the person: a download in the browser, the
/// share sheet on a phone.
library;

export 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart';
