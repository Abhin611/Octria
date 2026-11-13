import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../ai/ai.dart';
import '../ai/schedule.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart';
import 'resource_finder.dart';

enum _Stage { write, drafting, review, saving }

/// Ofy plans with the person: they say in their own words what they want (a
/// whole plan, or something to add), with their hours and anything the plan
/// must respect; in a group, how the group works and who does what. A few
/// questions are optional. Then a draft to look over, with dates worked out
/// from the hours, placed among the steps already there. Pops true once it's
/// in the classroom.
class PlanDraftSheet extends StatefulWidget {
  const PlanDraftSheet({
    super.key,
    required this.backend,
    required this.classroom,
    required this.plan,
    this.today,
  });

  final Backend backend;
  final Classroom classroom;

  /// The classroom's plan as it stands: who's asking, its phases and steps.
  final Plan plan;
  final DateTime? today;

  @override
  State<PlanDraftSheet> createState() => _PlanDraftSheetState();
}

class _PlanDraftSheetState extends State<PlanDraftSheet> {
  var _stage = _Stage.write;
  String? _problem;

  late final _request = TextEditingController()
    ..addListener(() => setState(() {}));
  late final _hours = TextEditingController(
    text: _number(widget.classroom.hoursPerWeek),
  );
  late final _constraints = TextEditingController(
    text: widget.classroom.constraints,
  );
  late var _linked = widget.classroom.linked;

  /// Whether the hours are for each day rather than each week.
  var _perDay = false;
  late DateTime? _deadline = widget.classroom.deadline;

  /// How progress is checked after each phase: tests, checks, both, none,
  /// or the person's own word.
  late var _checkKind = switch (widget.classroom.checking) {
    'tests' || 'checks' || 'both' || 'none' => widget.classroom.checking,
    _ => 'other',
  };
  late final _checkOther = TextEditingController(
    text: switch (widget.classroom.checking) {
      'tests' || 'checks' || 'both' || 'none' => '',
      final other => other,
    },
  );

  /// Each person's skills from their profile, by uid, once they've loaded.
  final _skillsOf = <String, List<String>>{};

  Future<void> _loadSkills() async {
    if (widget.classroom.individual) return;
    for (final m in widget.plan.members) {
      try {
        final profile = await widget.backend.profileOf(m.id);
        if (profile != null) _skillsOf[m.id] = profile.skills;
      } on Object {
        // Without them Ofy still has the roles.
      }
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSkills());
  }

  /// The syllabus Ofy looked up for this draft, if it named one.
  Research? _research;
  var _lookingUp = false;

  final _speech = SpeechToText();
  var _listening = false;

  /// Speaks the description instead of typing it.
  Future<void> _dictate() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ready = await _speech.initialize();
    if (!mounted) return;
    if (!ready) {
      setState(() => _problem = 'Voice isn’t available here. Type it instead.');
      return;
    }
    final before = _request.text.trim();
    setState(() {
      _listening = true;
      _problem = null;
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (r) {
        if (!mounted) return;
        _request.text = [
          if (before.isNotEmpty) before,
          r.recognizedWords,
        ].join(' ');
        if (r.finalResult) setState(() => _listening = false);
      },
    );
  }

  /// What the point after each phase is, as chosen here.
  String get _checking => _checkKind == 'other'
      ? (_checkOther.text.trim().isEmpty ? 'checks' : _checkOther.text.trim())
      : _checkKind;
  late final Map<String, TextEditingController> _roles = {
    for (final m in widget.plan.members)
      m.id: TextEditingController(text: widget.classroom.roles[m.id] ?? ''),
  };

  var _questions = <FollowUp>[];
  final _answers = <TextEditingController>[];
  var _askingQuestions = false;

  DraftPlan? _draft;

  /// Steps left out of the draft, by key.
  final _dropped = <String>{};

  DateTime get _today => widget.today ?? DateTime.now();
  Plan get _plan => widget.plan;
  bool get _manages => widget.classroom.canManage(_plan.meId);
  bool get _isMaster => widget.classroom.masterUid == _plan.meId;
  bool get _group => !widget.classroom.individual && _plan.members.length > 1;
  bool get _adding => _plan.steps.isNotEmpty;

