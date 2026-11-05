import '../model/plan.dart';
import 'models.dart';

/// Everything about one classroom that the screen needs, as it stands now.
class ClassroomState {
  const ClassroomState({
    required this.classroom,
    required this.members,
    required this.phases,
    required this.steps,
  });

  final Classroom classroom;
  final List<ClassroomMember> members;
  final List<PhaseRecord> phases;
  final List<PlanStep> steps;
}

/// The app's one door to accounts and stored plans. The real one is Firebase;
/// tests and local runs use an in-memory one that keeps the same rules.
abstract class Backend {
  /// Fires with the signed-in person, or null when signed out.
  Stream<AppUser?> get user;
  AppUser? get currentUser;

  Future<void> signInWithEmail(String email, String password);
  Future<void> registerWithEmail(String name, String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> signInWithGoogle();
  Future<void> signInWithGitHub();
  Future<void> signOut();
  Future<void> saveProfile({required String name, required String bio});

  /// The classrooms this person belongs to, newest first.
  Stream<List<Classroom>> classrooms();

  /// Returns the new classroom's id. The creator becomes its master.
  Future<String> createClassroom({
    required String title,
    required String description,
    String constraints = '',
    required TaskType taskType,
    required bool individual,
    DateTime? deadline,
    double? hoursPerWeek,
  });

  /// Returns the classroom's id, or null if the request now waits for the
  /// master. Throws [BackendFailure] with a plain reason if the code is wrong or
  /// the classroom is full.
  Future<String?> joinWithCode(String code);

  /// Who's waiting to join. For the master and co-master.
  Stream<List<JoinRequest>> joinRequests(String classroomId);
  Future<void> approveJoin(String classroomId, JoinRequest request);
  Future<void> declineJoin(String classroomId, String uid);

  /// Leaves the classroom. A master's role passes to the first co-master; with
  /// none, this throws [BackendFailure] saying what to do.
  Future<void> leaveClassroom(String classroomId);

  /// Removes a classroom and everything in it, for everyone. Master only.
  Future<void> deleteClassroom(String classroomId);

  /// Removes this person from their classrooms, then their profile and account.
  Future<void> deleteAccount();

  Stream<ClassroomState> watchClassroom(String classroomId);

  Future<void> updateClassroom(Classroom classroom);
  Future<void> setCoMaster(String classroomId, String uid, bool coMaster);
  Future<void> removeMember(String classroomId, String uid);

  Future<void> savePhase(String classroomId, PhaseRecord phase);

  /// Removes a phase and every step in it.
  Future<void> deletePhase(String classroomId, String phaseId);

  Future<void> saveStep(String classroomId, PlanStep step);
  Future<void> deleteStep(String classroomId, String stepId);

  Future<void> logActivity(String classroomId, ActivityEntry entry);

  /// Newest first. With [since], only what happened after it.
  Future<List<ActivityEntry>> activity(
    String classroomId, {
    DateTime? since,
    int limit = 50,
  });

  /// The same log, kept up to date as things happen. Newest first.
  Stream<List<ActivityEntry>> activityFeed(
    String classroomId, {
    int limit = 50,
  });

  /// Removes one entry from the log. Master only.
  Future<void> deleteActivity(String classroomId, String entryId);

  /// Empties the log. Master only.
  Future<void> clearActivity(String classroomId);

  /// Remembers that this person has seen what's new, as of now.
  Future<void> markSeen(String classroomId);

  /// A new id for a phase, step or activity entry, usable before saving.
  String newId();
}
