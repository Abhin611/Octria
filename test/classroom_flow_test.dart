import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/data/drive.dart';
import 'package:octria/data/local_backend.dart';
import 'package:octria/data/models.dart';
import 'package:octria/data/backend.dart';
import 'package:octria/data/plan_sync.dart';
import 'package:octria/data/user_stats.dart';
import 'package:octria/graph/graph_painter.dart';
import 'package:octria/main.dart';
import 'package:octria/model/plan.dart';
import 'package:octria/data/demo_seed.dart';
import 'package:octria/data/overview.dart';
import 'package:octria/screens/classroom_forms.dart';
import 'package:octria/screens/home_screen.dart';
import 'package:octria/theme/tokens.dart';

PlanStep _step(String id, String owner, {String phase = 'p1'}) => PlanStep(
  id: id,
  phaseId: phase,
  ownerId: owner,
  title: 'Step $id',
  estimateHours: 2,
  start: DateTime(2026, 11, 1),
  due: DateTime(2026, 11, 20),
);

Future<void> _font(WidgetTester tester) async {
  final bytes = await rootBundle.load('assets/fonts/Inter.ttf');
  await (FontLoader('Inter')..addFont(Future.value(bytes))).load();
}

Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

void main() {
  test('library files: shared for everyone, private for the owner, Drive '
      'links only', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Mina', 'm@f.dev', 'secret1');
    final room = await b.createClassroom(
      title: 'Files',
      description: '',
      taskType: TaskType.build,
      individual: false,
    );
    final code = (await b.watchClassroom(room).first).classroom.inviteCode;
    await b.signOut();
    await b.registerWithEmail('Amy', 'a@f.dev', 'secret1');
    final amy = b.currentUser!.uid;
    await b.joinWithCode(code);

    Future<LibraryFile> add(String name, {bool shared = true}) async {
      final up = await b.drive.upload(
        name: name,
        mimeType: mimeTypeFor(name),
        bytes: Uint8List(100),
        folder: 'Files',
        anyoneWithLink: shared,
      );
      final f = LibraryFile(
        id: up.id,
        name: up.name,
        mimeType: up.mimeType,
        size: up.size,
        url: up.url,
        ownerUid: amy,
        createdAt: DateTime.now(),
        shared: shared,
      );
      await b.addFile(room, f);
      return f;
    }

    final open = await add('Slides.pptx');
    final mine = await add('Draft.docx', shared: false);
    expect((b.drive as MemoryDrive).linkShared, {open.id});
    expect(await b.files(room).first, hasLength(2));
    await expectLater(
      b.addFile(
        room,
        LibraryFile(
          id: 'x',
          name: 'Bad',
          mimeType: '',
          size: 1,
          url: 'https://evil.example/x',
          ownerUid: amy,
          createdAt: DateTime.now(),
        ),
      ),
      throwsA(isA<BackendFailure>()),
    );

    await b.signOut();
    await b.signInWithEmail('m@f.dev', 'secret1');
    final seen = await b.files(room).first;
    expect(seen.map((f) => f.id), [open.id]);
    await expectLater(
      b.updateFile(room, open.copyWith(shared: false)),
      throwsA(isA<BackendFailure>()),
    );
    // The master can take a file out of the library.
    await b.removeFile(room, open.id);
    expect(await b.files(room).first, isEmpty);

    await b.signOut();
    await b.signInWithEmail('a@f.dev', 'secret1');
    expect((await b.files(room).first).map((f) => f.id), [mine.id]);
    expect(fileKindOf(mimeTypeFor('a.PDF')), FileKind.pdf);
    expect(sizeLabel(2 * 1024 * 1024), '2.0 MB');
  });

  group('permissions, as the rules enforce them', () {
    late LocalBackend b;
    late String room;
    late String master;
    late String amy;

    setUp(() async {
      b = LocalBackend();
      await b.registerWithEmail('Mina', 'mina@test.dev', 'secret1');
      master = b.currentUser!.uid;
      room = await b.createClassroom(
        title: 'Launch',
        description: '',
        taskType: TaskType.build,
        individual: false,
      );
      await b.savePhase(
        room,
        const PhaseRecord(id: 'p1', title: 'One', order: 1),
      );
      final code = (await b.watchClassroom(room).first).classroom.inviteCode;
      await b.signOut();
      await b.registerWithEmail('Amy', 'amy@test.dev', 'secret1');
      amy = b.currentUser!.uid;
      await b.joinWithCode(code.toLowerCase());
    });

    test('the creator is master, and a code lets someone join', () async {
      final state = await b.watchClassroom(room).first;
      expect(state.classroom.masterUid, master);
      expect(state.classroom.roleOf(amy), MemberRole.member);
      expect(state.members.map((m) => m.name), ['Mina', 'Amy']);
    });

    test('a wrong code and a full classroom are refused, in words', () async {
      expect(
        () => b.joinWithCode('NOPE22'),
        throwsA(
          isA<BackendFailure>().having(
            (e) => e.message,
            'message',
            contains('doesn’t match'),
          ),
        ),
      );
      final code = (await b.watchClassroom(room).first).classroom.inviteCode;
      for (var i = 0; i < 8; i++) {
        await b.registerWithEmail('P$i', 'p$i@test.dev', 'secret1');
        await b.joinWithCode(code);
      }
      await b.registerWithEmail('Late', 'late@test.dev', 'secret1');
      expect(
        () => b.joinWithCode(code),
        throwsA(
          isA<BackendFailure>().having(
            (e) => e.message,
            'message',
            contains('full'),
          ),
        ),
      );
    });

    test('a member changes only their own steps and no phases', () async {
      await b.saveStep(room, _step('mine', amy));
      expect(
        () => b.saveStep(room, _step('theirs', master)),
        throwsA(isA<BackendFailure>()),
      );
      expect(
        () => b.savePhase(
          room,
          const PhaseRecord(id: 'p2', title: 'Two', order: 2),
        ),
        throwsA(isA<BackendFailure>()),
      );
    });

    test('approval holds a member’s step until the master agrees', () async {
      await b.saveStep(room, _step('s', amy));
      await b.signOut();
      await b.signInWithEmail('mina@test.dev', 'secret1');
      final state = await b.watchClassroom(room).first;
      await b.updateClassroom(state.classroom.copyWith(approvalRequired: true));
      await b.signOut();
      await b.signInWithEmail('amy@test.dev', 'secret1');
      final s = _step('s', amy);
      expect(
        () => b.saveStep(room, s.copyWith(status: StepStatus.done)),
        throwsA(isA<BackendFailure>()),
      );
      await b.saveStep(room, s.copyWith(status: StepStatus.review));
      await b.signOut();
      await b.signInWithEmail('mina@test.dev', 'secret1');
      await b.saveStep(room, s.copyWith(status: StepStatus.done));
      final after = await b.watchClassroom(room).first;
      expect(after.steps.single.status, StepStatus.done);
    });
  });

  group('joining with approval, leaving and deleting', () {
    late LocalBackend b;
    late String room;
    late String code;

    Future<void> as(String who) async {
      await b.signOut();
      await b.signInWithEmail('$who@test.dev', 'secret1');
    }

    setUp(() async {
      b = LocalBackend();
      for (final who in ['amy', 'ben']) {
        await b.registerWithEmail(who, '$who@test.dev', 'secret1');
      }
      await b.registerWithEmail('mina', 'mina@test.dev', 'secret1');
      room = await b.createClassroom(
        title: 'Launch',
        description: '',
        taskType: TaskType.build,
        individual: false,
      );
      code = (await b.watchClassroom(room).first).classroom.inviteCode;
    });

    test('with approval on, a code only asks', () async {
      final c = (await b.watchClassroom(room).first).classroom;
      await b.updateClassroom(c.copyWith(joinApprovalRequired: true));
      await as('amy');
      expect(await b.joinWithCode(code), isNull);
      expect(await b.classrooms().first, isEmpty);

      await as('mina');
      final waiting = await b.joinRequests(room).first;
      expect(waiting.single.name, 'amy');
      await b.approveJoin(room, waiting.single);
      expect(await b.joinRequests(room).first, isEmpty);

      await as('amy');
      expect((await b.classrooms().first).single.id, room);
    });

    test('a declined request leaves no way in', () async {
      final c = (await b.watchClassroom(room).first).classroom;
      await b.updateClassroom(c.copyWith(joinApprovalRequired: true));
      await as('amy');
      await b.joinWithCode(code);
      await as('mina');
      await b.declineJoin(
        room,
        b.currentUser == null
            ? ''
            : (await b.joinRequests(room).first).single.uid,
      );
      await as('amy');
      expect(await b.classrooms().first, isEmpty);
    });

    test('a member leaves, and their steps stay under the master', () async {
      await as('amy');
      await b.joinWithCode(code);
      final amy = b.currentUser!.uid;
      await b.saveStep(room, _step('s', amy));
      await b.leaveClassroom(room);
      expect(await b.classrooms().first, isEmpty);

      await as('mina');
      final state = await b.watchClassroom(room).first;
      expect(state.classroom.memberUids, isNot(contains(amy)));
      final plan = planFrom(state, b.currentUser!.uid, DateTime(2026));
      expect(plan.steps['s']!.ownerId, b.currentUser!.uid);
    });

    test('a master leaving passes the classroom to the co-master', () async {
      await as('amy');
      await b.joinWithCode(code);
      final amy = b.currentUser!.uid;
      await as('mina');
      expect(
        () => b.leaveClassroom(room),
        throwsA(
          isA<BackendFailure>().having(
            (e) => e.message,
            'message',
            contains('co-master'),
          ),
        ),
      );
      await b.setCoMaster(room, amy, true);
      await b.leaveClassroom(room);
      await as('amy');
      final c = (await b.watchClassroom(room).first).classroom;
      expect(c.masterUid, amy);
      expect(c.coMasterUids, isEmpty);
      expect(c.memberUids, [amy]);
    });

    test('deleting an account takes care of each classroom first', () async {
      await as('amy');
      await b.joinWithCode(code);
      final amy = b.currentUser!.uid;
      await as('mina');
      final mina = b.currentUser!.uid;
      final solo = await b.createClassroom(
        title: 'Mine alone',
        description: '',
        taskType: TaskType.other,
        individual: true,
      );
      // Blocked until the shared classroom has someone to inherit it.
      expect(() => b.deleteAccount(), throwsA(isA<BackendFailure>()));
      expect(b.currentUser?.uid, mina);

      await b.setCoMaster(room, amy, true);
      await b.deleteAccount();
      expect(b.currentUser, isNull);
      expect(
        () => b.signInWithEmail('mina@test.dev', 'secret1'),
        throwsA(isA<BackendFailure>()),
      );

      await as('amy');
      final c = (await b.watchClassroom(room).first).classroom;
      expect(c.masterUid, amy);
      expect(
        (await b.classrooms().first).map((r) => r.id),
        isNot(contains(solo)),
      );
    });

    test('only the master can delete a classroom', () async {
      await as('amy');
      await b.joinWithCode(code);
      expect(() => b.deleteClassroom(room), throwsA(isA<BackendFailure>()));
      await as('mina');
      await b.deleteClassroom(room);
      expect(await b.classrooms().first, isEmpty);
    });
  });

  test('the profile’s numbers add up across classrooms', () {
    final now = DateTime(2026, 11, 5, 12); // A Thursday.
    Classroom room(String id, String master) => Classroom(
      id: id,
      title: id,
      masterUid: master,
      memberUids: const ['me', 'them'],
      inviteCode: 'X',
      createdAt: now,
    );
    ActivityEntry log(
      ActivityKind kind,
      DateTime when, {
      String actor = 'me',
      String affects = '',
    }) => ActivityEntry(
      id: 'i',
      actorUid: actor,
      kind: kind,
      summary: '',
      createdAt: when,
      affectsUid: affects,
    );
    final stats = summariseUser(
      me: 'me',
      now: now,
      rooms: [
        ClassroomState(
          classroom: room('a', 'me'),
          members: const [],
          phases: const [],
          steps: [
            _step('1', 'me').copyWith(status: StepStatus.done),
            _step('2', 'me').copyWith(status: StepStatus.doing),
            _step('3', 'them').copyWith(status: StepStatus.done),
          ],
        ),
        ClassroomState(
          classroom: room('b', 'them'),
          members: const [],
          phases: const [],
          steps: [_step('4', 'me')],
        ),
      ],
      activity: [
        log(ActivityKind.stepFinished, DateTime(2026, 11, 4)),
        // Approved by someone else, but it's still my finished step.
        log(
          ActivityKind.stepApproved,
          DateTime(2026, 11, 2),
          actor: 'them',
          affects: 'me',
        ),
        log(ActivityKind.stepFinished, DateTime(2026, 10, 28)),
        // Someone else's work doesn't count as mine.
        log(ActivityKind.stepFinished, DateTime(2026, 11, 4), actor: 'them'),
        // Older than the chart, so it's left off it.
        log(ActivityKind.stepFinished, DateTime(2026, 1, 5)),
      ],
    );
    expect(stats.classrooms, 2);
    expect(stats.leading, 1);
    expect(stats.stepsTotal, 3);
    expect(stats.stepsDone, 1);
    expect(stats.stepsInProgress, 1);
    expect(stats.hoursDone, 2);
    expect(stats.actionsThisWeek, 1);
    expect(stats.finishedThisWeek, 2);
    expect(stats.finishedLastWeek, 1);
    expect(stats.growth, '+100%');
    expect(stats.finishedPerWeek, hasLength(8));
    expect(stats.weeks.last, DateTime(2026, 11, 2));
  });

  testWidgets('the dashboard searches classrooms, shown as squares', (
    tester,
  ) async {
    await _font(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = LocalBackend();
    await backend.registerWithEmail('Mina', 'm@t.dev', 'secret1');
    for (final title in ['Physics', 'Chemistry']) {
      await backend.createClassroom(
        title: title,
        description: '',
        taskType: TaskType.study,
        individual: false,
      );
    }
    await tester.pumpWidget(OctriaApp(backend: backend));
    await _settle(tester, 60);
    final card = tester.getSize(find.bySemanticsLabel(RegExp('^Physics')));
    expect(card.width, card.height);
    expect(find.text('Chemistry'), findsOneWidget);

    await tester.enterText(
      find.bySemanticsLabel('Search classrooms').last,
      'phys',
    );
    await _settle(tester);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('Chemistry'), findsNothing);

    // Every tab opens cleanly.
    for (final tab in ['Activity', 'Timeline', 'Profile', 'Dashboard']) {
      await tester.tap(find.text(tab).last);
      await _settle(tester, 40);
      expect(tester.takeException(), isNull);
    }
    await tester.pump(const Duration(seconds: 10));
  });

  test('only the master can delete or clear activity', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Mina', 'm@t.dev', 'secret1');
    final room = await b.createClassroom(
      title: 'R',
      description: '',
      taskType: TaskType.build,
      individual: false,
    );
    final code = (await b.watchClassroom(room).first).classroom.inviteCode;
    await b.signOut();
    await b.registerWithEmail('Amy', 'a@t.dev', 'secret1');
    await b.joinWithCode(code);
    final log = await b.activity(room);
    expect(log, hasLength(1));
    expect(
      () => b.deleteActivity(room, log.single.id),
      throwsA(isA<BackendFailure>()),
    );
    expect(() => b.clearActivity(room), throwsA(isA<BackendFailure>()));
    await b.signOut();
    await b.signInWithEmail('m@t.dev', 'secret1');
    await b.deleteActivity(room, log.single.id);
    expect(await b.activity(room), isEmpty);
  });

  test('only safe web links can be stored, and their kind is guessed', () {
    expect(
      webAddress('youtube.com/watch?v=1'),
      'https://youtube.com/watch?v=1',
    );
    expect(webAddress('http://example.org/a'), 'http://example.org/a');
    expect(webAddress('javascript:alert(1)'), isNull);
    expect(webAddress('file:///etc/passwd'), isNull);
    expect(webAddress('not a link'), isNull);
    expect(webAddress('localhost'), isNull);
    expect(MaterialKind.guess('https://youtu.be/x'), MaterialKind.video);
    expect(MaterialKind.guess('github.com/a/b'), MaterialKind.repo);
    expect(MaterialKind.guess('https://notgithub.com/a'), MaterialKind.link);
    expect(MaterialKind.guess('https://docs.flutter.dev'), MaterialKind.link);
  });

  test(
    'comments and suggestions stay between the two people in them',
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
      await b.savePhase(room, const PhaseRecord(id: 'p', title: 'P', order: 0));
      final now = DateTime.now();
      await b.saveStep(
        room,
        PlanStep(
          id: 's1',
          phaseId: 'p',
          ownerId: mina,
          title: 'Mina’s step',
          estimateHours: 1,
          start: now,
          due: now,
        ),
      );
      final code = (await b.watchClassroom(room).first).classroom.inviteCode;
      await b.signOut();
      await b.registerWithEmail('Amy', 'a@t.dev', 'secret1');
      final amy = b.currentUser!.uid;
      await b.joinWithCode(code);
      await b.addComment(
        room,
        's1',
        'Just for you',
        ownerUid: mina,
        withUid: amy,
      );
      await b.addSuggestion(
        room,
        Suggestion(
          id: 'g1',
          stepId: 's1',
          fromUid: amy,
          toUid: mina,
          text: 'Split it in two',
          createdAt: now,
        ),
      );
      // Amy can't answer her own suggestion; only the step's owner can.
      expect(
        () => b.answerSuggestion(room, 'g1', SuggestionStatus.accepted),
        throwsA(isA<BackendFailure>()),
      );
      await b.notify(
        mina,
        Notice(
          classroomId: room,
          entry: ActivityEntry(
            id: '',
            actorUid: amy,
            kind: ActivityKind.commented,
            summary: 'Amy commented',
            createdAt: now,
          ),
        ),
      );
      await b.signOut();

      // Ben is in the classroom but sees neither.
      await b.registerWithEmail('Ben', 'b@t.dev', 'secret1');
      await b.joinWithCode(code);
      expect(await b.comments(room, 's1').first, isEmpty);
      expect(await b.suggestions(room).first, isEmpty);
      expect(await b.inbox(), isEmpty);
      expect(
        () => b.addComment(room, 's1', 'Sneaky', ownerUid: mina, withUid: amy),
        throwsA(isA<BackendFailure>()),
      );
      await b.signOut();

      // Amy shows it to everyone; now Ben can see it, but still not answer it.
      await b.signInWithEmail('a@t.dev', 'secret1');
      await b.setSuggestionPublic(room, 'g1', true);
      await b.signOut();
      await b.signInWithEmail('b@t.dev', 'secret1');
      expect((await b.suggestions(room).first).single.public, isTrue);
      expect(
        () => b.setSuggestionPublic(room, 'g1', false),
        throwsA(isA<BackendFailure>()),
      );
      await b.signOut();

      // Mina, as owner, sees her thread with Amy, answers, and can't answer twice.
      await b.signInWithEmail('m@t.dev', 'secret1');
      expect((await b.comments(room, 's1').first).single.text, 'Just for you');
      expect((await b.inbox()).single.entry.summary, 'Amy commented');
      await b.answerSuggestion(room, 'g1', SuggestionStatus.accepted);
      expect(
        () => b.answerSuggestion(room, 'g1', SuggestionStatus.dismissed),
        throwsA(isA<BackendFailure>()),
      );
      // A comment can only be removed by whoever wrote it, master or not.
      final c = (await b.comments(room, 's1').first).single;
      expect(
        () => b.deleteComment(room, 's1', c.id),
        throwsA(isA<BackendFailure>()),
      );
    },
  );

  test(
    'the class chat takes group suggestions that each person marks done',
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
      await b.sendChat(room, 'Hello');
      await b.sendChat(room, 'Everyone: rename your files', forEveryone: true);
      final chat = await b.chat(room).first;
      expect(chat.map((m) => m.text), ['Hello', 'Everyone: rename your files']);
      expect(
        () => b.setApplied(room, chat.first.id, true),
        throwsA(isA<BackendFailure>()),
      );
      await b.setApplied(room, chat.last.id, true);
      expect((await b.chat(room).first).last.appliedBy, [mina]);
      await b.setApplied(room, chat.last.id, false);
      expect((await b.chat(room).first).last.appliedBy, isEmpty);
    },
  );

  test('only the step’s owner writes its description', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Mina', 'm@t.dev', 'secret1');
    final room = await b.createClassroom(
      title: 'R',
      description: '',
      taskType: TaskType.build,
      individual: false,
    );
    await b.savePhase(room, const PhaseRecord(id: 'p', title: 'P', order: 0));
    final code = (await b.watchClassroom(room).first).classroom.inviteCode;
    await b.signOut();
    await b.registerWithEmail('Amy', 'a@t.dev', 'secret1');
    final amy = b.currentUser!.uid;
    await b.joinWithCode(code);
    final now = DateTime.now();
    final step = PlanStep(
      id: 's1',
      phaseId: 'p',
      ownerId: amy,
      title: 'Amy’s step',
      estimateHours: 1,
      start: now,
      due: now,
    );
    await b.saveStep(room, step.copyWith(description: 'My plan'));
    await b.signOut();
    // The master can still change everything else about it.
    await b.signInWithEmail('m@t.dev', 'secret1');
    expect(
      () => b.saveStep(room, step.copyWith(description: 'Master says')),
      throwsA(isA<BackendFailure>()),
    );
    await b.saveStep(
      room,
      step.copyWith(description: 'My plan', title: 'Renamed'),
    );
  });

  test('the demo opens as Mina, with Amy'
      's notes waiting for her', () async {
    final b = await demoBackend();
    expect(b.currentUser?.name, 'Mina');
    final room = (await b.classrooms().first).single;
    expect(
      (await b.suggestions(room.id).first).single.text,
      contains('forgot'),
    );
    expect(await b.comments(room.id, 'design').first, hasLength(2));
    expect(await b.chat(room.id).first, hasLength(3));
    final o = await loadOverview(b);
    expect(o.unreadNotices, 3);
  });
  test(
    'private chats, handovers and materials stay with the right people',
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
      await b.savePhase(room, const PhaseRecord(id: 'p', title: 'P', order: 0));
      final code = (await b.watchClassroom(room).first).classroom.inviteCode;
      await b.signOut();
      await b.registerWithEmail('Amy', 'a@t.dev', 'secret1');
      final amy = b.currentUser!.uid;
      await b.joinWithCode(code);
      await b.signOut();
      await b.registerWithEmail('Ben', 'b@t.dev', 'secret1');
      final ben = b.currentUser!.uid;
      await b.joinWithCode(code);
      final now = DateTime.now();
      final step = PlanStep(
        id: 's1',
        phaseId: 'p',
        ownerId: ben,
        title: 'Ben’s step',
        estimateHours: 1,
        start: now,
        due: now,
      );
      await b.saveStep(room, step);
      await b.saveMaterial(
        room,
        StudyMaterial(
          id: 'm1',
          kind: MaterialKind.link,
          title: 'Mine',
          url: 'https://example.org',
          ownerUid: ben,
          stepId: 's1',
          createdAt: now,
        ),
      );
      // Ben can't simply give his step away.
      expect(
        () => b.saveStep(room, step.copyWith(ownerId: amy)),
        throwsA(isA<BackendFailure>()),
      );
      await b.requestHandover(room, 's1', amy, 'Going away');
      // A private chat between Ben and Mina, the same one whoever opens it.
      final dm = await b.openThread(room, [mina]);
      await b.sendThreadMessage(room, dm, 'Can I hand my step to Amy?');
      // A group chat with both, which reopens rather than starting again.
      final group = await b.openThread(room, [mina, amy]);
      expect(await b.openThread(room, [amy, mina]), group);
      await b.signOut();

      // Amy can't take it on until the master agrees, and can't see Ben's
      // materials, his chat with Mina, or add materials to his step.
      await b.signInWithEmail('a@t.dev', 'secret1');
      expect(
        () => b.answerHandover(room, 's1', true),
        throwsA(isA<BackendFailure>()),
      );
      expect(await b.materials(room).first, isEmpty);
      final amysChats = await b.threads(room).first;
      expect(amysChats.single.participants, hasLength(3));
      expect(
        () => b.threadMessages(room, dm).first,
        throwsA(isA<BackendFailure>()),
      );
      expect(
        () => b.saveMaterial(
          room,
          StudyMaterial(
            id: 'm2',
            kind: MaterialKind.link,
            title: 'Not mine',
            url: 'https://example.org',
            ownerUid: amy,
            stepId: 's1',
            createdAt: now,
          ),
        ),
        throwsA(isA<BackendFailure>()),
      );
      await b.signOut();

      // The master sees the chat Ben started with her, agrees to the handover,
      // and still can't see Ben's materials.
      await b.signInWithEmail('m@t.dev', 'secret1');
      expect(await b.openThread(room, [ben]), dm);
      final chat = (await b.threads(room).first).firstWhere((t) => t.id == dm);
      expect(chat.unreadFor(mina), isTrue);
      expect(
        (await b.threadMessages(room, dm).first).single.text,
        contains('Amy'),
      );
      expect(await b.materials(room).first, isEmpty);
      await b.reviewHandover(room, 's1', true);
      await b.signOut();

      // Now Amy decides, and the step becomes hers.
      await b.signInWithEmail('a@t.dev', 'secret1');
      await b.answerHandover(room, 's1', true);
      final state = await b.watchClassroom(room).first;
      expect(state.steps.single.ownerId, amy);
      expect(
        (await b.handovers(room).first).single.status,
        HandoverStatus.accepted,
      );
    },
  );

  test('a master’s own handover goes straight to the person', () async {
    final b = LocalBackend();
    await b.registerWithEmail('Mina', 'm@t.dev', 'secret1');
    final mina = b.currentUser!.uid;
    final room = await b.createClassroom(
      title: 'R',
      description: '',
      taskType: TaskType.build,
      individual: false,
    );
    await b.savePhase(room, const PhaseRecord(id: 'p', title: 'P', order: 0));
    final now = DateTime.now();
    await b.saveStep(
      room,
      PlanStep(
        id: 's1',
        phaseId: 'p',
        ownerId: mina,
        title: 'Mina’s step',
        estimateHours: 1,
        start: now,
        due: now,
      ),
    );
    final code = (await b.watchClassroom(room).first).classroom.inviteCode;
    await b.signOut();
    await b.registerWithEmail('Amy', 'a@t.dev', 'secret1');
    final amy = b.currentUser!.uid;
    await b.joinWithCode(code);
    await b.signOut();
    await b.signInWithEmail('m@t.dev', 'secret1');
    await b.requestHandover(room, 's1', amy, '');
    expect(
      (await b.handovers(room).first).single.status,
      HandoverStatus.needsReceiver,
    );
    await b.signOut();
    await b.signInWithEmail('a@t.dev', 'secret1');
    await b.answerHandover(room, 's1', false);
    expect((await b.watchClassroom(room).first).steps.single.ownerId, mina);
  });

  test(
    'offers wait to be accepted; handovers are listed for everyone',
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
      await b.savePhase(room, const PhaseRecord(id: 'p', title: 'P', order: 0));
      final now = DateTime.now();
      await b.saveStep(
        room,
        PlanStep(
          id: 's1',
          phaseId: 'p',
          ownerId: mina,
          title: 'Mina’s step',
          estimateHours: 1,
          start: now,
          due: now,
        ),
      );
      final code = (await b.watchClassroom(room).first).classroom.inviteCode;
      await b.signOut();
      await b.registerWithEmail('Amy', 'a@t.dev', 'secret1');
      final amy = b.currentUser!.uid;
      await b.joinWithCode(code);
      final board = await b.createBoard(title: 'Colours');
      await b.makeOffer(
        room,
        Offer(
          id: 'o1',
          kind: OfferKind.board,
          fromUid: amy,
          toUid: mina,
          createdAt: now,
          title: 'Colours',
          boardId: board.id,
        ),
      );
      await b.makeOffer(
        room,
        Offer(
          id: 'o2',
          kind: OfferKind.material,
          fromUid: amy,
          toUid: mina,
          createdAt: now,
          stepId: 's1',
          title: 'Guide',
          url: 'https://example.org/guide',
        ),
      );
      expect(
        (await b.offers(room).first).map((o) => o.statusLabel),
        everyElement('Request pending'),
      );
      await b.signOut();

      // Ben sees neither offer.
      await b.registerWithEmail('Ben', 'b@t.dev', 'secret1');
      await b.joinWithCode(code);
      expect(await b.offers(room).first, isEmpty);
      await b.signOut();

      await b.signInWithEmail('m@t.dev', 'secret1');
      final offers = await b.offers(room).first;
      final material = offers.firstWhere((o) => o.id == 'o2');
      final boardOffer = offers.firstWhere((o) => o.id == 'o1');
      await b.answerOffer(room, material, true);
      expect((await b.materials(room).first).single.title, 'Guide');
      await b.answerOffer(room, boardOffer, false);
      expect(await b.watchBoard(amy, board.id).first, isNull);
      expect(
        () => b.answerOffer(room, material, false),
        throwsA(isA<BackendFailure>()),
      );
      // A handover is listed for everyone in the classroom.
      await b.requestHandover(room, 's1', amy, 'Busy');
      await b.signOut();
      await b.signInWithEmail('b@t.dev', 'secret1');
      final seen = (await b.handovers(room).first).single;
      expect(handoverLabel(seen.status), 'Acceptance pending');
      expect(seen.note, isEmpty);
    },
  );

  test('hours read naturally for the activity groups', () {
    expect(hourLabel(0), '12 am');
    expect(hourLabel(9), '9 am');
    expect(hourLabel(12), '12 pm');
    expect(hourLabel(21), '9 pm');
  });

  test('activity shows the exact moment, in 12-hour time', () {
    expect(
      exactTime(DateTime(2026, 11, 5, 21, 21, 5)),
      'Thu 5 Nov, 9:21:05 pm',
    );
    expect(exactTime(DateTime(2026, 11, 5, 0, 7, 9)), 'Thu 5 Nov, 12:07:09 am');
    expect(exactTime(DateTime(2026, 11, 5, 12)), 'Thu 5 Nov, 12:00:00 pm');
  });

  test('each status has its own light, in both themes', () {
    for (final p in [Palette.light, Palette.dark]) {
      final lit = [
        Standing.doing,
        Standing.review,
        Standing.done,
        Standing.blocked,
      ].map(p.standing).toSet();
      expect(lit, hasLength(4));
      expect(p.standing(Standing.review), p.review);
    }
    expect(standingLabel(Standing.review), 'Waiting for approval');
    expect(Standing.values.map(standingWord).toSet(), hasLength(6));
  });

  group('what gets logged', () {
    String name(String uid) => uid == 'm' ? 'Mina' : 'Amy';
    ActivityEntry? change(PlanStep? before, PlanStep after, String actor) =>
        describeChange(
          before: before,
          after: after,
          actorUid: actor,
          nameOf: name,
          id: 'x',
        );

    test('a master’s edit to someone’s step is flagged for them', () {
      final s = _step('s', 'a');
      final e = change(s, s.copyWith(title: 'Renamed'), 'm')!;
      expect(e.summary, 'Mina edited “Renamed”');
      expect(e.affectsUid, 'a');
    });

    test('a handover says who it went to and tells them', () {
      final s = _step('s', 'a');
      final e = change(s, s.copyWith(ownerId: 'm'), 'a')!;
      expect(e.kind, ActivityKind.stepHandedOver);
      expect(e.summary, 'Amy handed “Step s” to Mina');
      expect(e.affectsUid, 'm');
    });

    test('approval reads as approval, and being sent back as that', () {
      final s = _step('s', 'a').copyWith(status: StepStatus.review);
      expect(
        change(s, s.copyWith(status: StepStatus.done), 'm')!.kind,
        ActivityKind.stepApproved,
      );
      expect(
        change(s, s.copyWith(status: StepStatus.doing), 'm')!.kind,
        ActivityKind.stepSentBack,
      );
    });

    test('ticking your own checklist isn’t news', () {
      final s = _step('s', 'a');
      final ticked = s.copyWith(
        checklist: const [ChecklistItem(title: 'x', done: true)],
      );
      expect(change(s, ticked, 'a'), isNull);
    });

    test('since you were away: only what touches you, not your own', () {
      final mine = _step('mine', 'me').copyWith(dependsOn: ['dep']);
      ActivityEntry e(
        String actor,
        ActivityKind kind,
        String target,
        String affects,
      ) => ActivityEntry(
        id: 'i',
        actorUid: actor,
        kind: kind,
        summary: '',
        targetId: target,
        affectsUid: affects,
        createdAt: DateTime(2026),
      );
      final news = awayNews(
        [
          e('m', ActivityKind.stepEdited, 'mine', 'me'), // Changed my step.
          e('a', ActivityKind.stepFinished, 'dep', ''), // Unblocked me.
          e('a', ActivityKind.stepFinished, 'other', ''), // Nothing to me.
          e('me', ActivityKind.stepEdited, 'mine', ''), // My own doing.
        ],
        'me',
        [mine],
      );
      expect(news.map((n) => n.targetId), ['mine', 'dep']);
    });
  });

  group('screens', () {
    Future<LocalBackend> open(WidgetTester tester, Size size) async {
      await _font(tester);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = LocalBackend();
      await tester.pumpWidget(OctriaApp(backend: backend));
      await _settle(tester, 4);
      return backend;
    }

    for (final (name, size) in const [
      ('phone', Size(390, 844)),
      ('laptop', Size(1440, 900)),
    ]) {
      testWidgets('$name: sign up, create, add a phase and a step', (
        tester,
      ) async {
        final backend = await open(tester, size);
        expect(find.text('Continue with Google'), findsOneWidget);

        // Register.
        await tester.tap(find.text('Create an account'));
        await _settle(tester, 4);
        await tester.enterText(
          find.bySemanticsLabel('Your name').last,
          'Mina Rao',
        );
        await tester.enterText(find.bySemanticsLabel('Email').last, 'm@t.dev');
        await tester.enterText(
          find.bySemanticsLabel('Password').last,
          'secret1',
        );
        await tester.tap(find.text('Create account'));
        await _settle(tester);
        expect(find.textContaining('Nothing here yet'), findsOneWidget);
        expect(find.text('Join'), findsNothing);
        expect(backend.currentUser?.name, 'Mina Rao');

        // A new classroom opens on its empty state.
        await tester.tap(find.bySemanticsLabel('Add a classroom').first);
        await _settle(tester);
        await tester.tap(find.text('Create a classroom'));
        await _settle(tester);
        await tester.enterText(
          find.bySemanticsLabel('What do you need to finish?').last,
          'Campus app',
        );
        await tester.tap(find.text('Create classroom'));
        await _settle(tester, 60);
        expect(find.textContaining('big stages of the work'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // A phase.
        await tester.tap(find.text('Add phases'));
        await _settle(tester);
        await tester.enterText(
          find.bySemanticsLabel('New phase name').last,
          'Build',
        );
        await tester.tap(find.text('Add phase'));
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel('Close').last);
        await _settle(tester);
        expect(find.textContaining('No steps yet'), findsOneWidget);

        // A step, which reaches the stored classroom.
        await tester.tap(find.text('Add a step'));
        await _settle(tester);
        await tester.enterText(
          find.bySemanticsLabel('What needs doing?').last,
          'Write the brief',
        );
        await tester.tap(find.text('Add step'));
        await _settle(tester, 60);
        expect(find.textContaining('No steps yet'), findsNothing);
        expect(tester.takeException(), isNull);

        final rooms = await backend.classrooms().first;
        final state = await backend.watchClassroom(rooms.single.id).first;
        expect(state.steps.single.title, 'Write the brief');
        expect(state.steps.single.ownerId, backend.currentUser!.uid);
        final log = await backend.activity(rooms.single.id);
        expect(log.first.summary, 'Mina Rao added “Write the brief”');
        await tester.pump(const Duration(seconds: 10));
      });
    }

    testWidgets('constraint description is optional, and saved when written', (
      tester,
    ) async {
      final backend = await open(tester, const Size(1440, 900));
      await backend.registerWithEmail('Mina', 'm@t.dev', 'secret1');
      await _settle(tester);

      Future<void> create(String title, [String? constraints]) async {
        await tester.tap(find.bySemanticsLabel('Add a classroom').first);
        await _settle(tester);
        await tester.tap(find.text('Create a classroom'));
        await _settle(tester);
        await tester.enterText(
          find.bySemanticsLabel('What do you need to finish?').last,
          title,
        );
        if (constraints != null) {
          await tester.enterText(
            find.bySemanticsLabel('Constraint description (optional)').last,
            constraints,
          );
        }
        await tester.tap(find.text('Create classroom'));
        await _settle(tester, 60);
        await tester.tap(find.text('Dashboard').first);
        await _settle(tester, 60);
      }

      await create('Skipped it');
      await create('Physics', 'Study thermodynamics before waves');

      final rooms = await backend.classrooms().first;
      String of(String title) =>
          rooms.firstWhere((r) => r.title == title).constraints;
      expect(of('Skipped it'), isEmpty);
      expect(of('Physics'), 'Study thermodynamics before waves');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('an invite link opens the join form, filled in', (
      tester,
    ) async {
      final backend = await open(tester, const Size(390, 844));
      await backend.registerWithEmail('Mina', 'm@t.dev', 'secret1');
      final room = await backend.createClassroom(
        title: 'Launch',
        description: '',
        taskType: TaskType.build,
        individual: false,
      );
      final code =
          (await backend.watchClassroom(room).first).classroom.inviteCode;
      await backend.signOut();
      await _settle(tester);

      pendingJoinCode = code;
      await backend.registerWithEmail('Amy', 'a@t.dev', 'secret1');
      await _settle(tester);
      expect(find.text('Join a classroom'), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      expect(pendingJoinCode, isNull);

      await tester.tap(find.text('Join').last);
      await _settle(tester, 60);
      expect((await backend.classrooms().first).single.id, room);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a member can’t change someone else’s step', (tester) async {
      final backend = await open(tester, const Size(1440, 900));
      await backend.registerWithEmail('Mina', 'm@t.dev', 'secret1');
      final masterUid = backend.currentUser!.uid;
      final room = await backend.createClassroom(
        title: 'Launch',
        description: '',
        taskType: TaskType.build,
        individual: false,
      );
      await backend.savePhase(
        room,
        const PhaseRecord(id: 'p1', title: 'One', order: 1),
      );
      await backend.saveStep(room, _step('s', masterUid));
      final code =
          (await backend.watchClassroom(room).first).classroom.inviteCode;
      await backend.signOut();
      await backend.registerWithEmail('Amy', 'a@t.dev', 'secret1');
      await backend.joinWithCode(code);
      await _settle(tester);

      await tester.tap(find.text('Launch'));
      await _settle(tester, 60);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await _settle(tester, 80);
      // Opening the step shows it read-only, with no way to change it.
      final map = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter is GraphPainter &&
              !(w.painter as GraphPainter).headers,
        ),
      );
      final scene = (map.painter! as GraphPainter).scene;
      await tester.tapAt(
        scene.camera.toScreen(scene.controller.positions['s']!),
      );
      await _settle(tester);
      expect(scene.controller.plan.steps['s']!.ownerId, masterUid);
      expect(find.text('Step s'), findsWidgets);
      expect(find.textContaining('Mina’s step'), findsOneWidget);
      expect(find.text('Start step'), findsNothing);
      expect(find.text('Mark done'), findsNothing);
      expect(find.text('Delete step'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a first visit starts the count, and the tab is always there', (
      tester,
    ) async {
      var now = DateTime(2026, 11, 4, 9);
      await _font(tester);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = LocalBackend(clock: () => now);
      await backend.registerWithEmail('Mina', 'm@t.dev', 'secret1');
      final room = await backend.createClassroom(
        title: 'Launch',
        description: '',
        taskType: TaskType.build,
        individual: false,
      );
      await tester.pumpWidget(OctriaApp(backend: backend));
      await _settle(tester);
      await tester.tap(find.text('Launch'));
      await _settle(tester, 60);

      // Recorded on arrival, with no back button pressed.
      final state = await backend.watchClassroom(room).first;
      expect(state.members.single.lastSeenAt, now);

      // The menu can always find it, even with nothing to report.
      await tester.tap(find.text('Since you were away'));
      await _settle(tester);
      expect(find.textContaining('A red number appears'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('changes show as a red count, cleared by opening the tab', (
      tester,
    ) async {
      var now = DateTime(2026, 11, 4, 9);
      await _font(tester);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = LocalBackend(clock: () => now);

      await backend.registerWithEmail('Mina', 'm@t.dev', 'secret1');
      final room = await backend.createClassroom(
        title: 'Launch',
        description: '',
        taskType: TaskType.build,
        individual: false,
      );
      await backend.savePhase(
        room,
        const PhaseRecord(id: 'p1', title: 'One', order: 1),
      );
      final code =
          (await backend.watchClassroom(room).first).classroom.inviteCode;
      await backend.signOut();
      await backend.registerWithEmail('Amy', 'a@t.dev', 'secret1');
      final amy = backend.currentUser!.uid;
      await backend.joinWithCode(code);
      await backend.saveStep(room, _step('s', amy));
      await backend.markSeen(room);
      await backend.signOut();

      // While Amy is away, the master changes Amy's step.
      now = now.add(const Duration(hours: 2));
      await backend.signInWithEmail('m@t.dev', 'secret1');
      await backend.saveStep(room, _step('s', amy).copyWith(title: 'Renamed'));
      await backend.logActivity(
        room,
        ActivityEntry(
          id: 'x',
          actorUid: backend.currentUser!.uid,
          kind: ActivityKind.stepEdited,
          summary: 'Mina edited “Renamed”',
          targetId: 's',
          affectsUid: amy,
          createdAt: now,
        ),
      );
      await backend.signOut();

      now = now.add(const Duration(hours: 2));
      await backend.signInWithEmail('a@t.dev', 'secret1');
      await tester.pumpWidget(OctriaApp(backend: backend));
      await _settle(tester);
      await tester.tap(find.text('Launch'));
      await _settle(tester, 60);
      // No popup, just the count.
      expect(find.text('Mina edited “Renamed”'), findsNothing);
      expect(find.text('1'), findsWidgets);

      await tester.tap(find.text('Since you were away'));
      await _settle(tester);
      expect(find.text('Mina edited “Renamed”'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close').last);
      await _settle(tester);
      expect(find.text('Mina edited “Renamed”'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
