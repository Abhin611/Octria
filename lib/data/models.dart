/// What the app stores about people and classrooms, apart from the plan itself.
library;

import 'dart:math' as math;

import '../model/plan.dart';

/// The most people a classroom can hold.
const int kMaxMembers = 10;

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    this.email = '',
    this.photoUrl = '',
    this.bio = '',
    this.skills = const [],
  });

  final String uid;
  final String name;
  final String email;
  final String photoUrl;
  final String bio;

  /// What they're good at, in their own words, such as "Flutter". Ofy uses
  /// it to share work out. Anyone signed in can read it.
  final List<String> skills;

  AppUser copyWith({String? name, String? bio, List<String>? skills}) =>
      AppUser(
        uid: uid,
        name: name ?? this.name,
        email: email,
        photoUrl: photoUrl,
        bio: bio ?? this.bio,
        skills: skills ?? this.skills,
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
    this.linked = false,
    this.roles = const {},
    this.checkKind = '',
  });

  /// How the group checks its progress after each phase: `tests` (mock
  /// tests), `checks` (checklists), `both`, `none`, or the person's own word.
  /// Empty means it hasn't been chosen, and the kind of task decides.
  final String checkKind;

  /// [checkKind], or what suits the kind of task when none was chosen.
  String get checking => checkKind.isNotEmpty
      ? checkKind
      : switch (taskType) {
          TaskType.study || TaskType.research => 'tests',
          TaskType.build || TaskType.eventOrCreative => 'checks',
          TaskType.other => 'checks',
        };

  /// What the point after each phase is called, for its tab.
  String get checkLabel => switch (checking) {
    'tests' => 'Mock tests',
    'checks' => 'Checklists',
    'both' => 'Mock tests and checks',
    'none' => '',
    final other => other,
  };

  final String id;
  final String title;
  final String description;

  /// For a group: whether its people work together, each learning or doing a
  /// part and then sharing it with the others (a study group), rather than
  /// each following their own steps. Ofy plans joint steps when they do.
  final bool linked;

  /// What each person does, by uid, such as "Front end". Set by the master.
  final Map<String, String> roles;

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
    bool? linked,
    Map<String, String>? roles,
    String? checkKind,
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
    linked: linked ?? this.linked,
    roles: roles ?? this.roles,
    checkKind: checkKind ?? this.checkKind,
  );
}

class ClassroomMember {
  const ClassroomMember({
    required this.uid,
    required this.name,
    this.lastSeenAt,
    this.chatSeenAt,
    this.photoUrl = '',
  });

  final String uid;
  final String name;
  final String photoUrl;

  /// When this person last opened the classroom chat.
  final DateTime? chatSeenAt;

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
const String kAppVersion = '0.15.1';

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
  memberJoined,
  commented,
  suggested,
  suggestionAnswered,
  materialAdded;

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

// Collaboration -----------------------------------------------------------

/// What kind of thing a study material is. Practice links live in the
/// classroom's Practice page rather than on a step.
enum MaterialKind {
  link('Link'),
  video('Video'),
  note('Note'),
  repo('Repository'),
  practice('Practice');

  const MaterialKind(this.label);
  final String label;

  static MaterialKind named(String? name) => MaterialKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => MaterialKind.link,
  );

  /// A guess from the address, which the person can change.
  static MaterialKind guess(String url) {
    final host = Uri.tryParse(webAddress(url) ?? '')?.host.toLowerCase() ?? '';
    bool on(String site) => host == site || host.endsWith('.$site');
    if (on('youtube.com') || on('youtu.be') || on('vimeo.com')) {
      return MaterialKind.video;
    }
    if (on('github.com') || on('gitlab.com') || on('bitbucket.org')) {
      return MaterialKind.repo;
    }
    return MaterialKind.link;
  }
}

/// The address as a web link that's safe to open, or null if it isn't one.
/// A missing scheme gets https; anything other than http or https is refused.
String? webAddress(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.contains(' ')) return null;
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasAuthority || !uri.host.contains('.')) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri.toString();
}

/// A link, video, note or repository attached to a step, or a practice link.
class StudyMaterial {
  const StudyMaterial({
    required this.id,
    required this.kind,
    required this.title,
    required this.ownerUid,
    required this.createdAt,
    this.url = '',
    this.note = '',
    this.stepId = '',
  });

  final String id;
  final MaterialKind kind;
  final String title;

  /// Empty for a note.
  final String url;
  final String note;
  final String ownerUid;

  /// The step it belongs to. Empty for a practice link.
  final String stepId;
  final DateTime createdAt;

