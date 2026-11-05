// A placeholder with no keys in it. Copy it to lib/firebase_options.dart to run
// a fresh copy of this project, or generate the real file with
// `flutterfire configure`. See the README.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  /// The app catches this and opens on its sample plans.
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
    'No Firebase project is connected. Run `flutterfire configure`.',
  );
}
