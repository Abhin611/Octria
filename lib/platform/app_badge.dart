/// The red number on Octria's app icon, like the one on Settings: how many
/// things wait on this person. Phones whose launcher shows numbers show it;
/// on the web it shows on Octria once it's installed as an app.
library;

export 'app_badge_io.dart' if (dart.library.js_interop) 'app_badge_web.dart';
