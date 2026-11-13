import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/ai/sample_ai.dart';
import 'package:octria/kanvas/kanvas_model.dart';
import 'package:octria/kanvas/kanvas_ofy.dart';

KShape _note(String id, String text, double x, double y) => KShape(
  id: id,
  kind: ShapeKind.sticky,
  rect: Rect.fromLTWH(x, y, 180, 120),
  text: text,
);

void main() {
  group('what a board says', () {
    final shapes = [
      _note('b', 'Second in the top row', 300, 10),
      _note('a', 'First in the top row', 0, 20),
      _note('c', 'Lower down', 0, 400),
      _note('empty', '   ', 600, 0),
      const KShape(
        id: 'list',
        kind: ShapeKind.checklist,
        rect: Rect.fromLTWH(0, 800, 260, 160),
        text: 'To buy',
        items: [
          CheckItem('Paper', done: true),
          CheckItem('Pens'),
          CheckItem(''),
        ],
      ),
      const KShape(
        id: 'link',
        kind: ShapeKind.link,
        rect: Rect.fromLTWH(0, 1100, 260, 64),
        text: 'Docs',
        url: 'https://docs.flutter.dev',
      ),
      const KShape(id: 'arrow', kind: ShapeKind.arrow, fromId: 'a', toId: 'b'),
      const KShape(
        id: 'loose',
        kind: ShapeKind.arrow,
        fromId: 'a',
        toId: 'gone',
      ),
      const KShape(
        id: 'scribble',
        kind: ShapeKind.stroke,
        points: [Offset.zero, Offset(5, 5)],
      ),
    ];

    test('reads top to bottom, then left to right', () {
      expect(boardLines(shapes), [
        'Note: First in the top row',
        'Note: Second in the top row',
        'Note: Lower down',
        'List: To buy',
        '[done] Paper',
        '[to do] Pens',
        'Link: Docs (https://docs.flutter.dev)',
        '“First in the top row” leads to “Second in the top row”',
        '(Also 1 hand-drawn mark.)',
      ]);
    });

    test('a board of drawings alone has nothing to read', () {
      expect(
        boardLines(const [
          KShape(id: 's', kind: ShapeKind.stroke, points: [Offset.zero]),
        ]),
        isEmpty,
      );
      expect(boardLines(const []), isEmpty);
    });

    test('long notes are cut, and the lines are capped', () {
      final long = boardLines([_note('x', 'word ' * 200, 0, 0)]);
      expect(long.single.length, lessThan(320));
      final many = boardLines([
        for (var i = 0; i < 300; i++) _note('n$i', 'Note $i', 0, i * 150.0),
      ]);
      expect(many, hasLength(120));
    });
  });

  group('putting Ofy’s answer on the board', () {
    var n = 0;
    String id() => 'new${n++}';
    const around = Rect.fromLTWH(100, 50, 400, 300);

    test('a summary becomes one note, to the right of everything', () {
      final made = shapesFor(
        const BoardAddition(
          task: BoardTask.summary,
          help: BoardHelp(summary: 'About waves.', items: ['One', 'Two']),
        ),
        around: around,
        newId: id,
      );
      expect(made, hasLength(1));
      expect(made.single.kind, ShapeKind.sticky);
      expect(made.single.rect.left, around.right + 60);
      expect(made.single.rect.top, around.top);
      expect(made.single.text, 'About waves.\n• One\n• Two');
    });

    test('ideas become a note each, without overlapping', () {
      final made = shapesFor(
        const BoardAddition(
          task: BoardTask.ideas,
          help: BoardHelp(items: ['A', 'B', 'C', 'D', 'E']),
        ),
        around: around,
        newId: id,
      );
      expect(made.map((s) => s.text), ['A', 'B', 'C', 'D', 'E']);
      expect({for (final s in made) s.id}, hasLength(5));
      for (final a in made) {
        for (final b in made) {
          if (a.id != b.id) expect(a.rect.overlaps(b.rect), isFalse);
        }
        expect(a.rect.left, greaterThanOrEqualTo(around.right));
      }
    });

    test('steps become one checklist, nothing ticked', () {
      final made = shapesFor(
        const BoardAddition(
          task: BoardTask.steps,
          help: BoardHelp(items: ['Read', 'Write', 'Check']),
        ),
        around: null,
        newId: id,
      );
      expect(made.single.kind, ShapeKind.checklist);
      expect(made.single.items.map((i) => i.text), ['Read', 'Write', 'Check']);
      expect(made.single.items.any((i) => i.done), isFalse);
      // An empty board starts at the corner.
      expect(made.single.rect.topLeft, Offset.zero);
    });
  });

  group('Ofy’s answer', () {
    test('is tidied: no doubles, no blanks, at most twelve', () {
      final help = BoardHelp.fromJson({
        'summary': '  About waves.  ',
        'items': ['One', 'one', '', 42, for (var i = 0; i < 20; i++) 'Item $i'],
      });
      expect(help.summary, 'About waves.');
      expect(help.items.first, 'One');
      expect(help.items.where((i) => i.toLowerCase() == 'one'), hasLength(1));
      expect(help.items.length, lessThanOrEqualTo(12));
      expect(BoardHelp.fromJson(const {}).isEmpty, isTrue);
    });

    test('the sample model answers each kind of request', () async {
      final ai = SampleAi(delay: Duration.zero);
      for (final task in BoardTask.values) {
        final help = await ai.helpWithBoard(
          BoardBrief(
            title: 'Ideas',
            lines: const ['Note: Waves', 'Note: Optics'],
            task: task,
          ),
        );
        expect(help.isEmpty, isFalse, reason: task.name);
      }
    });
  });
}
