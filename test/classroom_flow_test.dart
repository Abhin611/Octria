import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/data/local_backend.dart';
import 'package:octria/data/models.dart';
import 'package:octria/data/backend.dart';
import 'package:octria/data/plan_sync.dart';
import 'package:octria/data/user_stats.dart';
import 'package:octria/graph/graph_painter.dart';
import 'package:octria/main.dart';
import 'package:octria/model/plan.dart';
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
