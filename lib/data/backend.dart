import '../kanvas/kanvas_model.dart';
import '../model/plan.dart';

import 'dart:typed_data';

import 'drive.dart';
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

  // Files -------------------------------------------------------------------

  /// The person's own Google Drive, where their library files live.
  DriveStore get drive;

  /// The classroom's library: everyone's shared files, and this person's own
  /// private ones, newest first.
  Stream<List<LibraryFile>> files(String classroomId);

  /// Adds a file already in the person's Drive to the library.
  Future<void> addFile(String classroomId, LibraryFile file);

  /// Shows a file to the whole classroom, or keeps it to its owner. Owner only.
  Future<void> updateFile(String classroomId, LibraryFile file);

  /// Takes a file out of the library. Its owner or a master can; the file
  /// stays in its owner's Drive.
  Future<void> removeFile(String classroomId, String fileId);

  // Collaboration ---------------------------------------------------------

  /// Every study material and practice link in the classroom, newest first.
  Stream<List<StudyMaterial>> materials(String classroomId);

  /// Adds or replaces one. Only its owner can change it.
  Future<void> saveMaterial(String classroomId, StudyMaterial material);

  /// Its owner, the master or a co-master can remove it.
  Future<void> deleteMaterial(String classroomId, String materialId);

  /// The step's comments this person can see, oldest first: each is private to
  /// the step's owner and one other person.
  Stream<List<StepComment>> comments(String classroomId, String stepId);

  /// Adds to the private thread between the step's owner and [withUid].
  Future<void> addComment(
    String classroomId,
    String stepId,
    String text, {
    required String ownerUid,
    required String withUid,
  });

  /// Only its author can remove it.
  Future<void> deleteComment(
    String classroomId,
    String stepId,
    String commentId,
  );

  /// The suggestions this person can see: their own, and public ones. Newest
  /// first.
  Stream<List<Suggestion>> suggestions(String classroomId);
  Future<void> addSuggestion(String classroomId, Suggestion suggestion);

  /// Only the person it's for, the step's owner, can answer it.
  Future<void> answerSuggestion(
    String classroomId,
    String suggestionId,
    SuggestionStatus status,
  );

  /// Either person in it can show it to everyone, or make it private again.
  Future<void> setSuggestionPublic(
    String classroomId,
    String suggestionId,
    bool public,
  );

  /// The classroom chat, oldest first.
  Stream<List<ChatMessage>> chat(String classroomId);
  Future<void> sendChat(String classroomId, String text, {bool forEveryone});

  /// Says this person has, or hasn't, made the change a message suggests.
  Future<void> setApplied(String classroomId, String messageId, bool applied);

  /// Its author or the master can remove it.
  Future<void> deleteChat(String classroomId, String messageId);
  Future<void> markChatSeen(String classroomId);

  /// Private chats this person is in, latest first.
  Stream<List<ChatThread>> threads(String classroomId);

  /// Opens the chat between exactly these people, starting it if it's new.
  /// Two people always share the same chat. Returns its id.
  Future<String> openThread(String classroomId, List<String> participants);
  Stream<List<ChatMessage>> threadMessages(String classroomId, String threadId);
  Future<void> sendThreadMessage(
    String classroomId,
    String threadId,
    String text,
  );
  Future<void> markThreadRead(String classroomId, String threadId);

  /// Handover requests this person is part of; every one, for the master and
  /// co-masters.
  Stream<List<Handover>> handovers(String classroomId);

  /// Asks to give a step of yours to [toUid]. A member's request waits for the
  /// master; a master's or co-master's goes straight to the person.
  Future<void> requestHandover(
    String classroomId,
    String stepId,
    String toUid,
    String note,
  );

  /// The master or a co-master lets a member's request go on, or stops it.
  Future<void> reviewHandover(String classroomId, String stepId, bool approve);

  /// The person receiving the step takes it on, or turns it down.
  Future<void> answerHandover(String classroomId, String stepId, bool accept);

  /// Withdraws a request that hasn't been answered.
  Future<void> cancelHandover(String classroomId, String stepId);

  // Kanvas ----------------------------------------------------------------

  /// This person's own boards, latest first.
  Stream<List<KanvasBoard>> myBoards();

  /// Boards other people have shared with this person by name.
  Stream<List<KanvasBoard>> boardsSharedWithMe();

  /// One board, kept up to date. Null once it's gone or out of reach.
  Stream<KanvasBoard?> watchBoard(String ownerUid, String boardId);

  Future<KanvasBoard> createBoard({
    required String title,
    String folder = '',
    List<KShape> shapes = const [],
  });

  /// Saves what's on a board. Its owner and anyone it's shared with to edit
  /// can.
  Future<void> saveBoardShapes(
    String ownerUid,
    String boardId,
    List<KShape> shapes,
  );

  /// Keeps a small picture of an image on a board, so everyone who can see
  /// the board sees it without reaching into the owner's Drive. Keyed by the
  /// file's Drive id. Anyone who can change the board can.
  Future<void> saveBoardPreview(
    String ownerUid,
    String boardId,
    String fileId,
    Uint8List jpeg,
  );

  /// That picture, or null if there isn't one.
  Future<Uint8List?> boardPreview(
    String ownerUid,
    String boardId,
    String fileId,
  );

  /// Renames a board or moves it to a folder. Owner only.
  Future<void> updateBoardInfo(String boardId, {String? title, String? folder});
  Future<void> deleteBoard(String boardId);

  /// Who can see or change a board, besides its owner. A board can be shared
  /// with one classroom at a time.
  Future<void> shareBoard(
    String boardId, {
    required Map<String, ShareMode> people,
    required String classroomId,
    required ShareMode classroomMode,
  });

  /// Saved copies of a board, newest first.
  Future<List<KanvasVersion>> boardVersions(String ownerUid, String boardId);
  Future<void> saveBoardVersion(
    String ownerUid,
    String boardId,
    List<KShape> shapes,
  );

  /// Boards shared with a classroom, including those pinned to its steps.
  Stream<List<ClassroomBoard>> classroomBoards(String classroomId);

  /// Pins one of this person's boards to a step, which shares it with the
  /// classroom to read.
  Future<void> pinBoard(String classroomId, String boardId, String stepId);
  Future<void> unpinBoard(String classroomId, String boardId);

  /// Offers this person is part of, sent or received. Newest first.
  Stream<List<Offer>> offers(String classroomId);

  /// Offers a board or a study material to someone. A board is shared with
  /// them straight away so they can look before deciding.
  Future<void> makeOffer(String classroomId, Offer offer);

  /// The receiver takes it or turns it down. An accepted material joins their
  /// step's study materials; a declined board stops being shared with them.
  Future<void> answerOffer(String classroomId, Offer offer, bool accept);

  /// Stops a board someone shared with this person being shared with them.
  Future<void> leaveBoard(String ownerUid, String boardId);

  /// Leaves a note in someone else's inbox.
  Future<void> notify(String uid, Notice notice);

  /// This person's inbox, newest first.
  Future<List<Notice>> inbox();

  /// When this person last opened their notifications. Null before the first
  /// time.
  Future<DateTime?> notificationsSeenAt();
  Future<void> markNotificationsSeen();
}
