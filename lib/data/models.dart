/// What the app stores about people and classrooms, apart from the plan itself.
library;

import 'dart:math' as math;

/// The most people a classroom can hold.
const int kMaxMembers = 10;

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    this.email = '',
    this.photoUrl = '',
    this.bio = '',
  });

  final String uid;
  final String name;
  final String email;
  final String photoUrl;
  final String bio;

  AppUser copyWith({String? name, String? bio}) => AppUser(
    uid: uid,
    name: name ?? this.name,
    email: email,
    photoUrl: photoUrl,
    bio: bio ?? this.bio,
  );
}

enum TaskType {
  build('Build'),
  study('Exam or study'),
  research('Research'),
  eventOrCreative('Event or creative'),
  other('Other');

  const TaskType(this.label);
  final String label;

  static TaskType named(String? name) => TaskType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => TaskType.other,
  );
}

enum MemberRole { master, coMaster, member }

class Classroom {
  const Classroom({
    required this.id,
    required this.title,
    required this.masterUid,
    required this.memberUids,
    required this.inviteCode,
    required this.createdAt,
    this.description = '',
    this.constraints = '',
    this.taskType = TaskType.other,
    this.individual = false,
    this.coMasterUids = const [],
    this.deadline,
    this.hoursPerWeek,
    this.approvalRequired = false,
    this.joinApprovalRequired = false,
  });

  final String id;
  final String title;
  final String description;

  /// What the plan must respect, in the person's own words, such as "study
  /// thermodynamics before waves". Optional. The AI planner reads it.
  final String constraints;
  final TaskType taskType;
  final bool individual;
  final String masterUid;
  final List<String> coMasterUids;
  final List<String> memberUids;
  final DateTime? deadline;
  final double? hoursPerWeek;
  final String inviteCode;
  final bool approvalRequired;

  /// Whether a code only asks to join, for the master to accept.
  final bool joinApprovalRequired;
  final DateTime createdAt;

  MemberRole roleOf(String uid) {
    if (uid == masterUid) return MemberRole.master;
    return coMasterUids.contains(uid) ? MemberRole.coMaster : MemberRole.member;
  }

  /// Masters and co-masters can edit anyone's steps and all the phases.
  bool canManage(String uid) => roleOf(uid) != MemberRole.member;

  Classroom copyWith({
    String? title,
    String? description,
    String? constraints,
    List<String>? coMasterUids,
    List<String>? memberUids,
    bool? approvalRequired,
    bool? joinApprovalRequired,
    DateTime? deadline,
    double? hoursPerWeek,
  }) => Classroom(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    constraints: constraints ?? this.constraints,
    taskType: taskType,
    individual: individual,
    masterUid: masterUid,
    coMasterUids: coMasterUids ?? this.coMasterUids,
    memberUids: memberUids ?? this.memberUids,
    deadline: deadline ?? this.deadline,
    hoursPerWeek: hoursPerWeek ?? this.hoursPerWeek,
    inviteCode: inviteCode,
    approvalRequired: approvalRequired ?? this.approvalRequired,
    joinApprovalRequired: joinApprovalRequired ?? this.joinApprovalRequired,
    createdAt: createdAt,
  );
}

class ClassroomMember {
  const ClassroomMember({
    required this.uid,
    required this.name,
    this.lastSeenAt,
    this.photoUrl = '',
  });

  final String uid;
  final String name;
  final String photoUrl;

  /// When this person last looked at the classroom. Empty until their first
  /// visit ends, so a newcomer isn't shown everything as news.
  final DateTime? lastSeenAt;
}

/// Someone asking to join a classroom that needs approval.
class JoinRequest {
  const JoinRequest({required this.uid, required this.name});

  final String uid;
  final String name;
}

/// Shown in the profile, so anyone can tell which version they're running.
const String kAppVersion = '0.3.2';

/// Where the app lives on the web, for invite links.
const String kAppUrl = String.fromEnvironment(
  'OCTRIA_APP_URL',
  defaultValue: 'https://octria-9a410.web.app',
);

class PhaseRecord {
  const PhaseRecord({
    required this.id,
    required this.title,
    required this.order,
  });

  final String id;
  final String title;
  final int order;
}

/// What happened, in a form the "Since you were away" screen can sort.
enum ActivityKind {
  stepAdded,
  stepEdited,
  stepRemoved,
  stepStarted,
  stepFinished,
  stepReopened,
  stepSentForApproval,
  stepApproved,
  stepSentBack,
  stepHandedOver,
  dependencyChanged,
  phaseChanged,
  memberJoined;

  static ActivityKind named(String? name) => ActivityKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => ActivityKind.stepEdited,
  );
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.actorUid,
    required this.kind,
    required this.summary,
    required this.createdAt,
    this.targetId = '',
    this.affectsUid = '',
  });

  final String id;
  final String actorUid;
  final ActivityKind kind;

  /// One plain sentence, already naming who and what.
  final String summary;

  /// The step or phase it's about.
  final String targetId;

  /// The person whose work this changed, if it's someone else's.
  final String affectsUid;
  final DateTime createdAt;
}

/// Why something couldn't be done, in words the person can act on.
class BackendFailure implements Exception {
  const BackendFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Six letters and digits with the easily confused ones left out, so a code can
/// be read aloud.
String newInviteCode([math.Random? random]) {
  const letters = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final r = random ?? math.Random.secure();
  return String.fromCharCodes(
    List.generate(6, (_) => letters.codeUnitAt(r.nextInt(letters.length))),
  );
}
