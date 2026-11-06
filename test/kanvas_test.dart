import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:octria/data/local_backend.dart';
import 'package:octria/data/models.dart';
import 'package:octria/kanvas/kanvas_files.dart';
import 'package:octria/kanvas/kanvas_model.dart';

void main() {
  test('file cards keep their Drive file, type and size', () {
    const card = KShape(
      id: 'f',
      kind: ShapeKind.file,
      rect: Rect.fromLTWH(0, 0, 320, 180),
      url: 'https://drive.google.com/file/d/abc/view',
      text: 'Sketch.png',
      fileId: 'abc',
      mime: 'image/png',
      bytes: 52000,
    );
    final back = decodeShapes(encodeShapes([card])).single;
    expect(back.kind, ShapeKind.file);
    expect(back.fileId, 'abc');
    expect(back.mime, 'image/png');
    expect(back.bytes, 52000);
    expect(back.text, 'Sketch.png');
    expect(back.opens, isTrue);
    expect(showsPicture(back.mime), isTrue);
    expect(showsPicture('application/pdf'), isFalse);
    expect(
      cardRect(Offset.zero, 'image/png', width: 1600, height: 900).size,
      const Size(320, 180),
    );
    expect(cardRect(Offset.zero, 'video/mp4').height, 88);
  });

  testWidgets('a picture of an image is small enough to keep with the board', (
    tester,
  ) async {
    final big = img.Image(width: 1600, height: 1000);
    for (final px in big) {
      px
        ..r = px.x % 255
        ..g = px.y % 255
        ..b = 120;
    }
    final png = img.encodePng(big);
    final made = await tester.runAsync(() => makePreview(png));
    expect(made, isNotNull);
    expect(made!.width, kPreviewSide);
    expect(made.height, 450);
    expect(made.jpeg.length, lessThanOrEqualTo(200 * 1024));
    expect(await tester.runAsync(() => makePreview(Uint8List(10))), isNull);
  });

  test('only people who can change a board keep pictures on it', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Mina', 'mp@t.dev', 'secret1');
    final mina = b.currentUser!.uid;
    final board = await b.createBoard(title: 'Pics');
    await b.saveBoardPreview(mina, board.id, 'f1', Uint8List(50));
    expect(await b.boardPreview(mina, board.id, 'f1'), hasLength(50));
    await expectLater(
      b.saveBoardPreview(mina, board.id, 'f2', Uint8List(300 * 1024)),
      throwsA(isA<BackendFailure>()),
    );
    await b.signOut();
    await b.registerWithEmail('Amy', 'ap@t.dev', 'secret1');
    final amy = b.currentUser!.uid;
    await expectLater(
      b.boardPreview(mina, board.id, 'f1'),
      throwsA(isA<BackendFailure>()),
    );
    await b.signOut();
    await b.signInWithEmail('mp@t.dev', 'secret1');
    await b.shareBoard(
      board.id,
      people: {amy: ShareMode.view},
      classroomId: '',
      classroomMode: ShareMode.view,
    );
    await b.signOut();
    await b.signInWithEmail('ap@t.dev', 'secret1');
    expect(await b.boardPreview(mina, board.id, 'f1'), hasLength(50));
    await expectLater(
      b.saveBoardPreview(mina, board.id, 'f3', Uint8List(10)),
      throwsA(isA<BackendFailure>()),
    );
  });

  test('shapes survive being stored and read back', () {
    final shapes = [
      const KShape(
        id: 'a',
        kind: ShapeKind.sticky,
        rect: Rect.fromLTWH(10, 20, 180, 150),
        colour: KColour.pink,
        text: 'Idea\nmore',
      ),
      const KShape(
        id: 'b',
        kind: ShapeKind.stroke,
        points: [Offset(1, 2), Offset(3.25, 4.5)],
        width: 4,
      ),
      const KShape(
        id: 'c',
        kind: ShapeKind.checklist,
        rect: Rect.fromLTWH(0, 0, 200, 100),
        items: [CheckItem('One', done: true), CheckItem('Two')],
      ),
      const KShape(
        id: 'd',
        kind: ShapeKind.arrow,
        fromId: 'a',
        toId: 'c',
        start: Offset(5, 5),
        end: Offset(50, 50),
      ),
      const KShape(
        id: 'e',
        kind: ShapeKind.link,
        rect: Rect.fromLTWH(0, 0, 260, 64),
        url: 'https://youtu.be/x',
        text: 'Talk',
      ),
    ];
    final back = decodeShapes(encodeShapes(shapes));
    expect(back, hasLength(5));
    expect(back[0].text, 'Idea\nmore');
    expect(back[0].colour, KColour.pink);
    expect(back[0].rect, const Rect.fromLTWH(10, 20, 180, 150));
    expect(back[1].points.last, const Offset(3.3, 4.5));
    expect(back[2].items.first.done, isTrue);
    expect(back[3].fromId, 'a');
    expect(back[3].toId, 'c');
    expect(back[4].url, 'https://youtu.be/x');
    expect(decodeShapes('not json'), isEmpty);
  });

  test('a long straight line keeps only the points it needs', () {
    final line = [for (var i = 0; i <= 100; i++) Offset(i.toDouble(), 0)];
    expect(simplify(line), [const Offset(0, 0), const Offset(100, 0)]);
    final corner = [
      for (var i = 0; i <= 50; i++) Offset(i.toDouble(), 0),
      for (var i = 1; i <= 50; i++) Offset(50, i.toDouble()),
    ];
    expect(simplify(corner), hasLength(3));
  });

  test('arrows join the edges of the shapes they connect', () {
    const a = KShape(
      id: 'a',
      kind: ShapeKind.box,
      rect: Rect.fromLTWH(0, 0, 100, 100),
    );
    const b = KShape(
      id: 'b',
      kind: ShapeKind.box,
      rect: Rect.fromLTWH(300, 0, 100, 100),
    );
    const arrow = KShape(
      id: 'x',
      kind: ShapeKind.arrow,
      fromId: 'a',
      toId: 'b',
    );
    final (start, end) = arrowEnds(arrow, {'a': a, 'b': b});
    expect(start, const Offset(100, 50));
    expect(end, const Offset(300, 50));
    // Moving a box carries its end of the arrow along.
    final moved = a.moved(const Offset(0, 200));
    final (start2, _) = arrowEnds(arrow, {'a': moved, 'b': b});
    expect(start2.dy, greaterThan(200));
    expect(hits(arrow, const Offset(200, 50), {'a': a, 'b': b}), isTrue);
    expect(hits(arrow, const Offset(200, 90), {'a': a, 'b': b}), isFalse);
  });

  test(
    'boards are private until shared, and sharing sets who can edit',
    () async {
      final b = LocalBackend();
      await b.registerWithEmail('Mina', 'm@t.dev', 'secret1');
      final mina = b.currentUser!.uid;
      final room = await b.createClassroom(
        title: 'R',
        description: '',
        taskType: TaskType.build,
        individual: false,
      );
      final code = (await b.watchClassroom(room).first).classroom.inviteCode;
      final board = await b.createBoard(title: 'Ideas', folder: 'School');
      await b.saveBoardShapes(mina, board.id, const [
        KShape(id: 'n', kind: ShapeKind.sticky, text: 'Hello'),
      ]);
      await b.signOut();
      await b.registerWithEmail('Amy', 'a@t.dev', 'secret1');
      final amy = b.currentUser!.uid;
      await b.joinWithCode(code);
      expect(await b.watchBoard(mina, board.id).first, isNull);
      expect(await b.boardsSharedWithMe().first, isEmpty);
      await b.signOut();

      await b.signInWithEmail('m@t.dev', 'secret1');
      await b.shareBoard(
        board.id,
        people: {amy: ShareMode.view},
        classroomId: '',
        classroomMode: ShareMode.view,
      );
      await b.signOut();
      await b.signInWithEmail('a@t.dev', 'secret1');
      final seen = await b.watchBoard(mina, board.id).first;
      expect(seen?.shapes.single.text, 'Hello');
      expect((await b.boardsSharedWithMe().first).single.id, board.id);
      expect(
        () => b.saveBoardShapes(mina, board.id, const []),
        throwsA(isA<BackendFailure>()),
      );
      expect(
        () => b.updateBoardInfo(board.id, title: 'Mine'),
        throwsA(isA<BackendFailure>()),
      );
      await b.signOut();

      // Pinned to a step, everyone in the classroom can look.
      await b.signInWithEmail('m@t.dev', 'secret1');
      await b.shareBoard(
        board.id,
        people: {},
        classroomId: '',
        classroomMode: ShareMode.view,
      );
      await b.pinBoard(room, board.id, 'step1');
      await b.signOut();
      await b.signInWithEmail('a@t.dev', 'secret1');
      expect(await b.watchBoard(mina, board.id).first, isNotNull);
      expect((await b.classroomBoards(room).first).single.stepId, 'step1');
      expect(
        () => b.saveBoardShapes(mina, board.id, const []),
        throwsA(isA<BackendFailure>()),
      );
    },
  );

  test('a board keeps saved copies to go back to', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Mina', 'm@t.dev', 'secret1');
    final mina = b.currentUser!.uid;
    final board = await b.createBoard(title: 'Plan');
    await b.saveBoardVersion(mina, board.id, const [
      KShape(id: 'n', kind: ShapeKind.text, text: 'First'),
    ]);
    final versions = await b.boardVersions(mina, board.id);
    expect(versions.single.shapes.single.text, 'First');
    await b.deleteBoard(board.id);
    expect(await b.myBoards().first, isEmpty);
  });
}
