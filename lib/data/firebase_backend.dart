import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../model/plan.dart';
import 'backend.dart';
import 'models.dart';

DateTime? _date(Object? value) => value is Timestamp ? value.toDate() : null;

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

const _estimate = ServerTimestampBehavior.estimate;

/// The real backend: Firebase Auth and Cloud Firestore. Who may do what is
/// enforced by `firestore.rules`; a refusal here surfaces as [BackendFailure].
class FirebaseBackend implements Backend {
  FirebaseBackend({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = firestore ?? FirebaseFirestore.instance {
    // Works offline: reads come from this cache and writes wait in it.
    _db.settings = const Settings(persistenceEnabled: true);
    _auth.authStateChanges().listen(_onAuth);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final _changes = StreamController<AppUser?>.broadcast();
  AppUser? _current;
  var _known = false;
  var _registering = false;

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> get user async* {
    if (_known) yield _current;
    yield* _changes.stream;
  }

  Future<void> _onAuth(User? user) async {
    if (user == null) {
      _publish(null);
      return;
    }
    final fromAuth = _fromAuth(user);
    // Sign-in goes ahead on what the account knows; the profile fills in after.
    _publish(fromAuth);
    // A new email account writes its own profile, with the name it was given.
    if (_registering) return;
    try {
      final doc = _db.collection('users').doc(user.uid);
      final snap = await doc.get();
      final data = snap.data();
      if (data == null) {
        await doc.set({
          'name': fromAuth.name,
          'photoUrl': fromAuth.photoUrl,
          'bio': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (_auth.currentUser?.uid == user.uid) {
        _publish(
          AppUser(
            uid: user.uid,
            name: (data['name'] as String?) ?? fromAuth.name,
            email: fromAuth.email,
            photoUrl: fromAuth.photoUrl,
            bio: (data['bio'] as String?) ?? '',
          ),
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('Profile not loaded: ${e.code}');
    }
  }

  AppUser _fromAuth(User user) {
    final email = user.email ?? '';
    final fallback = email.contains('@') ? email.split('@').first : 'Member';
    final name = user.displayName?.trim() ?? '';
    return AppUser(
      uid: user.uid,
      name: name.isEmpty ? fallback : name,
      email: email,
      photoUrl: user.photoURL ?? '',
    );
  }

  void _publish(AppUser? user) {
    _current = user;
    _known = true;
    _changes.add(user);
  }

  String get _uid {
    final uid = _current?.uid;
    if (uid == null) throw const BackendFailure('Please sign in first.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _room(String id) =>
      _db.collection('classrooms').doc(id);

  @override
  String newId() => _db.collection('ids').doc().id;

  // Accounts ------------------------------------------------------------------

  Future<T> _signingIn<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw BackendFailure(_authMessage(e));
    }
  }

  String _authMessage(FirebaseAuthException e) => switch (e.code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'That email or password isn’t right.',
    'invalid-email' => 'That doesn’t look like an email address.',
    'email-already-in-use' => 'That email already has an account.',
    'weak-password' => 'Use a password of at least 6 characters.',
    'network-request-failed' => 'Signing in needs a connection. Please retry.',
    'too-many-requests' => 'Too many tries. Please wait a little and retry.',
    'account-exists-with-different-credential' =>
      'That email already signs in another way. Please use that way.',
    'popup-closed-by-user' ||
    'web-context-canceled' ||
    'canceled' => 'Sign-in was cancelled.',
    _ => 'Couldn’t sign in (${e.code}). Please retry.',
  };

  @override
  Future<void> signInWithEmail(String email, String password) => _signingIn(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> registerWithEmail(String name, String email, String password) =>
      _signingIn(() async {
        _registering = true;
        try {
          final made = await _auth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
          await made.user?.updateDisplayName(name.trim());
          await saveProfile(name: name, bio: '');
        } finally {
          _registering = false;
        }
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _signingIn(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> _signInWith(AuthProvider provider) => _signingIn(
    () => kIsWeb
        ? _auth.signInWithPopup(provider)
        : _auth.signInWithProvider(provider),
  );

  @override
  Future<void> signInWithGoogle() => _signInWith(GoogleAuthProvider());

  @override
  Future<void> signInWithGitHub() => _signInWith(GithubAuthProvider());

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> saveProfile({required String name, required String bio}) async {
    final user = _auth.currentUser;
    if (user == null) throw const BackendFailure('Please sign in first.');
    final trimmed = name.trim();
    final next = _fromAuth(user);
    final batch = _db.batch()
      ..set(_db.collection('users').doc(user.uid), {
        'name': trimmed,
        'photoUrl': next.photoUrl,
        'bio': bio.trim(),
      }, SetOptions(merge: true));
    // Other people see this name on the graph, so it follows into each lane.
    final rooms = await _db
        .collection('classrooms')
        .where('memberUids', arrayContains: user.uid)
        .get();
    for (final room in rooms.docs) {
      batch.update(room.reference.collection('members').doc(user.uid), {
        'name': trimmed,
      });
    }
    unawaited(user.updateDisplayName(trimmed));
    await _writing(batch.commit());
    _publish(
      AppUser(
        uid: user.uid,
        name: trimmed,
        email: next.email,
        photoUrl: next.photoUrl,
        bio: bio.trim(),
      ),
    );
  }

  // Classrooms ----------------------------------------------------------------

  Future<void> _writing(Future<void> write) async {
    try {
      await write;
    } on FirebaseException catch (e) {
      throw BackendFailure(
        e.code == 'permission-denied'
            ? 'You don’t have permission to do that.'
            : 'That wasn’t saved (${e.code}). Please retry.',
      );
    }
  }

  Classroom _classroomFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Classroom(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      constraints: (d['constraintDescription'] as String?) ?? '',
      taskType: TaskType.named(d['taskType'] as String?),
      individual: d['mode'] == 'individual',
      masterUid: (d['masterUid'] as String?) ?? '',
      coMasterUids: _strings(d['coMasterUids']),
      memberUids: _strings(d['memberUids']),
      deadline: _date(d['deadline']),
      hoursPerWeek: (d['hoursPerWeek'] as num?)?.toDouble(),
      inviteCode: (d['inviteCode'] as String?) ?? '',
      approvalRequired: d['approvalRequired'] == true,
      joinApprovalRequired: d['joinApprovalRequired'] == true,
      createdAt: _date(d['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  Stream<List<Classroom>> classrooms() => _db
      .collection('classrooms')
      .where('memberUids', arrayContains: _uid)
      .snapshots()
      .map((snap) {
        return snap.docs.map(_classroomFrom).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });

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
    final me = _uid;
    final room = _db.collection('classrooms').doc();
    final code = newInviteCode();
    final batch = _db.batch()
      ..set(room, {
        'title': title.trim(),
        'description': description.trim(),
        'constraintDescription': constraints.trim(),
        'taskType': taskType.name,
        'mode': individual ? 'individual' : 'group',
        'masterUid': me,
        'coMasterUids': <String>[],
        'memberUids': [me],
        'deadline': deadline == null ? null : Timestamp.fromDate(deadline),
        'hoursPerWeek': hoursPerWeek,
        'inviteCode': code,
        'approvalRequired': false,
        'joinApprovalRequired': false,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(room.collection('members').doc(me), {
        'name': _current?.name ?? '',
        'photoUrl': _current?.photoUrl ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': null,
      });
    if (!individual) {
      batch.set(_db.collection('inviteCodes').doc(code), {
        'classroomId': room.id,
      });
    }
    // Waits in the cache when offline, so the classroom opens straight away.
    unawaited(_writing(batch.commit()));
    return room.id;
  }

  @override
  Future<String?> joinWithCode(String code) async {
    final me = _uid;
    final wanted = code.trim().toUpperCase();
    final DocumentSnapshot<Map<String, dynamic>> invite;
    try {
      invite = await _db.collection('inviteCodes').doc(wanted).get();
    } on FirebaseException {
      throw const BackendFailure('Joining needs a connection. Please retry.');
    }
    final id = invite.data()?['classroomId'] as String?;
    if (id == null) {
      throw const BackendFailure('That code doesn’t match a classroom.');
    }
    final room = _room(id);
    // Only a member can read a classroom, so a refusal here means not joined yet.
    try {
      final existing = await room.get();
      if (_strings(existing.data()?['memberUids']).contains(me)) return id;
    } on FirebaseException catch (_) {}
    if (invite.data()?['approval'] == true) {
      try {
        await room.collection('joinRequests').doc(me).set({
          'name': _current?.name ?? '',
          'inviteCode': wanted,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException {
        throw const BackendFailure('Couldn’t ask to join. Please retry.');
      }
      return null;
    }
    final batch = _db.batch()
      ..set(room.collection('members').doc(me), {
        'name': _current?.name ?? '',
        'photoUrl': _current?.photoUrl ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': null,
        'inviteCode': wanted,
      })
      ..update(room, {
        'memberUids': FieldValue.arrayUnion([me]),
      })
      ..set(room.collection('activity').doc(), {
        'actorUid': me,
        'kind': ActivityKind.memberJoined.name,
        'summary': '${_current?.name ?? 'Someone'} joined the classroom',
        'targetId': '',
        'affectsUid': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      throw BackendFailure(
        e.code == 'permission-denied'
            ? 'Couldn’t join. This classroom may already have $kMaxMembers '
                  'members, or the code may have changed.'
            : 'Joining needs a connection. Please retry.',
      );
    }
    return id;
  }

  PlanStep _stepFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final now = DateTime.now();
    return PlanStep(
      id: doc.id,
      phaseId: (d['phaseId'] as String?) ?? '',
      ownerId: (d['ownerUid'] as String?) ?? '',
      title: (d['title'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      status: StepStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => StepStatus.todo,
      ),
      dependsOn: _strings(d['dependsOn']),
      estimateHours: (d['estimateHours'] as num?)?.toDouble() ?? 1,
      start: _date(d['startDate']) ?? now,
      due: _date(d['dueDate']) ?? now,
      skills: _strings(d['skills']),
      checklist: [
        for (final item in (d['checklist'] as List?) ?? const [])
          if (item is Map)
            ChecklistItem(
              title: (item['title'] as String?) ?? '',
              done: item['done'] == true,
            ),
      ],
      order: (d['order'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Stream<ClassroomState> watchClassroom(String classroomId) {
    final room = _room(classroomId);
    late StreamController<ClassroomState> out;
    final subscriptions = <StreamSubscription<Object?>>[];
    Classroom? classroom;
    List<ClassroomMember>? members;
    List<PhaseRecord>? phases;
    List<PlanStep>? steps;

    void emit() {
      final c = classroom, m = members, p = phases, s = steps;
      if (c == null || m == null || p == null || s == null) return;
      out.add(ClassroomState(classroom: c, members: m, phases: p, steps: s));
    }

    out = StreamController<ClassroomState>(
      onListen: () {
        void onError(Object e, StackTrace _) =>
            out.addError(const BackendFailure('Couldn’t load this classroom.'));
        subscriptions.addAll([
          room.snapshots().listen((doc) {
            if (!doc.exists) return;
            classroom = _classroomFrom(doc);
            emit();
          }, onError: onError),
          room.collection('members').snapshots().listen((snap) {
            members = [
              for (final doc in snap.docs)
                ClassroomMember(
                  uid: doc.id,
                  name: (doc.data()['name'] as String?) ?? 'Member',
                  photoUrl: (doc.data()['photoUrl'] as String?) ?? '',
                  lastSeenAt: _date(doc.data()['lastSeenAt']),
                ),
            ];
            emit();
          }, onError: onError),
          room.collection('phases').orderBy('order').snapshots().listen((snap) {
            phases = [
              for (final doc in snap.docs)
                PhaseRecord(
                  id: doc.id,
                  title: (doc.data()['title'] as String?) ?? '',
                  order: (doc.data()['order'] as num?)?.toInt() ?? 0,
                ),
            ];
            emit();
          }, onError: onError),
          room.collection('steps').orderBy('order').snapshots().listen((snap) {
            steps = snap.docs.map(_stepFrom).toList();
            emit();
          }, onError: onError),
        ]);
      },
      onCancel: () async {
        for (final s in subscriptions) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  @override
  Future<void> updateClassroom(Classroom c) {
    final batch = _db.batch()
      ..update(_room(c.id), {
        'title': c.title,
        'description': c.description,
        'constraintDescription': c.constraints,
        'deadline': c.deadline == null ? null : Timestamp.fromDate(c.deadline!),
        'hoursPerWeek': c.hoursPerWeek,
        'approvalRequired': c.approvalRequired,
        'joinApprovalRequired': c.joinApprovalRequired,
      });
    // Someone with only a code can't read the classroom, so the code says too.
    if (!c.individual) {
      batch.update(_db.collection('inviteCodes').doc(c.inviteCode), {
        'approval': c.joinApprovalRequired,
      });
    }
    return _writing(batch.commit());
  }

  @override
  Future<void> setCoMaster(String classroomId, String uid, bool coMaster) =>
      _writing(
        _room(classroomId).update({
          'coMasterUids': coMaster
              ? FieldValue.arrayUnion([uid])
              : FieldValue.arrayRemove([uid]),
        }),
      );

  @override
  Future<void> removeMember(String classroomId, String uid) {
    final room = _room(classroomId);
    final batch = _db.batch()
      ..delete(room.collection('members').doc(uid))
      ..update(room, {
        'memberUids': FieldValue.arrayRemove([uid]),
        'coMasterUids': FieldValue.arrayRemove([uid]),
      });
    return _writing(batch.commit());
  }

  @override
  Future<void> savePhase(String classroomId, PhaseRecord phase) => _writing(
    _room(classroomId)
        .collection('phases')
        .doc(phase.id)
        .set({'title': phase.title, 'order': phase.order}),
  );

  @override
  Future<void> deletePhase(String classroomId, String phaseId) async {
    final room = _room(classroomId);
    final inPhase = await room
        .collection('steps')
        .where('phaseId', isEqualTo: phaseId)
        .get();
    final batch = _db.batch()..delete(room.collection('phases').doc(phaseId));
    for (final step in inPhase.docs) {
      batch.delete(step.reference);
    }
    await _writing(batch.commit());
  }

  @override
  Future<void> saveStep(String classroomId, PlanStep s) => _writing(
    _room(classroomId).collection('steps').doc(s.id).set({
      'phaseId': s.phaseId,
      'ownerUid': s.ownerId,
      'title': s.title,
      'description': s.description,
      'status': s.status.name,
      'dependsOn': s.dependsOn,
      'estimateHours': s.estimateHours,
      'startDate': Timestamp.fromDate(s.start),
      'dueDate': Timestamp.fromDate(s.due),
      'skills': s.skills,
      'checklist': [
        for (final item in s.checklist)
          {'title': item.title, 'done': item.done},
      ],
      'order': s.order,
    }),
  );

  @override
  Future<void> deleteStep(String classroomId, String stepId) =>
      _writing(_room(classroomId).collection('steps').doc(stepId).delete());

  // Join requests, leaving and deleting ----------------------------------------

  @override
  Stream<List<JoinRequest>> joinRequests(String classroomId) =>
      _room(classroomId)
          .collection('joinRequests')
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs)
                JoinRequest(
                  uid: doc.id,
                  name: (doc.data()['name'] as String?) ?? 'Someone',
                ),
            ],
          );

  @override
  Future<void> approveJoin(String classroomId, JoinRequest request) {
    final room = _room(classroomId);
    final batch = _db.batch()
      ..set(room.collection('members').doc(request.uid), {
        'name': request.name,
        'photoUrl': '',
        'joinedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': null,
      })
      ..update(room, {
        'memberUids': FieldValue.arrayUnion([request.uid]),
      })
      ..delete(room.collection('joinRequests').doc(request.uid))
      ..set(room.collection('activity').doc(), {
        'actorUid': _uid,
        'kind': ActivityKind.memberJoined.name,
        'summary': '${request.name} joined the classroom',
        'targetId': '',
        'affectsUid': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    return _writing(batch.commit());
  }

  @override
  Future<void> declineJoin(String classroomId, String uid) =>
      _writing(_room(classroomId).collection('joinRequests').doc(uid).delete());

  @override
  Future<void> leaveClassroom(String classroomId) async {
    final me = _uid;
    final room = _room(classroomId);
    final c = _classroomFrom(await room.get());
    final String? next;
    if (c.masterUid == me) {
      if (c.memberUids.length == 1) {
        throw const BackendFailure(
          'You’re the only one here. Delete the classroom in Settings instead.',
        );
      }
      if (c.coMasterUids.isEmpty) {
        throw const BackendFailure(
          'Make someone co-master first, so the classroom has a master when '
          'you leave.',
        );
      }
      next = c.coMasterUids.first;
    } else {
      next = null;
    }
    // Only members can write to the log, so this goes in while still one.
    await _writing(
      room.collection('activity').doc().set({
        'actorUid': me,
        'kind': ActivityKind.memberJoined.name,
        'summary': '${_current?.name ?? 'Someone'} left the classroom',
        'targetId': '',
        'affectsUid': '',
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
    final batch = _db.batch()
      ..update(room, {
        'memberUids': FieldValue.arrayRemove([me]),
        'coMasterUids': FieldValue.arrayRemove([next ?? me]),
        'masterUid': ?next,
      })
      ..delete(room.collection('members').doc(me));
    await _writing(batch.commit());
  }

  @override
  Future<void> deleteClassroom(String classroomId) async {
    final room = _room(classroomId);
    final c = _classroomFrom(await room.get());
    await _writing(room.update({'status': 'deleting'}));
    final me = _uid;
    for (final name in const [
      'activity',
      'joinRequests',
      'steps',
      'phases',
      'members',
    ]) {
      final docs = (await room.collection(name).get()).docs;
      for (var i = 0; i < docs.length; i += 400) {
        final batch = _db.batch();
        for (final doc in docs.skip(i).take(400)) {
          batch.delete(doc.reference);
        }
        await _writing(batch.commit());
      }
    }
    assert(c.masterUid == me);
    final batch = _db.batch()..delete(room);
    if (!c.individual) {
      batch.delete(_db.collection('inviteCodes').doc(c.inviteCode));
    }
    await _writing(batch.commit());
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw const BackendFailure('Please sign in first.');
    // Firebase refuses this on an old sign-in. Finding out now, rather than
    // after the classrooms have gone, leaves nothing half done.
    final signedInAt = user.metadata.lastSignInTime;
    if (signedInAt == null ||
        DateTime.now().difference(signedInAt) > const Duration(minutes: 4)) {
      throw const BackendFailure(
        'For safety, sign out and back in first, then delete your account '
        'straight away.',
      );
    }
    final me = user.uid;
    final rooms = await _db
        .collection('classrooms')
        .where('memberUids', arrayContains: me)
        .get();
    final mine = rooms.docs.map(_classroomFrom).toList();
    final stuck = mine
        .where(
          (c) =>
              c.masterUid == me &&
              c.memberUids.length > 1 &&
              c.coMasterUids.isEmpty,
        )
        .map((c) => '“${c.title}”');
    if (stuck.isNotEmpty) {
      throw BackendFailure(
        'First make someone co-master in ${stuck.join(', ')}, so it keeps a '
        'master after you’ve gone.',
      );
    }
    for (final c in mine) {
      if (c.masterUid == me && c.memberUids.length == 1) {
        await deleteClassroom(c.id);
      } else {
        await leaveClassroom(c.id);
      }
    }
    await _writing(_db.collection('users').doc(me).delete());
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw BackendFailure(_authMessage(e));
    }
  }

  // Activity ------------------------------------------------------------------

  @override
  Future<void> logActivity(String classroomId, ActivityEntry entry) => _writing(
    _room(classroomId).collection('activity').doc(entry.id).set({
      'actorUid': _uid,
      'kind': entry.kind.name,
      'summary': entry.summary,
      'targetId': entry.targetId,
      'affectsUid': entry.affectsUid,
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<List<ActivityEntry>> activity(
    String classroomId, {
    DateTime? since,
    int limit = 50,
  }) async {
    Query<Map<String, dynamic>> query = _room(classroomId)
        .collection('activity')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (since != null) {
      query = query.where(
        'createdAt',
        isGreaterThan: Timestamp.fromDate(since),
      );
    }
    final snap = await query.get(
      const GetOptions(serverTimestampBehavior: _estimate),
    );
    return snap.docs.map(_entryFrom).toList();
  }

  ActivityEntry _entryFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return ActivityEntry(
      id: doc.id,
      actorUid: (d['actorUid'] as String?) ?? '',
      kind: ActivityKind.named(d['kind'] as String?),
      summary: (d['summary'] as String?) ?? '',
      targetId: (d['targetId'] as String?) ?? '',
      affectsUid: (d['affectsUid'] as String?) ?? '',
      createdAt: _date(d['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  Future<void> deleteActivity(String classroomId, String entryId) =>
      _writing(_room(classroomId).collection('activity').doc(entryId).delete());

  @override
  Future<void> clearActivity(String classroomId) async {
    final docs = (await _room(classroomId).collection('activity').get()).docs;
    for (var i = 0; i < docs.length; i += 400) {
      final batch = _db.batch();
      for (final doc in docs.skip(i).take(400)) {
        batch.delete(doc.reference);
      }
      await _writing(batch.commit());
    }
  }

  @override
  Stream<List<ActivityEntry>> activityFeed(
    String classroomId, {
    int limit = 50,
  }) =>
      _room(classroomId)
          .collection('activity')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(_entryFrom).toList());

  @override
  Future<void> markSeen(String classroomId) => _writing(
    _room(classroomId)
        .collection('members')
        .doc(_uid)
        .update({'lastSeenAt': FieldValue.serverTimestamp()}),
  );
}
