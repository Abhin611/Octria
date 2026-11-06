import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../kanvas/kanvas_model.dart';
import '../model/plan.dart';
import 'backend.dart';
import 'drive.dart';
import 'google_drive.dart';
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
                  chatSeenAt: _date(doc.data()['chatSeenAt']),
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
  Future<void> deleteStep(String classroomId, String stepId) async {
    // Only the comments this person is in; the rest can't be read by anyone
    // but the two people in them, so they stay out of reach.
    await _deleteAll(
      _comments(classroomId, stepId).where('participants', arrayContains: _uid),
    );
    await _writing(_room(classroomId).collection('steps').doc(stepId).delete());
  }

  /// Deletes every document in a collection, a batch at a time.
  Future<void> _deleteAll(Query<Map<String, dynamic>> query) async {
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
    try {
      docs = (await query.get()).docs;
    } on FirebaseException {
      return;
    }
    for (var i = 0; i < docs.length; i += 400) {
      final batch = _db.batch();
      for (final doc in docs.skip(i).take(400)) {
        batch.delete(doc.reference);
      }
      await _writing(batch.commit());
    }
  }

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
    for (final step in (await room.collection('steps').get()).docs) {
      await _deleteAll(
        step.reference
            .collection('comments')
            .where('participants', arrayContains: me),
      );
    }
    await _deleteAll(
      room.collection('suggestions').where('public', isEqualTo: true),
    );
    await _deleteAll(
      room.collection('resources').where('type', isEqualTo: 'practice'),
    );
    await _deleteAll(
      room.collection('resources').where('ownerUid', isEqualTo: me),
    );
    await _deleteAll(room.collection('handovers'));
    await _deleteAll(
      room.collection('threads').where('participants', arrayContains: me),
    );
    await _deleteAll(
      room.collection('suggestions').where('participants', arrayContains: me),
    );
    for (final name in const [
      'activity',
      'joinRequests',
      'chat',
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

  // Collaboration -------------------------------------------------------------

  StudyMaterial _materialFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return StudyMaterial(
      id: doc.id,
      kind: MaterialKind.named(d['type'] as String?),
      title: (d['title'] as String?) ?? '',
      url: (d['url'] as String?) ?? '',
      note: (d['note'] as String?) ?? '',
      ownerUid: (d['ownerUid'] as String?) ?? '',
      stepId: (d['stepId'] as String?) ?? '',
      createdAt: _date(d['createdAt']) ?? DateTime.now(),
    );
  }

  // Files -------------------------------------------------------------------

  @override
  late final DriveStore drive = GoogleDrive(_auth);

  LibraryFile _fileFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return LibraryFile(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      mimeType: (d['mimeType'] as String?) ?? '',
      size: (d['size'] as num?)?.toInt() ?? 0,
      url: (d['url'] as String?) ?? '',
      ownerUid: (d['ownerUid'] as String?) ?? '',
      stepId: (d['stepId'] as String?) ?? '',
      shared: d['shared'] == true,
      createdAt: _date(d['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  Stream<List<LibraryFile>> files(String classroomId) {
    final all = _room(classroomId).collection('files');
    // Shared files are for everyone; private ones only for their owner.
    return _merge<LibraryFile>(
      [
        all.where('shared', isEqualTo: true).snapshots(),
        all.where('ownerUid', isEqualTo: _uid).snapshots(),
      ],
      _fileFrom,
      (f) => f.id,
    ).map((list) => list..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  @override
  Future<void> addFile(String classroomId, LibraryFile f) => _writing(
    _room(classroomId).collection('files').doc(f.id).set({
      'name': f.name.trim(),
      'mimeType': f.mimeType,
      'size': f.size,
      'url': f.url,
      'ownerUid': _uid,
      'stepId': f.stepId,
      'shared': f.shared,
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> updateFile(String classroomId, LibraryFile f) => _writing(
    _room(classroomId)
        .collection('files')
        .doc(f.id)
        .update({'shared': f.shared, 'stepId': f.stepId}),
  );

  @override
  Future<void> removeFile(String classroomId, String fileId) =>
      _writing(_room(classroomId).collection('files').doc(fileId).delete());

  @override
  Stream<List<StudyMaterial>> materials(String classroomId) {
    final all = _room(classroomId).collection('resources');
    // Practice links are for everyone; a step's materials only for its owner.
    return _merge<StudyMaterial>(
      [
        all.where('type', isEqualTo: MaterialKind.practice.name).snapshots(),
        all.where('ownerUid', isEqualTo: _uid).snapshots(),
      ],
      _materialFrom,
      (m) => m.id,
    ).map((list) => list..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  @override
  Future<void> saveMaterial(String classroomId, StudyMaterial m) => _writing(
    _room(classroomId).collection('resources').doc(m.id).set({
      'type': m.kind.name,
      'title': m.title,
      'url': m.url,
      'note': m.note,
      'ownerUid': _uid,
      'stepId': m.stepId,
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> deleteMaterial(String classroomId, String materialId) =>
      _writing(
        _room(classroomId).collection('resources').doc(materialId).delete(),
      );

  CollectionReference<Map<String, dynamic>> _comments(
    String classroomId,
    String stepId,
  ) =>
      _room(classroomId).collection('steps').doc(stepId).collection('comments');

  @override
  Stream<List<StepComment>> comments(String classroomId, String stepId) =>
      _comments(classroomId, stepId)
          .where('participants', arrayContains: _uid)
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs)
                StepComment(
                  id: doc.id,
                  authorUid: (doc.data()['authorUid'] as String?) ?? '',
                  text: (doc.data()['text'] as String?) ?? '',
                  participants: _strings(doc.data()['participants']),
                  createdAt: _date(doc.data()['createdAt']) ?? DateTime.now(),
                ),
            ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
          );

  @override
  Future<void> addComment(
    String classroomId,
    String stepId,
    String text, {
    required String ownerUid,
    required String withUid,
  }) => _writing(
    _comments(classroomId, stepId).doc().set({
      'authorUid': _uid,
      'text': text.trim(),
      'participants': {ownerUid, withUid}.toList(),
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> deleteComment(
    String classroomId,
    String stepId,
    String commentId,
  ) => _writing(_comments(classroomId, stepId).doc(commentId).delete());

  Suggestion _suggestionFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return Suggestion(
      id: doc.id,
      stepId: (d['targetId'] as String?) ?? '',
      fromUid: (d['fromUid'] as String?) ?? '',
      toUid: (d['toUid'] as String?) ?? '',
      text: (d['text'] as String?) ?? '',
      status: SuggestionStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => SuggestionStatus.open,
      ),
      public: d['public'] == true,
      publicAt: _date(d['publicAt']),
      createdAt: _date(d['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  Stream<List<Suggestion>> suggestions(String classroomId) {
    final all = _room(classroomId).collection('suggestions');
    // Two reads the rules can check: the public ones, and this person's own.
    return _merge<Suggestion>(
      [
        all.where('public', isEqualTo: true).snapshots(),
        all.where('participants', arrayContains: _uid).snapshots(),
      ],
      _suggestionFrom,
      (s) => s.id,
    ).map((list) => list..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  /// Keeps several live queries as one list, without repeats.
  Stream<List<T>> _merge<T>(
    List<Stream<QuerySnapshot<Map<String, dynamic>>>> sources,
    T Function(QueryDocumentSnapshot<Map<String, dynamic>>) read,
    String Function(T) idOf,
  ) {
    late StreamController<List<T>> out;
    final latest = List<List<T>?>.filled(sources.length, null);
    final subscriptions = <StreamSubscription<Object?>>[];
    out = StreamController<List<T>>(
      onListen: () {
        for (var i = 0; i < sources.length; i++) {
          subscriptions.add(
            sources[i].listen((snap) {
              latest[i] = snap.docs.map(read).toList();
              if (latest.any((l) => l == null)) return;
              final byId = <String, T>{};
              for (final list in latest) {
                for (final item in list!) {
                  byId[idOf(item)] = item;
                }
              }
              out.add(byId.values.toList());
            }, onError: out.addError),
          );
        }
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
  Future<void> addSuggestion(String classroomId, Suggestion s) => _writing(
    _room(classroomId).collection('suggestions').doc(s.id).set({
      'targetType': 'step',
      'targetId': s.stepId,
      'fromUid': _uid,
      'toUid': s.toUid,
      'participants': [_uid, s.toUid],
      'text': s.text.trim(),
      'status': SuggestionStatus.open.name,
      'public': s.public,
      'publicAt': s.public ? FieldValue.serverTimestamp() : null,
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> answerSuggestion(
    String classroomId,
    String suggestionId,
    SuggestionStatus status,
  ) => _writing(
    _room(classroomId).collection('suggestions').doc(suggestionId).update({
      'status': status.name,
      'answeredAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> setSuggestionPublic(
    String classroomId,
    String suggestionId,
    bool public,
  ) => _writing(
    _room(classroomId).collection('suggestions').doc(suggestionId).update({
      'public': public,
      'publicAt': public ? FieldValue.serverTimestamp() : null,
    }),
  );

  @override
  Stream<List<ChatMessage>> chat(String classroomId) =>
      _room(classroomId)
          .collection('chat')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs.reversed)
                ChatMessage(
                  id: doc.id,
                  authorUid: (doc.data()['authorUid'] as String?) ?? '',
                  text: (doc.data()['text'] as String?) ?? '',
                  forEveryone: doc.data()['forEveryone'] == true,
                  appliedBy: _strings(doc.data()['appliedBy']),
                  createdAt: _date(doc.data()['createdAt']) ?? DateTime.now(),
                ),
            ],
          );

  @override
  Future<void> sendChat(
    String classroomId,
    String text, {
    bool forEveryone = false,
  }) => _writing(
    _room(classroomId).collection('chat').doc().set({
      'authorUid': _uid,
      'text': text.trim(),
      'forEveryone': forEveryone,
      'appliedBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> setApplied(String classroomId, String messageId, bool applied) =>
      _writing(
        _room(classroomId).collection('chat').doc(messageId).update({
          'appliedBy': applied
              ? FieldValue.arrayUnion([_uid])
              : FieldValue.arrayRemove([_uid]),
        }),
      );

  @override
  Future<void> deleteChat(String classroomId, String messageId) =>
      _writing(_room(classroomId).collection('chat').doc(messageId).delete());

  @override
  Future<void> markChatSeen(String classroomId) => _writing(
    _room(classroomId)
        .collection('members')
        .doc(_uid)
        .update({'chatSeenAt': FieldValue.serverTimestamp()}),
  );

  ChatThread _threadFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final read = <String, DateTime>{};
    final raw = d['readAt'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final at = _date(v);
        if (k is String && at != null) read[k] = at;
      });
    }
    return ChatThread(
      id: doc.id,
      participants: _strings(d['participants']),
      lastAt: _date(d['lastAt']),
      lastText: (d['lastText'] as String?) ?? '',
      lastBy: (d['lastBy'] as String?) ?? '',
      readAt: read,
    );
  }

  @override
  Stream<List<ChatThread>> threads(String classroomId) => _room(classroomId)
      .collection('threads')
      .where('participants', arrayContains: _uid)
      .snapshots()
      .map(
        (snap) => snap.docs.map(_threadFrom).toList()
          ..sort(
            (a, b) => (b.lastAt ?? DateTime(2000)).compareTo(
              a.lastAt ?? DateTime(2000),
            ),
          ),
      );

  @override
  Future<String> openThread(
    String classroomId,
    List<String> participants,
  ) async {
    final me = _uid;
    final people = {me, ...participants}.toList()..sort();
    final threads = _room(classroomId).collection('threads');
    if (people.length > 2) {
      // The same group of people always shares one chat, so its history stays.
      try {
        final mine = await threads
            .where('participants', arrayContains: me)
            .get();
        for (final doc in mine.docs) {
          final others = _strings(doc.data()['participants']).toSet();
          if (setEquals(others, people.toSet())) return doc.id;
        }
      } on FirebaseException {
        // Offline with nothing cached: start a new one.
      }
    }
    final ref = people.length == 2
        ? threads.doc(ChatThread.directId(people[0], people[1]))
        : threads.doc();
    if (people.length == 2) {
      try {
        if ((await ref.get()).exists) return ref.id;
      } on FirebaseException {
        // Not readable means not there yet: two people share one id.
      }
    }
    await _writing(
      ref.set({
        'participants': people,
        'createdBy': me,
        'createdAt': FieldValue.serverTimestamp(),
        'lastAt': null,
        'lastText': '',
        'lastBy': '',
        'readAt': <String, Object>{},
      }),
    );
    return ref.id;
  }

  @override
  Stream<List<ChatMessage>> threadMessages(
    String classroomId,
    String threadId,
  ) =>
      _room(classroomId)
          .collection('threads')
          .doc(threadId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs.reversed)
                ChatMessage(
                  id: doc.id,
                  authorUid: (doc.data()['authorUid'] as String?) ?? '',
                  text: (doc.data()['text'] as String?) ?? '',
                  createdAt: _date(doc.data()['createdAt']) ?? DateTime.now(),
                ),
            ],
          );

  @override
  Future<void> sendThreadMessage(
    String classroomId,
    String threadId,
    String text,
  ) {
    final me = _uid;
    final thread = _room(classroomId).collection('threads').doc(threadId);
    final trimmed = text.trim();
    final batch = _db.batch()
      ..set(thread.collection('messages').doc(), {
        'authorUid': me,
        'text': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..update(thread, {
        'lastAt': FieldValue.serverTimestamp(),
        'lastText': trimmed.length > 120
            ? '${trimmed.substring(0, 119)}…'
            : trimmed,
        'lastBy': me,
        'readAt.$me': FieldValue.serverTimestamp(),
      });
    return _writing(batch.commit());
  }

  @override
  Future<void> markThreadRead(String classroomId, String threadId) => _writing(
    _room(classroomId)
        .collection('threads')
        .doc(threadId)
        .update({'readAt.$_uid': FieldValue.serverTimestamp()}),
  );

  Handover _handoverFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return Handover(
      stepId: doc.id,
      fromUid: (d['fromUid'] as String?) ?? '',
      toUid: (d['toUid'] as String?) ?? '',
      note: (d['note'] as String?) ?? '',
      status: HandoverStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => HandoverStatus.declined,
      ),
      createdAt: _date(d['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  Stream<List<Handover>> handovers(String classroomId) {
    // Everyone in a classroom can see who is handing what to whom.
    return _room(classroomId)
        .collection('handovers')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(_handoverFrom).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  @override
  Future<void> requestHandover(
    String classroomId,
    String stepId,
    String toUid,
    String note,
  ) async {
    final me = _uid;
    final room = _room(classroomId);
    final manages = _classroomFrom(await room.get()).canManage(me);
    final ref = room.collection('handovers').doc(stepId);
    // An old, finished request for this step makes way for the new one.
    try {
      await ref.delete();
    } on FirebaseException {
      // Nothing there, or nothing of ours.
    }
    await _writing(
      ref.set({
        'fromUid': me,
        'toUid': toUid,
        'participants': [me, toUid],
        // Everyone in the classroom can see a handover, so the reason goes
        // privately to the people deciding instead.
        'note': '',
        'status': manages
            ? HandoverStatus.needsReceiver.name
            : HandoverStatus.needsMaster.name,
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<void> reviewHandover(
    String classroomId,
    String stepId,
    bool approve,
  ) => _writing(
    _room(classroomId).collection('handovers').doc(stepId).update({
      'status': approve
          ? HandoverStatus.needsReceiver.name
          : HandoverStatus.declined.name,
      'decidedBy': _uid,
      'decidedAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> answerHandover(String classroomId, String stepId, bool accept) {
    final room = _room(classroomId);
    final batch = _db.batch()
      ..update(room.collection('handovers').doc(stepId), {
        'status': accept
            ? HandoverStatus.accepted.name
            : HandoverStatus.declined.name,
        'decidedAt': FieldValue.serverTimestamp(),
      });
    if (accept) {
      batch.update(room.collection('steps').doc(stepId), {'ownerUid': _uid});
    }
    return _writing(batch.commit());
  }

  @override
  Future<void> cancelHandover(String classroomId, String stepId) =>
      _writing(_room(classroomId).collection('handovers').doc(stepId).delete());

  // Kanvas ------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _boards(String uid) =>
      _db.collection('users').doc(uid).collection('kanvas');

  KanvasBoard _boardFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final people = <String, ShareMode>{};
    final raw = d['people'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String) {
          people[k] = v == 'edit' ? ShareMode.edit : ShareMode.view;
        }
      });
    }
    return KanvasBoard(
      id: doc.id,
      ownerUid: (d['ownerUid'] as String?) ?? doc.reference.parent.parent!.id,
      title: (d['title'] as String?) ?? 'Untitled',
      folder: (d['folder'] as String?) ?? '',
      shapes: decodeShapes(d['data'] as String?),
      updatedAt: _date(d['updatedAt']),
      updatedBy: (d['updatedBy'] as String?) ?? '',
      classroomId: (d['classroomId'] as String?) ?? '',
      classroomMode: d['classroomMode'] == 'edit'
          ? ShareMode.edit
          : ShareMode.view,
      people: people,
    );
  }

  List<KanvasBoard> _latestFirst(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(_boardFrom).toList()..sort(
        (a, b) => (b.updatedAt ?? DateTime(2000)).compareTo(
          a.updatedAt ?? DateTime(2000),
        ),
      );

  @override
  Stream<List<KanvasBoard>> myBoards() =>
      _boards(_uid).snapshots().map(_latestFirst);

  @override
  Stream<List<KanvasBoard>> boardsSharedWithMe() => _db
      .collectionGroup('kanvas')
      .where('sharedWith', arrayContains: _uid)
      .snapshots()
      .map(_latestFirst);

  @override
  Stream<KanvasBoard?> watchBoard(String ownerUid, String boardId) =>
      _boards(ownerUid)
          .doc(boardId)
          .snapshots()
          .map((doc) => doc.exists ? _boardFrom(doc) : null);

  String _encoded(List<KShape> shapes) {
    final text = encodeShapes(shapes);
    if (text.length > kMaxBoardBytes) {
      throw const BackendFailure(
        'This board is full. Start a new board, or remove some drawings.',
      );
    }
    return text;
  }

  @override
  Future<KanvasBoard> createBoard({
    required String title,
    String folder = '',
    List<KShape> shapes = const [],
  }) async {
    final me = _uid;
    final ref = _boards(me).doc();
    final data = {
      'ownerUid': me,
      'title': title.trim().isEmpty ? 'Untitled' : title.trim(),
      'folder': folder.trim(),
      'data': _encoded(shapes),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': me,
      'classroomId': '',
      'classroomMode': 'view',
      'people': <String, String>{},
      'sharedWith': <String>[],
    };
    unawaited(_writing(ref.set(data)));
    return KanvasBoard(
      id: ref.id,
      ownerUid: me,
      title: data['title']! as String,
      folder: folder.trim(),
      shapes: shapes,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> saveBoardShapes(
    String ownerUid,
    String boardId,
    List<KShape> shapes,
  ) => _writing(
    _boards(ownerUid).doc(boardId).update({
      'data': _encoded(shapes),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _uid,
    }),
  );

  @override
  Future<void> updateBoardInfo(
    String boardId, {
    String? title,
    String? folder,
  }) => _writing(
    _boards(_uid).doc(boardId).update({
      if (title != null)
        'title': title.trim().isEmpty ? 'Untitled' : title.trim(),
      if (folder != null) 'folder': folder.trim(),
    }),
  );

  @override
  Future<void> deleteBoard(String boardId) async {
    final me = _uid;
    final ref = _boards(me).doc(boardId);
    final board = _boardFrom(await ref.get());
    await _deleteAll(ref.collection('versions'));
    await _deleteAll(ref.collection('previews'));
    if (board.classroomId.isNotEmpty) {
      try {
        await _room(board.classroomId)
            .collection('boards')
            .doc(boardId)
            .delete();
      } on FirebaseException {
        // The classroom may be gone already.
      }
    }
    await _writing(ref.delete());
  }

  @override
  Future<void> shareBoard(
    String boardId, {
    required Map<String, ShareMode> people,
    required String classroomId,
    required ShareMode classroomMode,
  }) async {
    final me = _uid;
    final ref = _boards(me).doc(boardId);
    final before = _boardFrom(await ref.get());
    final batch = _db.batch()
      ..update(ref, {
        'people': {for (final e in people.entries) e.key: e.value.name},
        'sharedWith': people.keys.toList(),
        'classroomId': classroomId,
        'classroomMode': classroomMode.name,
      });
    // The classroom keeps a note of what's shared with it, so its members can
    // find the board.
    if (before.classroomId.isNotEmpty && before.classroomId != classroomId) {
      batch.delete(_room(before.classroomId).collection('boards').doc(boardId));
    }
    if (classroomId.isNotEmpty && before.classroomId != classroomId) {
      batch.set(_room(classroomId).collection('boards').doc(boardId), {
        'ownerUid': me,
        'title': before.title,
        'stepId': '',
      });
    }
    await _writing(batch.commit());
  }

  @override
  Future<void> saveBoardPreview(
    String ownerUid,
    String boardId,
    String fileId,
    Uint8List jpeg,
  ) => _writing(
    _boards(ownerUid)
        .doc(boardId)
        .collection('previews')
        .doc(fileId)
        .set({'data': Blob(jpeg), 'savedBy': _uid}),
  );

  @override
  Future<Uint8List?> boardPreview(
    String ownerUid,
    String boardId,
    String fileId,
  ) async {
    try {
      final snap = await _boards(ownerUid)
          .doc(boardId)
          .collection('previews')
          .doc(fileId)
          .get();
      final data = snap.data()?['data'];
      return data is Blob ? data.bytes : null;
    } on FirebaseException {
      return null;
    }
  }

  @override
  Future<List<KanvasVersion>> boardVersions(
    String ownerUid,
    String boardId,
  ) async {
    final snap = await _boards(ownerUid)
        .doc(boardId)
        .collection('versions')
        .orderBy('savedAt', descending: true)
        .limit(30)
        .get(const GetOptions(serverTimestampBehavior: _estimate));
    return [
      for (final doc in snap.docs)
        KanvasVersion(
          id: doc.id,
          shapes: decodeShapes(doc.data()['data'] as String?),
          savedAt: _date(doc.data()['savedAt']) ?? DateTime.now(),
          savedBy: (doc.data()['savedBy'] as String?) ?? '',
        ),
    ];
  }

  @override
  Future<void> saveBoardVersion(
    String ownerUid,
    String boardId,
    List<KShape> shapes,
  ) => _writing(
    _boards(ownerUid).doc(boardId).collection('versions').doc().set({
      'data': _encoded(shapes),
      'savedAt': FieldValue.serverTimestamp(),
      'savedBy': _uid,
    }),
  );

  @override
  Stream<List<ClassroomBoard>> classroomBoards(String classroomId) =>
      _room(classroomId)
          .collection('boards')
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs)
                ClassroomBoard(
                  boardId: doc.id,
                  ownerUid: (doc.data()['ownerUid'] as String?) ?? '',
                  title: (doc.data()['title'] as String?) ?? 'Board',
                  stepId: (doc.data()['stepId'] as String?) ?? '',
                ),
            ],
          );

  @override
  Future<void> pinBoard(
    String classroomId,
    String boardId,
    String stepId,
  ) async {
    final me = _uid;
    final ref = _boards(me).doc(boardId);
    final board = _boardFrom(await ref.get());
    if (board.classroomId.isNotEmpty && board.classroomId != classroomId) {
      throw const BackendFailure(
        'This board is shared with another classroom. Stop sharing it there '
        'first.',
      );
    }
    final batch = _db.batch()
      ..update(ref, {'classroomId': classroomId})
      ..set(_room(classroomId).collection('boards').doc(boardId), {
        'ownerUid': me,
        'title': board.title,
        'stepId': stepId,
      });
    await _writing(batch.commit());
  }

  @override
  Future<void> unpinBoard(String classroomId, String boardId) async {
    final batch = _db.batch()
      ..delete(_room(classroomId).collection('boards').doc(boardId))
      ..update(_boards(_uid).doc(boardId), {'classroomId': ''});
    await _writing(batch.commit());
  }

  Offer _offerFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return Offer(
      id: doc.id,
      kind: d['kind'] == 'board' ? OfferKind.board : OfferKind.material,
      fromUid: (d['fromUid'] as String?) ?? '',
      toUid: (d['toUid'] as String?) ?? '',
      status: OfferStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => OfferStatus.pending,
      ),
      createdAt: _date(d['createdAt']) ?? DateTime.now(),
      stepId: (d['stepId'] as String?) ?? '',
      title: (d['title'] as String?) ?? '',
      boardOwner: (d['boardOwner'] as String?) ?? '',
      boardId: (d['boardId'] as String?) ?? '',
      edit: d['edit'] == true,
      materialKind: MaterialKind.named(d['materialKind'] as String?),
      url: (d['url'] as String?) ?? '',
      note: (d['note'] as String?) ?? '',
    );
  }

  @override
  Stream<List<Offer>> offers(String classroomId) =>
      _room(classroomId)
          .collection('offers')
          .where('participants', arrayContains: _uid)
          .snapshots()
          .map(
            (snap) =>
                snap.docs.map(_offerFrom).toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          );

  @override
  Future<void> makeOffer(String classroomId, Offer o) async {
    final me = _uid;
    if (o.kind == OfferKind.board) {
      // Shared now, so they can look before they decide.
      final ref = _boards(me).doc(o.boardId);
      final board = _boardFrom(await ref.get());
      final people = {
        ...board.people,
        o.toUid: o.edit ? ShareMode.edit : ShareMode.view,
      };
      await _writing(
        ref.update({
          'people': {for (final e in people.entries) e.key: e.value.name},
          'sharedWith': people.keys.toList(),
        }),
      );
    }
    await _writing(
      _room(classroomId).collection('offers').doc(o.id).set({
        'kind': o.kind.name,
        'fromUid': me,
        'toUid': o.toUid,
        'participants': [me, o.toUid],
        'status': OfferStatus.pending.name,
        'stepId': o.stepId,
        'title': o.title,
        'boardOwner': o.kind == OfferKind.board ? me : '',
        'boardId': o.boardId,
        'edit': o.edit,
        'materialKind': o.materialKind.name,
        'url': o.url,
        'note': o.note,
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<void> answerOffer(String classroomId, Offer o, bool accept) async {
    await _writing(
      _room(classroomId).collection('offers').doc(o.id).update({
        'status': accept
            ? OfferStatus.accepted.name
            : OfferStatus.declined.name,
        'answeredAt': FieldValue.serverTimestamp(),
      }),
    );
    if (o.kind == OfferKind.board && !accept) {
      await leaveBoard(o.boardOwner, o.boardId);
    }
    if (o.kind == OfferKind.material && accept) {
      await saveMaterial(
        classroomId,
        StudyMaterial(
          id: newId(),
          kind: o.materialKind,
          title: o.title,
          url: o.url,
          note: o.note,
          ownerUid: _uid,
          stepId: o.stepId,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<void> leaveBoard(String ownerUid, String boardId) async {
    final me = _uid;
    final ref = _boards(ownerUid).doc(boardId);
    final board = _boardFrom(await ref.get());
    final people = {...board.people}..remove(me);
    await _writing(
      ref.update({
        'people': {for (final e in people.entries) e.key: e.value.name},
        'sharedWith': people.keys.toList(),
      }),
    );
  }

  @override
  Future<void> notify(String uid, Notice notice) => _writing(
    _db.collection('users').doc(uid).collection('inbox').doc().set({
      'classroomId': notice.classroomId,
      'actorUid': _uid,
      'kind': notice.entry.kind.name,
      'summary': notice.entry.summary,
      'targetId': notice.entry.targetId,
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<List<Notice>> inbox() async {
    final snap = await _db
        .collection('users')
        .doc(_uid)
        .collection('inbox')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get(const GetOptions(serverTimestampBehavior: _estimate));
    return [
      for (final doc in snap.docs)
        Notice(
          classroomId: (doc.data()['classroomId'] as String?) ?? '',
          entry: ActivityEntry(
            id: doc.id,
            actorUid: (doc.data()['actorUid'] as String?) ?? '',
            kind: ActivityKind.named(doc.data()['kind'] as String?),
            summary: (doc.data()['summary'] as String?) ?? '',
            targetId: (doc.data()['targetId'] as String?) ?? '',
            affectsUid: _uid,
            createdAt: _date(doc.data()['createdAt']) ?? DateTime.now(),
          ),
        ),
    ];
  }

  @override
  Future<DateTime?> notificationsSeenAt() async {
    try {
      final snap = await _db.collection('users').doc(_uid).get();
      return _date(snap.data()?['notificationsSeenAt']);
    } on FirebaseException {
      return null;
    }
  }

  @override
  Future<void> markNotificationsSeen() => _writing(
    _db.collection('users').doc(_uid).set({
      'notificationsSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)),
  );

  @override
  Future<void> markSeen(String classroomId) => _writing(
    _room(classroomId)
        .collection('members')
        .doc(_uid)
        .update({'lastSeenAt': FieldValue.serverTimestamp()}),
  );
}
