import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../data/plan_sync.dart';
import '../graph/camera.dart';
import '../graph/graph_painter.dart';
import '../graph/graph_view.dart';
import '../graph/layout.dart';
import '../graph/plan_controller.dart';
import '../model/plan.dart';
import '../model/sample_plans.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../ofy/ofy.dart';
import '../widgets/glass_menu.dart';
import '../widgets/glass_motion.dart';
import '../widgets/spring_sheet.dart';
import '../model/calendar.dart';
import 'calendar_sheet.dart';
import 'replan_sheet.dart';
import 'classroom_forms.dart';
import 'map_key.dart';
import 'plan_views.dart';
import 'chat_sheet.dart';
import 'files_sheet.dart';
import 'plan_draft_sheet.dart';
import 'practice_points.dart';
import 'practice_sheet.dart';
import 'step_collab.dart';
import 'step_panel.dart';
import 'requests_sheets.dart';
import 'room_lists.dart';
import 'threads_sheet.dart';
import 'timeline_view.dart';
import 'skills_sheets.dart';
import '../graph/plan_changes.dart';

enum PlanView { graph, timeline, list }

const double _narrowWidth = 840;
const double _shortHeight = 500;
const double _shortRowHeight = 112;
const double _verticalCellWidth = 200;
const double _verticalRowHeight = 196;
const double _shortVerticalRowHeight = 150;

/// A view of one whole phase is only worth opening on at this zoom or closer.
const double _readableScale = 0.5;

/// How many people's steps the opening view tries to show at once.
const int _peopleToShow = 3;
const double _sidebarWidth = 232;
const double _panelWidth = 360;

/// Below this the graph is too small to spare room for a minimap.
const double _mapMinWidth = 600;

/// Heights of the floating bars, fixed so the canvas knows what they cover.
const double _barHeight = 52;
const double _shortBarHeight = 44;
const double _tabBarHeight = 56;
const double _tabBarWidth = 340;

/// A wide toolbar narrower than this drops its button labels.
const double _labelledToolbarWidth = 900;

/// The row of zoom buttons and next step above a phone's tab bar.
const double _phoneRowHeight = 56;

class _Notice {
  const _Notice(this.message, {this.actionLabel, this.action});
  final String message;
  final String? actionLabel;
  final VoidCallback? action;
}

/// A stored classroom to open, rather than the sample plans.
class ClassroomSession {
  const ClassroomSession({required this.backend, required this.classroomId});

  final Backend backend;
  final String classroomId;
}

class ClassroomScreen extends StatefulWidget {
  const ClassroomScreen({
    super.key,
    required this.onBrightnessChanged,
    this.session,
  });

  final ClassroomSession? session;

  /// Asks the app to switch between the white and dark backgrounds.
  final ValueChanged<Brightness> onBrightnessChanged;

