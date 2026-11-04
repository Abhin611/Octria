import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/graph/graph_painter.dart';
import 'package:octria/main.dart';
import 'package:octria/model/plan.dart';
import 'package:octria/model/sample_plans.dart';
import 'package:octria/widgets/spring_sheet.dart';

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  final bytes = await rootBundle.load('assets/fonts/Inter.ttf');
  await (FontLoader('Inter')..addFont(Future.value(bytes))).load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const OctriaApp());
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  // The wide layout opens on the next step; these tests want the whole plan.
  if (size.width >= 840) {
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    // The camera glides there over many frames.
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
  }
}

bool _isMap(Widget w) =>
    w is CustomPaint &&
    w.painter is GraphPainter &&
    !(w.painter as GraphPainter).headers;

GraphScene _scene(WidgetTester tester) {
  final finder = find.byWidgetPredicate(_isMap);
  return (tester.widget<CustomPaint>(finder).painter as GraphPainter).scene;
}

Plan _plan(WidgetTester tester) => _scene(tester).controller.plan;

/// A step's position on the test screen.
Offset _at(WidgetTester tester, String id) {
  final scene = _scene(tester);
  final canvas = tester.getTopLeft(find.byWidgetPredicate(_isMap));
  return canvas + scene.camera.toScreen(scene.controller.positions[id]!);
}

