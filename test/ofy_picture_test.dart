import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/ai/sample_ai.dart';
import 'package:octria/ofy/ofy.dart';
import 'package:octria/ofy/ofy_host.dart';
import 'package:octria/platform/picture.dart';

/// Remembers what it was asked, and answers like the sample model.
class _Watching extends SampleAi {
  _Watching() : super(delay: Duration.zero);

  OfyQuestion? asked;

  @override
  Future<OfyAnswer> chat(OfyQuestion q) {
    asked = q;
    return super.chat(q);
  }
}

void main() {
  final picture = Uint8List.fromList(List.filled(2048, 7));

  test(
    'a picture goes to Ofy with the question, and shows in the chat',
    () async {
      final ai = _Watching();
      final ofy = Ofy(ai: ai);
      await ofy.ask('What is this error?', picture: picture);
      expect(ai.asked?.picture, picture);
      expect(ai.asked?.text, 'What is this error?');
      expect(ofy.messages.first.fromMe, isTrue);
      expect(ofy.messages.first.picture, picture);
      expect(ofy.messages.last.text, contains('2 KB'));
      expect(ofy.messages.last.picture, isNull);
    },
  );

  test(
    'a picture alone asks what it shows; nothing at all asks nothing',
    () async {
      final ai = _Watching();
      final ofy = Ofy(ai: ai);
      await ofy.ask('   ', picture: picture);
      expect(ai.asked?.text, contains('What does this show'));
      ai.asked = null;
      await ofy.ask('   ');
      expect(ai.asked, isNull);
    },
  );

  test('a question with no picture carries none', () async {
    final ai = _Watching();
    await Ofy(ai: ai).ask('How do I invite people?');
    expect(ai.asked?.picture, isNull);
  });

  test('a capture is scaled down to fit, never up', () {
    expect(captureScale(2560, 1440), 0.5);
    expect(captureScale(1440, 2560), 0.5);
    expect(captureScale(800, 600), 1);
    expect(captureScale(0, 0), 1);
  });

  test('something that isn’t a picture is refused, not sent', () async {
    expect(await shrinkPicture(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  testWidgets('the chat offers the screen behind it, or a picture', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ofy = Ofy(ai: SampleAi(delay: Duration.zero));
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            OfyHost(ofy: ofy, navigator: navigator, child: child!),
        home: const CupertinoPageScaffold(child: Center(child: Text('Home'))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Ofy's button sits in the bottom right corner.
    await tester.tapAt(const Offset(860, 850));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    final attach = find.bySemanticsLabel('Show Ofy a picture');
    expect(attach, findsOneWidget);
    await tester.tap(attach);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(find.text('The screen behind this chat'), findsOneWidget);
    expect(find.text('A picture from this device'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