  /// The site's name, for the line under the title.
  String get site {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

/// A file in a classroom's library. The file itself is in its owner's Google
/// Drive; Octria keeps only its name, size and link.
class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.url,
    required this.ownerUid,
    required this.createdAt,
    this.stepId = '',
    this.shared = true,
  });

  /// The file's id in Drive.
  final String id;
  final String name;
  final String mimeType;
  final int size;

  /// Where it opens in Drive.
  final String url;
  final String ownerUid;

  /// The step it's for, or empty for the whole classroom.
  final String stepId;

  /// Whether everyone in the classroom sees it, or only its owner.
  final bool shared;
  final DateTime createdAt;

  LibraryFile copyWith({bool? shared, String? stepId}) => LibraryFile(
    id: id,
    name: name,
    mimeType: mimeType,
    size: size,
    url: url,
    ownerUid: ownerUid,
    createdAt: createdAt,
    stepId: stepId ?? this.stepId,
    shared: shared ?? this.shared,
  );
}

/// One message in a private thread on a step, between the step's owner and one
/// other person. Nobody else can read it.
class StepComment {
  const StepComment({
    required this.id,
    required this.authorUid,
    required this.text,
    required this.createdAt,
    required this.participants,
  });

  final String id;
  final String authorUid;
  final String text;
  final DateTime createdAt;

  /// The step's owner and the other person in the thread.
  final List<String> participants;

  /// The person in the thread who isn't [owner].
  String other(String owner) =>
      participants.firstWhere((u) => u != owner, orElse: () => owner);
}

enum SuggestionStatus { open, accepted, dismissed }

/// An idea for someone else's step. Private to the two people by default;
/// either of them can show it to the whole classroom. Only the step's owner
/// accepts or dismisses it, and accepting doesn't change the step: they make
/// the change themselves.
class Suggestion {
  const Suggestion({
    required this.id,
    required this.stepId,
    required this.fromUid,
    required this.toUid,
    required this.text,
    required this.createdAt,
    this.status = SuggestionStatus.open,
    this.public = false,
    this.publicAt,
  });

  final String id;
  final String stepId;
  final String fromUid;
  final String toUid;
  final String text;
  final SuggestionStatus status;

  /// Whether everyone in the classroom can see it.
  final bool public;
  final DateTime? publicAt;
  final DateTime createdAt;

  bool involves(String uid) => uid == fromUid || uid == toUid;

  Suggestion copyWith({SuggestionStatus? status, bool? public}) => Suggestion(
    id: id,
    stepId: stepId,
    fromUid: fromUid,
    toUid: toUid,
    text: text,
    createdAt: createdAt,
    status: status ?? this.status,
    public: public ?? this.public,
    publicAt: (public ?? this.public) ? (publicAt ?? DateTime.now()) : null,
  );
}

/// A message in the classroom chat, which everyone in it can read. One marked
/// [forEveryone] is a suggestion for the whole group, and each person can say
/// they've made that change.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.authorUid,
    required this.text,
    required this.createdAt,
    this.forEveryone = false,
    this.appliedBy = const [],
  });

  final String id;
  final String authorUid;
  final String text;
  final DateTime createdAt;
  final bool forEveryone;

  /// Who has made the change this suggests.
  final List<String> appliedBy;
}

/// Something addressed to one person, in a classroom. Kept in their own inbox,
/// which only they can read, so private comments stay private.
class Notice {
  const Notice({required this.classroomId, required this.entry});

  final String classroomId;
  final ActivityEntry entry;
}

/// Limits that `firestore.rules` also enforces.
const int kMaxCommentLength = 2000;
const int kMaxNoteLength = 5000;
const int kMaxTitleLength = 200;

/// A private conversation inside a classroom: two people, or a small group.
/// Only the people in it can read it.
class ChatThread {
  const ChatThread({
    required this.id,
    required this.participants,
    this.lastAt,
    this.lastText = '',
    this.lastBy = '',
    this.readAt = const {},
    this.hiddenBy = const [],
  });

  final String id;
  final List<String> participants;

  /// People who deleted this chat from their lists. It stays in their
  /// Deleted chats, ready to bring back, and everyone else still has it.
  final List<String> hiddenBy;

  bool hiddenFor(String uid) => hiddenBy.contains(uid);

  ChatThread copyWith({
    DateTime? lastAt,
    String? lastText,
    String? lastBy,
    Map<String, DateTime>? readAt,
    List<String>? hiddenBy,
  }) => ChatThread(
    id: id,
    participants: participants,
    lastAt: lastAt ?? this.lastAt,
    lastText: lastText ?? this.lastText,
    lastBy: lastBy ?? this.lastBy,
    readAt: readAt ?? this.readAt,
    hiddenBy: hiddenBy ?? this.hiddenBy,
  );
  final DateTime? lastAt;
  final String lastText;
  final String lastBy;

