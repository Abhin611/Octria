import 'dart:typed_data';

import 'dart:ui';

import '../kanvas/kanvas_model.dart';
import '../model/plan.dart';
import 'local_backend.dart';
import 'models.dart';
import 'drive.dart';

import 'package:image/image.dart' as img;

import '../kanvas/kanvas_files.dart';

/// A ready-made local classroom for trying the collaboration features without
/// clicking everything in. Mina is master, with her own study materials; Amy
/// has privately commented on and suggested a change to Mina's step, posted in
/// the class chat and messaged Mina privately; Ben has joined, can't see the
/// private ones, and has asked to hand his step to Amy. Opens signed in as Mina,
/// with her notifications waiting. Nothing is saved.
Future<LocalBackend> demoBackend() async {
  final b = LocalBackend();
  final now = DateTime.now();
  DateTime day(int d) => DateTime(now.year, now.month, now.day + d, 18);

  await b.registerWithEmail('Mina', 'mina@demo.test', 'demo-only');
  final mina = b.currentUser!.uid;
  final room = await b.createClassroom(
    title: 'App launch',
    description: 'Ship the first version of our app.',
    taskType: TaskType.build,
    individual: false,
    deadline: day(21),
  );
  await b.savePhase(
    room,
    const PhaseRecord(id: 'build', title: 'Build', order: 0),
  );
  await b.savePhase(
    room,
    const PhaseRecord(id: 'launch', title: 'Launch', order: 1),
  );
  final design = PlanStep(
    id: 'design',
    phaseId: 'build',
    ownerId: mina,
    title: 'Design the login page',
    description: 'Sign-in with email, Google and GitHub.',
    status: StepStatus.doing,
    estimateHours: 4,
    start: day(-1),
    due: day(3),
    checklist: const [
      ChecklistItem(title: 'Sketch the layout', done: true),
      ChecklistItem(title: 'Pick the colours'),
    ],
  );
  await b.saveStep(room, design);
  await b.saveStep(
    room,
    PlanStep(
      id: 'listing',
      phaseId: 'launch',
      ownerId: mina,
      title: 'Write the store listing',
      estimateHours: 2,
      start: day(10),
      due: day(14),
      order: 1,
    ),
  );
  await b.saveMaterial(
    room,
    StudyMaterial(
      id: b.newId(),
      kind: MaterialKind.video,
      title: 'Login page walkthrough',
      url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      ownerUid: mina,
      stepId: design.id,
      createdAt: now,
    ),
  );
  await b.saveMaterial(
    room,
    StudyMaterial(
      id: b.newId(),
      kind: MaterialKind.note,
      title: 'Colours to try',
      note: 'Warm orange for buttons, dark charcoal behind. Keep text white.',
      ownerUid: mina,
      stepId: design.id,
      createdAt: now,
    ),
  );
  final code = (await b.watchClassroom(room).first).classroom.inviteCode;
  await b.signOut();

  await b.registerWithEmail('Amy', 'amy@demo.test', 'demo-only');
  final amy = b.currentUser!.uid;
  await b.joinWithCode(code);
  await b.saveStep(
    room,
    PlanStep(
      id: 'firebase',
      phaseId: 'build',
      ownerId: amy,
      title: 'Set up Firebase',
      status: StepStatus.done,
      estimateHours: 3,
      start: day(-4),
      due: day(-1),
      order: 2,
    ),
  );
  await b.saveStep(
    room,
    PlanStep(
      id: 'signin',
      phaseId: 'build',
      ownerId: amy,
      title: 'Build sign-in',
      status: StepStatus.doing,
      dependsOn: const ['design', 'firebase'],
      estimateHours: 6,
      start: day(1),
      due: day(6),
      order: 3,
    ),
  );

  // Private notes go to Mina's own inbox; the rest of the class can't see them.
  Future<void> tellMina(ActivityKind kind, String summary) => b.notify(
    mina,
    Notice(
      classroomId: room,
      entry: ActivityEntry(
        id: '',
        actorUid: amy,
        kind: kind,
        summary: summary,
        targetId: design.id,
        affectsUid: mina,
        createdAt: now,
      ),
    ),
  );

  await b.addComment(
    room,
    design.id,
    'Love it! Can I see the mockups first?',
    ownerUid: mina,
    withUid: amy,
  );
  await tellMina(
    ActivityKind.commented,
    'Amy commented on your step “Design the login page”: Love it! Can I see '
    'the mockups first?',
  );
  await b.addSuggestion(
    room,
    Suggestion(
      id: b.newId(),
      stepId: design.id,
      fromUid: amy,
      toUid: mina,
      text: 'Add a forgot password link under the form',
      createdAt: now,
    ),
  );
  await tellMina(
    ActivityKind.suggested,
    'Amy suggested a change to your step “Design the login page”: Add a '
    'forgot password link under the form',
  );
  await b.saveMaterial(
    room,
    StudyMaterial(
      id: b.newId(),
      kind: MaterialKind.practice,
      title: 'LeetCode',
      url: 'https://leetcode.com/problemset/',
      ownerUid: amy,
      createdAt: now,
    ),
  );
  // Two files from Amy's Drive in the library: one for her step, one for all.
  for (final (name, stepId) in [
    ('Firebase setup notes.pdf', 'firebase'),
    ('Brand colours.png', ''),
  ]) {
    final up = await b.drive.upload(
      name: name,
      mimeType: mimeTypeFor(name),
      bytes: Uint8List(name.length * 9000),
      folder: 'App launch',
      anyoneWithLink: true,
    );
    await b.addFile(
      room,
      LibraryFile(
        id: up.id,
        name: up.name,
        mimeType: up.mimeType,
        size: up.size,
        url: up.url,
        ownerUid: amy,
        createdAt: now,
        stepId: stepId,
      ),
    );
  }
  await b.sendChat(room, 'Hi all! Firebase is set up, so sign-in can start.');
  await b.sendChat(
    room,
    'Everyone: use the shared colour palette in your screens, so the app '
    'looks like one thing.',
    forEveryone: true,
  );
  await b.setApplied(room, (await b.chat(room).first).last.id, true);
  // Amy offers Mina a study material and a board, for Mina to accept.
  await b.makeOffer(
    room,
    Offer(
      id: b.newId(),
      kind: OfferKind.material,
      fromUid: amy,
      toUid: mina,
      createdAt: now,
      stepId: design.id,
      title: 'Apple sign-in guidelines',
      url: 'https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple',
    ),
  );
  final amysBoard = await b.createBoard(
    title: 'Colour ideas',
    shapes: const [
      KShape(
        id: 'p1',
        kind: ShapeKind.sticky,
        rect: Rect.fromLTWH(0, 0, 180, 120),
        colour: KColour.orange,
        text: 'Warm orange buttons',
      ),
    ],
  );
  await b.makeOffer(
    room,
    Offer(
      id: b.newId(),
      kind: OfferKind.board,
      fromUid: amy,
      toUid: mina,
      createdAt: now,
      title: amysBoard.title,
      boardId: amysBoard.id,
    ),
  );
  final dm = await b.openThread(room, [mina]);
  await b.sendThreadMessage(
    room,
    dm,
    'Can we go over the login screens tomorrow?',
  );
  await b.signOut();

  // Ben joins too. He can't see Amy and Mina's private comment or suggestion.
  await b.registerWithEmail('Ben', 'ben@demo.test', 'demo-only');
  final ben = b.currentUser!.uid;
  await b.joinWithCode(code);
  await b.saveStep(
    room,
    PlanStep(
      id: 'tests',
      phaseId: 'launch',
      ownerId: ben,
      title: 'Test on three phones',
      dependsOn: const ['signin'],
      estimateHours: 3,
      start: day(7),
      due: day(10),
      order: 4,
    ),
  );
  await b.sendChat(room, 'Joined! I’ll take testing.');
  // Ben can't keep his step, so he asks the master to give it to Amy.
  await b.requestHandover(
    room,
    'tests',
    amy,
    'I’m away next week. Amy has the phones.',
  );
  await b.notify(
    mina,
    Notice(
      classroomId: room,
      entry: ActivityEntry(
        id: '',
        actorUid: ben,
        kind: ActivityKind.stepHandedOver,
        summary:
            'Ben asked to hand “Test on three phones” to Amy: I’m away next '
            'week. Amy has the phones.',
        targetId: 'tests',
        affectsUid: mina,
        createdAt: now,
      ),
    ),
  );
  await b.signOut();

  await b.signInWithEmail('mina@demo.test', 'demo-only');
  final board = await b.createBoard(
    title: 'Login page ideas',
    folder: 'App launch',
    shapes: const [
      KShape(
        id: 'n1',
        kind: ShapeKind.sticky,
        colour: KColour.yellow,
        rect: Rect.fromLTWH(0, 0, 190, 140),
        text: 'Email and password\nBig, clear fields',
      ),
      KShape(
        id: 'n2',
        kind: ShapeKind.sticky,
        rect: Rect.fromLTWH(260, 0, 190, 140),
        colour: KColour.blue,
        text: 'Google and GitHub\nOne tap each',
      ),
      KShape(
        id: 'n3',
        kind: ShapeKind.sticky,
        rect: Rect.fromLTWH(520, 0, 190, 140),
        colour: KColour.green,
        text: 'Forgot password\nUnder the form',
      ),
      KShape(id: 'a1', kind: ShapeKind.arrow, fromId: 'n1', toId: 'n2'),
      KShape(id: 'a2', kind: ShapeKind.arrow, fromId: 'n2', toId: 'n3'),
      KShape(
        id: 'c1',
        kind: ShapeKind.checklist,
        rect: Rect.fromLTWH(0, 200, 260, 110),
        items: [
          CheckItem('Sketch on paper', done: true),
          CheckItem('Mock up in Figma'),
          CheckItem('Show Amy'),
        ],
      ),
      KShape(
        id: 'l1',
        kind: ShapeKind.link,
        rect: Rect.fromLTWH(320, 220, 260, 64),
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        text: 'Login page walkthrough',
      ),
    ],
  );
  await b.shareBoard(
    board.id,
    people: {amy: ShareMode.edit},
    classroomId: '',
    classroomMode: ShareMode.view,
  );
  await b.pinBoard(room, board.id, design.id);
  await _addFileCards(b, mina, board);
  await b.createBoard(title: 'Weekend sketches');
  await b.addComment(
    room,
    design.id,
    'Sure, I’ll share them tonight.',
    ownerUid: mina,
    withUid: amy,
  );
  return b;
}

