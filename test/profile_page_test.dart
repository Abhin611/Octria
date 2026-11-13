import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/data/demo_seed.dart';
import 'package:octria/main.dart';
import 'package:octria/theme/tokens.dart';
import 'package:octria/widgets/controls.dart';

Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

void main() {
  testWidgets('the profile page shows its numbers and the reminders switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = await tester.runAsync(demoBackend);
    await tester.pumpWidget(OctriaApp(backend: backend));
    await _settle(tester, 60);
    await tester.tap(find.text('Profile').first);
    await _settle(tester, 60);
    expect(tester.takeException(), isNull);
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Edit profile and account'), findsOneWidget);
  });

  testWidgets('the backdrop draws nothing, and breaks nothing, with no room', (
    tester,
  ) async {
    // A window that is still opening has no size for a frame or two.
    for (final size in const [Size.zero, Size(0, 300), Size(400, 300)]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PaletteScope(
            palette: Palette.dark,
            child: Center(
              child: SizedBox.fromSize(
                size: size,
                child: const AmbientBackdrop(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a classroom offers its steps for the calendar', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = await tester.runAsync(demoBackend);
    await tester.pumpWidget(OctriaApp(backend: backend));
    await _settle(tester, 60);
    await tester.tap(find.text('App launch').first);
    await _settle(tester, 80);
    final entry = find.text('Add to calendar');
    await tester.ensureVisible(entry);
    await _settle(tester, 10);
    await tester.tap(entry);
    await _settle(tester, 40);
    expect(tester.takeException(), isNull);
    expect(find.text('My steps'), findsOneWidget);
    expect(find.textContaining('Everyone'), findsOneWidget);
  });
  testWidgets('applying a re-plan plays the changes back on the graph', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = await tester.runAsync(demoBackend);
    await tester.pumpWidget(OctriaApp(backend: backend));
    await _settle(tester, 60);
    await tester.tap(find.text('App launch').first);
    await _settle(tester, 80);
    await tester.tap(find.text('Re-plan'));
    await _settle(tester, 40);
    final apply = find.textContaining('Apply: move');
    expect(apply, findsOneWidget);
    await tester.tap(apply);
    // The sheet leaves, then every changed step takes its turn: nothing in
    // the drawing may fail at any point along the way.
    for (var i = 0; i < 260; i++) {
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull, reason: 'frame $i');
    }
    expect(find.textContaining('Apply: move'), findsNothing);
    expect(find.text('Flowspace'), findsWidgets);
  });
}
