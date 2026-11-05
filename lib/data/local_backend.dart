import 'dart:async';
import 'dart:math' as math;

import '../model/plan.dart';
import 'backend.dart';
import 'models.dart';

class _Room {
  _Room(this.classroom);

  Classroom classroom;
  final Map<String, ClassroomMember> members = {};
  final Map<String, PhaseRecord> phases = {};
  final Map<String, PlanStep> steps = {};
  final List<ActivityEntry> activity = [];
  final Map<String, JoinRequest> requests = {};
}

class _Account {
  _Account(this.user, this.password);
  AppUser user;
  final String password;
}

/// An in-memory backend for tests and running without a Firebase project. It
/// refuses what `firestore.rules` refuses, so screens see the same failures.
class LocalBackend implements Backend {
  LocalBackend({this.clock});

  /// Lets tests move time along.
  final DateTime Function()? clock;
  DateTime get _now => clock?.call() ?? DateTime.now();

  final _accounts = <String, _Account>{};
  final _rooms = <String, _Room>{};
  final _userChanges = StreamController<AppUser?>.broadcast();
  final _changes = StreamController<void>.broadcast();
  final _random = math.Random(7);
  AppUser? _current;
  var _nextId = 0;

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> get user async* {
    yield _current;
    yield* _userChanges.stream;
  }

  AppUser get _me {
    final me = _current;
    if (me == null) throw const BackendFailure('Please sign in first.');
    return me;
  }

  void _setUser(AppUser? user) {
    _current = user;
    _userChanges.add(user);
    _changes.add(null);
  }

  @override
  String newId() => 'local${_nextId++}';

  @override
  Future<void> signInWithEmail(String email, String password) async {
    final account = _accounts[email.trim().toLowerCase()];
    if (account == null || account.password != password) {
      throw const BackendFailure('That email or password isn’t right.');
    }
    _setUser(account.user);
  }

  @override
  Future<void> registerWithEmail(
    String name,
    String email,
    String password,
  ) async {
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw const BackendFailure('That email already has an account.');
    }
    if (password.length < 6) {
      throw const BackendFailure('Use a password of at least 6 characters.');
    }
    final user = AppUser(uid: newId(), name: name.trim(), email: key);
    _accounts[key] = _Account(user, password);
    _setUser(user);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signInWithGoogle() =>
      throw const BackendFailure('Google sign-in needs a Firebase project.');

  @override
  Future<void> signInWithGitHub() =>
      throw const BackendFailure('GitHub sign-in needs a Firebase project.');

  @override
  Future<void> signOut() async => _setUser(null);

  @override
  Future<void> saveProfile({required String name, required String bio}) async {
    final next = _me.copyWith(name: name.trim(), bio: bio.trim());
    _accounts[next.email]?.user = next;
    for (final room in _rooms.values) {
      final m = room.members[next.uid];
      if (m != null) {
        room.members[next.uid] = ClassroomMember(
          uid: m.uid,
          name: next.name,
          lastSeenAt: m.lastSeenAt,
        );
      }
    }
    _setUser(next);
  }