/// A mock-up picture, a PDF and a video on Mina's board, as if she had added
/// them from her Drive.
Future<void> _addFileCards(
  LocalBackend b,
  String mina,
  KanvasBoard board,
) async {
  final mock = img.Image(width: 900, height: 600);
  img.fill(mock, color: img.ColorRgb8(255, 226, 196));
  img.fillRect(
    mock,
    x1: 250,
    y1: 70,
    x2: 650,
    y2: 530,
    radius: 28,
    color: img.ColorRgb8(255, 255, 255),
  );
  for (final y in [190, 270]) {
    img.fillRect(
      mock,
      x1: 290,
      y1: y,
      x2: 610,
      y2: y + 52,
      radius: 12,
      color: img.ColorRgb8(238, 232, 226),
    );
  }
  img.fillRect(
    mock,
    x1: 290,
    y1: 370,
    x2: 610,
    y2: 430,
    radius: 30,
    color: img.ColorRgb8(255, 122, 0),
  );
  img.fillRect(
    mock,
    x1: 360,
    y1: 110,
    x2: 540,
    y2: 140,
    radius: 8,
    color: img.ColorRgb8(60, 44, 32),
  );
  final picture = await makePreview(img.encodePng(mock));
  final shapes = [...board.shapes];
  Future<void> add(String name, int size, Rect rect, {Uint8List? jpeg}) async {
    final up = await b.drive.upload(
      name: name,
      mimeType: mimeTypeFor(name),
      bytes: Uint8List(8),
      folder: 'Kanvas',
      anyoneWithLink: true,
    );
    if (jpeg != null) await b.saveBoardPreview(mina, board.id, up.id, jpeg);
    shapes.add(
      KShape(
        id: 'file-${shapes.length}',
        kind: ShapeKind.file,
        rect: rect,
        url: up.url,
        text: name,
        fileId: up.id,
        mime: up.mimeType,
        bytes: size,
      ),
    );
  }

  if (picture != null) {
    await add(
      'Login mock-up.png',
      picture.jpeg.length,
      const Rect.fromLTWH(760, -10, 320, 213),
      jpeg: picture.jpeg,
    );
  }
  await add(
    'Sign-in guidelines.pdf',
    2400000,
    const Rect.fromLTWH(320, 320, 280, 88),
  );
  await add(
    'Usability test.mp4',
    18300000,
    const Rect.fromLTWH(760, 240, 280, 88),
  );
  await b.saveBoardShapes(mina, board.id, shapes);
}