/// Lets the pending notice timer finish so no timer outlives the test.
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  testWidgets('dragging a step to another lane hands it over', (tester) async {
    await _pumpApp(tester, const Size(1440, 900));
    final from = _at(tester, 'detail');
    final chenLane = _scene(tester).controller.layout.laneBands['chen']!;
    final camera = _scene(tester).camera;
    final canvasTop =
        from.dy -
        camera.toScreen(_scene(tester).controller.positions['detail']!).dy;
    final to = Offset(from.dx, canvasTop + camera.toScreen(chenLane.center).dy);

    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_scene(tester).movingId, 'detail');
    await gesture.up();
    await tester.pump();

    expect(_plan(tester).steps['detail']!.ownerId, 'chen');
    await _drainTimers(tester);
  });

  testWidgets('a dependency that would make a loop is refused', (tester) async {
    await _pumpApp(tester, const Size(1440, 900));
    final handleFrom = _at(tester, 'test');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: handleFrom);
    await mouse.moveTo(handleFrom);
    await tester.pump();
    expect(_scene(tester).hoveredId, 'test');

    final handle =
        handleFrom +
        Offset(
          nodeSizeAt(
                    _scene(tester).camera.scale,
                    row: _scene(tester).camera.rowHeight,
                  ).width /
                  2 +
              16,
          0,
        );
    final target = _at(tester, 'list');
    await mouse.moveTo(handle);
    await tester.pump();
    await mouse.down(handle);
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await mouse.moveTo(Offset.lerp(handle, target, i / 6)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_scene(tester).linkFromId, 'test');
    await mouse.up();
    await tester.pump();

    expect(find.textContaining('create a loop'), findsOneWidget);
    expect(_plan(tester).steps['list']!.dependsOn, isNot(contains('test')));
    await mouse.removePointer();
    await _drainTimers(tester);
  });

  testWidgets('right-click opens the step menu', (tester) async {
    await _pumpApp(tester, const Size(1440, 900));
    final gesture = await tester.startGesture(
      _at(tester, 'survey'),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Open step'), findsOneWidget);
  });

  testWidgets('finishing a step moves your next step on', (tester) async {
    await _pumpApp(tester, const Size(1440, 900));
    expect(_scene(tester).nextId, 'list');

    await tester.tapAt(_at(tester, 'list'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Start step'));
    await tester.pump();
    // Touch devices slide to finish; the thumb starts at the left of the track.
    final track = find.ancestor(
      of: find.text('Slide to mark done'),
      matching: find.byType(SwipeToDone),
    );
    await tester.dragFrom(
      tester.getTopLeft(track) + Offset(25, tester.getSize(track).height / 2),
      Offset(tester.getSize(track).width, 0),
    );
    await tester.pump();
    expect(_plan(tester).steps['list']!.status, StepStatus.done);
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(_plan(tester).steps['list']!.status, StepStatus.doing);
    await _drainTimers(tester);
  });

  testWidgets('focus on me dims other people', (tester) async {
    await _pumpApp(tester, const Size(1440, 900));
    await tester.tap(find.text('Focus on me'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_scene(tester).focus, 1);
  });

  testWidgets('phone layout: no overflow, sheet opens and closes', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(390, 844));
    expect(find.text('Timeline'), findsOneWidget); // The bottom tab.
    expect(find.textContaining('Next: Build event list'), findsOneWidget);
    await tester.tapAt(_at(tester, 'list'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Start step'), findsOneWidget);

    // Back closes the sheet rather than leaving the screen.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    expect(_scene(tester).selectedId, isNull);

    await tester.tap(find.text('List'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Research'), findsOneWidget);
  });

  testWidgets('dark, big text and narrow all lay out cleanly', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await _pumpApp(tester, const Size(360, 640));
    await tester.tap(find.text('List'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Timeline'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a step under Needs takes you to that step', (tester) async {
    await _pumpApp(tester, const Size(1440, 900));
    await tester.tap(find.text('Exam prep: Physics'));
    await tester.pump(const Duration(seconds: 2));

    await tester.tapAt(_at(tester, 'p2'));
    await tester.pump(const Duration(seconds: 1));
    expect(_scene(tester).selectedId, 'p2');
    expect(find.text('Study materials'), findsOneWidget);
    expect(find.text('Thermodynamics notes'), findsOneWidget);

    final needed = find.text('Waves and optics');
    await tester.ensureVisible(needed);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(needed);
    await tester.pump(const Duration(seconds: 2));

    expect(_scene(tester).selectedId, 'p1');
    expect(find.text('Waves and optics notes'), findsOneWidget);
    final at = _at(tester, 'p1');
    expect(at.dx, inInclusiveRange(0, 1440));
    expect(at.dy, inInclusiveRange(0, 900));
  });

  testWidgets('ticking a checklist item updates the step', (tester) async {
    await _pumpApp(tester, const Size(1440, 900));
    await tester.tap(find.text('Exam prep: Physics'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tapAt(_at(tester, 'p2'));
    await tester.pump(const Duration(seconds: 1));
    expect(_plan(tester).steps['p2']!.checklistDone, 1);

    final item = find.text('Entropy problems');
    await tester.ensureVisible(item);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(item);
    await tester.pump();
    expect(_plan(tester).steps['p2']!.checklistDone, 2);
  });

  testWidgets('tapping an arrow highlights it and names both ends', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(1440, 900));
    final scene = _scene(tester);
    final canvas = tester.getTopLeft(find.byWidgetPredicate(_isMap));
    final positions = scene.controller.positions;
    final points = edgeLineFor(
      scene.controller.layout,
      scene.camera,
      'firebase',
      'signin',
      positions['firebase']!,
      positions['signin']!,
    ).points;
    final onTrack = points[points.length ~/ 2];

    await tester.tapAt(canvas + onTrack);
    await tester.pump(const Duration(milliseconds: 300));

    expect(_scene(tester).selectedEdge, ('firebase', 'signin'));
    expect(_scene(tester).selectedId, isNull);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('Set up Firebase'), findsOneWidget);
    expect(find.text('Add sign-in'), findsOneWidget);

    // Tapping empty map clears it.
    await tester.tapAt(const Offset(1000, 860));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_scene(tester).selectedEdge, isNull);
    expect(find.text('From'), findsNothing);
  });

  for (final (name, size) in const [
    ('landscape phone', Size(800, 360)),
    ('wide landscape phone', Size(915, 412)),
  ]) {
    testWidgets('$name opens with the next step\'s whole phase on screen', (
      tester,
    ) async {
      await _pumpApp(tester, size);
      final canvas = find.byWidgetPredicate(_isMap);
      expect(canvas, findsOneWidget);
      final camera = _scene(tester).camera;
      final half = cameraNodeSize(camera);
      for (final step in _plan(tester).stepsIn('build')) {
        final at = _at(tester, step.id);
        expect(
          at.dx - half.width / 2,
          greaterThanOrEqualTo(gutterEndFor(camera)),
        );
        expect(at.dx + half.width / 2, lessThanOrEqualTo(camera.clear.right));
        expect(
          at.dy - half.height / 2,
          greaterThanOrEqualTo(stripEndFor(camera)),
        );
        expect(at.dy + half.height / 2, lessThanOrEqualTo(camera.clear.bottom));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('landscape stays clear of the navigation bar', (tester) async {
    tester.view.padding = const FakeViewPadding(right: 48);
    addTearDown(tester.view.resetPadding);
    await _pumpApp(tester, const Size(800, 360));
    final focus = find.bySemanticsLabel('Focus on me');
    expect(tester.getRect(focus).right, lessThanOrEqualTo(800 - 48));
    // One slim bar: everything moves up and nothing floats over the map.
    expect(find.bySemanticsLabel('Show the map key'), findsOneWidget);
    expect(find.text('Next: Build event list'), findsOneWidget);
  });

  testWidgets('tapping a phase name frames that phase', (tester) async {
    await _pumpApp(tester, const Size(800, 360));
    final canvas = tester.getRect(find.byWidgetPredicate(_isMap));
    final scene = _scene(tester);
    final band = scene.controller.layout.phaseBands['launch']!;
    final x = canvas.left + scene.camera.toScreen(band.centerLeft).dx + 30;
    expect(x, lessThan(canvas.right), reason: 'the name must be on screen');
    await tester.tapAt(Offset(x, stripPaneFor(scene.camera).center.dy));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    final half = nodeSizeAt(
      _scene(tester).camera.scale,
      row: _scene(tester).camera.rowHeight,
    );
    for (final step in _plan(tester).stepsIn('launch')) {
      final at = _at(tester, step.id);
      expect(at.dx - half.width / 2, greaterThanOrEqualTo(canvas.left));
      expect(at.dx + half.width / 2, lessThanOrEqualTo(canvas.right));
    }
  });

  testWidgets('the graph switches between left-right and top-bottom', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(1440, 900));
    expect(_scene(tester).controller.layout.vertical, isFalse);
    final before = _at(tester, 'list');

    await tester.tap(find.text('Left to right'));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(_scene(tester).controller.layout.vertical, isTrue);
    expect(find.text('Top to bottom'), findsWidgets);
    expect(_at(tester, 'list'), isNot(before));

    // Tapping a step and an arrow both still work this way up.
    await tester.tapAt(_at(tester, 'list'));
    await tester.pump(const Duration(seconds: 1));
    expect(_scene(tester).selectedId, 'list');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));

    final scene = _scene(tester);
    final canvas = tester.getTopLeft(find.byWidgetPredicate(_isMap));
    final line = edgeLineFor(
      scene.controller.layout,
      scene.camera,
      'firebase',
      'signin',
      scene.controller.positions['firebase']!,
      scene.controller.positions['signin']!,
    );
    final points = line.points;
    await tester.tapAt(canvas + Offset.lerp(points[1], points[2], 0.5)!);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_scene(tester).selectedEdge, ('firebase', 'signin'));
    expect(tester.takeException(), isNull);

    // And it switches back.
    await tester.tap(find.text('Top to bottom').first);
    await tester.pump(const Duration(seconds: 1));
    expect(_scene(tester).controller.layout.vertical, isFalse);
    await tester.pump(const Duration(seconds: 10));
  });

  for (final size in const [Size(390, 844), Size(800, 360)]) {
    testWidgets('top to bottom lays out cleanly at ${size.width}', (
      tester,
    ) async {
      await _pumpApp(tester, size);
      await tester.tap(find.bySemanticsLabel('Graph direction: Left to right'));
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(_scene(tester).controller.layout.vertical, isTrue);
      final area = tester.getRect(find.byWidgetPredicate(_isMap));
      expect(area.contains(_at(tester, 'list')), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });
  }

  // People with a step whole on screen, clear of the floating controls.
  Set<String> peopleOnScreen(WidgetTester tester) {
    final scene = _scene(tester);
    final clear = scene.camera.clear;
    final node = cameraNodeSize(scene.camera);
    final left = gutterEndFor(scene.camera);
    final top = stripEndFor(scene.camera);
    return {
      for (final step in _plan(tester).steps.values)
        if (Rect.fromCenter(
              center: _at(tester, step.id),
              width: node.width,
              height: node.height,
            ).left >=
            left)
          if (_at(tester, step.id).dx + node.width / 2 <= clear.right &&
              _at(tester, step.id).dy - node.height / 2 >= top &&
              _at(tester, step.id).dy + node.height / 2 <= clear.bottom)
            step.ownerId,
    };
  }

  for (final (name, size) in const [
    ('portrait phone', Size(390, 844)),
    ('small portrait phone', Size(360, 640)),
    ('landscape phone', Size(800, 360)),
    ('tablet', Size(768, 1024)),
    ('laptop', Size(1440, 900)),
  ]) {
    for (final vertical in [false, true]) {
      final way = vertical ? 'top to bottom' : 'left to right';
      testWidgets('$name opens on 3 people with names, $way', (tester) async {
        await _pumpApp(tester, size);
        if (vertical) {
          final toggle = size.width >= 840
              ? find.text('Left to right')
              : find.bySemanticsLabel('Graph direction: Left to right');
          await tester.tap(toggle);
        } else if (size.width >= 840) {
          // The shared helper fits the plan; press through to the opening view.
          await tester.tap(find.text('Left to right'));
          for (var i = 0; i < 80; i++) {
            await tester.pump(const Duration(milliseconds: 32));
          }
          await tester.tap(find.text('Top to bottom').first);
        }
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 32));
        }
        // Names are drawn from this zoom in, and this view must show them.
        expect(_scene(tester).camera.scale, greaterThan(0.34));
        expect(peopleOnScreen(tester).length, greaterThanOrEqualTo(3));
        await tester.pump(const Duration(seconds: 10));
      });
    }
  }

  testWidgets('the background switches between white and dark', (tester) async {
    await _pumpApp(tester, const Size(390, 844));
    expect(_scene(tester).palette.brightness, Brightness.light);

    await tester.tap(find.bySemanticsLabel('Switch to dark background'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_scene(tester).palette.brightness, Brightness.dark);

    // The graph keeps its place when the background changes.
    await tester.tap(find.bySemanticsLabel('Switch to white background'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_scene(tester).palette.brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every sample step in the real plans has study materials', (
    tester,
  ) async {
    for (final plan in [campusEventsPlan(), physicsExamPlan()]) {
      for (final step in plan.steps.values) {
        expect(step.resources, isNotEmpty, reason: step.title);
        expect(step.description, isNotEmpty, reason: step.title);
      }
    }
  });
}
