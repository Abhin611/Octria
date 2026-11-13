import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'data/backend.dart';
import 'data/demo_seed.dart';
import 'data/firebase_backend.dart';
import 'data/local_backend.dart';
import 'ai/sample_ai.dart';
import 'firebase_options.dart';
import 'ofy/ofy.dart';
import 'ofy/ofy_host.dart';
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
    await _checkApp();
    return FirebaseBackend();
  } on UnsupportedError catch (e) {
    debugPrint('Running on sample plans: ${e.message}');
    return null;
  }
}

/// The site's Fraud Defense (reCAPTCHA Enterprise) key, which proves to Firebase that requests to Ofy
/// come from Octria's own website. Public by design, but set at build time
/// so anyone running their own copy uses their own.
const _recaptchaKey = String.fromEnvironment('OCTRIA_RECAPTCHA_KEY');

/// An App Check debug token for phone builds handed out before the app is on
/// Google Play. Never commit one: it's given only at build time.
const _appCheckDebugToken = String.fromEnvironment(
  'OCTRIA_APPCHECK_DEBUG_TOKEN',
);

/// Turns on App Check, which Firebase requires before Ofy will answer.
Future<void> _checkApp() async {
  try {
    if (kIsWeb) {
      if (_recaptchaKey.isEmpty) return;
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaEnterpriseProvider(_recaptchaKey),
      );
      return;
    }
    await FirebaseAppCheck.instance.activate(
      providerAndroid: _appCheckDebugToken.isNotEmpty || kDebugMode
          ? AndroidDebugProvider(
              debugToken: _appCheckDebugToken.isEmpty
                  ? null
                  : _appCheckDebugToken,
            )
          : const AndroidPlayIntegrityProvider(),
    );
  } on Object catch (e) {
    // Everything but Ofy works without it; Ofy says what's missing.
    debugPrint('App Check is off: $e');
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
  final _navigator = GlobalKey<NavigatorState>();

  /// Ofy, on every screen. Without a backend it answers from its own guide.
  late final _ofy = Ofy(ai: widget.backend?.ai ?? SampleAi());

  @override
  void dispose() {
    _ofy.dispose();
    super.dispose();
  }

  void _setBrightness(Brightness value) => setState(() => _brightness = value);

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Octria',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      builder: (context, child) => PaletteFade(
        child: OfyHost(
          ofy: _ofy,
          navigator: _navigator,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
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
