/// Reminders outside the app. A phone holds them and shows each at its time,
/// even with Octria closed. A browser can't hold one for later, so it shows
/// what's due while Octria is open.
library;

export 'reminders_io.dart' if (dart.library.js_interop) 'reminders_web.dart';
