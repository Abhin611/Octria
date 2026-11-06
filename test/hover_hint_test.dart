import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/widgets/controls.dart';

Widget _app({required VoidCallback onTap}) => CupertinoApp(
  home: Center(
    child: PressButton(
      label: 'Pen',
      icon: CupertinoIcons.pencil,
      iconOnly: true,
      onTap: onTap,
    ),
  ),
);

void main() {
  testWidgets('an icon button says what it does when the pointer rests on it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onTap: () {}));
    expect(find.text('Pen'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PressButton)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Pen'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Pen'), findsOneWidget);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(find.text('Pen'), findsNothing);
  });

  testWidgets('holding an icon explains it without pressing it', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_app(onTap: () => taps++));
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(PressButton)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Pen'), findsOneWidget);
    await hold.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Pen'), findsNothing);
    await tester.tap(find.byType(PressButton));
    expect(taps, 1);
  });

  testWidgets('a button with words on it needs no hint', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: PressButton(label: 'Save', onTap: () {}),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PressButton)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Save'), findsOneWidget);
  });
}
