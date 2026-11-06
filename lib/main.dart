import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'data/backend.dart';
import 'data/demo_seed.dart';
import 'data/firebase_backend.dart';
import 'data/local_backend.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/classroom_screen.dart';
import 'screens/home_screen.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Right-click belongs to the graph, not the browser's page menu.
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  // An invite link: the site's address, then /?join=CODE
  pendingJoinCode = Uri.base.queryParameters['join'];
  // The glass runs behind the system bars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(OctriaApp(backend: await _connect()));
}

/// The real backend once a Firebase project is connected. Without one the app
/// runs on its sample plans. `--dart-define=OCTRIA_BACKEND=local` tries the real
/// screens against an in-memory backend, with nothing saved, and `=sample` opens
/// the sample plans.
Future<Backend?> _connect() async {
  const choice = String.fromEnvironment('OCTRIA_BACKEND');
  if (choice == 'local') return LocalBackend();
  // A ready-made classroom for trying comments, suggestions and notifications.
  if (choice == 'demo') return demoBackend();
  if (choice == 'sample') return null;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return FirebaseBackend();
  } on UnsupportedError catch (e) {
    debugPrint('Running on sample plans: ${e.message}');
    return null;
  }
}

class OctriaApp extends StatefulWidget {
  const OctriaApp({super.key, this.backend});

  /// Accounts and stored classrooms. Without it, the sample plans.
  final Backend? backend;

  @override
  State<OctriaApp> createState() => _OctriaAppState();
}

class _OctriaAppState extends State<OctriaApp> {
  // Follows the system until someone chooses a background.
  Brightness? _brightness;

  void _setBrightness(Brightness value) => setState(() => _brightness = value);

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Octria',
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        brightness: _brightness,
        primaryColor: const CupertinoDynamicColor.withBrightness(
          color: Color(0xFF1B1F27),
          darkColor: Color(0xFFF2F4F8),
        ),
        textTheme: CupertinoTextThemeData(
          textStyle: TypeRamp.body(const Color(0xFF1B1F27)),
        ),
      ),
      home: widget.backend == null
          ? ClassroomScreen(onBrightnessChanged: _setBrightness)
          : AuthGate(
              backend: widget.backend!,
              onBrightnessChanged: _setBrightness,
            ),
    );
  }
}
