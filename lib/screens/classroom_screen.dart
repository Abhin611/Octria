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
import '../widgets/spring_sheet.dart';
import 'classroom_forms.dart';
import 'map_key.dart';
import 'plan_views.dart';
import 'step_panel.dart';
import 'timeline_view.dart';

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
        (_) => ActionListSheet(
          title: 'Classroom',
          items: [
            if (_isShort(context)) ('Add a step', 0, _addStep),
            ..._classroomActions(),
          ],
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
    _controller.adopt(_plan.withSteps([..._plan.steps.values, added]));
    _showNotice('Added “${added.title}”');
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

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _sync?.dispose();
    unawaited(_feed?.cancel());
    _controller.removeListener(_onPlanChanged);
    _controller.dispose();
    _camera.dispose();
    _focus.dispose();
    _celebration.dispose();
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
    return PressButton(
      label: dark ? 'Switch to white background' : 'Switch to dark background',
      icon: dark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
      iconOnly: true,
      quiet: true,
      height: height,
      onTap: () =>
          widget.onBrightnessChanged(dark ? Brightness.light : Brightness.dark),
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
            item('Dashboard', false, () => Navigator.of(context).maybePop()),
            const SizedBox(height: 14),
            for (final (label, count, action) in _classroomActions())
              item(label, false, action, count: count),
            const Spacer(),
            item('Your profile', false, _showProfile),
          ],
        ],
      ),
    );
  }

  /// Everything to do with the open classroom, for the sidebar and the menu.
  List<(String, int, VoidCallback)> _classroomActions() {
    final individual = _room?.individual ?? false;
    return [
      if (_manages) ('Phases', 0, _showPhases),
      if (!individual) ('Members and invite code', 0, _showMembers),
      if (!individual) ('Since you were away', _unread, _showAwayNews),
      if (!individual) ('Activity', 0, _showActivity),
      if (_isMaster) ('Settings', 0, _showSettings),
      if (!individual) ('Leave classroom', 0, _leaveClassroom),
    ];
  }

  Widget _buildToolbar(Palette p) {
    final room =
        MediaQuery.sizeOf(context).width - _shellInsets(context).horizontal;
    final compact = room < _labelledToolbarWidth;
    return GlassPanel(
      radius: _barHeight / 2,
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
          const SizedBox(width: 12),
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showClassroomSheet,
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showClassroomSheet,
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
          const SizedBox(width: 8),
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
            CountBadge(
              count: _unread,
              child: PressButton(
                label: _unread > 0 ? 'More, $_unread new' : 'More',
                icon: CupertinoIcons.ellipsis_circle,
                iconOnly: true,
                quiet: true,
                height: 44,
                onTap: _showMore,
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
    }) => Expanded(
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
    );

    return Positioned(
      left: (width - barWidth) / 2,
      width: barWidth,
      bottom: MediaQuery.paddingOf(context).bottom + kPaneGap,
      height: _tabBarHeight,
      child: GlassPanel(
        radius: _tabBarHeight / 2,
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
                  decoration: BoxDecoration(
                    color: p.control,
                    borderRadius: BorderRadius.circular(
                      (_tabBarHeight - 8) / 2,
                    ),
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
                  ),
                if (session) ...[
                  tab(
                    'More',
                    CupertinoIcons.ellipsis_circle,
                    false,
                    _showMore,
                    count: _unread,
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

  void _showClassroomSheet() {
    if (widget.session != null) {
      unawaited(_switchClassroom());
      return;
    }
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Classrooms'),
        message: const Text('All plans here are sample data.'),
        actions: [
          for (var i = 0; i < _planNames.length; i++)
            CupertinoActionSheetAction(
              isDefaultAction: i == _planIndex,
              onPressed: () {
                Navigator.of(context).pop();
                _switchPlan(i);
              },
              child: Text(_planNames[i]),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  /// The classroom's name switches classrooms, and nothing else.
  Future<void> _switchClassroom() async {
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
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('Switch classroom'),
          actions: [
            for (final room in rooms)
              CupertinoActionSheetAction(
                isDefaultAction: room.id == session.classroomId,
                onPressed: () {
                  Navigator.of(context).pop();
                  if (room.id == session.classroomId) return;
                  navigator.pushReplacement(
                    CupertinoPageRoute<void>(
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
                child: Text(room.title),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(context).pop();
                navigator.maybePop();
              },
              child: const Text('Dashboard'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
      ),
    );
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
            Positioned.fill(child: _buildPlanView(p, panelOpen, narrow, shell)),
            if (_view == PlanView.graph && _plan.steps.isNotEmpty) ...[
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
                left: 0,
                right: 0,
                bottom: 0,
                height: constraints.maxHeight - shell.top,
                child: BottomSheetHost(
                  open: panelOpen,
                  height: constraints.maxHeight - shell.top,
                  onDismissed: () => _select(null),
                  builder: (context, grabber) => GlassPanel(
                    radius: 28,
                    weight: GlassWeight.thick,
                    padding: EdgeInsets.only(bottom: safeBottom),
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
          ? 'Start with the big stages of the work. Add them as phases, then '
                'fill each with steps.'
          : 'The master hasn’t added any phases yet.';
      action = _manages ? 'Add phases' : null;
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
                if (action != null) ...[
                  const SizedBox(height: 14),
                  PressButton(
                    label: action,
                    prominent: true,
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
    return StepPanel(
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
        _controller.handOver(step.id, ownerId);
        _showNotice('Handed to ${_plan.member(ownerId).name}');
      },
      onOpenStep: _goTo,
      onRemoveDependency: (id) => _controller.removeDependency(step.id, id),
      onToggleChecklist: (i) => _controller.toggleChecklist(step.id, i),
      onDelete: () => _delete(step.id),
      editable: widget.session == null || _canEdit(step.id),
      approvals: _room?.approvalRequired ?? false,
      canApprove: _room != null && _manages,
      onApprove: () => _controller.setStatus(step.id, StepStatus.done),
      onSendBack: () => _controller.setStatus(step.id, StepStatus.doing),
      onEdit: widget.session == null ? null : () => _editStep(step),
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
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (next != null) ...[
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 3, right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.route, width: 4),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: narrow
                          ? TypeRamp.title(p.ink)
                          : TypeRamp.title(p.ink)
                                .copyWith(fontSize: 25, letterSpacing: -0.6),
                    ),
                    const SizedBox(height: 3),
                    Text(line, style: TypeRamp.label(p.inkSoft)),
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
    final top = stripEnd + 12;
    final right = shell.right + 6;
    return Positioned(
      top: top,
      right: right,
      width: 320,
      child: _clearOfNextStep(
        next,
        (v) => Rect.fromLTWH(v.width - right - 320, top, 320, 112),
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
              PressButton(
                label: 'Add a step',
                icon: CupertinoIcons.plus,
                iconOnly: true,
                quiet: true,
                height: 44,
                onTap: _addStep,
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
      right: panelOpen ? _panelWidth + 20 : shell.right + 6,
      bottom: shell.bottom + 6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GlassPanel(
            radius: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.session != null)
                  PressButton(
                    label: 'Add a step',
                    icon: CupertinoIcons.plus_circle,
                    iconOnly: true,
                    quiet: true,
                    height: 36,
                    onTap: _addStep,
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
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlassPanel(
            radius: 18,
            child: Minimap(controller: _controller, camera: _camera),
          ),
        ],
      ),
    );
  }

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