  static String _number(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1));

  double? get _hoursPerWeek {
    final v = double.tryParse(_hours.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return (_perDay ? v * 7 : v).clamp(0.5, 120).toDouble();
  }

  // The plan as Ofy is shown it ------------------------------------------------

  late final List<PlanStep> _ordered = () {
    final order = {
      for (var i = 0; i < _plan.phases.length; i++) _plan.phases[i].id: i,
    };
    return _plan.steps.values.toList()..sort((a, b) {
      final byPhase = (order[a.phaseId] ?? 99).compareTo(
        order[b.phaseId] ?? 99,
      );
      if (byPhase != 0) return byPhase;
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.order.compareTo(b.order);
    });
  }();

  /// e1, e2… for each step already there, and back.
  late final Map<String, String> _refOf = {
    for (var i = 0; i < _ordered.length; i++) _ordered[i].id: 'e${i + 1}',
  };
  late final Map<String, PlanStep> _stepOfRef = {
    for (final s in _ordered) _refOf[s.id]!: s,
  };

  String _nameOf(String uid) =>
      _plan.members.where((m) => m.id == uid).firstOrNull?.name ?? '';

  String _phaseTitle(String id) =>
      _plan.phases.where((p) => p.id == id).firstOrNull?.title ?? '';

  TaskBrief get _brief => TaskBrief(
    existing: [
      for (final ph in _plan.phases)
        (ph.title, [for (final s in _plan.stepsIn(ph.id)) s.title]),
    ],
    steps: [
      for (final s in _ordered)
        ExistingStep(
          ref: _refOf[s.id]!,
          phase: _phaseTitle(s.phaseId),
          title: s.title,
          done: s.status == StepStatus.done,
          owner: _group ? _nameOf(s.ownerId) : '',
          needs: [for (final n in s.dependsOn) ?_refOf[n]],
        ),
    ],
    newPhasesAllowed: _manages,
    title: widget.classroom.title,
    description: widget.classroom.description,
    constraints: _constraints.text.trim(),
    taskType: widget.classroom.taskType,
    deadline: _deadline,
    hoursPerWeek: _hoursPerWeek,
    individual: !_group,
    syllabus: _research?.syllabus ?? '',
    today: _today,
    request: _request.text.trim(),
    linked: _group && _linked,
    people: _group
        ? [
            for (final m in _plan.members)
              (
                m.name,
                // Their skills ride along with their role, so Ofy can give
                // each person what suits them.
                [
                  _roles[m.id]?.text.trim() ?? '',
                  if ((_skillsOf[m.id] ?? const <String>[]).isNotEmpty)
                    'skills: ${_skillsOf[m.id]!.take(10).join(', ')}',
                ].where((x) => x.isNotEmpty).join('; '),
              ),
          ]
        : const [],
  );

  @override
  void dispose() {
    if (_listening) unawaited(_speech.stop());
    for (final c in [
      _request,
      _hours,
      _constraints,
      _checkOther,
      ..._answers,
      ..._roles.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Asking -----------------------------------------------------------------------

  Future<void> _askQuestions() async {
    setState(() {
      _askingQuestions = true;
      _problem = null;
    });
    try {
      final qs = await widget.backend.ai.followUps(_brief);
      if (!mounted) return;
      for (final c in _answers) {
        c.dispose();
      }
      _answers
        ..clear()
        ..addAll([for (final _ in qs) TextEditingController()]);
      setState(() {
        _questions = qs;
        _askingQuestions = false;
        if (qs.isEmpty) _problem = 'Ofy has no questions. Draft away.';
      });
    } on Object catch (e) {
      _fail(e);
      if (mounted) setState(() => _askingQuestions = false);
    }
  }

  /// Keeps what was set here on the classroom, for next time and for
  /// everyone. Only the master can change the classroom.
  Future<void> _keepSettings() async {
    if (!_isMaster) return;
    final c = widget.classroom;
    final roles = {
      for (final e in _roles.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    final hours = _hoursPerWeek;
    final changed =
        hours != c.hoursPerWeek ||
        _deadline != c.deadline ||
        _checking != c.checking ||
        _constraints.text.trim() != c.constraints ||
        (_group && _linked != c.linked) ||
        (_group && !_sameRoles(roles, c.roles));
    if (!changed) return;
    try {
      await widget.backend.updateClassroom(
        Classroom(
          id: c.id,
          title: c.title,
          masterUid: c.masterUid,
          memberUids: c.memberUids,
          inviteCode: c.inviteCode,
          createdAt: c.createdAt,
          description: c.description,
          constraints: _constraints.text.trim(),
          taskType: c.taskType,
          individual: c.individual,
          coMasterUids: c.coMasterUids,
          deadline: _deadline,
          hoursPerWeek: hours,
          checkKind: _checking,
          approvalRequired: c.approvalRequired,
          joinApprovalRequired: c.joinApprovalRequired,
          linked: _group ? _linked : c.linked,
          roles: _group ? roles : c.roles,
        ),
      );
    } on BackendFailure {
      // The plan matters more than remembering the settings.
    }
  }

  static bool _sameRoles(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  Future<void> _makeDraft() async {
    if (_request.text.trim().isEmpty) {
      setState(
        () => _problem = _adding
            ? 'Say what to add first.'
            : 'Describe the plan you want first.',
      );
      return;
    }
    setState(() {
      _stage = _Stage.drafting;
      _problem = null;
    });
    unawaited(_keepSettings());
    try {
      _research = null;
      if (namesASyllabus(_request.text)) {
        setState(() => _lookingUp = true);
        try {
          _research = await widget.backend.ai.research(_brief);
        } on AiFailure {
          _research = null;
        } finally {
          if (mounted) setState(() => _lookingUp = false);
        }
        if (!mounted) return;
      }
      var draft = await widget.backend.ai.draftPlan(_brief, [
        for (var i = 0; i < _questions.length; i++)
          (_questions[i].question, _answers[i].text),
      ]);
      if (_group && _manages) {
        draft = draft.forPeople([for (final m in _plan.members) m.name]);
      }
      draft = _withChecks(draft);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _dropped.clear();
        _stage = _Stage.review;
      });
    } on Object catch (e) {
      _fail(e);
      if (mounted) setState(() => _stage = _Stage.write);
    }
  }

  /// The test or check points Ofy adds, by draft key.
  final _checkKinds = <String, StepKind>{};

  StepKind get _pointKind => switch (_checking) {
    'tests' => StepKind.test,
    'both' => StepKind.both,
    _ => StepKind.check,
  };

  String _pointTitle(String phase) => switch (_checking) {
    'tests' => 'Mock test: $phase',
    'checks' => 'Check: $phase',
    'both' => 'Mock test and check: $phase',
    final other => '${other[0].toUpperCase()}${other.substring(1)}: $phase',
  };

  /// After each new phase, a point where everyone in it takes their own mock
  /// test or goes through their own checklist; the next phase waits for it.
  DraftPlan _withChecks(DraftPlan d) {
    _checkKinds.clear();
    if (!_manages || _checking == 'none' || d.phases.isEmpty) return d;
    final phases = [
      for (final ph in d.phases) [...ph.steps],
    ];
    for (var i = 0; i < phases.length; i++) {
      final steps = phases[i];
      if (steps.isEmpty) continue;
      final key = 'chk$i';
      final keys = {for (final s in steps) s.key};
      final needed = {for (final s in steps) ...s.needs};
      // The phase's last steps: nothing else in it needs them.
      final ends = [
        for (final s in steps)
          if (!needed.contains(s.key)) s.key,
      ];
      _checkKinds[key] = _pointKind;
      steps.add(
        DraftStep(
          key: key,
          title: _pointTitle(d.phases[i].title),
          hours: 1,
          needs: ends,
          description: switch (_pointKind) {
            StepKind.test =>
              'Everyone takes their own mock test on their part of this phase.',
            StepKind.both =>
              'Everyone takes their own mock test and checks their own work.',
            _ => 'Everyone goes through their own checklist for this phase.',
          },
        ),
      );
      if (i + 1 < phases.length) {
        final next = phases[i + 1];
        final nextKeys = {for (final s in next) s.key};
        final linked = next.any((s) => s.needs.any(keys.contains));
        for (var j = 0; j < next.length; j++) {
          final s = next[j];
          final starts = !s.needs.any(nextKeys.contains);
          if (s.needs.any(keys.contains) || (!linked && starts)) {
            next[j] = s.copyWith(
              needs: [
                for (final n in s.needs)
                  if (!keys.contains(n)) n,
                key,
              ],
            );
          }
        }
      }
    }
    return DraftPlan(
      summary: d.summary,
      covered: d.covered,
      phases: [
        for (var i = 0; i < d.phases.length; i++)
          DraftPhase(
            title: d.phases[i].title,
            after: d.phases[i].after,
            steps: phases[i],
          ),
      ],
    );
  }

  void _fail(Object e) {
    debugPrint('Ofy failed: ${e.runtimeType}: $e');
    if (!mounted) return;
    setState(() {
      _problem = switch (e) {
        AiFailure(:final message) => message,
        BackendFailure(:final message) => message,
        // Something unexpected: say what, so it can be put right.
        _ => 'Ofy couldn’t answer (${_short(e)}).',
      };
    });
  }

  static String _short(Object e) {
    final text = '$e'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 220 ? '${text.substring(0, 220)}…' : text;
  }

  // The draft --------------------------------------------------------------------

  /// Who does a draft step: the person it names, or whoever is drafting. A
  /// member can only add steps of their own.
  /// Work for the whole group: one joint step between everyone.
  bool _joint(DraftStep s) =>
      _group && _manages && s.owner.trim().toLowerCase() == 'everyone';

  String _ownerOf(DraftStep s) {
    if (!_manages || !_group || _checkKinds.containsKey(s.key) || _joint(s)) {
      return _plan.meId;
    }
    final want = s.owner.trim().toLowerCase();
    if (want.isEmpty) return _plan.meId;
    for (final m in _plan.members) {
      if (m.name.toLowerCase() == want) return m.id;
    }
    for (final m in _plan.members) {
      final first = m.name.toLowerCase().split(' ').first;
      if (first.isNotEmpty && want.startsWith(first)) return m.id;
    }
    return _plan.meId;
  }

  /// The draft without the steps left out, and without needs on them.
  DraftPlan get _kept {
    final d = _draft!;
    return DraftPlan(
      summary: d.summary,
      covered: d.covered,
      phases: [
        for (final ph in d.phases)
          if (ph.steps.any((s) => !_dropped.contains(s.key)))
            DraftPhase(
              title: ph.title,
              after: ph.after,
              steps: [
                for (final s in ph.steps)
                  if (!_dropped.contains(s.key))
                    s.copyWith(
                      needs: [
                        for (final n in s.needs)
                          if (!_dropped.contains(n)) n,
                      ],
                    ),
              ],
            ),
      ],
    );
  }

  /// The existing phase a draft phase adds to, if any.
  String? _knownPhase(String title) {
    final want = title.trim().toLowerCase();
    return _plan.phases
        .where((p) => p.title.trim().toLowerCase() == want)
        .firstOrNull
        ?.id;
  }

  /// Every step, old and new, laid out together, so the new ones fit in and
  /// the rest move along to make room. Existing steps go by their refs.
  Schedule _schedule(DraftPlan plan) {
    final rank = <String, double>{};
    for (var i = 0; i < _ordered.length; i++) {
      rank[_refOf[_ordered[i].id]!] = i.toDouble();
    }
    // Extra needs on existing steps, from new steps they now wait for.
    final waitsFor = <String, List<String>>{};
    var i = 0;
    for (final s in plan.steps) {
      i++;
      final before = [for (final n in s.needs) ?rank[n]];
      final after = [for (final n in s.neededBy) ?rank[n]];
      rank[s.key] = before.isNotEmpty
          ? before.reduce((a, b) => a > b ? a : b) + 0.001 * i
          : after.isNotEmpty
          ? after.reduce((a, b) => a < b ? a : b) - 0.5 + 0.001 * i
          : 100000.0 + i;
      for (final r in s.neededBy) {
        (waitsFor[r] ??= []).add(s.key);
      }
    }
    return scheduleItems(
      [
        for (final s in _ordered)
          ScheduleItem(
            key: _refOf[s.id]!,
            hours: s.estimateHours,
            needs: [
              for (final n in s.dependsOn) ?_refOf[n],
              ...?waitsFor[_refOf[s.id]],
            ],
            owner: s.ownerId,
            done: s.status == StepStatus.done,
            rank: rank[_refOf[s.id]!]!,
          ),
        for (final s in plan.steps)
          ScheduleItem(
            key: s.key,
            hours: s.hours,
            needs: s.needs,
            // A shared point doesn't take anyone's own time.
            owner: _checkKinds.containsKey(s.key) || _joint(s)
                ? 'shared:${s.key}'
                : _ownerOf(s),
            rank: rank[s.key]!,
          ),
      ],
      today: _today,
      hoursPerWeek: _hoursPerWeek,
      deadline: widget.classroom.deadline,
    );
  }

  bool _canChange(PlanStep s) => _manages || s.ownerId == _plan.meId;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Existing steps whose dates change to make room, that this person may
  /// change.
  List<PlanStep> _moved(Schedule when) => [
    for (final s in _ordered)
      if (s.status != StepStatus.done && _canChange(s))
        if (when.dates[_refOf[s.id]] case final d?)
          if (!_sameDay(d.start, s.start) || !_sameDay(d.due, s.due)) s,
  ];

  Future<void> _add() async {
    final plan = _kept;
    if (plan.steps.isEmpty) return;
    setState(() {
      _stage = _Stage.saving;
      _problem = null;
    });
    final when = _schedule(plan);
    final b = widget.backend;
    final cid = widget.classroom.id;
    final ids = {for (final s in plan.steps) s.key: b.newId()};
    String? idOf(String key) => ids[key] ?? _stepOfRef[key]?.id;

    try {
      // Phases: new ones where Ofy placed them, the rest renumbered around.
      final phaseIds = <String, String>{};
      final order = [for (final ph in _plan.phases) (ph.id, ph.title, true)];
      for (final ph in plan.phases) {
        final known = _knownPhase(ph.title);
        if (known != null) {
          phaseIds[ph.title] = known;
          continue;
        }
        if (!_manages) continue;
        final id = b.newId();
        phaseIds[ph.title] = id;
        final after = ph.after?.trim();
        var at = order.length;
        if (after != null && after.isNotEmpty) {
          if (after.toUpperCase() == 'START') {
            at = 0;
          } else {
            final i = order.indexWhere(
              (o) => o.$2.trim().toLowerCase() == after.toLowerCase(),
            );
            if (i >= 0) at = i + 1;
          }
        }
        order.insert(at, (id, ph.title, false));
      }
      final oldOrder = {
        for (final s
            in await b.watchClassroom(cid).first.then((st) => st.phases))
          s.id: s.order,
      };
      for (var i = 0; i < order.length; i++) {
        final (id, title, existed) = order[i];
        if (!existed || (_manages && oldOrder[id] != i + 1)) {
          await b.savePhase(
            cid,
            PhaseRecord(id: id, title: title, order: i + 1),
          );
        }
      }

      // New steps, in their places.
      final count = <String, int>{
        for (final ph in _plan.phases) ph.id: _plan.stepsIn(ph.id).length,
      };
      final writes = <Future<void>>[];
      for (final ph in plan.phases) {
        final phaseId = phaseIds[ph.title];
        if (phaseId == null) continue;
        for (final s in ph.steps) {
          final dates = when.dates[s.key]!;
          count[phaseId] = (count[phaseId] ?? 0) + 1;
          writes.add(
            b.saveStep(
              cid,
              PlanStep(
                id: ids[s.key]!,
                phaseId: phaseId,
                ownerId: _ownerOf(s),
                title: s.title,
                description: _ownerOf(s) == _plan.meId ? s.description : '',
                estimateHours: s.hours,
                start: dates.start,
                due: dates.due,
                dependsOn: [
                  for (final n in s.needs)
                    if (_placed(plan, n)) ?idOf(n),
                ],
                checklist: [
                  for (final c in s.checklist) ChecklistItem(title: c),
                ],
                skills: s.skills,
                order: count[phaseId]!,
                kind:
                    _checkKinds[s.key] ??
                    (_joint(s) ? StepKind.joint : StepKind.work),
                participants: _joint(s)
                    ? [for (final m in _plan.members) m.id]
                    : _checkKinds.containsKey(s.key)
                    ? {
                        for (final x in ph.steps)
                          if (!_checkKinds.containsKey(x.key) && !_joint(x))
                            _ownerOf(x),
                        if (ph.steps.any(_joint))
                          for (final m in _plan.members) m.id,
                      }.toList()
                    : const [],
              ),
            ),
          );
        }
      }
      await Future.wait(writes);
      // The syllabus and books Ofy found, for everyone, in Files.
      for (final (title, url)
          in _research?.sources ?? const <(String, String)>[]) {
        try {
          await b.addFile(
            cid,
            LibraryFile(
              id: b.newId(),
              name: title,
              mimeType: 'text/html',
              size: 0,
              url: url,
              ownerUid: _plan.meId,
              createdAt: DateTime.now(),
            ),
          );
        } on BackendFailure {
          // A link that won't save shouldn't stop the plan.
        }
      }

      // Steps already there: what they now wait for, and their new dates.
      final newNeeds = <String, List<String>>{};
      for (final s in plan.steps) {
        if (!_placed(plan, s.key)) continue;
        for (final r in s.neededBy) {
          (newNeeds[r] ??= []).add(ids[s.key]!);
        }
      }
      final moved = {for (final s in _moved(when)) s.id};
      await Future.wait([
        for (final s in _ordered)
          if (_canChange(s) &&
              (moved.contains(s.id) || newNeeds.containsKey(_refOf[s.id])))
            b.saveStep(
              cid,
              s.copyWith(
                dependsOn: [...s.dependsOn, ...?newNeeds[_refOf[s.id]]],
                start: moved.contains(s.id)
                    ? when.dates[_refOf[s.id]]!.start
                    : null,
                due: moved.contains(s.id)
                    ? when.dates[_refOf[s.id]]!.due
                    : null,
              ),
            ),
      ]);
      if (mounted) Navigator.of(context).pop(true);
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.message;
          _stage = _Stage.review;
        });
      }
    }
  }

  /// Whether the step [key] goes into the classroom: a member's draft can't
  /// add phases, so steps in new phases are left out. Existing steps are
  /// always there.
  bool _placed(DraftPlan plan, String key) {
    if (_stepOfRef.containsKey(key)) return true;
    for (final ph in plan.phases) {
      if (ph.steps.any((s) => s.key == key)) {
        return _manages || _knownPhase(ph.title) != null;
      }
    }
    return false;
  }

  // Pages --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _Stage.drafting when _lookingUp => _waiting(
        'Ofy is looking up the official syllabus…',
      ),
      _Stage.drafting => _waiting(
        _adding
            ? 'Ofy is fitting it into your plan…'
            : 'Ofy is drafting your plan…',
      ),
      _Stage.saving => _waiting('Adding it to the classroom…'),
      _Stage.write => _writePage(context),
      _Stage.review => _reviewPage(context),
    };
  }

  String get _title => _adding ? 'Add to the plan' : 'Plan with Ofy';

  Widget _waiting(String what) {
    final p = Palette.of(context);
    return SheetFrame(
      title: _title,
      children: [
        const SizedBox(height: 28),
        const Center(child: CupertinoActivityIndicator(radius: 13)),
        const SizedBox(height: 14),
        Text(
          what,
          textAlign: TextAlign.center,
          style: TypeRamp.body(p.inkSoft),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _label(String text, Palette p, {double top = 22}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(text, style: TypeRamp.label(p.ink).weighted(FontWeight.w600)),
    ),
  );

  Widget _problemBox(Palette p) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: glassTint(p, p.blocked, radius: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 18,
            color: p.blocked,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_problem!, style: TypeRamp.label(p.ink))),
        ],
      ),
    ),
  );

  Widget _writePage(BuildContext context) {
    final p = Palette.of(context);
    final ready = _request.text.trim().isNotEmpty;
    return SheetFrame(
      title: _title,
      action: PressButton(
        label: _adding ? 'Add it with Ofy' : 'Draft my plan',
        icon: CupertinoIcons.sparkles,
        prominent: true,
        height: 48,
        expand: true,
        onTap: ready ? _makeDraft : null,
      ),
      children: [
        Text(
          _adding
              ? 'Say what to add. Ofy looks at the ${_plan.steps.length} steps '
                    'already here, tells you if one covers it, and otherwise '
                    'puts the new steps where they belong and moves the dates '
                    'to fit.'
              : 'Describe the plan you want for “${widget.classroom.title}”. '
                    'Ofy turns it into phases and steps.',
          style: TypeRamp.label(p.inkSoft),
        ),
        _label(
          _adding ? 'What should Ofy add?' : 'Your plan, in your words',
          p,
          top: 18,
        ),
        GlassField(
          label: _adding
              ? 'For example: a step to practise past papers before the exam'
              : 'For example: cover the whole ICSE class 12 physics theory, '
                    'one chapter at a time, with revision at the end',
          controller: _request,
          maxLines: 5,
          minLines: 3,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _listening
                      ? 'Listening… tap the microphone again to stop.'
                      : 'Required. Type it, or say it. Name a syllabus, such '
                            'as CBSE class 12 physics, and Ofy looks it up.',
                  style: TypeRamp.caption(_listening ? p.route : p.inkFaint),
                ),
              ),
              PressButton(
                label: _listening ? 'Stop listening' : 'Say it instead',
                icon: _listening
                    ? CupertinoIcons.stop_circle
                    : CupertinoIcons.mic,
                iconOnly: true,
                selected: _listening,
                height: 40,
                onTap: () => unawaited(_dictate()),
              ),
            ],
          ),
        ),
        _label('Time and limits', p),
        GlassField(
          label: _perDay
              ? 'Hours each day each person can give (optional)'
              : 'Hours each week each person can give (optional)',
          controller: _hours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            SelectChip(
              label: 'Each day',
              selected: _perDay,
              onTap: () => setState(() => _perDay = true),
            ),
            SelectChip(
              label: 'Each week',
              selected: !_perDay,
              onTap: () => setState(() => _perDay = false),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GlassDateField(
          label: 'Deadline (optional)',
          value: _deadline,
          onChanged: (d) => setState(() => _deadline = d),
          onClear: () => setState(() => _deadline = null),
        ),
        const SizedBox(height: 8),
        GlassField(
          label: 'Anything the plan must respect (optional)',
          controller: _constraints,
          maxLines: 3,
          minLines: 1,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'For example: thermodynamics before waves. Dates come from the '
            'hours: ${_number(kDefaultHoursPerWeek)} a week if you leave it '
            'empty.',
            style: TypeRamp.caption(p.inkFaint),
          ),
        ),
        if (_group) ..._groupSection(p),
        if (_manages) ..._checkSection(p),
        _label('Questions from Ofy (optional)', p),
        if (_questions.isEmpty)
          PressButton(
            label: _askingQuestions
                ? 'Ofy is thinking of questions…'
                : 'Let Ofy ask a few questions',
            icon: CupertinoIcons.question_circle,
            height: 42,
            expand: true,
            onTap: _askingQuestions ? null : _askQuestions,
          )
        else
          for (var i = 0; i < _questions.length; i++) ...[
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 16, bottom: 8),
              child: Text(_questions[i].question, style: TypeRamp.body(p.ink)),
            ),
            if (_questions[i].choices.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in _questions[i].choices)
                    SelectChip(
                      label: c,
                      selected: _answers[i].text == c,
                      onTap: () => setState(() => _answers[i].text = c),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            GlassField(label: 'Or in your own words', controller: _answers[i]),
          ],
        if (_problem != null) _problemBox(p),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            'Each request uses one of your $kAiCallsPerDay a day with Ofy.',
            style: TypeRamp.caption(p.inkFaint),
          ),
        ),
      ],
    );
  }

  List<Widget> _checkSection(Palette p) => [
    _label('After each phase', p),
    Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (kind, label) in const [
          ('tests', 'Mock tests'),
          ('checks', 'Checklists'),
          ('both', 'Both'),
          ('none', 'Nothing'),
          ('other', 'Something else'),
        ])
          SelectChip(
            label: label,
            selected: _checkKind == kind,
            onTap: () => setState(() => _checkKind = kind),
          ),
      ],
    ),
    if (_checkKind == 'other') ...[
      const SizedBox(height: 8),
      GlassField(
        label: 'What to call it, such as Review or Rehearsal',
        controller: _checkOther,
      ),
    ],
    Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        _checkKind == 'none'
            ? 'No point after each phase; the next phase follows straight on.'
            : 'Ofy adds one point after each phase. Everyone in it does their '
                  'own part there, and marks only their own part done. It has '
                  'its own tab in the menu.',
        style: TypeRamp.caption(p.inkSoft),
      ),
    ),
  ];

  List<Widget> _groupSection(Palette p) {
    final canSet = _isMaster;
    return [
      _label('How this group works', p),
      if (canSet)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SelectChip(
              label: 'Together: learn parts, teach each other',
              selected: _linked,
              onTap: () => setState(() => _linked = true),
            ),
            SelectChip(
              label: 'Separate roles',
              selected: !_linked,
              onTap: () => setState(() => _linked = false),
            ),
          ],
        ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _linked
              ? 'Ofy splits each phase evenly, one part each, and ends it with '
                    'a session where you teach each other, so all of you know '
                    'all of it.'
              : 'Ofy gives each step to the person whose role fits it, and '
                    'keeps everyone’s share even.',
          style: TypeRamp.caption(p.inkSoft),
        ),
      ),
      if (!_linked) ...[
        _label('Who does what', p, top: 16),
        for (final m in _plan.members)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    m.id == _plan.meId ? '${m.name} (you)' : m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.label(p.ink),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: canSet
                      ? GlassField(
                          label: 'Role, such as Front end',
                          controller: _roles[m.id]!,
                        )
                      : Text(
                          _roles[m.id]!.text.isEmpty
                              ? 'No role yet'
                              : _roles[m.id]!.text,
                          style: TypeRamp.label(p.inkSoft),
                        ),
                ),
              ],
            ),
          ),
        if (!canSet)
          Text(
            'The master sets everyone’s role.',
            style: TypeRamp.caption(p.inkFaint),
          ),
      ],
    ];
  }

  String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  String _hoursText(double h) =>
      h == h.roundToDouble() ? '${h.round()} h' : '${h.toStringAsFixed(1)} h';

  Widget _reviewPage(BuildContext context) {
    final p = Palette.of(context);
    final draft = _draft!;
    final kept = _kept;
    final when = _schedule(kept);
    final count = kept.steps.length;
    final moved = _moved(when);
    final newFinish = [for (final s in kept.steps) ?when.dates[s.key]?.due];
    final last = [for (final d in when.dates.values) d.due]
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final pace =
        '${_hoursText(when.hoursPerWeek)} a week each'
        '${when.assumedHours ? ' (assumed; add your hours to change it)' : ''}';
    final timing = count == 0
        ? null
        : _adding
        ? 'The new steps are done by '
              '${_date(newFinish.reduce((a, b) => b.isAfter(a) ? b : a))}, '
              'at $pace. The whole plan finishes ${_date(last ?? _today)}.'
        : 'About ${when.weeksFrom(_today)} weeks at $pace, finishing '
              '${_date(when.finish)}.';
    final deadline = count == 0 || when.deadline == null
        ? null
        : when.fitsDeadline
        ? 'That’s before your deadline of ${_date(when.deadline!)}.'
        : 'That’s after your deadline of ${_date(when.deadline!)}. Give it '
              'more hours a week, or leave some steps out.';
    var number = 0;
    final numberOf = <String, int>{};
    for (final s in draft.steps) {
      numberOf[s.key] = ++number;
    }
    String needName(String key) {
      final n = numberOf[key];
      if (n != null) return '$n';
      final existing = _stepOfRef[key];
      return existing == null ? '' : '“${existing.title}”';
    }

    return SheetFrame(
      title: count == 0 && draft.covered.isNotEmpty
          ? 'Already in your plan'
          : (_adding ? 'What Ofy would add' : 'Your draft plan'),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draft.steps.isNotEmpty) ...[
            PressButton(
              label: count == 0
                  ? 'Keep at least one step'
                  : _adding
                  ? 'Add $count ${count == 1 ? 'step' : 'steps'}'
                  : 'Add ${kept.phases.length} phases and $count steps',
              icon: CupertinoIcons.checkmark_alt,
              prominent: true,
              height: 48,
              expand: true,
              onTap: count == 0 ? null : _add,
            ),
            const SizedBox(height: 8),
          ],
          PressButton(
            label: 'Change what I asked',
            icon: CupertinoIcons.pencil,
            height: 44,
            expand: true,
            prominent: draft.steps.isEmpty,
            onTap: () => setState(() {
              _stage = _Stage.write;
              _problem = null;
            }),
          ),
        ],
      ),
      children: [
        if (draft.summary.isNotEmpty)
          Text(draft.summary, style: TypeRamp.body(p.ink)),
        for (final cov in draft.covered)
          if (_stepOfRef[cov.ref] case final s?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: glassTint(p, p.done, radius: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_seal,
                      size: 18,
                      color: p.done,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${cov.what.isEmpty ? 'That' : '“${cov.what}”'} is '
                        'already in the step “${s.title}”, in '
                        '${_phaseTitle(s.phaseId)}'
                        '${s.status == StepStatus.done ? ', and it’s done' : ''}'
                        '${_group ? ' (${_nameOf(s.ownerId)})' : ''}.',
                        style: TypeRamp.label(p.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (timing != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: glassTint(
              p,
              when.fitsDeadline ? p.accent : p.blocked,
              radius: 14,
            ),
            child: Text(
              [
                timing,
                ?deadline,
                if (moved.isNotEmpty)
                  '${moved.length} of the steps already here move to make '
                      'room.',
              ].join(' '),
              style: TypeRamp.label(p.ink),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Dates come from the hours and what each step needs, not from Ofy. '
            'Untick anything you don’t want. You can change everything once '
            'it’s added.',
            style: TypeRamp.caption(p.inkFaint),
          ),
        ],
        if (_research case final r? when r.sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: glassTint(p, p.accentTeal, radius: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ofy followed the syllabus it found on the web, and adds '
                  'these to Files for everyone:',
                  style: TypeRamp.label(p.ink),
                ),
                const SizedBox(height: 6),
                for (final (title, url) in r.sources)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '•  $title  ($url)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TypeRamp.caption(p.inkSoft),
                    ),
                  ),
                if (r.searches.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GoogleSuggestions(searches: r.searches),
                ],
              ],
            ),
          ),
        ],
        if (_problem != null) _problemBox(p),
        for (final ph in draft.phases) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  text: ph.title,
                  style: TypeRamp.title(p.ink),
                  children: [
                    if (_adding)
                      TextSpan(
                        text: _knownPhase(ph.title) != null
                            ? '  in this phase'
                            : '  new phase'
                                  '${(ph.after ?? '').isEmpty
                                      ? ''
                                      : ph.after!.toUpperCase() == 'START'
                                      ? ', first'
                                      : ', after ${ph.after}'}',
                        style: TypeRamp.caption(p.inkSoft),
                      ),
                  ],
                ),
              ),
            ),
          ),
          for (final s in ph.steps)
            _DraftRow(
              number: numberOf[s.key]!,
              step: s,
              kept: !_dropped.contains(s.key),
              detail: [
                if (_group && _manages)
                  _checkKinds.containsKey(s.key) || _joint(s)
                      ? 'Everyone'
                      : _nameOf(_ownerOf(s)),
                _hoursText(s.hours),
                if (!_dropped.contains(s.key) && when.dates[s.key] != null)
                  'due ${_date(when.dates[s.key]!.due)}',
                if (s.needs.isNotEmpty)
                  'after ${s.needs.map(needName).where((n) => n.isNotEmpty).join(', ')}',
                if (s.neededBy.isNotEmpty)
                  'before ${s.neededBy.map(needName).where((n) => n.isNotEmpty).join(', ')}',
              ].join(' · '),
              onToggle: () => setState(() {
                _dropped.contains(s.key)
                    ? _dropped.remove(s.key)
                    : _dropped.add(s.key);
              }),
            ),
        ],
      ],
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.number,
    required this.step,
    required this.kept,
    required this.detail,
    required this.onToggle,
  });

  final int number;
  final DraftStep step;
  final bool kept;
  final String detail;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        checked: kept,
        label: '$number. ${step.title}. $detail',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: AnimatedOpacity(
            opacity: kept ? 1 : 0.45,
            duration: const Duration(milliseconds: 160),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    kept
                        ? CupertinoIcons.checkmark_square_fill
                        : CupertinoIcons.square,
                    size: 20,
                    color: kept ? p.accent : p.inkFaint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$number. ${step.title}',
                          style: TypeRamp.body(p.ink).copyWith(
                            decoration: kept
                                ? TextDecoration.none
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        if (step.description.isNotEmpty)
                          Text(
                            step.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TypeRamp.caption(p.inkSoft),
                          ),
                        const SizedBox(height: 2),
                        Text(detail, style: TypeRamp.caption(p.inkFaint)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
