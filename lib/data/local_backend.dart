import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show setEquals;

import '../kanvas/kanvas_model.dart';
import '../model/plan.dart';
import 'backend.dart';
import 'drive.dart';
import 'models.dart';

class _Room {
  _Room(this.classroom);

  Classroom classroom;
  final Map<String, ClassroomMember> members = {};
  final Map<String, PhaseRecord> phases = {};
  final Map<String, PlanStep> steps = {};
  final List<ActivityEntry> activity = [];
  final Map<String, JoinRequest> requests = {};
  final Map<String, StudyMaterial> materials = {};
  final Map<String, LibraryFile> files = {};
  final Map<String, List<StepComment>> comments = {};
  final Map<String, Suggestion> suggestions = {};
  final List<ChatMessage> chat = [];
  final Map<String, ChatThread> threads = {};
  final Map<String, List<ChatMessage>> threadMessages = {};
  final Map<String, Handover> handovers = {};
  final Map<String, ClassroomBoard> boards = {};
  final Map<String, Offer> offers = {};
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
  final _notificationsSeen = <String, DateTime>{};
  final _inboxes = <String, List<Notice>>{};
  final _boards = <String, KanvasBoard>{};
  final _versions = <String, List<KanvasVersion>>{};
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
        before != null &&
        before.ownerId != step.ownerId &&
        !_handoverAccepted(room, step)) {
      throw const BackendFailure(
        'Ask to hand this step over first. The person has to accept it.',
      );
    }
    final ownerBefore = before?.ownerId ?? step.ownerId;
    if (step.description != (before?.description ?? '') && ownerBefore != me) {
      throw const BackendFailure(
        'Only the person whose step it is can write its description.',
      );
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
    room.comments.remove(stepId);
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
    room.members[me] = ClassroomMember(
      uid: me,
      name: m.name,
      lastSeenAt: _now,
      chatSeenAt: m.chatSeenAt,
    );
  }

  // Files -------------------------------------------------------------------

  @override
  final DriveStore drive = MemoryDrive();

  @override
  Stream<List<LibraryFile>> files(String classroomId) => _live(() {
    final me = _me.uid;
    return [
      for (final f in _room(classroomId).files.values)
        if (f.shared || f.ownerUid == me) f,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });

  void _checkFile(LibraryFile f) {
    if (f.name.trim().isEmpty || f.name.length > 300) {
      throw const BackendFailure('That file needs a shorter name.');
    }
    final host = Uri.tryParse(f.url)?.host ?? '';
    if (!f.url.startsWith('https://') ||
        (host != 'drive.google.com' && host != 'docs.google.com')) {
      throw const BackendFailure('Only files in Google Drive can be added.');
    }
  }

  @override
  Future<void> addFile(String classroomId, LibraryFile f) async {
    final room = _room(classroomId);
    _checkFile(f);
    if (room.files.containsKey(f.id)) {
      throw const BackendFailure('That file is already in the library.');
    }
    room.files[f.id] = LibraryFile(
      id: f.id,
      name: f.name.trim(),
      mimeType: f.mimeType,
      size: f.size,
      url: f.url,
      ownerUid: _me.uid,
      createdAt: _now,
      stepId: f.stepId,
      shared: f.shared,
    );
    _changes.add(null);
  }

  @override
  Future<void> updateFile(String classroomId, LibraryFile f) async {
    final room = _room(classroomId);
    final before = room.files[f.id];
    if (before == null) return;
    if (before.ownerUid != _me.uid) {
      throw const BackendFailure('Only the person who added it can change it.');
    }
    room.files[f.id] = before.copyWith(shared: f.shared, stepId: f.stepId);
    _changes.add(null);
  }

  @override
  Future<void> removeFile(String classroomId, String fileId) async {
    final room = _room(classroomId);
    final f = room.files[fileId];
    if (f == null) return;
    if (f.ownerUid != _me.uid && !room.classroom.canManage(_me.uid)) {
      throw const BackendFailure('You can only remove what you added.');
    }
    room.files.remove(fileId);
    _changes.add(null);
  }

  /// Puts a file straight into a library, as its owner, for the demo.
  void seedFile(String classroomId, LibraryFile f) {
    _room(classroomId).files[f.id] = f;
  }

  // Collaboration -----------------------------------------------------------

  @override
  Stream<List<StudyMaterial>> materials(String classroomId) => _live(() {
    final me = _me.uid;
    return [
      for (final m in _room(classroomId).materials.values)
        if (m.kind == MaterialKind.practice || m.ownerUid == me) m,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });

  @override
  Future<void> saveMaterial(String classroomId, StudyMaterial m) async {
    final room = _room(classroomId);
    final before = room.materials[m.id];
    if (before != null && before.ownerUid != _me.uid) {
      throw const BackendFailure('Only the person who added it can change it.');
    }
    if (m.title.length > kMaxTitleLength || m.note.length > kMaxNoteLength) {
      throw const BackendFailure('That’s too long to save.');
    }
    if (m.kind != MaterialKind.note && webAddress(m.url) == null) {
      throw const BackendFailure('That doesn’t look like a web address.');
    }
    if (m.kind != MaterialKind.practice &&
        room.steps[m.stepId]?.ownerId != _me.uid) {
      throw const BackendFailure(
        'Only the person whose step it is can add study materials to it.',
      );
    }
    room.materials[m.id] = StudyMaterial(
      id: m.id,
      kind: m.kind,
      title: m.title,
      url: m.url,
      note: m.note,
      ownerUid: _me.uid,
      stepId: m.stepId,
      createdAt: before?.createdAt ?? _now,
    );
    _changes.add(null);
  }

  @override
  Future<void> deleteMaterial(String classroomId, String materialId) async {
    final room = _room(classroomId);
    final m = room.materials[materialId];
    if (m == null) return;
    if (m.ownerUid != _me.uid && !room.classroom.canManage(_me.uid)) {
      throw const BackendFailure('You can only remove what you added.');
    }
    room.materials.remove(materialId);
    _changes.add(null);
  }

  @override
  Stream<List<StepComment>> comments(String classroomId, String stepId) =>
      _live(() {
        final me = _me.uid;
        return [
          for (final c in _room(classroomId).comments[stepId] ?? const [])
            if (c.participants.contains(me)) c,
        ];
      });

  @override
  Future<void> addComment(
    String classroomId,
    String stepId,
    String text, {
    required String ownerUid,
    required String withUid,
  }) async {
    final room = _room(classroomId);
    final me = _me.uid;
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > kMaxCommentLength) {
      throw const BackendFailure('A comment needs between 1 and 2000 letters.');
    }
    final participants = {ownerUid, withUid}.toList();
    final step = room.steps[stepId];
    if (!participants.contains(me) ||
        (step != null && step.ownerId != ownerUid) ||
        !participants.every(room.classroom.memberUids.contains)) {
      throw const BackendFailure(
        'A comment is between the step’s owner and one other person.',
      );
    }
    (room.comments[stepId] ??= []).add(
      StepComment(
        id: newId(),
        authorUid: me,
        text: trimmed,
        participants: participants,
        createdAt: _now,
      ),
    );
    _changes.add(null);
  }

  @override
  Future<void> deleteComment(
    String classroomId,
    String stepId,
    String commentId,
  ) async {
    final room = _room(classroomId);
    final list = room.comments[stepId];
    final c = list?.where((c) => c.id == commentId).firstOrNull;
    if (c == null) return;
    if (c.authorUid != _me.uid) {
      throw const BackendFailure('You can only remove your own comments.');
    }
    list!.remove(c);
    _changes.add(null);
  }

  @override
  Stream<List<Suggestion>> suggestions(String classroomId) => _live(() {
    final me = _me.uid;
    return [
      for (final s in _room(classroomId).suggestions.values)
        if (s.public || s.involves(me)) s,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });

  @override
  Future<void> addSuggestion(String classroomId, Suggestion s) async {
    final room = _room(classroomId);
    final text = s.text.trim();
    if (text.isEmpty || text.length > kMaxCommentLength) {
      throw const BackendFailure(
        'A suggestion needs between 1 and 2000 letters.',
      );
    }
    if (!room.classroom.memberUids.contains(s.toUid)) {
      throw const BackendFailure('That person isn’t in this classroom.');
    }
    room.suggestions[s.id] = Suggestion(
      id: s.id,
      stepId: s.stepId,
      fromUid: _me.uid,
      toUid: s.toUid,
      text: text,
      public: s.public,
      publicAt: s.public ? _now : null,
      createdAt: _now,
    );
    _changes.add(null);
  }

  @override
  Future<void> answerSuggestion(
    String classroomId,
    String suggestionId,
    SuggestionStatus status,
  ) async {
    final room = _room(classroomId);
    final s = room.suggestions[suggestionId];
    if (s == null) return;
    if (s.toUid != _me.uid) {
      throw const BackendFailure(
        'Only the person it’s for can answer a suggestion.',
      );
    }
    if (status == SuggestionStatus.open || s.status != SuggestionStatus.open) {
      throw const BackendFailure('This suggestion has already been answered.');
    }
    room.suggestions[suggestionId] = s.copyWith(status: status);
    _changes.add(null);
  }

  @override
  Future<void> setSuggestionPublic(
    String classroomId,
    String suggestionId,
    bool public,
  ) async {
    final room = _room(classroomId);
    final s = room.suggestions[suggestionId];
    if (s == null) return;
    if (!s.involves(_me.uid)) {
      throw const BackendFailure(
        'Only the two people in a suggestion can change who sees it.',
      );
    }
    room.suggestions[suggestionId] = s.copyWith(public: public);
    _changes.add(null);
  }

  @override
  Stream<List<ChatMessage>> chat(String classroomId) =>
      _live(() => List.of(_room(classroomId).chat));

  @override
  Future<void> sendChat(
    String classroomId,
    String text, {
    bool forEveryone = false,
  }) async {
    final room = _room(classroomId);
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > kMaxCommentLength) {
      throw const BackendFailure('A message needs between 1 and 2000 letters.');
    }
    room.chat.add(
      ChatMessage(
        id: newId(),
        authorUid: _me.uid,
        text: trimmed,
        forEveryone: forEveryone,
        createdAt: _now,
      ),
    );
    _changes.add(null);
  }

  @override
  Future<void> setApplied(
    String classroomId,
    String messageId,
    bool applied,
  ) async {
    final room = _room(classroomId);
    final i = room.chat.indexWhere((m) => m.id == messageId);
    if (i < 0) return;
    final m = room.chat[i];
    if (!m.forEveryone) {
      throw const BackendFailure('Only a suggestion for everyone can be done.');
    }
    final me = _me.uid;
    final others = m.appliedBy.where((u) => u != me);
    room.chat[i] = ChatMessage(
      id: m.id,
      authorUid: m.authorUid,
      text: m.text,
      forEveryone: true,
      createdAt: m.createdAt,
      appliedBy: [...others, if (applied) me],
    );
    _changes.add(null);
  }

  @override
  Future<void> deleteChat(String classroomId, String messageId) async {
    final room = _room(classroomId);
    final m = room.chat.where((m) => m.id == messageId).firstOrNull;
    if (m == null) return;
    if (m.authorUid != _me.uid && room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('You can only remove your own messages.');
    }
    room.chat.remove(m);
    _changes.add(null);
  }

  @override
  Future<void> markChatSeen(String classroomId) async {
    final room = _room(classroomId);
    final me = _me.uid;
    final m = room.members[me];
    if (m == null) return;
    room.members[me] = ClassroomMember(
      uid: me,
      name: m.name,
      lastSeenAt: m.lastSeenAt,
      chatSeenAt: _now,
    );
    _changes.add(null);
  }

  @override
  Future<void> notify(String uid, Notice notice) async {
    final room = _room(notice.classroomId);
    if (uid == _me.uid || !room.classroom.memberUids.contains(uid)) {
      throw const BackendFailure('That person isn’t in this classroom.');
    }
    (_inboxes[uid] ??= []).insert(
      0,
      Notice(
        classroomId: notice.classroomId,
        entry: ActivityEntry(
          id: newId(),
          actorUid: _me.uid,
          kind: notice.entry.kind,
          summary: notice.entry.summary,
          targetId: notice.entry.targetId,
          affectsUid: uid,
          createdAt: _now,
        ),
      ),
    );
  }

  @override
  Future<List<Notice>> inbox() async => List.of(_inboxes[_me.uid] ?? const []);

  @override
  Future<DateTime?> notificationsSeenAt() async => _notificationsSeen[_me.uid];

  @override
  Future<void> markNotificationsSeen() async {
    _notificationsSeen[_me.uid] = _now;
  }

  bool _handoverAccepted(_Room room, PlanStep step) {
    final h = room.handovers[step.id];
    return h != null &&
        h.status == HandoverStatus.needsReceiver &&
        h.toUid == _me.uid &&
        step.ownerId == _me.uid;
  }

  // Private chats -----------------------------------------------------------

  @override
  Stream<List<ChatThread>> threads(String classroomId) => _live(() {
    final me = _me.uid;
    return [
      for (final t in _room(classroomId).threads.values)
        if (t.participants.contains(me)) t,
    ]..sort(
      (a, b) =>
          (b.lastAt ?? DateTime(2000)).compareTo(a.lastAt ?? DateTime(2000)),
    );
  });

  @override
  Future<String> openThread(
    String classroomId,
    List<String> participants,
  ) async {
    final room = _room(classroomId);
    final people = {_me.uid, ...participants}.toList()..sort();
    if (people.length < 2 ||
        !people.every(room.classroom.memberUids.contains)) {
      throw const BackendFailure('Pick people in this classroom to chat with.');
    }
    // The same people always share one chat, so its history stays.
    final same = room.threads.values
        .where((t) => setEquals(t.participants.toSet(), people.toSet()))
        .firstOrNull;
    final id =
        same?.id ??
        (people.length == 2
            ? ChatThread.directId(people[0], people[1])
            : newId());
    room.threads[id] ??= ChatThread(id: id, participants: people);
    _changes.add(null);
    return id;
  }

  ChatThread _thread(_Room room, String id) {
    final t = room.threads[id];
    if (t == null || !t.participants.contains(_me.uid)) {
      throw const BackendFailure('That chat isn’t yours to read.');
    }
    return t;
  }

  @override
  Stream<List<ChatMessage>> threadMessages(
    String classroomId,
    String threadId,
  ) => _live(() {
    final room = _room(classroomId);
    _thread(room, threadId);
    return List.of(room.threadMessages[threadId] ?? const []);
  });

  @override
  Future<void> sendThreadMessage(
    String classroomId,
    String threadId,
    String text,
  ) async {
    final room = _room(classroomId);
    final t = _thread(room, threadId);
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > kMaxCommentLength) {
      throw const BackendFailure('A message needs between 1 and 2000 letters.');
    }
    final me = _me.uid;
    (room.threadMessages[threadId] ??= []).add(
      ChatMessage(id: newId(), authorUid: me, text: trimmed, createdAt: _now),
    );
    room.threads[threadId] = ChatThread(
      id: t.id,
      participants: t.participants,
      lastAt: _now,
      lastText: trimmed,
      lastBy: me,
      readAt: {...t.readAt, me: _now},
    );
    _changes.add(null);
  }

  @override
  Future<void> markThreadRead(String classroomId, String threadId) async {
    final room = _room(classroomId);
    final t = _thread(room, threadId);
    room.threads[threadId] = ChatThread(
      id: t.id,
      participants: t.participants,
      lastAt: t.lastAt,
      lastText: t.lastText,
      lastBy: t.lastBy,
      readAt: {...t.readAt, _me.uid: _now},
    );
    _changes.add(null);
  }

  // Handovers ---------------------------------------------------------------

  @override
  Stream<List<Handover>> handovers(String classroomId) => _live(() {
    return _room(classroomId).handovers.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });

  @override
  Future<void> requestHandover(
    String classroomId,
    String stepId,
    String toUid,
    String note,
  ) async {
    final room = _room(classroomId);
    final me = _me.uid;
    final step = room.steps[stepId];
    if (step == null || step.ownerId != me) {
      throw const BackendFailure('You can only hand over your own steps.');
    }
    if (toUid == me || !room.classroom.memberUids.contains(toUid)) {
      throw const BackendFailure('Pick someone else in this classroom.');
    }
    room.handovers[stepId] = Handover(
      stepId: stepId,
      fromUid: me,
      toUid: toUid,
      status: room.classroom.canManage(me)
          ? HandoverStatus.needsReceiver
          : HandoverStatus.needsMaster,
      createdAt: _now,
    );
    _changes.add(null);
  }

  @override
  Future<void> reviewHandover(
    String classroomId,
    String stepId,
    bool approve,
  ) async {
    final room = _room(classroomId);
    _requireManager(room);
    final h = room.handovers[stepId];
    if (h == null || h.status != HandoverStatus.needsMaster) {
      throw const BackendFailure('That request isn’t waiting for you.');
    }
    room.handovers[stepId] = Handover(
      stepId: stepId,
      fromUid: h.fromUid,
      toUid: h.toUid,
      note: h.note,
      status: approve ? HandoverStatus.needsReceiver : HandoverStatus.declined,
      createdAt: h.createdAt,
    );
    _changes.add(null);
  }

  @override
  Future<void> answerHandover(
    String classroomId,
    String stepId,
    bool accept,
  ) async {
    final room = _room(classroomId);
    final h = room.handovers[stepId];
    if (h == null ||
        h.status != HandoverStatus.needsReceiver ||
        h.toUid != _me.uid) {
      throw const BackendFailure('That request isn’t waiting for you.');
    }
    final step = room.steps[stepId];
    if (accept && step != null) {
      room.steps[stepId] = step.copyWith(ownerId: _me.uid);
    }
    room.handovers[stepId] = Handover(
      stepId: stepId,
      fromUid: h.fromUid,
      toUid: h.toUid,
      note: h.note,
      status: accept ? HandoverStatus.accepted : HandoverStatus.declined,
      createdAt: h.createdAt,
    );
    _changes.add(null);
  }

  @override
  Future<void> cancelHandover(String classroomId, String stepId) async {
    final room = _room(classroomId);
    final h = room.handovers[stepId];
    if (h == null) return;
    if (h.fromUid != _me.uid && room.classroom.masterUid != _me.uid) {
      throw const BackendFailure('Only the person who asked can withdraw it.');
    }
    room.handovers.remove(stepId);
    _changes.add(null);
  }

  // Kanvas ------------------------------------------------------------------

  bool _canSee(KanvasBoard b, String me) =>
      b.ownerUid == me ||
      b.people.containsKey(me) ||
      (b.classroomId.isNotEmpty &&
          (_rooms[b.classroomId]?.classroom.memberUids.contains(me) ?? false));

  bool _canChange(KanvasBoard b, String me) =>
      b.ownerUid == me ||
      b.people[me] == ShareMode.edit ||
      (b.classroomMode == ShareMode.edit &&
          b.classroomId.isNotEmpty &&
          (_rooms[b.classroomId]?.classroom.memberUids.contains(me) ?? false));

  KanvasBoard _board(String ownerUid, String id) {
    final b = _boards[id];
    if (b == null || b.ownerUid != ownerUid || !_canSee(b, _me.uid)) {
      throw const BackendFailure('That board isn’t shared with you.');
    }
    return b;
  }

  KanvasBoard _stamped(KanvasBoard b, {List<KShape>? shapes}) => KanvasBoard(
    id: b.id,
    ownerUid: b.ownerUid,
    title: b.title,
    folder: b.folder,
    shapes: shapes ?? b.shapes,
    updatedAt: _now,
    updatedBy: _me.uid,
    classroomId: b.classroomId,
    classroomMode: b.classroomMode,
    people: b.people,
  );

  List<KanvasBoard> _latest(Iterable<KanvasBoard> boards) => boards.toList()
    ..sort(
      (a, b) => (b.updatedAt ?? DateTime(2000)).compareTo(
        a.updatedAt ?? DateTime(2000),
      ),
    );

  @override
  Stream<List<KanvasBoard>> myBoards() =>
      _live(() => _latest(_boards.values.where((b) => b.ownerUid == _me.uid)));

  @override
  Stream<List<KanvasBoard>> boardsSharedWithMe() => _live(
    () => _latest(
      _boards.values.where(
        (b) => b.ownerUid != _me.uid && b.people.containsKey(_me.uid),
      ),
    ),
  );

  @override
  Stream<KanvasBoard?> watchBoard(String ownerUid, String boardId) => _live(() {
    final b = _boards[boardId];
    if (b == null || b.ownerUid != ownerUid || !_canSee(b, _me.uid)) {
      return null;
    }
    return b;
  });

  @override
  Future<KanvasBoard> createBoard({
    required String title,
    String folder = '',
    List<KShape> shapes = const [],
  }) async {
    final b = KanvasBoard(
      id: newId(),
      ownerUid: _me.uid,
      title: title.trim().isEmpty ? 'Untitled' : title.trim(),
      folder: folder.trim(),
      shapes: shapes,
      updatedAt: _now,
      updatedBy: _me.uid,
    );
    _boards[b.id] = b;
    _changes.add(null);
    return b;
  }

  @override
  Future<void> saveBoardShapes(
    String ownerUid,
    String boardId,
    List<KShape> shapes,
  ) async {
    final b = _board(ownerUid, boardId);
    if (!_canChange(b, _me.uid)) {
      throw const BackendFailure('This board is shared with you to read only.');
    }
    if (encodeShapes(shapes).length > kMaxBoardBytes) {
      throw const BackendFailure(
        'This board is full. Start a new board, or remove some drawings.',
      );
    }
    _boards[boardId] = _stamped(b, shapes: shapes);
    _changes.add(null);
  }

  KanvasBoard _mine(String boardId) {
    final b = _boards[boardId];
    if (b == null || b.ownerUid != _me.uid) {
      throw const BackendFailure('Only the board’s owner can do that.');
    }
    return b;
  }

  @override
  Future<void> updateBoardInfo(
    String boardId, {
    String? title,
    String? folder,
  }) async {
    final b = _mine(boardId);
    _boards[boardId] = b.copyWith(
      title: title == null
          ? null
          : (title.trim().isEmpty ? 'Untitled' : title.trim()),
      folder: folder?.trim(),
    );
    _changes.add(null);
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    final b = _mine(boardId);
    _boards.remove(boardId);
    _versions.remove(boardId);
    _rooms[b.classroomId]?.boards.remove(boardId);
    _changes.add(null);
  }

  @override
  Future<void> shareBoard(
    String boardId, {
    required Map<String, ShareMode> people,
    required String classroomId,
    required ShareMode classroomMode,
  }) async {
    final b = _mine(boardId);
    if (b.classroomId.isNotEmpty && b.classroomId != classroomId) {
      _rooms[b.classroomId]?.boards.remove(boardId);
    }
    if (classroomId.isNotEmpty) {
      final room = _room(classroomId);
      room.boards[boardId] ??= ClassroomBoard(
        boardId: boardId,
        ownerUid: b.ownerUid,
        title: b.title,
      );
    }
    _boards[boardId] = b.copyWith(
      people: people,
      classroomId: classroomId,
      classroomMode: classroomMode,
    );
    _changes.add(null);
  }

  final _previews = <String, Uint8List>{};

  /// The most a board picture may take up, matching the rules.
  static const maxPreviewBytes = 200 * 1024;

  @override
  Future<void> saveBoardPreview(
    String ownerUid,
    String boardId,
    String fileId,
    Uint8List jpeg,
  ) async {
    final b = _board(ownerUid, boardId);
    if (!_canChange(b, _me.uid)) {
      throw const BackendFailure('This board is shared with you to read only.');
    }
    if (jpeg.length > maxPreviewBytes) {
      throw const BackendFailure('That picture is too big to keep.');
    }
    _previews['$boardId/$fileId'] = jpeg;
  }

  @override
  Future<Uint8List?> boardPreview(
    String ownerUid,
    String boardId,
    String fileId,
  ) async {
    _board(ownerUid, boardId);
    return _previews['$boardId/$fileId'];
  }

  @override
  Future<List<KanvasVersion>> boardVersions(
    String ownerUid,
    String boardId,
  ) async {
    _board(ownerUid, boardId);
    return List.of(_versions[boardId] ?? const []);
  }

  @override
  Future<void> saveBoardVersion(
    String ownerUid,
    String boardId,
    List<KShape> shapes,
  ) async {
    final b = _board(ownerUid, boardId);
    if (!_canChange(b, _me.uid)) {
      throw const BackendFailure('This board is shared with you to read only.');
    }
    (_versions[boardId] ??= []).insert(
      0,
      KanvasVersion(
        id: newId(),
        shapes: shapes,
        savedAt: _now,
        savedBy: _me.uid,
      ),
    );
  }

  @override
  Stream<List<ClassroomBoard>> classroomBoards(String classroomId) =>
      _live(() => _room(classroomId).boards.values.toList());

  @override
  Future<void> pinBoard(
    String classroomId,
    String boardId,
    String stepId,
  ) async {
    final b = _mine(boardId);
    final room = _room(classroomId);
    if (b.classroomId.isNotEmpty && b.classroomId != classroomId) {
      throw const BackendFailure(
        'This board is shared with another classroom. Stop sharing it there '
        'first.',
      );
    }
    room.boards[boardId] = ClassroomBoard(
      boardId: boardId,
      ownerUid: b.ownerUid,
      title: b.title,
      stepId: stepId,
    );
    _boards[boardId] = b.copyWith(classroomId: classroomId);
    _changes.add(null);
  }

  @override
  Future<void> unpinBoard(String classroomId, String boardId) async {
    final b = _mine(boardId);
    _room(classroomId).boards.remove(boardId);
    _boards[boardId] = b.copyWith(classroomId: '');
    _changes.add(null);
  }

  // Offers ------------------------------------------------------------------

  @override
  Stream<List<Offer>> offers(String classroomId) => _live(() {
    final me = _me.uid;
    return [
      for (final o in _room(classroomId).offers.values)
        if (o.fromUid == me || o.toUid == me) o,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });

  @override
  Future<void> makeOffer(String classroomId, Offer o) async {
    final room = _room(classroomId);
    final me = _me.uid;
    if (o.toUid == me || !room.classroom.memberUids.contains(o.toUid)) {
      throw const BackendFailure('Pick someone else in this classroom.');
    }
    if (o.kind == OfferKind.board) {
      final b = _mine(o.boardId);
      _boards[o.boardId] = b.copyWith(
        people: {
          ...b.people,
          o.toUid: o.edit ? ShareMode.edit : ShareMode.view,
        },
      );
    }
    if (o.kind == OfferKind.material &&
        o.materialKind != MaterialKind.note &&
        webAddress(o.url) == null) {
      throw const BackendFailure('That doesn’t look like a web address.');
    }
    room.offers[o.id] = Offer(
      id: o.id,
      kind: o.kind,
      fromUid: me,
      toUid: o.toUid,
      createdAt: _now,
      stepId: o.stepId,
      title: o.title,
      boardOwner: o.kind == OfferKind.board ? me : '',
      boardId: o.boardId,
      edit: o.edit,
      materialKind: o.materialKind,
      url: o.url,
      note: o.note,
    );
    _changes.add(null);
  }

  @override
  Future<void> answerOffer(String classroomId, Offer o, bool accept) async {
    final room = _room(classroomId);
    final stored = room.offers[o.id];
    if (stored == null ||
        stored.toUid != _me.uid ||
        stored.status != OfferStatus.pending) {
      throw const BackendFailure('That isn’t waiting for you.');
    }
    room.offers[o.id] = Offer(
      id: stored.id,
      kind: stored.kind,
      fromUid: stored.fromUid,
      toUid: stored.toUid,
      createdAt: stored.createdAt,
      status: accept ? OfferStatus.accepted : OfferStatus.declined,
      stepId: stored.stepId,
      title: stored.title,
      boardOwner: stored.boardOwner,
      boardId: stored.boardId,
      edit: stored.edit,
      materialKind: stored.materialKind,
      url: stored.url,
      note: stored.note,
    );
    if (stored.kind == OfferKind.board && !accept) {
      await leaveBoard(stored.boardOwner, stored.boardId);
    }
    if (stored.kind == OfferKind.material && accept) {
      await saveMaterial(
        classroomId,
        StudyMaterial(
          id: newId(),
          kind: stored.materialKind,
          title: stored.title,
          url: stored.url,
          note: stored.note,
          ownerUid: _me.uid,
          stepId: stored.stepId,
          createdAt: _now,
        ),
      );
    }
    _changes.add(null);
  }

  @override
  Future<void> leaveBoard(String ownerUid, String boardId) async {
    final b = _boards[boardId];
    if (b == null || b.ownerUid != ownerUid) return;
    _boards[boardId] = b.copyWith(people: {...b.people}..remove(_me.uid));
    _changes.add(null);
  }
}