  /// When each person last read it.
  final Map<String, DateTime> readAt;

  bool unreadFor(String uid) {
    final last = lastAt;
    if (last == null || lastBy == uid || lastBy.isEmpty) return false;
    final read = readAt[uid];
    return read == null || last.isAfter(read);
  }

  /// The same id for the same two people, whoever starts it.
  static String directId(String a, String b) {
    final pair = [a, b]..sort();
    return 'dm_${pair[0]}_${pair[1]}';
  }
}

/// One practice set or mock test someone finished: what it covered and how it
/// went. Private to the person who took it.
class TestResult {
  const TestResult({
    required this.id,
    required this.classroomId,
    required this.label,
    required this.right,
    required this.total,
    required this.at,
    this.targetId = '',
    this.mock = false,
    this.missed = const [],
    this.level = '',
    this.interview = false,
  });

  /// `easy` or `hard`; empty for the usual level.
  final String level;

  /// A mock interview, answered in the person's own words and marked by Ofy.
  final bool interview;

  /// What kind of test it was, for lists.
  String get kindLabel => [
    interview ? 'Mock interview' : (mock ? 'Mock test' : 'Practice'),
    if (level == 'easy') 'easier',
    if (level == 'hard') 'harder',
  ].join(', ');

  final String id;
  final String classroomId;

  /// What it was on, as shown above the questions.
  final String label;

  /// The step, phase or point it covered; empty for the whole plan.
  final String targetId;
  final int right;
  final int total;

  /// A mock test rather than practice.
  final bool mock;

  /// The questions they got wrong, to look at again.
  final List<String> missed;
  final DateTime at;

  /// From 0 to 1.
  double get score => total == 0 ? 0 : right / total;
  int get percent => (score * 100).round();
}

enum TrashKind { step, phase }

/// A deleted step, or a deleted phase with the steps that were in it, kept so
/// it can be brought back.
class TrashItem {
  const TrashItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.deletedBy,
    required this.deletedAt,
    this.phase,
    this.steps = const [],
  });

  final String id;
  final TrashKind kind;
  final String title;
  final String deletedBy;
  final DateTime deletedAt;

  /// The phase, when a phase was deleted.
  final PhaseRecord? phase;

  /// The step that was deleted, or every step the phase held.
  final List<PlanStep> steps;
}

/// Where a request to hand a step to someone else has got to.
enum HandoverStatus { needsMaster, needsReceiver, accepted, declined }

/// A request to give one of your steps to someone else. A member's request goes
/// to the master first; then the person receiving it decides.
class Handover {
  const Handover({
    required this.stepId,
    required this.fromUid,
    required this.toUid,
    required this.status,
    required this.createdAt,
    this.note = '',
  });

  final String stepId;
  final String fromUid;
  final String toUid;
  final HandoverStatus status;
  final String note;
  final DateTime createdAt;

  bool get open =>
      status == HandoverStatus.needsMaster ||
      status == HandoverStatus.needsReceiver;
}

enum OfferKind { board, material }

enum OfferStatus { pending, accepted, declined }

/// Something one person offers another, which waits in the receiver's
/// Important notes until they accept or decline it: a Kanvas board shared
/// with them, or a study material for their step. Only the two of them can
/// see it.
class Offer {
  const Offer({
    required this.id,
    required this.kind,
    required this.fromUid,
    required this.toUid,
    required this.createdAt,
    this.status = OfferStatus.pending,
    this.stepId = '',
    this.title = '',
    this.boardOwner = '',
    this.boardId = '',
    this.edit = false,
    this.materialKind = MaterialKind.link,
    this.url = '',
    this.note = '',
  });

  final String id;
  final OfferKind kind;
  final String fromUid;
  final String toUid;
  final OfferStatus status;
  final DateTime createdAt;

  /// The step it's for, if any.
  final String stepId;
  final String title;

  /// A board: whose, which, and whether they may change it.
  final String boardOwner;
  final String boardId;
  final bool edit;

  /// A study material.
  final MaterialKind materialKind;
  final String url;
  final String note;

  /// "Request pending" or "Request accepted", as everyone reads it.
  String get statusLabel => switch (status) {
    OfferStatus.pending => 'Request pending',
    OfferStatus.accepted => 'Request accepted',
    OfferStatus.declined => 'Declined',
  };
}

/// What a handover's state reads as in a list.
String handoverLabel(HandoverStatus s) => switch (s) {
  HandoverStatus.needsMaster => 'Request pending',
  HandoverStatus.needsReceiver => 'Acceptance pending',
  HandoverStatus.accepted => 'Request accepted',
  HandoverStatus.declined => 'Declined',
};