  @override
  Stream<List<Classroom>> classrooms() {
    List<Classroom> mine() {
      final me = _current;
      if (me == null) return const [];
      return _rooms.values
          .map((r) => r.classroom)
          .where((c) => c.memberUids.contains(me.uid))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return _live(mine);
  }

  @override
  Future<String> createClassroom({
    required String title,
    required String description,
    String constraints = '',
    required TaskType taskType,
    required bool individual,
    DateTime? deadline,
    double? hoursPerWeek,
  }) async {
    final me = _me;
    final id = newId();
    final room = _Room(
      Classroom(
        id: id,
        title: title.trim(),
        description: description.trim(),
        constraints: constraints.trim(),
        taskType: taskType,
        individual: individual,
        masterUid: me.uid,
        memberUids: [me.uid],
        deadline: deadline,
        hoursPerWeek: hoursPerWeek,
        inviteCode: newInviteCode(_random),
        createdAt: _now,
      ),
    );
    room.members[me.uid] = ClassroomMember(uid: me.uid, name: me.name);
    _rooms[id] = room;
    _changes.add(null);
    return id;
  }

  @override
  Future<String?> joinWithCode(String code) async {
    final me = _me;
    final wanted = code.trim().toUpperCase();
    _Room? room;
    for (final r in _rooms.values) {
      if (r.classroom.inviteCode == wanted) room = r;
    }
    if (room == null || room.classroom.individual) {
      throw const BackendFailure('That code doesn’t match a classroom.');
    }
    if (room.classroom.memberUids.contains(me.uid)) return room.classroom.id;
    if (room.classroom.memberUids.length >= kMaxMembers) {
      throw const BackendFailure(
        'This classroom is full. It already has $kMaxMembers members.',
      );
    }
    if (room.classroom.joinApprovalRequired) {
      room.requests[me.uid] = JoinRequest(uid: me.uid, name: me.name);
      _changes.add(null);
      return null;
    }
    room.classroom = room.classroom.copyWith(
      memberUids: [...room.classroom.memberUids, me.uid],
    );
    room.members[me.uid] = ClassroomMember(uid: me.uid, name: me.name);
    room.activity.insert(
      0,
      ActivityEntry(
        id: newId(),
        actorUid: me.uid,
        kind: ActivityKind.memberJoined,
        summary: '${me.name} joined the classroom',
        createdAt: _now,
      ),
    );
    _changes.add(null);
    return room.classroom.id;
  }

  @override
  Stream<List<JoinRequest>> joinRequests(String classroomId) => _live(() {
    final room = _room(classroomId);
    _requireManager(room);
    return room.requests.values.toList();
  });

  @override
  Future<void> approveJoin(String classroomId, JoinRequest request) async {
    final room = _room(classroomId);
    if (room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('Only the master can accept someone.');
    }
    if (room.classroom.memberUids.length >= kMaxMembers) {
      throw const BackendFailure(
        'This classroom is full. It already has $kMaxMembers members.',
      );
    }
    room.requests.remove(request.uid);
    room.classroom = room.classroom.copyWith(
      memberUids: [...room.classroom.memberUids, request.uid],
    );
    room.members[request.uid] = ClassroomMember(
      uid: request.uid,
      name: request.name,
    );
    room.activity.insert(
      0,
      ActivityEntry(
        id: newId(),
        actorUid: _me.uid,
        kind: ActivityKind.memberJoined,
        summary: '${request.name} joined the classroom',
        createdAt: _now,
      ),
    );
    _changes.add(null);
  }

  @override
  Future<void> declineJoin(String classroomId, String uid) async {
    final room = _room(classroomId);
    if (room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('Only the master can decline someone.');
    }
    room.requests.remove(uid);
    _changes.add(null);
  }

  @override
  Future<void> leaveClassroom(String classroomId) async {
    final room = _room(classroomId);
    final me = _me.uid;
    final c = room.classroom;
    var master = c.masterUid;
    var coMasters = c.coMasterUids;
    if (master == me) {
      if (c.memberUids.length == 1) {
        throw const BackendFailure(
          'You’re the only one here. Delete the classroom in Settings instead.',
        );
      }
      if (coMasters.isEmpty) {
        throw const BackendFailure(
          'Make someone co-master first, so the classroom has a master when '
          'you leave.',
        );
      }
      master = coMasters.first;
    }
    room.classroom = Classroom(
      id: c.id,
      title: c.title,
      description: c.description,
      constraints: c.constraints,
      taskType: c.taskType,
      individual: c.individual,
      masterUid: master,
      coMasterUids: coMasters.where((u) => u != me && u != master).toList(),
      memberUids: c.memberUids.where((u) => u != me).toList(),
      deadline: c.deadline,
      hoursPerWeek: c.hoursPerWeek,
      inviteCode: c.inviteCode,
      approvalRequired: c.approvalRequired,
      joinApprovalRequired: c.joinApprovalRequired,
      createdAt: c.createdAt,
    );
    room.members.remove(me);
    _changes.add(null);
  }

  @override
  Future<void> deleteClassroom(String classroomId) async {
    final room = _room(classroomId);
    if (room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('Only the master can delete a classroom.');
    }
    _rooms.remove(classroomId);
    _changes.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    final me = _me;
    final mine = _rooms.values
        .where((r) => r.classroom.memberUids.contains(me.uid))
        .toList();
    final stuck = mine
        .where(
          (r) =>
              r.classroom.masterUid == me.uid &&
              r.classroom.memberUids.length > 1 &&
              r.classroom.coMasterUids.isEmpty,
        )
        .map((r) => '“${r.classroom.title}”');
    if (stuck.isNotEmpty) {
      throw BackendFailure(
        'First make someone co-master in ${stuck.join(', ')}, so it keeps a '
        'master after you’ve gone.',
      );
    }
    for (final room in mine) {
      if (room.classroom.masterUid == me.uid &&
          room.classroom.memberUids.length == 1) {
        await deleteClassroom(room.classroom.id);
      } else {
        await leaveClassroom(room.classroom.id);
      }
    }
    _accounts.remove(me.email);
    _setUser(null);
  }

  _Room _room(String id) {
    final room = _rooms[id];
    if (room == null || !room.classroom.memberUids.contains(_me.uid)) {
      throw const BackendFailure('You aren’t a member of that classroom.');
    }
    return room;
  }

  void _requireManager(_Room room) {
    if (!room.classroom.canManage(_me.uid)) {
      throw const BackendFailure('Only the master or co-master can do that.');
    }
  }

  @override
  Stream<ClassroomState> watchClassroom(String classroomId) {
    ClassroomState state() {
      final room = _room(classroomId);
      return ClassroomState(
        classroom: room.classroom,
        members: room.classroom.memberUids
            .map((uid) => room.members[uid])
            .whereType<ClassroomMember>()
            .toList(),
        phases: room.phases.values.toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
        steps: room.steps.values.toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
      );
    }

    return _live(state);
  }

  Stream<T> _live<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  @override
  Future<void> updateClassroom(Classroom classroom) async {
    final room = _room(classroom.id);
    if (room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('Only the master can change these settings.');
    }
    room.classroom = classroom;
    _changes.add(null);
  }

  @override
  Future<void> setCoMaster(
    String classroomId,
    String uid,
    bool coMaster,
  ) async {
    final room = _room(classroomId);
    if (room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('Only the master can assign a co-master.');
    }
    final others = room.classroom.coMasterUids.where((u) => u != uid);
    room.classroom = room.classroom.copyWith(
      coMasterUids: [...others, if (coMaster) uid],
    );
    _changes.add(null);
  }

  @override
  Future<void> removeMember(String classroomId, String uid) async {
    final room = _room(classroomId);
    if (room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('Only the master can remove a member.');
    }
    if (uid == room.classroom.masterUid) {
      throw const BackendFailure('The master can’t be removed.');
    }
    room.classroom = room.classroom.copyWith(
      memberUids: room.classroom.memberUids.where((u) => u != uid).toList(),
      coMasterUids: room.classroom.coMasterUids.where((u) => u != uid).toList(),
    );
    room.members.remove(uid);
    _changes.add(null);
  }

  @override
  Future<void> savePhase(String classroomId, PhaseRecord phase) async {
    final room = _room(classroomId);
    _requireManager(room);
    room.phases[phase.id] = phase;
    _changes.add(null);
  }

  @override
  Future<void> deletePhase(String classroomId, String phaseId) async {
    final room = _room(classroomId);
    _requireManager(room);
    room.phases.remove(phaseId);
    room.steps.removeWhere((_, s) => s.phaseId == phaseId);
    _changes.add(null);
  }

  @override
  Future<void> saveStep(String classroomId, PlanStep step) async {
    final room = _room(classroomId);
    final me = _me.uid;
    final before = room.steps[step.id];
    final manages = room.classroom.canManage(me);
    final mine = before == null ? step.ownerId == me : before.ownerId == me;
    // Deleting a step clears it from what others' steps need, and nothing more.
    final unlinks =
        before != null &&
        before.dependsOn.toSet().containsAll(step.dependsOn) &&
        before.copyWith(dependsOn: step.dependsOn).storedSameAs(step);
    if (!manages && !mine && !unlinks) {
      throw const BackendFailure('You can only change your own steps.');
    }
    if (!manages &&
        room.classroom.approvalRequired &&
        step.status == StepStatus.done &&
        before?.status != StepStatus.done) {
      throw const BackendFailure(
        'This classroom needs the master’s approval to finish a step.',
      );
    }
    room.steps[step.id] = step;
    _changes.add(null);
  }

  @override
  Future<void> deleteStep(String classroomId, String stepId) async {
    final room = _room(classroomId);
    final step = room.steps[stepId];
    if (step == null) return;
    if (!room.classroom.canManage(_me.uid) && step.ownerId != _me.uid) {
      throw const BackendFailure('You can only delete your own steps.');
    }
    room.steps.remove(stepId);
    _changes.add(null);
  }

  @override
  Future<void> logActivity(String classroomId, ActivityEntry entry) async {
    _room(classroomId).activity.insert(
      0,
      ActivityEntry(
        id: entry.id,
        actorUid: _me.uid,
        kind: entry.kind,
        summary: entry.summary,
        targetId: entry.targetId,
        affectsUid: entry.affectsUid,
        createdAt: _now,
      ),
    );
    _changes.add(null);
  }

  void _requireMaster(_Room room) {
    if (room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('Only the master can do that.');
    }
  }

  @override
  Future<void> deleteActivity(String classroomId, String entryId) async {
    final room = _room(classroomId);
    _requireMaster(room);
    room.activity.removeWhere((e) => e.id == entryId);
    _changes.add(null);
  }

  @override
  Future<void> clearActivity(String classroomId) async {
    final room = _room(classroomId);
    _requireMaster(room);
    room.activity.clear();
    _changes.add(null);
  }

  @override
  Stream<List<ActivityEntry>> activityFeed(
    String classroomId, {
    int limit = 50,
  }) => _live(() => _room(classroomId).activity.take(limit).toList());

  @override
  Future<List<ActivityEntry>> activity(
    String classroomId, {
    DateTime? since,
    int limit = 50,
  }) async =>
      _room(classroomId).activity
          .where((e) => since == null || e.createdAt.isAfter(since))
          .take(limit)
          .toList();

  @override
  Future<void> markSeen(String classroomId) async {
    final room = _room(classroomId);
    final me = _me.uid;
    final m = room.members[me];
    if (m == null) return;
    room.members[me] = ClassroomMember(uid: me, name: m.name, lastSeenAt: _now);
  }
}