  @override
  State<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends State<ClassroomScreen>
    with TickerProviderStateMixin {
  static final _plans = <Plan Function()>[
    campusEventsPlan,
    physicsExamPlan,
    stressPlan,
  ];
  static const _planNames = [
    'Campus Events App',
    'Exam prep: Physics',
    'Stress test: 600 steps',
  ];

  late final PlanController _controller = PlanController(
    widget.session == null
        ? _plans.first()
        : Plan(
            title: '',
            members: const [],
            phases: const [],
            steps: const [],
            meId: widget.session!.backend.currentUser?.uid ?? '',
            today: DateTime.now(),
          ),
    this,
  );
  late final GraphCamera _camera = GraphCamera(this);
  late final AnimationController _focus = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final AnimationController _celebration = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  int _planIndex = 0;
  PlanView _view = PlanView.graph;
  GraphFilter _filter = const GraphFilter();
  String? _selectedId;
  String? _lastSelectedId;
  String? _celebrateId;

  /// A re-plan playing back on the graph.
  late final AnimationController _changing = AnimationController(vsync: this);
  PlanChanges? _changes;
  String? _linkFromId;
  (String, String)? _selectedEdge;
  GraphDirection _direction = GraphDirection.leftToRight;
  bool _focusOn = false;
  bool _filterOpen = false;
  bool _keyOpen = false;
  (String, Offset)? _menu;
  _Notice? _notice;
  Timer? _noticeTimer;
  int _graphEpoch = 0;
  int _framedEpoch = -1;
  bool? _framedWide;
  PlanSync? _sync;
  ClassroomState? _stored;
  StreamSubscription<List<ActivityEntry>>? _feed;
  List<ActivityEntry> _feedEntries = const [];
  List<ActivityEntry> _forMe = const [];
  DateTime? _seenAt;

  /// Changes for this person they haven't looked at yet.
  int get _unread {
    final seen = _seenAt;
    if (seen == null) return 0;
    return _forMe.where((e) => e.createdAt.isAfter(seen)).length;
  }

  Plan get _plan => _controller.plan;
  Backend? get _backend => widget.session?.backend;
  String get _classroomId => widget.session?.classroomId ?? '';
  Classroom? get _room => _stored?.classroom;
  String get _me => _plan.meId;

  /// Offers one step, or this person's and everyone's unfinished steps, for
  /// their own calendar.
  void _showCalendar({String? stepId}) {
    CalEvent event(PlanStep s) =>
        eventForStep(s, room: _plan.title, phase: _plan.phase(s.phaseId).title);
    final one = _plan.steps[stepId];
    final mine = stepsToSchedule(_plan.steps.values, owner: _me);
    final all = stepsToSchedule(_plan.steps.values);
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => CalendarSheet(
          fileName: calendarFileName(one?.title ?? _plan.title),
          choices: one != null
              ? [
                  ('This step', [event(one)]),
                ]
              : [
                  ('My steps', mine.map(event).toList()),
                  if (all.length != mine.length)
                    ('Everyone’s steps', all.map(event).toList()),
                ],
        ),
      ),
    );
  }

  /// Masters and co-masters. With sample plans there's nobody to answer to.
  bool get _manages => _room?.canManage(_me) ?? widget.session == null;
  bool get _isMaster => _room?.masterUid == _me;

  bool _canEdit(String id) => _manages || _plan.steps[id]?.ownerId == _me;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPlanChanged);
    final session = widget.session;
    if (session != null) {
      _sync = PlanSync(
        backend: session.backend,
        classroomId: session.classroomId,
        controller: _controller,
        onRefused: (message) {
          if (mounted) _showNotice(message);
        },
        onState: _onStored,
      );
      _chatFeed = session.backend.chat(session.classroomId).listen((messages) {
        if (mounted) setState(() => _chatMessages = messages);
      }, onError: (Object _) {});
      _threadFeed = session.backend.threads(session.classroomId).listen((list) {
        if (mounted) {
          setState(
            () => _threads = [
              for (final t in list)
                if (!t.hiddenFor(session.backend.currentUser?.uid ?? '')) t,
            ],
          );
        }
      }, onError: (Object _) {});
      _offerFeed = session.backend.offers(session.classroomId).listen((list) {
        if (mounted) setState(() => _offers = list);
      }, onError: (Object _) {});
      _suggestionFeed = session.backend.suggestions(session.classroomId).listen(
        (list) {
          if (mounted) setState(() => _suggestions = list);
        },
        onError: (Object _) {},
      );
      _handoverFeed = session.backend.handovers(session.classroomId).listen((
        list,
      ) {
        if (mounted) setState(() => _handovers = list);
      }, onError: (Object _) {});
      _feed = session.backend.activityFeed(session.classroomId).listen((
        entries,
      ) {
        _feedEntries = entries;
        _refreshNews();
      }, onError: (Object _) {});
    }
  }

  void _onStored(ClassroomState state) {
    if (!mounted) return;
    final first = _stored == null;
    final hadSteps = _stored?.steps.isNotEmpty ?? false;
    setState(() {
      _stored = state;
      // A plan's first steps are worth framing; later ones keep the camera put.
      if (first || (!hadSteps && state.steps.isNotEmpty)) _graphEpoch++;
    });
    if (first) _startCounting(state);
    _refreshNews();
  }

  /// Sets where the red count starts from: their last look, or now on a first
  /// visit, when nothing that came before is news.
  void _startCounting(ClassroomState state) {
    DateTime? lastSeen;
    for (final m in state.members) {
      if (m.uid == _me) lastSeen = m.lastSeenAt;
    }
    if (lastSeen == null) _markSeen();
    _seenAt = lastSeen ?? DateTime.now();
  }

  void _markSeen() =>
      unawaited(_backend?.markSeen(_classroomId).catchError((Object _) {}));

  void _refreshNews() {
    final state = _stored;
    if (state == null || !mounted) return;
    final forMe = awayNews(_feedEntries, _me, state.steps);
    setState(() => _forMe = forMe);
    final seen = _seenAt;
    final changed = {
      for (final e in forMe)
        if (seen != null && e.createdAt.isAfter(seen) && e.targetId.isNotEmpty)
          e.targetId,
    };
    // Badges on the graph, only when the set really changes.
    if (!setEquals(changed, _badged)) {
      _badged = changed;
      _sync?.showChanged(changed);
    }
  }

  Set<String> _badged = const {};

  /// "Since you were away": opening it is what clears the red count.
  void _showAwayNews() {
    final fresh = _unread;
    final entries = _forMe;
    if (fresh > 0) {
      _markSeen();
      setState(() => _seenAt = entries.first.createdAt);
      _refreshNews();
    }
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ActivitySheet(
          title: 'Since you were away',
          intro: 'Changes that affect you, newest first.',
          empty:
              'Nothing yet. A red number appears here when someone changes '
              'your steps, or finishes a step yours need.',
          entries: entries,
          newCount: fresh,
        ),
      ),
    );
  }

  void _showProfile() {
    final backend = _backend;
    if (backend == null) return;
    unawaited(
      showGlassSheet<void>(context, (_) => ProfileSheet(backend: backend)),
    );
  }

  void _showMore() {
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => GlassMenuSheet(
          title: _room?.title ?? 'Classroom',
          sections: _menuSections(withAddStep: _isShort(context)),
          onReopen: _showMore,
        ),
      ),
    );
  }

  Future<void> _showActivity() async {
    final backend = _backend;
    if (backend == null) return;
    final List<ActivityEntry> entries;
    try {
      entries = await backend.activity(_classroomId);
    } on Object {
      _showNotice('The activity log couldn’t load. Please retry.');
      return;
    }
    if (!mounted) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ActivitySheet(
          title: 'Activity',
          entries: entries,
          backend: _isMaster ? backend : null,
          classroomId: _isMaster ? _classroomId : null,
        ),
      ),
    );
  }

  Future<void> _showPhases() async {
    final state = _stored;
    final backend = _backend;
    if (state == null || backend == null) return;
    await showGlassSheet<void>(
      context,
      (_) => PhasesSheet(
        backend: backend,
        classroomId: _classroomId,
        phases: state.phases,
        steps: state.steps,
      ),
    );
  }

  void _showMembers() {
    final state = _stored;
    final backend = _backend;
    if (state == null || backend == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => MembersSheet(backend: backend, state: state),
      ),
    );
  }

  Future<void> _leaveClassroom() async {
    final backend = _backend;
    if (backend == null) return;
    final sure = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Leave this classroom?'),
        content: Text(
          _isMaster
              ? 'The co-master becomes master. Your steps stay in the plan.'
              : 'Your steps stay in the plan, under the master. You’d need the '
                    'code to come back.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await backend.leaveClassroom(_classroomId);
      navigator.pop();
    } on BackendFailure catch (e) {
      if (mounted) _showNotice(e.message);
    }
  }

  /// Another step this one has to wait for. Steps that would make a loop
  /// aren't offered.
  void _pickNeed(PlanStep step) {
    final options = [
      for (final s in _plan.steps.values)
        if (s.id != step.id &&
            !step.dependsOn.contains(s.id) &&
            !_plan.wouldCycle(step.id, s.id))
          s,
    ]..sort((a, b) => a.due.compareTo(b.due));
    if (options.isEmpty) {
      _showNotice('No other step can be added without making a loop.');
      return;
    }
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ActionListSheet(
          title: 'It needs…',
          items: [
            for (final s in options)
              (
                '${s.title} · ${_plan.member(s.ownerId).name}',
                0,
                () => _link(s.id, step.id),
              ),
          ],
        ),
      ),
    );
  }

  List<ChatMessage> _chatMessages = const [];
  List<ChatThread> _threads = const [];
  StreamSubscription<List<ChatThread>>? _threadFeed;
  List<Handover> _handovers = const [];
  StreamSubscription<List<Handover>>? _handoverFeed;

  /// Everything new behind the More button.
  int get _moreCount =>
      _unread + _unreadChat + _unreadThreads + _handoversForMe;

  List<Offer> _offers = const [];
  StreamSubscription<List<Offer>>? _offerFeed;
  List<Suggestion> _suggestions = const [];
  StreamSubscription<List<Suggestion>>? _suggestionFeed;

  /// Everything waiting on this person to accept or decline here.
  int get _importantCount =>
      _handoversForMe +
      _offers
          .where((o) => o.toUid == _me && o.status == OfferStatus.pending)
          .length +
      _suggestions
          .where((s) => s.toUid == _me && s.status == SuggestionStatus.open)
          .length;

  RoomContext? get _roomContext {
    final s = _stored;
    return s == null ? null : RoomContext.of(s, _me);
  }

  void _showImportant() {
    final backend = _backend;
    final room = _roomContext;
    if (backend == null || room == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ImportantSheet(backend: backend, rooms: [room]),
      ),
    );
  }

  /// The + beside a step: link it, send its owner something, or suggest.
  void _stepPlus(String id) {
    final backend = _backend;
    final room = _roomContext;
    final step = _plan.steps[id];
    if (step == null) return;
    if (backend == null || room == null) {
      _select(id);
      setState(() => _linkFromId = id);
      return;
    }
    final mine = step.ownerId == _me;
    final owner = _plan.member(step.ownerId).name;
    Future<void> guard(Future<void> Function() run, String done) async {
      try {
        await run();
        _showNotice(done);
      } on BackendFailure catch (e) {
        _showNotice(e.message);
      }
    }

    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ActionListSheet(
          title: '“${step.title}”',
          items: [
            if (_canEdit(id))
              (
                'Link it to another step',
                0,
                () => setState(() => _linkFromId = id),
              ),
            if (mine) ...[
              (
                'Add a study material',
                0,
                () async {
                  final made = await showGlassSheet<StudyMaterial>(
                    context,
                    (_) => MaterialEditorSheet(
                      newId: backend.newId,
                      ownerUid: _me,
                      stepId: id,
                    ),
                  );
                  if (made == null) return;
                  await guard(
                    () => backend.saveMaterial(_classroomId, made),
                    'Added to your study materials',
                  );
                },
              ),
              ('Open the step', 0, () => _select(id)),
            ] else ...[
              (
                'Send $owner a study material',
                0,
                () => guard(
                  () => offerMaterial(
                    context,
                    backend: backend,
                    room: room,
                    step: step,
                  ),
                  'Sent. It waits for $owner to accept.',
                ),
              ),
              (
                'Share a board with $owner',
                0,
                () => guard(
                  () => offerBoard(
                    context,
                    backend: backend,
                    room: room,
                    step: step,
                  ),
                  'Shared. It waits for $owner to accept.',
                ),
              ),
              (
                'Suggest a change',
                0,
                () => suggestChange(
                  context,
                  backend: backend,
                  classroomId: _classroomId,
                  plan: _plan,
                  step: step,
                  onNotice: _showNotice,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _newHandover() async {
    final picked = await showGlassSheet<(String, String, String)>(
      context,
      (_) => NewHandoverSheet(plan: _plan, viaMaster: !_manages),
    );
    if (picked == null || !mounted) return;
    await _sendHandover(picked.$1, picked.$2, picked.$3);
  }

  int get _unreadThreads => _threads.where((t) => t.unreadFor(_me)).length;

  /// Handover requests waiting on this person to decide.
  int get _handoversForMe => _handovers
      .where(
        (h) =>
            (h.status == HandoverStatus.needsMaster && _manages) ||
            (h.status == HandoverStatus.needsReceiver && h.toUid == _me),
      )
      .length;

  /// A private chat with just these people (and this person).
  Future<void> _openChatWith(List<String> people) async {
    final backend = _backend;
    if (backend == null) return;
    final others = people.where((u) => u != _me).toList();
    if (others.isEmpty) {
      _showNotice('That’s you. Tap someone else to message them.');
      return;
    }
    final String id;
    try {
      id = await backend.openThread(_classroomId, others);
    } on BackendFailure catch (e) {
      _showNotice(e.message);
      return;
    }
    if (!mounted) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ThreadSheet(
          backend: backend,
          classroomId: _classroomId,
          threadId: id,
          plan: _plan,
          participants: [_me, ...others],
        ),
      ),
    );
  }

  void _showChats() {
    final backend = _backend;
    if (backend == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ChatsSheet(
          backend: backend,
          classroomId: _classroomId,
          plan: _plan,
          masterUid: _room?.masterUid ?? '',
          onOpen: _openChatWith,
          onNewGroup: _newGroupChat,
        ),
      ),
    );
  }

  Future<void> _newGroupChat() async {
    final picked = await showGlassSheet<List<String>>(
      context,
      (_) => GroupPickerSheet(plan: _plan),
    );
    if (picked == null || picked.length < 2 || !mounted) return;
    await _openChatWith(picked);
  }

  /// Asks to give one of this person's steps to someone else: through the
  /// master for a member, straight to the person for a master or co-master.
  Future<void> _requestHandover(String stepId, String toUid) async {
    final backend = _backend;
    final step = _plan.steps[stepId];
    if (backend == null || step == null || toUid == step.ownerId) return;
    if (step.ownerId != _me) {
      _showNotice('Only the person whose step it is can hand it over.');
      return;
    }
    final to = _plan.member(toUid).name;
    final viaMaster = !_manages;
    final note = await showGlassSheet<String>(
      context,
      (_) => HandoverRequestSheet(
        stepTitle: step.title,
        to: to,
        viaMaster: viaMaster,
      ),
    );
    if (note == null || !mounted) return;
    await _sendHandover(stepId, toUid, note);
  }

  Future<void> _sendHandover(String stepId, String toUid, String note) async {
    final backend = _backend;
    final step = _plan.steps[stepId];
    if (backend == null || step == null) return;
    final to = _plan.member(toUid).name;
    final viaMaster = !_manages;
    try {
      await backend.requestHandover(_classroomId, stepId, toUid, note);
    } on BackendFailure catch (e) {
      _showNotice(e.message);
      return;
    }
    final me = _plan.member(_me).name;
    final master = _room?.masterUid ?? '';
    final tellUid = viaMaster ? master : toUid;
    if (tellUid.isNotEmpty && tellUid != _me) {
      unawaited(
        backend
            .notify(
              tellUid,
              Notice(
                classroomId: _classroomId,
                entry: ActivityEntry(
                  id: '',
                  actorUid: _me,
                  kind: ActivityKind.stepHandedOver,
                  summary: viaMaster
                      ? '$me asked to hand “${step.title}” to $to'
                            '${note.isEmpty ? '' : ': ${clipLine(note)}'}'
                      : '$me wants to hand you “${step.title}”'
                            '${note.isEmpty ? '' : ': ${clipLine(note)}'}',
                  targetId: stepId,
                  affectsUid: tellUid,
                  createdAt: DateTime.now(),
                ),
              ),
            )
            .catchError((Object _) {}),
      );
    }
    _showNotice(
      viaMaster
          ? 'Asked the master to hand it to $to'
          : 'Asked $to to take it on',
    );
  }

  void _showHandovers() {
    final backend = _backend;
    final room = _roomContext;
    if (backend == null || room == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => HandoversSheet(
          backend: backend,
          room: room,
          onOpenStep: _goTo,
          onNew: () => unawaited(_newHandover()),
        ),
      ),
    );
  }

  StreamSubscription<List<ChatMessage>>? _chatFeed;

  /// Messages from others since this person last opened the chat.
  int get _unreadChat {
    final state = _stored;
    if (state == null) return 0;
    DateTime? seen;
    for (final m in state.members) {
      if (m.uid == _me) seen = m.chatSeenAt;
    }
    return _chatMessages
        .where(
          (m) =>
              m.authorUid != _me && (seen == null || m.createdAt.isAfter(seen)),
        )
        .length;
  }

  void _showChat() {
    final backend = _backend;
    if (backend == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ChatSheet(
          backend: backend,
          classroomId: _classroomId,
          plan: _plan,
          isMaster: _isMaster,
        ),
      ),
    );
  }

  void _showSharedBoards() {
    final backend = _backend;
    final room = _roomContext;
    if (backend == null || room == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => SharedBoardsSheet(backend: backend, room: room),
      ),
    );
  }

  void _showFiles() {
    final backend = _backend;
    final room = _room;
    if (backend == null || room == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => FilesSheet(
          backend: backend,
          classroomId: _classroomId,
          classroomTitle: room.title,
          plan: _plan,
          canManage: _manages,
        ),
      ),
    );
  }

  void _showPractice() {
    final backend = _backend;
    final room = _room;
    if (backend == null || room == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => PracticeSheet(
          backend: backend,
          classroomId: _classroomId,
          taskType: room.taskType,
          plan: _plan,
          canManage: _manages,
          classroom: room,
        ),
      ),
    );
  }

  void _showSettings() {
    final room = _room;
    final backend = _backend;
    if (room == null || backend == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ClassroomSettingsSheet(backend: backend, classroom: room),
      ),
    );
  }

  /// Ofy drafts phases and steps from the classroom's task, for the master
  /// to look over before any of it is added.
  Future<void> _draftPlan() async {
    final backend = _backend;
    final room = _room;
    if (backend == null || room == null) return;
    final added = await showGlassSheet<bool>(
      context,
      (_) => PlanDraftSheet(backend: backend, classroom: room, plan: _plan),
    );
    if (added == true && mounted) {
      _showNotice('Ofy’s plan is in. Change anything you like.');
    }
  }

  /// Gives the steps that haven't started to whoever suits each best.
  Future<void> _shareOut() async {
    final backend = _backend;
    final room = _room;
    if (backend == null || room == null) return;
    final moved = await showGlassSheet<int>(
      context,
      (_) => SplitSheet(backend: backend, classroom: room, plan: _plan),
    );
    if (moved != null && moved > 0 && mounted) {
      _showNotice(
        '$moved ${moved == 1 ? 'step has a new owner' : 'steps have new owners'}. '
        'Re-plan to refresh the dates.',
      );
    }
  }

  /// Lays what's left out again from today, to look over before it's applied.
  Future<void> _replan() async {
    final backend = _backend;
    final room = _room;
    if (backend == null || room == null) return;
    // Where every step sits now: one that's left out is gone from the plan
    // by the time its fading is shown.
    final before = Map.of(_controller.positions);
    // Slower than an ordinary edit, so the moves can be followed.
    _controller.travelResponse = 0.95;
    final outcome = await showGlassSheet<ReplanOutcome>(
      context,
      (_) => ReplanSheet(backend: backend, classroom: room, plan: _plan),
    );
    if (outcome == null || !mounted) {
      _controller.travelResponse = 0.42;
      return;
    }
    _showNotice(
      outcome.what.isEmpty ? 'Settings saved.' : 'Re-planned: ${outcome.what}.',
    );
    final moves = [...outcome.moves]..sort((a, b) => a.due.compareTo(b.due));
    // Once the sheet has gone and the new dates have arrived.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    _playChanges(
      PlanChanges([
        for (final m in moves)
          StepChange(
            id: m.step.id,
            title: m.step.title,
            fromDue: m.step.due,
            toDue: m.due,
            fromHours: m.step.estimateHours,
            toHours: m.hours ?? m.step.estimateHours,
          ),
        for (final s in outcome.dropped)
          StepChange(id: s.id, title: s.title, dropped: true, at: before[s.id]),
      ]),
    );
  }

  /// Plays a set of changes back on the graph, step by step, with the whole
  /// plan in view. With motion turned down, nothing plays: the notice says it.
  void _playChanges(PlanChanges changes) {
    void settle() {
      _controller.travelResponse = 0.42;
      if (mounted && _changes == changes) setState(() => _changes = null);
    }

    if (changes.changes.isEmpty || MediaQuery.disableAnimationsOf(context)) {
      settle();
      return;
    }
    setState(() {
      _view = PlanView.graph;
      _changes = changes;
    });
    _camera.fit(fitPadding);
    _changing.duration = changes.duration;
    unawaited(_changing.forward(from: 0).whenComplete(settle));
  }

  Future<void> _addStep() async {
    if (_plan.phases.isEmpty) {
      await _showPhases();
      return;
    }
    final added = await showGlassSheet<PlanStep>(
      context,
      (_) => StepEditorSheet(
        plan: _plan,
        newId: _backend!.newId,
        canAssignOthers: _manages,
        defaultDue: _room?.deadline,
      ),
    );
    if (added == null || !mounted) return;
    final twin = similarStep(_plan, added.title);
    if (twin != null) {
      final done = twin.status == StepStatus.done;
      final phase =
          _plan.phases
              .where((ph) => ph.id == twin.phaseId)
              .firstOrNull
              ?.title ??
          '';
      final choice = await showGlassSheet<String>(
        context,
        (_) => ChoiceSheet<String>(
          title: 'Already in the plan?',
          message:
              '“${twin.title}” in $phase seems to cover this already'
              '${done ? ', and it’s done' : ''}'
              '${twin.ownerId == _me ? '' : ' (${nameIn(_plan, twin.ownerId)}’s step)'}. '
              '${done ? 'Do you want to do it again, or add a new step anyway?' : 'Open that step, or add a new one anyway?'}',
          choices: [
            if (done && _canEdit(twin.id))
              ('Do “${twin.title}” again', 'reopen', true)
            else
              ('Open “${twin.title}”', 'open', true),
            ('Add a new step anyway', 'add', false),
            ('Cancel', 'cancel', false),
          ],
        ),
      );
      if (!mounted) return;
      switch (choice) {
        case 'reopen':
          _controller.setStatus(twin.id, StepStatus.todo);
          _goTo(twin.id);
          _showNotice('“${twin.title}” is open again');
          return;
        case 'open':
          _goTo(twin.id);
          return;
        case 'add':
          break;
        default:
          return;
      }
    }
    _controller.adopt(_plan.withSteps([..._plan.steps.values, added]));
    _showNotice('Added “${added.title}”');
  }

  /// Marks this person's own part of a test or check point done, or not.
  /// The point is done once everyone's part is.
  void _markPart(String stepId, bool done) {
    final s = _plan.steps[stepId];
    if (s == null || !s.participants.contains(_me)) return;
    final doneBy = [
      for (final u in s.doneBy)
        if (u != _me) u,
      if (done) _me,
    ];
    final next = s.copyWith(doneBy: doneBy);
    _controller.adopt(
      _plan.replacing(next.copyWith(status: next.sharedStatus)),
    );
    _showNotice(
      done
          ? (next.sharedStatus == StepStatus.done
                ? 'Everyone’s part is done: “${s.title}” is finished'
                : 'Your part of “${s.title}” is done')
          : 'Your part of “${s.title}” is open again',
    );
  }

  /// Keeps what this person ticked on their own checklist for a point.
  void _saveTicks(String stepId, List<String> ticked) {
    final s = _plan.steps[stepId];
    if (s == null || !s.participants.contains(_me)) return;
    _controller.adopt(
      _plan.replacing(s.copyWith(ticks: {...s.ticks, _me: ticked})),
    );
    _showNotice('Checklist saved');
  }

  void _openPart(String stepId, [String? uid]) {
    final backend = _backend;
    final room = _room;
    if (backend == null || room == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => MyPartSheet(
          backend: backend,
          classroom: room,
          plan: _plan,
          stepId: stepId,
          uid: uid,
          onMark: _markPart,
          onSaveTicks: _saveTicks,
        ),
      ),
    );
  }

  void _showPoints() {
    final room = _room;
    if (room == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => PointsSheet(
          classroom: room,
          plan: _plan,
          onOpen: (id) {
            final s = _plan.steps[id];
            if (s != null && s.participants.contains(_me)) {
              _openPart(id);
            } else {
              _goTo(id);
            }
          },
          onAddPoints: _manages ? _addPoints : null,
        ),
      ),
    );
  }

  /// Puts a test or check point after every phase that hasn't one, between
  /// the people whose steps are in it; the next phase then waits for it.
  void _addPoints() {
    final room = _room;
    final backend = _backend;
    if (room == null || backend == null || !_manages) return;
    final kind = switch (room.checking) {
      'tests' => StepKind.test,
      'both' => StepKind.both,
      'none' => StepKind.check,
      _ => StepKind.check,
    };
    String title(String phase) => switch (room.checking) {
      'tests' => 'Mock test: $phase',
      'both' => 'Mock test and check: $phase',
      'checks' || 'none' => 'Check: $phase',
      final other => '${other[0].toUpperCase()}${other.substring(1)}: $phase',
    };
    final steps = {for (final s in _plan.steps.values) s.id: s};
    var added = 0;
    for (var i = 0; i < _plan.phases.length; i++) {
      final ph = _plan.phases[i];
      final work = steps.values
          .where((s) => s.phaseId == ph.id && !s.isPoint)
          .toList();
      if (work.isEmpty ||
          steps.values.any((s) => s.phaseId == ph.id && s.isPoint)) {
        continue;
      }
      final needed = {for (final s in work) ...s.dependsOn};
      final ends = [
        for (final s in work)
          if (!needed.contains(s.id)) s,
      ];
      final last = work
          .map((s) => s.due)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final day = DateTime(last.year, last.month, last.day + 1);
      final id = backend.newId();
      steps[id] = PlanStep(
        id: id,
        phaseId: ph.id,
        ownerId: _me,
        title: title(ph.title),
        estimateHours: 1,
        start: day,
        due: day,
        dependsOn: [for (final s in ends) s.id],
        kind: kind,
        participants: {for (final s in work) s.ownerId}.toList(),
        order: work.length + 1,
      );
      added++;
      if (i + 1 < _plan.phases.length) {
        final ids = {for (final s in work) s.id};
        final nextId = _plan.phases[i + 1].id;
        final next = steps.values.where((s) => s.phaseId == nextId).toList();
        final nextIds = {for (final s in next) s.id};
        final linked = next.any((s) => s.dependsOn.any(ids.contains));
        for (final s in next) {
          final starts = !s.dependsOn.any(nextIds.contains);
          if (s.dependsOn.any(ids.contains) || (!linked && starts)) {
            steps[s.id] = s.copyWith(
              dependsOn: [
                for (final d in s.dependsOn)
                  if (!ids.contains(d)) d,
                id,
              ],
            );
          }
        }
      }
    }
    if (added == 0) {
      _showNotice('Every phase already has one');
      return;
    }
    _controller.adopt(_plan.withSteps(steps.values));
    _showNotice(
      'Added $added ${added == 1 ? 'point' : 'points'}, one after each phase',
    );
  }

  /// Steps in one phase with the same name, owned by different people: the
  /// same work, better as one joint step between them.
  List<List<PlanStep>> get _matching {
    final groups = <String, List<PlanStep>>{};
    for (final s in _plan.steps.values) {
      if (s.shared) continue;
      final name = s.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      if (name.isEmpty) continue;
      (groups['${s.phaseId}|$name'] ??= []).add(s);
    }
    return [
      for (final g in groups.values)
        if ({for (final s in g) s.ownerId}.length > 1) g,
    ];
  }

  /// Turns each set of matching steps into one joint step between the people
  /// who had them. Each then marks their own part; it's done once all have.
  void _combineMatching() {
    final groups = _matching;
    if (groups.isEmpty || !_manages) return;
    final steps = {for (final s in _plan.steps.values) s.id: s};
    for (final g in groups) {
      g.sort((a, b) => a.order.compareTo(b.order));
      final keep = g.first;
      final gone = {for (final s in g.skip(1)) s.id};
      final ids = {for (final s in g) s.id};
      final people = {for (final s in g) s.ownerId}.toList();
      final done = [
        for (final s in g)
          if (s.status == StepStatus.done) s.ownerId,
      ];
      final joint = keep.copyWith(
        kind: StepKind.joint,
        participants: people,
        doneBy: {...done}.toList(),
        dependsOn: {
          for (final s in g)
            for (final d in s.dependsOn)
              if (!ids.contains(d)) d,
        }.toList(),
        due: g.map((s) => s.due).reduce((a, b) => a.isAfter(b) ? a : b),
        estimateHours: g
            .map((s) => s.estimateHours)
            .reduce((a, b) => a > b ? a : b),
      );
      steps[keep.id] = joint.copyWith(status: joint.sharedStatus);
      gone.forEach(steps.remove);
      // Whatever needed any of them now needs the joint step, once.
      for (final s in steps.values.toList()) {
        if (!s.dependsOn.any(gone.contains)) continue;
        steps[s.id] = s.copyWith(
          dependsOn: {
            for (final d in s.dependsOn) gone.contains(d) ? keep.id : d,
          }.where((d) => d != s.id).toList(),
        );
      }
    }
    _controller.adopt(_plan.withSteps(steps.values));
    _showNotice(
      'Combined ${groups.length} '
      '${groups.length == 1 ? 'pair of matching steps' : 'sets of matching steps'} '
      'into joint steps',
    );
  }

  void _showDone() {
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => DoneSheet(plan: _plan, onOpen: (s) => _goTo(s.id)),
      ),
    );
  }

  void _showDeleted() {
    final backend = _backend;
    if (backend == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => DeletedSheet(
          backend: backend,
          classroomId: _classroomId,
          plan: _plan,
        ),
      ),
    );
  }

  void _showRoles() {
    final backend = _backend;
    final room = _room;
    if (backend == null || room == null) return;
    unawaited(
      showGlassSheet<bool>(
        context,
        (_) => RolesSheet(backend: backend, classroom: room, plan: _plan),
      ).then((saved) {
        if (saved == true && mounted) _showNotice('Roles saved');
      }),
    );
  }

  /// A person's round icon beside their lane: chat with them, or more.
  void _memberTap(String uid) {
    final backend = _backend;
    final room = _room;
    if (backend == null || room == null) return;
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => MemberSheet(
          backend: backend,
          classroom: room,
          plan: _plan,
          uid: uid,
          onChat: () => unawaited(_openChatWith([uid])),
        ),
      ),
    );
  }

  Future<void> _editStep(PlanStep step) async {
    final edited = await showGlassSheet<PlanStep>(
      context,
      (_) => StepEditorSheet(
        plan: _plan,
        newId: _backend!.newId,
        canAssignOthers: _manages,
        step: step,
      ),
    );
    if (edited == null || !mounted) return;
    _controller.adopt(_plan.replacing(edited));
  }

  void _onPlanChanged() {
    if (mounted) setState(() {});
  }

  // Ofy ----------------------------------------------------------------------

  Ofy? _ofy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.session != null) {
      _ofy = OfyScope.maybeOf(context)?..enter(this, _ofyScreen);
    }
  }

  /// The step named [name], as near as can be found.
  PlanStep? _stepNamed(String? name) {
    final want = (name ?? '').toLowerCase().trim();
    if (want.isEmpty) return null;
    final steps = _plan.steps.values.toList();
    return steps.where((s) => s.title.toLowerCase() == want).firstOrNull ??
        steps.where((s) => s.title.toLowerCase().contains(want)).firstOrNull ??
        steps.where((s) => want.contains(s.title.toLowerCase())).firstOrNull;
  }

  String _day(DateTime d) => '${d.day}/${d.month}';

  late final OfyScreen _ofyScreen = OfyScreen(
    name: 'classroom',
    summary: () {
      final room = _room;
      final me = _me;
      final next = _plan.nextStepFor(me);
      final lines = <String>[
        'Classroom: ${room?.title ?? _plan.title}'
            '${room == null ? '' : ' (${room.taskType.label}, ${room.individual ? 'just them' : 'a group'})'}.',
        'Their role: ${_isMaster
            ? 'master'
            : _manages
            ? 'co-master'
            : 'member'}.',
        'View: ${_view.name}.',
        'People: ${_plan.members.map((m) => m.id == me ? '${m.name} (them)' : m.name).join(', ')}.',
        if (next != null)
          'Your next step: “${next.title}”, due ${_day(next.due)}.',
        if (_selectedId != null && _plan.steps[_selectedId] != null)
          'Open step: “${_plan.steps[_selectedId]!.title}”.',
      ];
      var count = 0;
      for (final ph in _plan.phases) {
        final steps = _plan.stepsIn(ph.id).toList();
        lines.add('Phase ${ph.title}: ${steps.isEmpty ? 'no steps' : ''}');
        for (final s in steps) {
          if (++count > 40) break;
          lines.add(
            '  - ${s.title} (${_plan.member(s.ownerId).name}, '
            '${_plan.standing(s).name}, due ${_day(s.due)})',
          );
        }
      }
      if (_plan.phases.isEmpty) lines.add('There are no phases or steps yet.');
      return lines.join('\n');
    },
    actions: [
      OfyAction(
        id: 'open-my-step',
        description: 'Open the person’s own next step',
        run: (_) async {
          final next =
              _plan.nextStepFor(_me) ??
              _plan.steps.values.where((s) => s.ownerId == _me).firstOrNull;
          if (next == null) return 'You have no steps here yet.';
          _goTo(next.id);
          return 'Opened “${next.title}”.';
        },
      ),
      OfyAction(
        id: 'open-any-step',
        description: 'Open someone else’s step',
        run: (_) async {
          final other =
              _plan.steps.values.where((s) => s.ownerId != _me).firstOrNull ??
              _plan.steps.values.firstOrNull;
          if (other == null) return 'There are no steps yet.';
          _goTo(other.id);
          return 'Opened “${other.title}”.';
        },
      ),
      OfyAction(
        id: 'open-step',
        description: 'Open a step by name',
        params: const ['step'],
        run: (args) async {
          final step = _stepNamed(args['step']);
          if (step == null) return 'There’s no step called “${args['step']}”.';
          _goTo(step.id);
          return 'Opened “${step.title}”.';
        },
      ),
      OfyAction(
        id: 'open-menu',
        description:
            'Open something from the classroom menu: Files, Class chat, '
            'Private chats, Practice, Handovers, Important, Phases, Settings, '
            'Activity, Shared boards, Members and invite code, Since you were away',
        params: const ['item'],
        run: (args) async {
          final want = (args['item'] ?? '').toLowerCase().trim();
          // Out of More first, so the page opens on its own.
          Navigator.of(context).popUntil((r) => r is! PopupRoute);
          for (final section in _menuSections()) {
            for (final entry in section.entries) {
              final label = entry.label.toLowerCase();
              if (label == want ||
                  label.startsWith(want) ||
                  want.startsWith(label)) {
                entry.onTap();
                return 'Opened ${entry.label}.';
              }
            }
          }
          return 'There’s no $want here.';
        },
      ),
      OfyAction(
        id: 'show-more',
        description: 'Open More, the classroom menu',
        run: (_) async {
          _showMore();
          return 'Opened More.';
        },
      ),
      OfyAction(
        id: 'draft-plan',
        description: 'Draft a plan, or add to the plan, with Ofy’s questions',
        run: (_) async {
          unawaited(_draftPlan());
          return 'Opened the planner.';
        },
      ),
      OfyAction(
        id: 'add-step',
        description: 'Add a step owned by the person, in the last phase',
        params: const ['title'],
        needsApproval: true,
        run: (args) async {
          final title = (args['title'] ?? '').trim();
          if (title.isEmpty) return 'The step needs a name.';
          if (_plan.phases.isEmpty) {
            return 'Add a phase first, or ask me to draft a plan.';
          }
          final today = DateTime.now();
          final step = PlanStep(
            id: _backend!.newId(),
            phaseId: _plan.phases.last.id,
            ownerId: _me,
            title: title,
            estimateHours: 2,
            start: DateTime(today.year, today.month, today.day),
            due:
                _room?.deadline ??
                DateTime(today.year, today.month, today.day + 7),
            order: _plan.stepsIn(_plan.phases.last.id).length + 1,
          );
          _controller.adopt(_plan.withSteps([..._plan.steps.values, step]));
          _goTo(step.id);
          return 'Added “$title” to ${_plan.phases.last.title}.';
        },
      ),
      OfyAction(
        id: 'start-step',
        description: 'Start a step, marking it in progress',
        params: const ['step'],
        needsApproval: true,
        run: (args) async {
          final step = _stepNamed(args['step']) ?? _plan.nextStepFor(_me);
          if (step == null) return 'I couldn’t find that step.';
          if (!_canEdit(step.id)) {
            return 'Only its owner or a master can start it.';
          }
          _controller.setStatus(step.id, StepStatus.doing);
          return 'Started “${step.title}”.';
        },
      ),
      OfyAction(
        id: 'mark-done',
        description: 'Mark a step done (it waits for approval if the classroom needs it)',
        params: const ['step'],
        needsApproval: true,
        run: (args) async {
          final step = _stepNamed(args['step']);
          if (step == null) return 'There’s no step called “${args['step']}”.';
          if (!_canEdit(step.id)) {
            return 'Only its owner or a master can finish it.';
          }
          _markDone(step.id);
          return 'Marked “${step.title}” done.';
        },
      ),
      OfyAction(
        id: 'switch-view',
        description: 'Show the plan as the map (graph), Timeline or List',
        params: const ['view'],
        run: (args) async {
          final want = (args['view'] ?? '').toLowerCase();
          final view = want.contains('time')
              ? PlanView.timeline
              : want.contains('list')
              ? PlanView.list
              : PlanView.graph;
          setState(() => _view = view);
          return 'Showing the ${view.name}.';
        },
      ),
      OfyAction(
        id: 'toggle-theme',
        description: 'Switch between the light and dark background',
        run: (_) async {
          final dark = Palette.of(context).brightness == Brightness.dark;
          widget.onBrightnessChanged(dark ? Brightness.light : Brightness.dark);
          return 'Switched the background.';
        },
      ),
      OfyAction(
        id: 'go-home',
        description: 'Go back to the dashboard',
        run: (_) async {
          unawaited(Navigator.of(context).maybePop());
          return 'Back to the dashboard.';
        },
      ),
    ],
  );

  @override
  void dispose() {
    _ofy?.leave(this);
    _noticeTimer?.cancel();
    _sync?.dispose();
    unawaited(_feed?.cancel());
    unawaited(_chatFeed?.cancel());
    unawaited(_threadFeed?.cancel());
    unawaited(_handoverFeed?.cancel());
    unawaited(_offerFeed?.cancel());
    unawaited(_suggestionFeed?.cancel());
    _controller.removeListener(_onPlanChanged);
    _controller.dispose();
    _camera.dispose();
    _focus.dispose();
    _celebration.dispose();
    _changing.dispose();
    super.dispose();
  }

  /// A phone on its side: too short for a title bar and a bottom bar both.
  bool _isShort(BuildContext context) =>
      MediaQuery.sizeOf(context).height < _shortHeight;

  bool _isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _narrowWidth || _isShort(context);

  /// What the floating bars cover at each edge. Content runs underneath them.
  EdgeInsets _shellInsets(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    if (_isShort(context)) {
      return EdgeInsets.fromLTRB(
        kPaneGap,
        safe.top + 4 + _shortBarHeight + 4,
        kPaneGap,
        safe.bottom + 4,
      );
    }
    if (_isNarrow(context)) {
      return EdgeInsets.fromLTRB(
        kPaneGap,
        safe.top + kPaneGap + _barHeight + kPaneGap,
        kPaneGap,
        safe.bottom + kPaneGap + _tabBarHeight + kPaneGap,
      );
    }
    return EdgeInsets.fromLTRB(
      10 + _sidebarWidth + 10,
      safe.top + 10 + _barHeight + 8,
      10,
      safe.bottom + 10,
    );
  }

  /// A canvas too small for a minimap, so its controls sit in a row of their own.
  bool _phoneCanvas(BuildContext context) =>
      !_isShort(context) &&
      MediaQuery.sizeOf(context).width - _shellInsets(context).horizontal <
          _mapMinWidth;

  /// What the graph should stay clear of when it frames something.
  EdgeInsets _graphInsets(BuildContext context) {
    final shell = _shellInsets(context);
    return _phoneCanvas(context)
        ? shell.copyWith(bottom: shell.bottom + _phoneRowHeight)
        : shell;
  }

  void _showNotice(
    String message, {
    String? actionLabel,
    VoidCallback? action,
  }) {
    _noticeTimer?.cancel();
    setState(
      () =>
          _notice = _Notice(message, actionLabel: actionLabel, action: action),
    );
    _noticeTimer = Timer(Duration(seconds: action == null ? 4 : 7), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// Opens on the view worked out by [_frameOpening].
  void _frameInitialView() {
    final viewport = _camera.viewport;
    final wide = viewport.width > viewport.height;
    if (_framedEpoch == _graphEpoch && _framedWide == wide) return;
    _framedEpoch = _graphEpoch;
    _framedWide = wide;
    _applyLayoutOptions();
    _frameOpening(animate: false);
  }

  /// Spacing for the current direction and screen. A short screen tightens the
  /// spacing along its height, so the graph uses it well.
  void _applyLayoutOptions({bool animate = false}) {
    final short = _camera.clear.height < 420;
    final vertical = _direction == GraphDirection.topToBottom;
    final options = LayoutOptions(
      direction: _direction,
      cellWidth: vertical ? _verticalCellWidth : kCellWidth,
      rowHeight: vertical
          ? (short ? _shortVerticalRowHeight : _verticalRowHeight)
          : (short ? _shortRowHeight : kRowHeight),
    );
    _camera
      ..cellWidth = options.cellWidth
      ..rowHeight = options.rowHeight;
    _controller.setOptions(options, animate: animate);
    _camera.world = _controller.layout.size;
  }

  void _toggleDirection() {
    setState(() {
      _direction = _direction == GraphDirection.leftToRight
          ? GraphDirection.topToBottom
          : GraphDirection.leftToRight;
    });
    _applyLayoutOptions(animate: true);
    _frameOpening(animate: true);
    _showNotice(_directionLabel);
  }

  String get _directionLabel => _direction == GraphDirection.leftToRight
      ? 'Left to right'
      : 'Top to bottom';

  /// Switches between the white and dark backgrounds, in every view.
  Widget _themeButton({double height = 44}) {
    final dark = Palette.of(context).brightness == Brightness.dark;
    return OfyTarget(
      id: 'theme',
      child: PressButton(
        label: dark
            ? 'Switch to white background'
            : 'Switch to dark background',
        icon: dark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
        iconOnly: true,
        quiet: true,
        height: height,
        onTap: () => widget.onBrightnessChanged(
          dark ? Brightness.light : Brightness.dark,
        ),
      ),
    );
  }

  /// Shows which way the graph flows; tapping switches it. Only the graph has a
  /// direction, so other views leave it out.
  List<Widget> _directionControl({required bool iconOnly, double height = 44}) {
    if (_view != PlanView.graph) return const [];
    return [
      PressButton(
        label: iconOnly ? 'Graph direction: $_directionLabel' : _directionLabel,
        icon: _direction == GraphDirection.leftToRight
            ? CupertinoIcons.arrow_right
            : CupertinoIcons.arrow_down,
        iconOnly: iconOnly,
        quiet: iconOnly,
        height: height,
        onTap: _toggleDirection,
      ),
      if (!iconOnly) const SizedBox(width: 8),
    ];
  }

  /// The part of the canvas clear of the sticky headers and floating controls.
  Rect _graphArea() {
    final clear = _camera.clear;
    return Rect.fromLTRB(
      gutterEndFor(_camera) + 8,
      stripEndFor(_camera) + 8,
      clear.right - 8,
      clear.bottom - 8,
    );
  }

  Size _plateAt(double scale) =>
      nodeSize(scale, row: _camera.rowHeight, cell: _camera.cellWidth);

  /// The closest zoom, up to the usual maximum, at which every step in a phase
  /// fits. A rectangle's size depends on the zoom, so the two settle together.
  double _scaleToFit(Rect bounds, Rect area) {
    var fitted = 0.72;
    for (var i = 0; i < 4; i++) {
      final plate = _plateAt(fitted);
      final fitX = bounds.width == 0
          ? double.infinity
          : (area.width - plate.width) / bounds.width;
      final fitY = bounds.height == 0
          ? double.infinity
          : (area.height - plate.height) / bounds.height;
      fitted = math.min(math.min(fitX, fitY), 0.72);
    }
    return fitted.clamp(0.36, 0.72);
  }

  Rect? _phaseBounds(String phaseId) {
    // Where steps are heading, in case they're still gliding to a new layout.
    final targets = _controller.layout.positions;
    Rect? bounds;
    for (final step in _plan.stepsIn(phaseId)) {
      final p = targets[step.id];
      if (p == null) continue;
      final point = Rect.fromLTWH(p.dx, p.dy, 0, 0);
      bounds = bounds?.expandToInclude(point) ?? point;
    }
    return bounds;
  }

  void _moveCamera(Offset pan, double scale, {required bool animate}) {
    if (animate) {
      _camera.moveTo(pan, scale);
    } else {
      _camera.jumpTo(pan, scale);
      _camera.release(Offset.zero);
    }
  }

  /// Frames every step in a phase, clear of the floating controls.
  void _fitPhase(String phaseId, {bool animate = true}) {
    final bounds = _phaseBounds(phaseId);
    if (bounds == null) return;
    final area = _graphArea();
    final s = _scaleToFit(bounds, area);
    _moveCamera(area.center - bounds.center * s, s, animate: animate);
  }

  /// Where a classroom opens. The whole plan if it fits comfortably; otherwise
  /// the next step's whole phase if that's readable and shows enough people;
  /// otherwise the closest view around the next step that has at least three
  /// people's steps whole on screen, so their names can be read.
  void _frameOpening({required bool animate}) {
    final next = _plan.nextStepFor(_plan.meId);
    if (_camera.fitScale(fitPadding) >= 0.7 || next == null) {
      _camera.fit(fitPadding, animate: animate);
      return;
    }
    final targets = _controller.layout.positions;
    final nextAt = targets[next.id];
    if (nextAt == null) return;
    final area = _graphArea();
    final people = _plan.steps.values.map((s) => s.ownerId).toSet().length;
    final wanted = math.min(_peopleToShow, people);

    final bounds = _phaseBounds(next.phaseId);
    if (bounds != null) {
      final s = _scaleToFit(bounds, area);
      final inPhase = _plan
          .stepsIn(next.phaseId)
          .map((step) => step.ownerId)
          .toSet();
      if (s >= _readableScale && inPhase.length >= wanted) {
        _moveCamera(area.center - bounds.center * s, s, animate: animate);
        return;
      }
    }

    Offset? bestPan;
    var bestScale = 0.42;
    for (final s in const [0.72, 0.66, 0.6, 0.54, 0.48, 0.42]) {
      final plate = _plateAt(s);
      final viewW = (area.width - plate.width) / s;
      final viewH = (area.height - plate.height) / s;
      // Only steps within one view of the next step could share the screen.
      final nearby = [
        for (final step in _plan.steps.values)
          if (targets[step.id] case final p?)
            if ((p.dx - nextAt.dx).abs() <= viewW &&
                (p.dy - nextAt.dy).abs() <= viewH)
              (step.ownerId, p),
      ];
      final lefts = {
        nextAt.dx - viewW / 2,
        for (final (_, p) in nearby)
          if (p.dx <= nextAt.dx) p.dx,
      };
      final tops = {
        nextAt.dy - viewH / 2,
        for (final (_, p) in nearby)
          if (p.dy <= nextAt.dy) p.dy,
      };
      var bestPeople = -1;
      var bestDistance = double.infinity;
      Offset? origin;
      for (final left in lefts) {
        for (final top in tops) {
          final view = Rect.fromLTWH(left, top, viewW + 0.5, viewH + 0.5);
          final shown = {
            for (final (owner, p) in nearby)
              if (view.contains(p)) owner,
          };
          final distance = (view.center - nextAt).distance;
          if (shown.length > bestPeople ||
              (shown.length == bestPeople && distance < bestDistance)) {
            bestPeople = shown.length;
            bestDistance = distance;
            origin = Offset(left, top);
          }
        }
      }
      if (origin == null) continue;
      bestPan =
          area.topLeft + Offset(plate.width / 2, plate.height / 2) - origin * s;
      bestScale = s;
      if (bestPeople >= wanted) break;
    }
    if (bestPan != null) _moveCamera(bestPan, bestScale, animate: animate);
  }

  void _switchPlan(int index) {
    _controller.replacePlan(_plans[index]());
    setState(() {
      _planIndex = index;
      _selectedId = null;
      _filter = const GraphFilter();
      _linkFromId = null;
      _selectedEdge = null;
      _focusOn = false;
      _focus.value = 0;
      _graphEpoch++;
    });
  }

  /// The tapped arrow, if it still exists after any edits.
  (String, String)? get _activeEdge {
    final edge = _selectedEdge;
    if (edge == null) return null;
    final to = _plan.steps[edge.$2];
    final linked = to != null && to.dependsOn.contains(edge.$1);
    return linked && _plan.steps[edge.$1] != null ? edge : null;
  }

  void _selectEdge((String, String) edge) {
    setState(() {
      _selectedEdge = edge;
      _selectedId = null;
      _menu = null;
    });
  }

  /// Moves to one end of the tapped arrow, keeping the arrow highlighted so it
  /// can be followed back.
  void _showEnd(String id) {
    final at = _controller.positions[id];
    if (at == null) return;
    _camera.centreOn(at, atScale: _camera.scale < 0.6 ? 0.72 : _camera.scale);
  }

  void _select(String? id) {
    setState(() {
      _selectedId = id;
      _selectedEdge = null;
      if (id != null) _lastSelectedId = id;
      _menu = null;
    });
  }

  void _goTo(String id) {
    _select(id);
    final at = _controller.positions[id];
    if (at == null || _view != PlanView.graph) return;
    final narrow = _isNarrow(context);
    _camera.centreOn(
      at,
      atScale: _camera.scale < 0.6 ? 0.82 : _camera.scale,
      bias: narrow && !_isShort(context)
          ? Offset(0, -_camera.viewport.height * 0.22)
          : const Offset(-(_panelWidth / 2), 0),
    );
  }

  void _toggleFocus() {
    final next = _plan.nextStepFor(_plan.meId);
    final reduce = MediaQuery.disableAnimationsOf(context);
    setState(() => _focusOn = !_focusOn);
    if (_focusOn) {
      reduce ? _focus.value = 1 : _focus.forward();
      final mineId = next?.id;
      final at = mineId == null ? null : _controller.positions[mineId];
      if (at != null && _view == PlanView.graph) {
        _camera.centreOn(
          at,
          atScale: _camera.scale < 0.7 ? 0.9 : _camera.scale,
        );
      }
    } else {
      reduce ? _focus.value = 0 : _focus.reverse();
    }
  }

  void _markDone(String id) {
    final step = _plan.steps[id];
    if (step == null) return;
    // A shared point: only this person's own part.
    if (step.shared && widget.session != null) {
      if (step.participants.contains(_me)) {
        _markPart(id, !step.doneFor(_me));
      } else {
        _showNotice('Each person in it marks their own part done.');
      }
      return;
    }
    if (!_canEdit(id)) {
      _showNotice(
        'Only ${_plan.member(step.ownerId).name} or the master can '
        'change this step.',
      );
      return;
    }
    if (step.status == StepStatus.done) {
      _controller.setStatus(id, StepStatus.todo);
      return;
    }
    if ((_room?.approvalRequired ?? false) && !_manages) {
      _controller.setStatus(id, StepStatus.review);
      setState(() => _menu = null);
      HapticFeedback.mediumImpact();
      _showNotice('“${step.title}” is waiting for approval');
      return;
    }
    final before = step.status;
    final unlocked = _plan
        .dependents(step)
        .where((d) => _plan.openDependencies(d).length == 1)
        .toList();
    _controller.setStatus(id, StepStatus.done);
    setState(() => _menu = null);
    HapticFeedback.mediumImpact();
    // With reduced motion the step simply changes; the notice says what happened.
    if (!MediaQuery.disableAnimationsOf(context)) {
      setState(() => _celebrateId = id);
      _celebration.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _celebrateId = null);
      });
    }
    final message = unlocked.isEmpty
        ? 'Marked “${step.title}” done'
        : unlocked.length == 1
        ? '“${unlocked.first.title}” can start now'
        : '${unlocked.length} steps can start now';
    _showNotice(
      message,
      actionLabel: 'Undo',
      action: () => _controller.setStatus(id, before),
    );
  }

  void _link(String fromId, String toId) {
    if (!_canEdit(toId)) {
      setState(() => _linkFromId = null);
      _showNotice(
        'Only that step’s owner or the master can change what it '
        'depends on.',
      );
      return;
    }
    try {
      _controller.addDependency(toId, fromId);
      HapticFeedback.mediumImpact();
      _showNotice(
        '“${_plan.steps[toId]?.title}” now depends on “${_plan.steps[fromId]?.title}”',
        actionLabel: 'Undo',
        action: () => _controller.removeDependency(toId, fromId),
      );
    } on DependencyRefused catch (e) {
      HapticFeedback.heavyImpact();
      _showNotice(e.message);
    }
    setState(() => _linkFromId = null);
  }

  void _delete(String id) {
    if (!_canEdit(id)) return;
    final title = _plan.steps[id]?.title;
    final before = _controller.deleteStep(id);
    setState(() => _selectedId = null);
    _showNotice(
      'Deleted “$title”',
      actionLabel: 'Undo',
      action: () => _controller.restore(before),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final narrow = _isNarrow(context);
    final short = _isShort(context);
    final sides = MediaQuery.paddingOf(context);
    final shell = _shellInsets(context);
    _camera.chrome = _graphInsets(context);
    GlassBudget.watch();
    final body = BackdropGroup(
      child: Stack(
        children: [
          Positioned.fill(child: _buildContent(p, narrow, shell)),
          // Content fades out where it meets the status bar and the screen's edge.
          if (sides.top > 0)
            _edgeFade(p, top: true, height: sides.top + kPaneGap),
          if (sides.bottom > 0)
            _edgeFade(p, top: false, height: sides.bottom + kPaneGap),
          if (!narrow)
            Positioned(
              left: 10,
              top: sides.top + 10,
              bottom: sides.bottom + 10,
              width: _sidebarWidth,
              child: _buildSidebar(p),
            ),
          Positioned(
            left: short || narrow ? kPaneGap : shell.left,
            right: short || narrow ? kPaneGap : 10,
            top: sides.top + (short ? 4 : (narrow ? kPaneGap : 10)),
            height: short ? _shortBarHeight : _barHeight,
            child: short
                ? _buildShortBar(p)
                : (narrow ? _buildNarrowBar(p) : _buildToolbar(p)),
          ),
          if (_filterOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _filterOpen = false),
              ),
            ),
            Positioned(
              top: shell.top,
              right: narrow ? 12 : 16,
              left: narrow ? 12 : null,
              child: _materialize(
                alignment: Alignment.topRight,
                child: _buildFilterPanel(p, narrow),
              ),
            ),
          ],
        ],
      ),
    );

    final dark = p.brightness == Brightness.dark;
    final overlay = SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: p.brightness,
      systemNavigationBarColor: const Color(0x00000000),
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: PopScope(
        canPop:
            _selectedId == null &&
            !_filterOpen &&
            !_keyOpen &&
            _linkFromId == null &&
            _activeEdge == null &&
            _menu == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() {
            _menu = null;
            _filterOpen = false;
            _keyOpen = false;
            _linkFromId = null;
            _selectedEdge = null;
            _selectedId = null;
          });
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            const AmbientBackdrop(),
            // Stay clear of the navigation bar and camera cutout on a turned phone.
            Padding(
              padding: EdgeInsets.only(left: sides.left, right: sides.right),
              child: MediaQuery.removePadding(
                context: context,
                removeLeft: true,
                removeRight: true,
                child: DefaultTextStyle(
                  style: TypeRamp.body(p.ink),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _edgeFade(Palette p, {required bool top, required double height}) {
    return Positioned(
      left: 0,
      right: 0,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [p.ground, p.ground.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }

  /// A glass surface arriving: grows from where it was asked for as it appears.
  Widget _materialize({required Alignment alignment, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: ((value - 0.92) / 0.08).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: value,
          alignment: alignment,
          child: child,
        ),
      ),
      child: child,
    );
  }

  // Shell ---------------------------------------------------------------------

  Widget _buildSidebar(Palette p) {
    Widget item(
      String label,
      bool selected,
      VoidCallback onTap, {
      int count = 0,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _SidebarItem(
        label: label,
        selected: selected,
        onTap: onTap,
        count: count,
      ),
    );
    return GlassPanel(
      radius: 24,
      weight: GlassWeight.thin,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
            child: Text(
              'Octria',
              style: TypeRamp.title(p.ink).copyWith(fontSize: 22),
            ),
          ),
          if (widget.session == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text('Classrooms', style: TypeRamp.caption(p.inkFaint)),
            ),
          if (widget.session == null) ...[
            for (var i = 0; i < _planNames.length; i++)
              item(_planNames[i], i == _planIndex, () => _switchPlan(i)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Prototype. All plans here are sample data.',
                style: TypeRamp.caption(p.inkFaint),
              ),
            ),
          ] else ...[
            GlassMenuRow(
              entry: MenuEntry(
                'Dashboard',
                CupertinoIcons.square_grid_2x2,
                () => Navigator.of(context).maybePop(),
              ),
              dense: true,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: GlassMenuList(sections: _menuSections(), dense: true),
              ),
            ),
            const SizedBox(height: 6),
            GlassMenuRow(
              entry: MenuEntry(
                'Your profile',
                CupertinoIcons.person_crop_circle,
                _showProfile,
                colour: p.route,
              ),
              dense: true,
            ),
          ],
        ],
      ),
    );
  }

  /// Everything to do with the open classroom, for the sidebar and the menu,
  /// grouped by what it's for.
  List<MenuSection> _menuSections({bool withAddStep = false}) {
    final individual = _room?.individual ?? false;
    final live = _backend != null;
    final p = Palette.of(context);
    return [
      MenuSection('Needs you', [
        if (withAddStep)
          MenuEntry('Add a step', CupertinoIcons.plus_circle, _addStep),
        if (live && !individual)
          MenuEntry(
            'Important',
            CupertinoIcons.exclamationmark_bubble,
            _showImportant,
            colour: p.accentWarm,
            count: _importantCount,
          ),
        if (!individual)
          MenuEntry(
            'Since you were away',
            CupertinoIcons.bell,
            _showAwayNews,
            colour: p.route,
            count: _unread,
          ),
        if (live && !individual)
          MenuEntry(
            'Handovers',
            CupertinoIcons.arrow_right_arrow_left,
            _showHandovers,
            colour: p.accentViolet,
            count: _handoversForMe,
          ),
      ]),
      if (live && !individual)
        MenuSection('Talk', [
          MenuEntry(
            'Class chat',
            CupertinoIcons.chat_bubble_2,
            _showChat,
            colour: p.accentTeal,
            count: _unreadChat,
          ),
          MenuEntry(
            'Private chats',
            CupertinoIcons.lock,
            _showChats,
            colour: p.accent,
            count: _unreadThreads,
          ),
          if (_plan.members.length > 2)
            MenuEntry(
              'New group chat',
              CupertinoIcons.person_3,
              _newGroupChat,
              colour: p.accentViolet,
            ),
          // Group chats stay here, with their messages, once started.
          for (final th in _threads)
            if (th.participants.length > 2)
              MenuEntry(
                threadTitle(th, _plan),
                CupertinoIcons.person_2,
                () => unawaited(_openChatWith(th.participants)),
                colour: p.accentViolet,
                count: th.unreadFor(_me) ? 1 : 0,
                indent: true,
              ),
        ]),
      MenuSection('Work', [
        if (_manages)
          MenuEntry(
            'Phases',
            CupertinoIcons.square_stack_3d_up,
            _showPhases,
            colour: p.doing,
          ),
        if (live)
          MenuEntry(
            _plan.steps.isEmpty
                ? 'Draft a plan with Ofy'
                : 'Add to the plan with Ofy',
            CupertinoIcons.sparkles,
            () => unawaited(_draftPlan()),
            colour: p.accentViolet,
          ),
        if (live && _plan.steps.values.any((s) => s.status != StepStatus.done))
          MenuEntry(
            'Re-plan',
            CupertinoIcons.arrow_2_circlepath,
            () => unawaited(_replan()),
            colour: p.accentWarm,
            count: _plan.steps.values
                .where((s) => _plan.isOverdue(s) && _canEdit(s.id))
                .length,
          ),
        if (_manages && _matching.isNotEmpty)
          MenuEntry(
            'Combine matching steps',
            CupertinoIcons.arrow_merge,
            _combineMatching,
            colour: p.accentTeal,
            count: _matching.length,
          ),
        if (live)
          MenuEntry(
            'Files',
            CupertinoIcons.folder,
            _showFiles,
            colour: p.accent,
          ),
        if (live)
          MenuEntry(
            'Practice',
            CupertinoIcons.flag,
            _showPractice,
            colour: p.accentTeal,
          ),
        if (live && !individual)
          MenuEntry(
            'Shared boards',
            CupertinoIcons.paintbrush,
            _showSharedBoards,
            colour: p.accentWarm,
          ),
        if (!individual)
          MenuEntry(
            'Activity',
            CupertinoIcons.waveform_path_ecg,
            _showActivity,
            colour: p.accent,
          ),
        if (live && (_room?.checkLabel ?? '').isNotEmpty)
          MenuEntry(
            _room!.checkLabel,
            CupertinoIcons.doc_checkmark,
            _showPoints,
            colour: p.accentViolet,
            count: _plan.steps.values
                .where(
                  (s) =>
                      s.isPoint &&
                      s.participants.contains(_me) &&
                      !s.doneFor(_me) &&
                      _plan.standing(s) != Standing.waiting,
                )
                .length,
          ),
        MenuEntry(
          'Add to calendar',
          CupertinoIcons.calendar_badge_plus,
          _showCalendar,
          colour: p.accentWarm,
        ),
        MenuEntry(
          'Done',
          CupertinoIcons.checkmark_seal,
          _showDone,
          colour: p.done,
        ),
        if (live)
          MenuEntry(
            'Deleted',
            CupertinoIcons.trash,
            _showDeleted,
            colour: p.inkSoft,
          ),
      ]),
      MenuSection('Classroom', [
        if (!individual)
          MenuEntry(
            'Members and invite code',
            CupertinoIcons.person_crop_circle_badge_plus,
            _showMembers,
            colour: p.done,
          ),
        if (live && !individual)
          MenuEntry(
            'Roles',
            CupertinoIcons.person_2_square_stack,
            _showRoles,
            colour: p.accentViolet,
          ),
        if (live && !individual && _manages && _plan.members.length > 1)
          MenuEntry(
            'Share out by skills',
            CupertinoIcons.arrow_right_arrow_left,
            () => unawaited(_shareOut()),
            colour: p.accentTeal,
          ),
        if (_isMaster)
          MenuEntry(
            'Settings',
            CupertinoIcons.gear,
            _showSettings,
            colour: p.inkSoft,
          ),
        if (!individual)
          MenuEntry(
            'Leave classroom',
            CupertinoIcons.square_arrow_left,
            _leaveClassroom,
            destructive: true,
          ),
      ]),
    ];
  }

  Widget _buildToolbar(Palette p) {
    final room =
        MediaQuery.sizeOf(context).width - _shellInsets(context).horizontal;
    final compact = room < _labelledToolbarWidth;
    return GlassPanel(
      radius: _barHeight / 2,
      weight: GlassWeight.thin,
      padding: const EdgeInsets.only(left: 20, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _plan.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeRamp.title(p.ink),
            ),
          ),
          const OfyTarget(id: 'classroom:views', child: SizedBox(width: 12)),
          SizedBox(
            width: 264,
            child: CupertinoSlidingSegmentedControl<PlanView>(
              groupValue: _view,
              onValueChanged: (v) {
                if (v != null) setState(() => _view = v);
              },
              children: {
                PlanView.graph: _segment('Flowspace', p),
                PlanView.timeline: _segment('Timeline', p),
                PlanView.list: _segment('List', p),
              },
            ),
          ),
          const SizedBox(width: 12),
          _themeButton(height: 36),
          const SizedBox(width: 8),
          ..._directionControl(iconOnly: compact, height: 36),
          _filterButton(p, 36, compact),
          const SizedBox(width: 8),
          _focusButton(p, 36, compact),
        ],
      ),
    );
  }

  Widget _segment(String label, Palette p) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(label, style: TypeRamp.label(p.ink)),
  );

  Widget _filterButton(Palette p, double height, bool iconOnly) => PressButton(
    label: _filter.isActive ? 'Filter (${_filter.count})' : 'Filter',
    icon: CupertinoIcons.line_horizontal_3_decrease,
    iconOnly: iconOnly,
    quiet: iconOnly,
    selected: _filter.isActive,
    height: height,
    onTap: () => setState(() => _filterOpen = !_filterOpen),
  );

  Widget _focusButton(Palette p, double height, bool iconOnly) => PressButton(
    label: 'Focus on me',
    icon: CupertinoIcons.scope,
    iconOnly: iconOnly,
    quiet: iconOnly,
    selected: _focusOn,
    selectedColor: p.route,
    height: height,
    onTap: _toggleFocus,
  );

  Widget _buildNarrowBar(Palette p) {
    return GlassPanel(
      radius: _barHeight / 2,
      padding: const EdgeInsets.only(left: 18, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Switch classroom. Current: ${_plan.title}',
              excludeSemantics: true,
              child: Builder(
                builder: (anchor) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showClassroomSheet(anchor: anchor),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _plan.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TypeRamp.heading(p.ink)
                                .weighted(FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.chevron_down,
                          size: 13,
                          color: p.inkSoft,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _themeButton(),
          ..._directionControl(iconOnly: true),
          PressButton(
            label: _filter.isActive
                ? 'Filter, ${_filter.count} active'
                : 'Filter',
            icon: CupertinoIcons.line_horizontal_3_decrease,
            iconOnly: true,
            selected: _filter.isActive,
            quiet: true,
            height: 44,
            onTap: () => setState(() => _filterOpen = !_filterOpen),
          ),
          PressButton(
            label: 'Focus on me',
            icon: CupertinoIcons.scope,
            iconOnly: true,
            selected: _focusOn,
            selectedColor: p.route,
            quiet: true,
            height: 44,
            onTap: _toggleFocus,
          ),
        ],
      ),
    );
  }

  /// The next step's headline, or what to say when there isn't one.
  String get _nextHeadline {
    final next = _plan.nextStepFor(_plan.meId);
    if (next != null) return 'Next: ${next.title}';
    if (_plan.steps.isEmpty) return 'No steps yet';
    final left = _plan.steps.values.any(
      (s) => s.ownerId == _plan.meId && s.status != StepStatus.done,
    );
    return left ? 'Nothing ready yet' : 'You’re all done';
  }

  Widget _iconSegment(IconData icon, String label, Palette p) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Icon(icon, size: 18, color: p.ink),
    ),
  );

  /// Everything on one slim line, so a turned phone keeps its height for the
  /// graph: no bottom bar, and nothing floating over the map.
  Widget _buildShortBar(Palette p) {
    final next = _plan.nextStepFor(_plan.meId);
    return GlassPanel(
      radius: _shortBarHeight / 2,
      padding: const EdgeInsets.only(left: 14),
      child: Row(
        children: [
          Flexible(
            flex: 2,
            child: Semantics(
              button: true,
              label: 'Switch classroom. Current: ${_plan.title}',
              excludeSemantics: true,
              child: Builder(
                builder: (anchor) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showClassroomSheet(anchor: anchor),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _plan.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TypeRamp.label(p.ink)
                                .weighted(FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          CupertinoIcons.chevron_down,
                          size: 12,
                          color: p.inkSoft,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 3,
            child: Semantics(
              button: next != null,
              label: _nextHeadline,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: next == null ? null : () => _goTo(next.id),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (next != null)
                        Container(
                          width: 13,
                          height: 13,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: p.route, width: 3),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          _nextHeadline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeRamp.label(p.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const OfyTarget(id: 'classroom:views', child: SizedBox(width: 8)),
          SizedBox(
            width: 138,
            child: CupertinoSlidingSegmentedControl<PlanView>(
              groupValue: _view,
              onValueChanged: (v) {
                if (v != null) setState(() => _view = v);
              },
              children: {
                PlanView.graph: _iconSegment(
                  CupertinoIcons.flowchart,
                  'Flowspace',
                  p,
                ),
                PlanView.timeline: _iconSegment(
                  CupertinoIcons.chart_bar,
                  'Timeline',
                  p,
                ),
                PlanView.list: _iconSegment(
                  CupertinoIcons.list_bullet,
                  'List',
                  p,
                ),
              },
            ),
          ),
          const SizedBox(width: 2),
          _themeButton(),
          ..._directionControl(iconOnly: true),
          PressButton(
            label: _filter.isActive
                ? 'Filter, ${_filter.count} active'
                : 'Filter',
            icon: CupertinoIcons.line_horizontal_3_decrease,
            iconOnly: true,
            selected: _filter.isActive,
            quiet: true,
            height: 44,
            onTap: () => setState(() => _filterOpen = !_filterOpen),
          ),
          PressButton(
            label: 'Focus on me',
            icon: CupertinoIcons.scope,
            iconOnly: true,
            selected: _focusOn,
            selectedColor: p.route,
            quiet: true,
            height: 44,
            onTap: _toggleFocus,
          ),
          PressButton(
            label: 'Show the whole plan',
            icon: CupertinoIcons.arrow_up_left_arrow_down_right,
            iconOnly: true,
            quiet: true,
            height: 44,
            onTap: () => _camera.fit(fitPadding),
          ),
          _keyButton(44),
          if (widget.session != null) ...[
            OfyTarget(
              id: 'classroom:more',
              child: CountBadge(
                count: _moreCount,
                child: PressButton(
                  label: _moreCount > 0 ? 'More, $_moreCount new' : 'More',
                  icon: CupertinoIcons.ellipsis_circle,
                  iconOnly: true,
                  quiet: true,
                  height: 44,
                  onTap: _showMore,
                ),
              ),
            ),
            PressButton(
              label: 'Your profile',
              icon: CupertinoIcons.person_crop_circle,
              iconOnly: true,
              quiet: true,
              height: 44,
              onTap: _showProfile,
            ),
          ],
        ],
      ),
    );
  }

  /// A floating capsule, so the plan carries on underneath it.
  Widget _buildTabBar(Palette p, double width) {
    const views = [
      (PlanView.graph, CupertinoIcons.flowchart, 'Flowspace'),
      (PlanView.timeline, CupertinoIcons.chart_bar, 'Timeline'),
      (PlanView.list, CupertinoIcons.list_bullet, 'List'),
    ];
    final session = widget.session != null;
    final tabs = views.length + (session ? 2 : 0);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final barWidth = math.min(session ? 420.0 : _tabBarWidth, width - 24);

    Widget tab(
      String label,
      IconData icon,
      bool selected,
      VoidCallback onTap, {
      int count = 0,
      String? target,
    }) => Expanded(
      child: OfyTarget(
        id: target ?? 'tab:$label',
        child: Semantics(
          button: true,
          selected: selected,
          label: count > 0 ? '$label, $count new' : label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CountBadge(
                  count: count,
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? p.ink : p.inkSoft,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  textScaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.15),
                  style: TypeRamp.caption(selected ? p.ink : p.inkSoft)
                      .copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: (width - barWidth) / 2,
      width: barWidth,
      bottom: MediaQuery.paddingOf(context).bottom + kPaneGap,
      height: _tabBarHeight,
      child: GlassPanel(
        radius: _tabBarHeight / 2,
        weight: GlassWeight.thin,
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            AnimatedAlign(
              alignment: Alignment(-1 + 2 * _view.index / (tabs - 1), 0),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 1 / tabs,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: glassTint(
                    p,
                    p.accent,
                    radius: (_tabBarHeight - 8) / 2,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final (view, icon, label) in views)
                  tab(
                    label,
                    icon,
                    _view == view,
                    () => setState(() => _view = view),
                    target: 'classroom:views',
                  ),
                if (session) ...[
                  tab(
                    'More',
                    CupertinoIcons.ellipsis_circle,
                    false,
                    _showMore,
                    count: _moreCount,
                    target: 'classroom:more',
                  ),
                  tab(
                    'Profile',
                    CupertinoIcons.person_crop_circle,
                    false,
                    _showProfile,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Opens [sections] as a pane of glass dropping from [anchor], or as a sheet
  /// when there's nothing to drop from.
  void _dropMenu(
    BuildContext? anchor,
    String title,
    List<MenuSection> sections,
  ) {
    if (anchor == null) {
      unawaited(
        showGlassSheet<void>(
          context,
          (_) => GlassMenuSheet(title: title, sections: sections),
        ),
      );
      return;
    }
    unawaited(
      showGlassPopover<void>(
        anchor,
        builder: (popover) => GlassPanel(
          radius: 22,
          weight: GlassWeight.thick,
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
          child: SingleChildScrollView(
            child: GlassMenuList(
              sections: sections,
              dense: true,
              onDone: () => Navigator.of(popover).pop(),
            ),
          ),
        ),
      ),
    );
  }

  void _showClassroomSheet({BuildContext? anchor}) {
    if (widget.session != null) {
      unawaited(_switchClassroom(anchor));
      return;
    }
    final p = Palette.of(context);
    _dropMenu(anchor, 'Classrooms', [
      MenuSection('Sample plans', [
        for (var i = 0; i < _planNames.length; i++)
          MenuEntry(
            _planNames[i],
            i == _planIndex
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.rectangle_stack,
            () => _switchPlan(i),
            colour: i == _planIndex ? p.done : p.accent,
          ),
      ]),
    ]);
  }

  /// The classroom's name switches classrooms, and nothing else.
  Future<void> _switchClassroom([BuildContext? anchor]) async {
    final session = widget.session!;
    final List<Classroom> rooms;
    try {
      rooms = await session.backend.classrooms().first;
    } on Object {
      _showNotice('Your classrooms couldn’t load. Please retry.');
      return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final p = Palette.of(context);
    // The name it drops from may have gone while the list loaded; checked here.
    final from = anchor != null && anchor.mounted ? anchor : null;
    // ignore: use_build_context_synchronously
    _dropMenu(from, 'Switch classroom', [
      MenuSection('Your classrooms', [
        for (final room in rooms)
          MenuEntry(
            room.title,
            room.id == session.classroomId
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.rectangle_stack,
            () {
              if (room.id == session.classroomId) return;
              navigator.pushReplacement(
                GlassRoute<void>(
                  builder: (_) => ClassroomScreen(
                    onBrightnessChanged: widget.onBrightnessChanged,
                    session: ClassroomSession(
                      backend: session.backend,
                      classroomId: room.id,
                    ),
                  ),
                ),
              );
            },
            colour: room.id == session.classroomId ? p.done : p.accent,
          ),
      ]),
      MenuSection('Elsewhere', [
        MenuEntry(
          'Dashboard',
          CupertinoIcons.square_grid_2x2,
          () => navigator.maybePop(),
          colour: p.route,
        ),
      ]),
    ]);
  }

  // Content -------------------------------------------------------------------

  Widget _buildContent(Palette p, bool narrow, EdgeInsets shell) {
    final selected = _plan.steps[_selectedId];
    final panelStep = selected ?? _plan.steps[_lastSelectedId];
    final panelOpen = selected != null;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final short = _isShort(context);
        final clear = _graphInsets(context).deflateSize(constraints.biggest);
        final phone = _phoneCanvas(context);
        final stripEnd = _graphInsets(context).top + phaseStripFor(clear);
        final gutterEnd = shell.left + laneGutterFor(clear);
        final showMap = !phone && !short;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                switchInCurve: Curves.linear,
                switchOutCurve: Curves.linear,
                layoutBuilder: onlyNewest,
                transitionBuilder: (child, animation) =>
                    glassSwitch(child, animation, drift: 16),
                child: KeyedSubtree(
                  key: ValueKey(_view),
                  child: _buildPlanView(p, panelOpen, narrow, shell),
                ),
              ),
            ),
            if (_view == PlanView.graph && _plan.steps.isNotEmpty) ...[
              if (!short && _activeEdge == null)
                Positioned(
                  left: gutterEnd + 10,
                  top: stripEnd + 8,
                  child: InProgressTab(plan: _plan, onOpen: (id) => _goTo(id)),
                ),
              if (!short && (_activeEdge == null || showMap))
                _buildNextCard(p, phone, panelOpen, shell, stripEnd),
              if (_activeEdge != null)
                _buildEdgeBar(
                  p,
                  _activeEdge!,
                  clear.width,
                  shell,
                  stripEnd,
                  gutterEnd,
                ),
              if (showMap)
                _buildMapControls(p, panelOpen && !narrow, shell)
              else if (!short)
                _buildZoomControls(p, shell),
              if (_keyOpen)
                if (short)
                  Positioned(
                    top: shell.top,
                    right: 16,
                    bottom: 8,
                    width: 300,
                    child: const SingleChildScrollView(child: MapKey()),
                  )
                else
                  Positioned(
                    left: phone ? 12 : null,
                    right: 16,
                    bottom: shell.bottom + (phone ? 60 : 168),
                    width: phone ? null : 300,
                    child: const MapKey(),
                  ),
            ],
            if (_linkFromId != null) _buildLinkBanner(p, stripEnd, gutterEnd),
            if (narrow && !short) _buildTabBar(p, constraints.maxWidth),
            if (_menu != null) ..._buildContextMenu(p, constraints.biggest),
            if (panelStep != null && (!narrow || short))
              Positioned(
                top: shell.top,
                right: 10,
                bottom: shell.bottom,
                width: _panelWidth,
                child: SidePanelHost(
                  open: panelOpen,
                  width: _panelWidth,
                  child: GlassPanel(
                    radius: 24,
                    weight: GlassWeight.thick,
                    child: _stepPanel(panelStep, narrow, null),
                  ),
                ),
              ),
            if (panelStep != null && narrow && !short)
              Positioned(
                left: 8,
                right: 8,
                bottom: safeBottom + 8,
                height: math.min(
                  (constraints.maxHeight - shell.top - safeBottom) * 0.62,
                  680,
                ),
                child: BottomSheetHost(
                  open: panelOpen,
                  height: math.min(
                    (constraints.maxHeight - shell.top - safeBottom) * 0.62,
                    680,
                  ),
                  onDismissed: () => _select(null),
                  boxed: true,
                  builder: (context, grabber) => GlassPanel(
                    radius: 28,
                    weight: GlassWeight.thick,
                    child: _stepPanel(panelStep, narrow, grabber),
                  ),
                ),
              ),
            if (widget.session != null && _plan.steps.isEmpty)
              Positioned(
                left: gutterEnd,
                top: stripEnd,
                right: shell.right,
                bottom: shell.bottom,
                child: _buildEmptyPlan(p),
              ),
            _buildNotice(p, narrow, shell, gutterEnd),
          ],
        );
      },
    );
  }

  /// A new classroom, or one still loading, in place of an empty map.
  Widget _buildEmptyPlan(Palette p) {
    final String text;
    final String? action;
    if (_stored == null) {
      return const Center(child: CupertinoActivityIndicator());
    } else if (_plan.phases.isEmpty) {
      text = _manages
          ? 'Let Ofy draft the phases and steps from your task, or add the big '
                'stages yourself as phases, then fill each with steps.'
          : 'The master hasn’t added any phases yet.';
      action = _manages ? 'Add phases myself' : null;
    } else {
      text = 'No steps yet. Add what needs doing, who’s doing it and when.';
      action = 'Add a step';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassPanel(
            radius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TypeRamp.body(p.ink),
                ),
                if (_manages) ...[
                  const SizedBox(height: 14),
                  PressButton(
                    label: 'Draft a plan with Ofy',
                    icon: CupertinoIcons.sparkles,
                    prominent: true,
                    height: 44,
                    expand: true,
                    onTap: _draftPlan,
                  ),
                ],
                if (action != null) ...[
                  SizedBox(height: _manages ? 8 : 14),
                  PressButton(
                    label: action,
                    prominent: !_manages,
                    height: 44,
                    expand: true,
                    onTap: _plan.phases.isEmpty ? _showPhases : _addStep,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepPanel(PlanStep step, bool narrow, Widget? header) {
    final touch = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => narrow,
    };
    return OfyTarget(
      id: 'step:panel',
      child: StepPanel(
        plan: _plan,
        step: step,
        touch: touch,
        header: header,
        onClose: () => _select(null),
        onMarkDone: () => _markDone(step.id),
        onStart: () => _controller.setStatus(step.id, StepStatus.doing),
        onReopen: () => _controller.setStatus(step.id, StepStatus.todo),
        onHandOver: (ownerId) {
          if (ownerId == step.ownerId || !_canEdit(step.id)) return;
          // In a classroom, your own step goes by request; the master and
          // co-masters can still move anyone else's.
          if (widget.session != null && step.ownerId == _me) {
            unawaited(_requestHandover(step.id, ownerId));
            return;
          }
          _controller.handOver(step.id, ownerId);
          _showNotice('Handed to ${_plan.member(ownerId).name}');
        },
        onOpenStep: _goTo,
        onRemoveDependency: (id) => _controller.removeDependency(step.id, id),
        onToggleChecklist: (i) => _controller.toggleChecklist(step.id, i),
        onDelete: () => _delete(step.id),
        onCalendar: () => _showCalendar(stepId: step.id),
        sharedPart: step.shared && widget.session != null
            ? SharedPartPanel(
                plan: _plan,
                step: step,
                onOpenPart: (u) => _openPart(step.id, u),
              )
            : null,
        editable: widget.session == null || _canEdit(step.id),
        approvals: _room?.approvalRequired ?? false,
        canApprove: _room != null && _manages,
        onApprove: () => _controller.setStatus(step.id, StepStatus.done),
        onSendBack: () => _controller.setStatus(step.id, StepStatus.doing),
        onEdit: widget.session == null ? null : () => _editStep(step),
        onAddDependency: widget.session == null || step.ownerId != _me
            ? null
            : () => _pickNeed(step),
        showNeeds: widget.session == null || step.ownerId == _me,
        onSaveDescription: step.ownerId == _me
            ? (text) {
                _controller.adopt(
                  _plan.replacing(step.copyWith(description: text)),
                );
                _showNotice('Description saved');
              }
            : null,
        collab: _backend == null
            ? null
            : StepCollab(
                key: ValueKey('collab-${step.id}'),
                backend: _backend!,
                classroomId: _classroomId,
                plan: _plan,
                step: step,
                canManage: _manages,
                onNotice: _showNotice,
                masterUid: _room?.masterUid ?? '',
                classroomTitle: _room?.title ?? '',
              ),
      ),
    );
  }

  Widget _buildPlanView(
    Palette p,
    bool panelOpen,
    bool narrow,
    EdgeInsets shell,
  ) {
    // An empty plan has no dates to chart or rows to list.
    if (_plan.steps.isEmpty && _view != PlanView.graph) {
      return const SizedBox.shrink();
    }
    switch (_view) {
      case PlanView.graph:
        return GraphView(
          key: ValueKey('graph-$_graphEpoch'),
          controller: _controller,
          camera: _camera,
          filter: _filter,
          focus: _focus,
          celebration: _celebration,
          celebrateId: _celebrateId,
          changes: _changes,
          changing: _changing,
          selectedId: _selectedId,
          linkFromId: _linkFromId,
          selectedEdge: _activeEdge,
          onSelect: _select,
          onSelectEdge: _selectEdge,
          onContextMenu: (id, position) {
            setState(() {
              _selectedId = null;
              _menu = (id, position);
            });
          },
          onLinked: _link,
          onMoved: (id) {
            final s = _plan.steps[id];
            if (s == null) return;
            _showNotice(
              'Moved to ${_plan.phase(s.phaseId).title}, ${_plan.member(s.ownerId).name}',
            );
          },
          onToggleFocus: _toggleFocus,
          onMarkDone: _markDone,
          onStartLink: (id) => setState(() {
            _linkFromId = id.isEmpty ? null : id;
          }),
          onViewportReady: _frameInitialView,
          onFitPhase: _fitPhase,
          onToggleDirection: _toggleDirection,
          canEdit: widget.session == null ? null : _canEdit,
          onMemberTap: widget.session == null ? null : _memberTap,
          onRequestHandover: widget.session == null || _manages
              ? null
              : (id, to) => unawaited(_requestHandover(id, to)),
          onHandleTap: _stepPlus,
        );
      case PlanView.timeline:
        return Padding(
          padding: shell,
          child: PlanTimelineView(
            key: ValueKey(_planIndex),
            plan: _plan,
            filter: _filter,
            selectedId: _selectedId,
            onOpen: _select,
          ),
        );
      case PlanView.list:
        // Scrolls under the floating bars, and clears them at either end.
        return Padding(
          padding: EdgeInsets.only(left: shell.left, right: shell.right),
          child: PlanListView(
            plan: _plan,
            filter: _filter,
            selectedId: _selectedId,
            onOpen: _select,
            topInset: shell.top,
            bottomInset: shell.bottom,
          ),
        );
    }
  }

  String _nextLine(PlanStep next) {
    final due = 'Due ${shortDate(next.due)}.';
    if (next.status == StepStatus.doing) return 'In progress. $due';
    final finished =
        next.dependsOn
            .map((id) => _plan.steps[id])
            .whereType<PlanStep>()
            .toList()
          ..sort((a, b) => b.due.compareTo(a.due));
    if (finished.isEmpty) return 'You can start now. $due';
    return '“${finished.first.title}” is done, so you can start. $due';
  }

  /// Hides the card when it would cover the very step it names.
  Widget _clearOfNextStep(
    PlanStep? next,
    Rect Function(Size viewport) cardRect,
    bool panelOpen,
    Widget card,
  ) {
    return ListenableBuilder(
      listenable: _camera,
      builder: (context, child) {
        var hidden = panelOpen;
        final at = next == null ? null : _controller.positions[next.id];
        if (at != null && !hidden) {
          final size = cameraNodeSize(_camera);
          final step = Rect.fromCenter(
            center: _camera.toScreen(at),
            width: size.width,
            height: size.height,
          );
          hidden = step.overlaps(cardRect(_camera.viewport));
        }
        return AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: const Duration(milliseconds: 160),
          child: IgnorePointer(ignoring: hidden, child: child),
        );
      },
      child: card,
    );
  }

  Widget _buildNextCard(
    Palette p,
    bool narrow,
    bool panelOpen,
    EdgeInsets shell,
    double stripEnd,
  ) {
    final next = _plan.nextStepFor(_plan.meId);
    final mineLeft = _plan.steps.values
        .where((s) => s.ownerId == _plan.meId && s.status != StepStatus.done)
        .length;
    final String title;
    final String line;
    if (next != null) {
      title = 'Next: ${next.title}';
      line = _nextLine(next);
    } else if (mineLeft > 0) {
      title = 'Nothing ready yet';
      line = 'Your steps are waiting on other people.';
    } else {
      title = 'You’re all done';
      line = 'None of your steps are left in this plan.';
    }
    final card = Semantics(
      button: next != null,
      label: '$title. $line',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: next == null ? null : () => _goTo(next.id),
        child: GlassPanel(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (next != null) ...[
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 2, right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.route, width: 3),
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeRamp.label(p.ink).weighted(FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TypeRamp.caption(p.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (narrow) {
      // On a phone: one line, so the map keeps its room.
      final pill = Semantics(
        button: next != null,
        label: '$title. $line',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: next == null ? null : () => _goTo(next.id),
          child: GlassPanel(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (next != null)
                  Container(
                    width: 15,
                    height: 15,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: p.route, width: 3),
                    ),
                  ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.label(p.ink).weighted(FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final left = shell.left + (widget.session == null ? 96 : 140);
      final bottom = shell.bottom + kPaneGap;
      return Positioned(
        left: left,
        right: shell.right,
        bottom: bottom,
        child: _clearOfNextStep(
          next,
          (v) => Rect.fromLTRB(
            left,
            v.height - bottom - 48,
            v.width - shell.right,
            v.height - bottom,
          ),
          panelOpen,
          pill,
        ),
      );
    }
    final top = stripEnd + 8;
    final right = shell.right + 6;
    return Positioned(
      top: top,
      right: right,
      width: 250,
      child: _clearOfNextStep(
        next,
        (v) => Rect.fromLTWH(v.width - right - 250, top, 250, 72),
        panelOpen,
        card,
      ),
    );
  }

  Widget _buildZoomControls(Palette p, EdgeInsets shell) {
    return Positioned(
      left: shell.left,
      bottom: shell.bottom + kPaneGap,
      child: GlassPanel(
        radius: 22,
        child: Flex(
          direction: Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.session != null)
              OfyTarget(
                id: 'classroom:add-step',
                child: PressButton(
                  label: 'Add a step',
                  icon: CupertinoIcons.plus,
                  iconOnly: true,
                  quiet: true,
                  height: 44,
                  onTap: _addStep,
                ),
              ),
            PressButton(
              label: 'Show the whole plan',
              icon: CupertinoIcons.arrow_up_left_arrow_down_right,
              iconOnly: true,
              quiet: true,
              height: 44,
              onTap: () => _camera.fit(fitPadding),
            ),
            _keyButton(44),
          ],
        ),
      ),
    );
  }

  Widget _keyButton(double height) => PressButton(
    label: _keyOpen ? 'Hide the map key' : 'Show the map key',
    icon: CupertinoIcons.info,
    iconOnly: true,
    quiet: !_keyOpen,
    selected: _keyOpen,
    height: height,
    onTap: () => setState(() => _keyOpen = !_keyOpen),
  );

  Widget _buildMapControls(Palette p, bool panelOpen, EdgeInsets shell) {
    void zoom(double f) => _camera.zoomStep(f);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      right: panelOpen ? _panelWidth + 20 : shell.right + 70,
      bottom: shell.bottom + 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_mapShown) ...[
            GlassPanel(
              radius: 16,
              child: Minimap(
                controller: _controller,
                camera: _camera,
                size: const Size(140, 80),
              ),
            ),
            const SizedBox(height: 6),
          ],
          GlassPanel(
            radius: 18,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.session != null)
                  OfyTarget(
                    id: 'classroom:add-step',
                    child: PressButton(
                      label: 'Add a step',
                      icon: CupertinoIcons.plus_circle,
                      iconOnly: true,
                      quiet: true,
                      height: 36,
                      onTap: _addStep,
                    ),
                  ),
                PressButton(
                  label: 'Zoom in',
                  icon: CupertinoIcons.plus,
                  iconOnly: true,
                  quiet: true,
                  height: 36,
                  onTap: () => zoom(1.3),
                ),
                PressButton(
                  label: 'Zoom out',
                  icon: CupertinoIcons.minus,
                  iconOnly: true,
                  quiet: true,
                  height: 36,
                  onTap: () => zoom(0.77),
                ),
                PressButton(
                  label: 'Fit to screen',
                  icon: CupertinoIcons.arrow_up_left_arrow_down_right,
                  iconOnly: true,
                  quiet: true,
                  height: 36,
                  onTap: () => _camera.fit(fitPadding),
                ),
                _keyButton(36),
                PressButton(
                  label: _mapShown ? 'Hide the minimap' : 'Show the minimap',
                  icon: CupertinoIcons.map,
                  iconOnly: true,
                  quiet: !_mapShown,
                  selected: _mapShown,
                  height: 36,
                  onTap: () => setState(() => _mapShown = !_mapShown),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Whether the small overview of the whole plan shows above the controls.
  var _mapShown = false;

  /// Names both ends of the tapped arrow. Either may be off screen in a big
  /// plan, so each name takes you there.
  Widget _buildEdgeBar(
    Palette p,
    (String, String) edge,
    double width,
    EdgeInsets shell,
    double stripEnd,
    double gutterEnd,
  ) {
    final from = _plan.steps[edge.$1]!;
    final to = _plan.steps[edge.$2]!;
    final bar = Semantics(
      label: 'Arrow from ${from.title} to ${to.title}.',
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: _EdgeEnd(
                plan: _plan,
                step: from,
                label: 'From',
                onTap: () => _showEnd(from.id),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                CupertinoIcons.arrow_right,
                size: 16,
                color: p.inkSoft,
              ),
            ),
            Expanded(
              child: _EdgeEnd(
                plan: _plan,
                step: to,
                label: 'To',
                onTap: () => _showEnd(to.id),
              ),
            ),
            PressButton(
              label: 'Clear highlighted arrow',
              icon: CupertinoIcons.xmark,
              iconOnly: true,
              quiet: true,
              height: 44,
              onTap: () => setState(() => _selectedEdge = null),
            ),
          ],
        ),
      ),
    );
    if (_isShort(context)) {
      return Positioned(
        left: gutterEnd + 8,
        right: 12,
        top: stripEnd + 4,
        child: bar,
      );
    }
    if (width < _mapMinWidth) {
      return Positioned(
        left: shell.left,
        right: shell.right,
        bottom: shell.bottom + kPaneGap,
        child: bar,
      );
    }
    if (width < 900) {
      return Positioned(
        left: gutterEnd + 8,
        right: shell.right + 6,
        top: stripEnd + 132,
        child: bar,
      );
    }
    return Positioned(
      left: gutterEnd + 8,
      right: shell.right + 342,
      top: stripEnd + 12,
      child: bar,
    );
  }

  Widget _buildLinkBanner(Palette p, double stripEnd, double gutterEnd) {
    final title = _plan.steps[_linkFromId]?.title ?? '';
    return Positioned(
      top: stripEnd + 12,
      left: gutterEnd + 8,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          'Now choose the step that depends on “$title”. Esc cancels.',
          style: TypeRamp.label(p.ink),
        ),
      ),
    );
  }

  List<Widget> _buildContextMenu(Palette p, Size area) {
    final (id, global) = _menu!;
    final step = _plan.steps[id];
    if (step == null) return const [];
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.globalToLocal(global) ?? global;
    const width = 220.0;
    const height = 188.0;
    final x = origin.dx.clamp(8.0, area.width - width - 8);
    final y = origin.dy.clamp(8.0, area.height - height - 8);
    void close() => setState(() => _menu = null);
    return [
      Positioned.fill(
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: close),
      ),
      Positioned(
        left: x,
        top: y,
        width: width,
        child: _materialize(
          alignment: Alignment.topLeft,
          child: GlassPanel(
            weight: GlassWeight.thick,
            padding: const EdgeInsets.all(5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                PressButton(
                  label: 'Open step',
                  quiet: true,
                  height: 40,
                  onTap: () => _select(id),
                ),
                PressButton(
                  label: step.status == StepStatus.done
                      ? 'Reopen'
                      : 'Mark done',
                  quiet: true,
                  height: 40,
                  onTap: () {
                    close();
                    _markDone(id);
                  },
                ),
                PressButton(
                  label: 'Add a step that depends on this',
                  quiet: true,
                  height: 40,
                  onTap: () => setState(() {
                    _menu = null;
                    _linkFromId = id;
                  }),
                ),
                PressButton(
                  label: 'Delete step',
                  quiet: true,
                  destructive: true,
                  height: 40,
                  onTap: () {
                    close();
                    _delete(id);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildNotice(
    Palette p,
    bool narrow,
    EdgeInsets shell,
    double gutterEnd,
  ) {
    final notice = _notice;
    return Positioned(
      left: narrow ? 12 : gutterEnd + 8,
      right: narrow ? 12 : null,
      bottom: _isShort(context)
          ? 12
          : shell.bottom + (narrow ? _phoneRowHeight : 10),
      child: IgnorePointer(
        ignoring: notice == null,
        child: Align(
          alignment: narrow ? Alignment.center : Alignment.centerLeft,
          widthFactor: narrow ? null : 1,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            child: notice == null
                ? const SizedBox.shrink()
                : Semantics(
                    liveRegion: true,
                    child: ConstrainedBox(
                      key: ValueKey(notice.message),
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: GlassPanel(
                        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  notice.message,
                                  style: TypeRamp.label(p.ink),
                                ),
                              ),
                            ),
                            if (notice.actionLabel != null) ...[
                              const SizedBox(width: 10),
                              PressButton(
                                label: notice.actionLabel!,
                                height: 36,
                                onTap: () {
                                  notice.action?.call();
                                  setState(() => _notice = null);
                                },
                              ),
                            ] else
                              const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // Filters -------------------------------------------------------------------

  Widget _buildFilterPanel(Palette p, bool narrow) {
    Set<T> toggled<T>(Set<T> set, T value) =>
        set.contains(value) ? ({...set}..remove(value)) : {...set, value};

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(text, style: TypeRamp.label(p.inkSoft)),
    );

    const standings = [
      (Standing.doing, 'In progress'),
      (Standing.ready, 'Ready'),
      (Standing.waiting, 'Waiting'),
      (Standing.blocked, 'Blocked'),
      (Standing.done, 'Done'),
    ];

    return SizedBox(
      width: narrow ? null : 340,
      child: GlassPanel(
        weight: GlassWeight.thick,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height - 160,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Filter', style: TypeRamp.heading(p.ink)),
                    ),
                    PressButton(
                      label: 'Clear',
                      quiet: true,
                      onTap: _filter.isActive
                          ? () => setState(() => _filter = const GraphFilter())
                          : null,
                    ),
                  ],
                ),
                label('Member'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in _plan.members)
                      SelectChip(
                        label: m.name,
                        selected: _filter.memberIds.contains(m.id),
                        onTap: () => setState(() {
                          _filter = _filter.copyWith(
                            memberIds: toggled(_filter.memberIds, m.id),
                          );
                        }),
                      ),
                  ],
                ),
                label('Phase'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ph in _plan.phases)
                      SelectChip(
                        label: ph.title,
                        selected: _filter.phaseIds.contains(ph.id),
                        onTap: () => setState(() {
                          _filter = _filter.copyWith(
                            phaseIds: toggled(_filter.phaseIds, ph.id),
                          );
                        }),
                      ),
                  ],
                ),
                label('Status'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (s, name) in standings)
                      SelectChip(
                        label: name,
                        selected: _filter.standings.contains(s),
                        onTap: () => setState(() {
                          _filter = _filter.copyWith(
                            standings: toggled(_filter.standings, s),
                          );
                        }),
                      ),
                    SelectChip(
                      label: 'Overdue',
                      selected: _filter.overdueOnly,
                      onTap: () => setState(() {
                        _filter = _filter.copyWith(
                          overdueOnly: !_filter.overdueOnly,
                        );
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeEnd extends StatelessWidget {
  const _EdgeEnd({
    required this.plan,
    required this.step,
    required this.label,
    required this.onTap,
  });

  final Plan plan;
  final PlanStep step;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: 'Go to $label step: ${step.title}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TypeRamp.caption(p.inkSoft)),
              const SizedBox(height: 1),
              Row(
                children: [
                  StandingMark(plan.standing(step), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      step.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeRamp.label(p.ink),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Changes waiting to be seen, shown as a red number.
  final int count;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.count > 0
          ? '${widget.label}, ${widget.count} new'
          : widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: widget.selected
                  ? p.control
                  : (_hovered ? p.hairline : const Color(0x00000000)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.label(widget.selected ? p.ink : p.inkSoft)
                        .weighted(
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                ),
                if (widget.count > 0)
                  CountBadge(
                    count: widget.count,
                    child: const SizedBox(width: 15, height: 10),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
