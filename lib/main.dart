import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'screens/classroom_screen.dart';
import 'theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Right-click belongs to the graph, not the browser's page menu.
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  // The glass runs behind the system bars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const OctriaApp());
}

class OctriaApp extends StatefulWidget {
  const OctriaApp({super.key});

  @override
  State<OctriaApp> createState() => _OctriaAppState();
}

class _OctriaAppState extends State<OctriaApp> {
  // Follows the system until someone chooses a background.
  Brightness? _brightness;

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
      home: ClassroomScreen(
        onBrightnessChanged: (value) => setState(() => _brightness = value),
      ),
    );
  }
}
