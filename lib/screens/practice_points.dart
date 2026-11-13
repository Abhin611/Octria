/// Practice and the points after each phase: questions Ofy writes for a step,
/// a phase or the whole plan; and each person's own part of a mock test or
/// checklist point, which they mark done themselves.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../ai/ai.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart';
import 'interview_sheet.dart';
import 'room_lists.dart';
import 'step_collab.dart';
import 'step_panel.dart';

/// What a list of steps is about, for Ofy to write questions on.
List<String> topicsOf(Iterable<PlanStep> steps) => [
  for (final s in steps)
    s.description.trim().isEmpty ? s.title : '${s.title}: ${s.description}',
];

/// The work steps a point checks: in its phase, before it.
List<PlanStep> stepsBehind(Plan plan, PlanStep point, {String? owner}) {
  final seen = <String>{};
  final out = <PlanStep>[];
  void walk(String id) {
    if (!seen.add(id)) return;
    final s = plan.steps[id];
    if (s == null || s.phaseId != point.phaseId) return;
    if (!s.isPoint && (owner == null || s.ownerId == owner)) out.add(s);
    s.dependsOn.forEach(walk);
  }

  point.dependsOn.forEach(walk);
  if (out.isEmpty) {
    // Linked loosely: the whole phase.
    out.addAll(
      plan
          .stepsIn(point.phaseId)
          .where((s) => !s.isPoint && (owner == null || s.ownerId == owner)),
    );
  }
  out.sort((a, b) => a.due.compareTo(b.due));
  return out;
}

// Questions ----------------------------------------------------------------------

/// A practice set or mock test: Ofy writes it, then one question at a time,
/// with the answer and why after each. Pops the score, from 0 to 1, once
/// finished.
class QuizSheet extends StatefulWidget {
  const QuizSheet({
    super.key,
    required this.backend,
    required this.brief,
    required this.title,
    this.classroomId = '',
    this.targetId = '',
  });

  final Backend backend;
  final QuizBrief brief;
  final String title;

  /// Where the result is kept. With no classroom it isn't kept.
  final String classroomId;

  /// The step, phase or point it covers; empty for the whole plan.
  final String targetId;

  @override
  State<QuizSheet> createState() => _QuizSheetState();
}

class _QuizSheetState extends State<QuizSheet> {
  Quiz? _quiz;
  String? _problem;
  var _index = 0;
  int? _picked;
  var _right = 0;

  /// The questions answered wrong, in order.
  final _missed = <QuizQuestion>[];

  /// Whether the result reached this person's results: null while saving.
  bool? _kept;

  Future<void> _keep() async {
    final quiz = _quiz;
    if (quiz == null || widget.classroomId.isEmpty || quiz.questions.isEmpty) {
      return;
    }
    try {
      await widget.backend.saveResult(
        TestResult(
          id: '',
          classroomId: widget.classroomId,
          label: widget.title,
          targetId: widget.targetId,
          right: _right,
          total: quiz.questions.length,
          mock: widget.brief.mock,
          level: widget.brief.level.stored,
          missed: [for (final q in _missed) q.question],
          at: DateTime.now(),
        ),
      );
      if (mounted) setState(() => _kept = true);
    } on BackendFailure {
      if (mounted) setState(() => _kept = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _problem = null;
      _quiz = null;
    });
    try {
      final quiz = await widget.backend.ai.makeQuiz(widget.brief);
      if (mounted) setState(() => _quiz = quiz);
    } on AiFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  void _pick(int i) {
    if (_picked != null) return;
    setState(() {
      _picked = i;
      final q = _quiz!.questions[_index];
      if (i == q.answer) {
        _right++;
      } else {
        _missed.add(q);
      }
    });
  }

  void _next() {
    setState(() {
      _index++;
      _picked = null;
    });
    if (_index >= _quiz!.questions.length) unawaited(_keep());
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final quiz = _quiz;
    if (quiz == null) {
      return SheetFrame(
        title: widget.title,
        action: _problem == null
            ? null
            : PressButton(
                label: 'Try again',
                prominent: true,
                height: 46,
                expand: true,
                onTap: _load,
              ),
        children: [
          const SizedBox(height: 24),
          if (_problem == null) ...[
            const Center(child: CupertinoActivityIndicator(radius: 13)),
            const SizedBox(height: 12),
            Text(
              widget.brief.mock
                  ? 'Ofy is writing your mock test…'
                  : 'Ofy is writing your practice…',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          ] else
            Text(_problem!, style: TypeRamp.body(p.ink)),
          const SizedBox(height: 24),
        ],
      );
    }
    final total = quiz.questions.length;
    if (_index >= total) {
      final score = total == 0 ? 0.0 : _right / total;
      return SheetFrame(
        title: quiz.title,
        action: PressButton(
          label: 'Finish',
          prominent: true,
          height: 46,
          expand: true,
          onTap: () => Navigator.of(context).pop(score),
        ),
        children: [
          const SizedBox(height: 10),
          Text(
            '$_right of $total right',
            textAlign: TextAlign.center,
            style: TypeRamp.title(p.ink).copyWith(fontSize: 30),
          ),
          const SizedBox(height: 6),
          Text(
            score >= 0.8
                ? 'Well done. You know this.'
                : score >= 0.5
                ? 'Good going. Look again at the ones you missed.'
                : 'Worth another look before moving on.',
            textAlign: TextAlign.center,
            style: TypeRamp.body(p.inkSoft),
          ),
          if (widget.classroomId.isNotEmpty && _kept != null) ...[
            const SizedBox(height: 6),
            Text(
              _kept!
                  ? 'Saved to your results.'
                  : 'This result couldn’t be saved.',
              textAlign: TextAlign.center,
              style: TypeRamp.caption(_kept! ? p.inkSoft : p.blocked),
            ),
          ],
          if (_missed.isNotEmpty) ...[
            const StepSectionTitle('Look at these again'),
            for (final q in _missed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListRow(
                  title: q.question,
                  lines: 8,
                  detail: 'Answer: ${q.choices[q.answer]}',
                  leading: Icon(
                    CupertinoIcons.arrow_counterclockwise,
                    size: 18,
                    color: p.accentWarm,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 18),
        ],
      );
    }
    final q = quiz.questions[_index];
    final picked = _picked;
    return SheetFrame(
      title: quiz.title,
      action: PressButton(
        label: _index + 1 == total ? 'See my score' : 'Next question',
        prominent: true,
        height: 46,
        expand: true,
        onTap: picked == null ? null : _next,
      ),
      children: [
        Text(
          'Question ${_index + 1} of $total',
          style: TypeRamp.caption(p.inkSoft),
        ),
        const SizedBox(height: 8),
        Text(q.question, style: TypeRamp.body(p.ink)),
        const SizedBox(height: 14),
        for (var i = 0; i < q.choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListRow(
              title: q.choices[i],
              leading: Icon(
                picked == null
                    ? CupertinoIcons.circle
                    : i == q.answer
                    ? CupertinoIcons.checkmark_circle_fill
                    : i == picked
                    ? CupertinoIcons.xmark_circle_fill
                    : CupertinoIcons.circle,
                size: 20,
                color: picked == null
                    ? p.inkFaint
                    : i == q.answer
                    ? p.done
                    : i == picked
                    ? p.blocked
                    : p.inkFaint,
              ),
              onTap: picked == null ? () => _pick(i) : null,
            ),
          ),
        if (picked != null && q.explain.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(12),
            decoration: glassTint(
              p,
              picked == q.answer ? p.done : p.accentWarm,
              radius: 14,
            ),
            child: Text(
              '${picked == q.answer ? 'Right. ' : 'Not quite. '}${q.explain}',
              style: TypeRamp.label(p.ink),
            ),
          ),
      ],
    );
  }
}

/// Easier, standard or harder questions.
class LevelChips extends StatelessWidget {
  const LevelChips({super.key, required this.level, required this.onChanged});

  final QuizLevel level;
  final ValueChanged<QuizLevel> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final l in QuizLevel.values)
        SelectChip(
          label: l.label,
          selected: level == l,
          onTap: () => onChanged(l),
        ),
    ],
  );
}

// Practice by step, phase or the whole plan ------------------------------------

enum PracticeScope { step, phase, whole }

/// Picks what to practise, then opens Ofy's questions on it.
class PracticePicker extends StatefulWidget {
  const PracticePicker({
    super.key,
    required this.backend,
    required this.classroom,
    required this.plan,
  });

  final Backend backend;
  final Classroom classroom;
  final Plan plan;

  @override
  State<PracticePicker> createState() => _PracticePickerState();
}

class _PracticePickerState extends State<PracticePicker> {
  var _scope = PracticeScope.step;
  String? _stepId;
  String? _phaseId;
  var _level = QuizLevel.standard;

  /// This person's results in this classroom, newest first.
  var _results = const <TestResult>[];
  StreamSubscription<List<TestResult>>? _resultsSub;

  @override
  void initState() {
    super.initState();
    _resultsSub = widget.backend.results().listen((all) {
      if (!mounted) return;
      setState(
        () => _results = [
          for (final r in all)
            if (r.classroomId == widget.classroom.id) r,
        ],
      );
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    unawaited(_resultsSub?.cancel());
    super.dispose();
  }

  List<PlanStep> get _steps {
    final order = {
      for (var i = 0; i < widget.plan.phases.length; i++)
        widget.plan.phases[i].id: i,
    };
    return widget.plan.steps.values.where((s) => !s.isPoint).toList()..sort((
      a,
      b,
    ) {
      final byPhase = (order[a.phaseId] ?? 0).compareTo(order[b.phaseId] ?? 0);
      return byPhase != 0 ? byPhase : a.due.compareTo(b.due);
    });
  }

  Future<void> _pickStep() async {
    final id = await showGlassSheet<String>(
      context,
      (_) => ChoiceSheet<String>(
        title: 'Which step?',
        message: 'Ofy writes practice on just this step.',
        choices: [for (final s in _steps) (s.title, s.id, false)],
      ),
    );
    if (id != null && mounted) setState(() => _stepId = id);
  }

  Future<void> _pickPhase() async {
    final id = await showGlassSheet<String>(
      context,
      (_) => ChoiceSheet<String>(
        title: 'Which phase?',
        message: 'Ofy writes practice covering every step in it.',
        choices: [
          for (final ph in widget.plan.phases) (ph.title, ph.id, false),
        ],
      ),
    );
    if (id != null && mounted) setState(() => _phaseId = id);
  }

  Future<void> _start({bool interview = false}) async {
    final plan = widget.plan;
    final (title, steps) = switch (_scope) {
      PracticeScope.step => (
        'Practice: ${plan.steps[_stepId]?.title ?? ''}',
        [?plan.steps[_stepId]],
      ),
      PracticeScope.phase => (
        'Practice: ${plan.phases.where((p) => p.id == _phaseId).firstOrNull?.title ?? ''}',
        _steps.where((s) => s.phaseId == _phaseId).toList(),
      ),
      PracticeScope.whole => ('Practice: ${plan.title}', _steps),
    };
    if (steps.isEmpty) return;
    final target = switch (_scope) {
      PracticeScope.step => _stepId ?? '',
      PracticeScope.phase => _phaseId ?? '',
      PracticeScope.whole => '',
    };
    final brief = QuizBrief(
      subject: widget.classroom.title,
      topics: topicsOf(steps.take(30)),
      count: interview ? 4 : (_scope == PracticeScope.step ? 6 : 10),
      focus: missedBefore(_results, target),
      level: _level,
    );
    await showGlassSheet<double>(
      context,
      (_) => interview
          ? InterviewSheet(
              backend: widget.backend,
              title: title.replaceFirst('Practice:', 'Mock interview:'),
              classroomId: widget.classroom.id,
              targetId: target,
              brief: brief,
            )
          : QuizSheet(
              backend: widget.backend,
              title: title,
              classroomId: widget.classroom.id,
              targetId: target,
              brief: brief,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final plan = widget.plan;
    final chosen = switch (_scope) {
      PracticeScope.step => plan.steps[_stepId]?.title,
      PracticeScope.phase =>
        plan.phases.where((x) => x.id == _phaseId).firstOrNull?.title,
      PracticeScope.whole => 'Everything in the plan',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (scope, label) in const [
              (PracticeScope.step, 'By step'),
              (PracticeScope.phase, 'By phase'),
              (PracticeScope.whole, 'The whole plan'),
            ])
              SelectChip(
                label: label,
                selected: _scope == scope,
                onTap: () => setState(() => _scope = scope),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_scope != PracticeScope.whole)
          ListRow(
            title:
                chosen ??
                (_scope == PracticeScope.step
                    ? 'Choose a step'
                    : 'Choose a phase'),
            detail: chosen == null ? null : 'Tap to change',
            leading: Icon(
              _scope == PracticeScope.step
                  ? CupertinoIcons.circle_grid_hex
                  : CupertinoIcons.square_stack_3d_up,
              size: 18,
              color: p.accent,
            ),
            trailing: Icon(
              CupertinoIcons.chevron_down,
              size: 14,
              color: p.inkFaint,
            ),
            onTap: () => unawaited(
              _scope == PracticeScope.step ? _pickStep() : _pickPhase(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LevelChips(
            level: _level,
            onChanged: (l) => setState(() => _level = l),
          ),
        ),
        PressButton(
          label: 'Practise with Ofy',
          icon: CupertinoIcons.sparkles,
          prominent: true,
          height: 44,
          expand: true,
          onTap: chosen == null ? null : () => unawaited(_start()),
        ),
        const SizedBox(height: 8),
        PressButton(
          label: 'Mock interview',
          icon: CupertinoIcons.mic,
          height: 44,
          expand: true,
          onTap: chosen == null
              ? null
              : () => unawaited(_start(interview: true)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'An interview asks open questions. You answer in your own words, '
            'typed or spoken, and Ofy marks each one.',
            style: TypeRamp.caption(p.inkSoft),
          ),
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 8),
          ListRow(
            title: 'My results',
            detail:
                '${_results.length} taken. Last: ${_results.first.percent}%, '
                '${shortDate(_results.first.at)}',
            leading: Icon(CupertinoIcons.chart_bar, size: 18, color: p.accent),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: p.inkFaint,
            ),
            onTap: () => unawaited(
              showGlassSheet<void>(
                context,
                (_) => ResultsSheet(
                  backend: widget.backend,
                  classroom: widget.classroom,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// Results ---------------------------------------------------------------------

/// What this person got wrong the last time they were tested on [targetId].
List<String> missedBefore(List<TestResult> newestFirst, String targetId) {
  for (final r in newestFirst) {
    if (r.targetId == targetId) return r.missed;
  }
  return const [];
}

/// A person's results in one classroom, and how they're doing overall.
class ResultSummary {
  ResultSummary(List<TestResult> results)
    : count = results.length,
      average = results.isEmpty
          ? 0
          : (results.map((r) => r.score).reduce((a, b) => a + b) /
                    results.length *
                    100)
                .round(),
      best = results.isEmpty
          ? 0
          : results.map((r) => r.percent).reduce((a, b) => a > b ? a : b);

  final int count;
  final int average;
  final int best;
}

/// Every practice set and mock test this person finished in a classroom, with
/// what they missed in each. Only they see it.
class ResultsSheet extends StatelessWidget {
  const ResultsSheet({
    super.key,
    required this.backend,
    required this.classroom,
  });

  final Backend backend;
  final Classroom classroom;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<TestResult>>(
      stream: backend.results(),
      builder: (context, snap) {
        final results = [
          for (final r in snap.data ?? const <TestResult>[])
            if (r.classroomId == classroom.id) r,
        ];
        final sum = ResultSummary(results);
        return SheetFrame(
          title: 'My results',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Only you see these.',
                style: TypeRamp.label(p.inkSoft),
              ),
            ),
            if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  snap.hasData
                      ? 'No results yet. Finish a practice set or a mock test '
                            'and it shows here.'
                      : 'Loading…',
                  textAlign: TextAlign.center,
                  style: TypeRamp.body(p.inkSoft),
                ),
              )
            else ...[
              Row(
                children: [
                  for (final (value, label) in [
                    ('${sum.count}', 'Taken'),
                    ('${sum.average}%', 'Average'),
                    ('${sum.best}%', 'Best'),
                  ])
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            value,
                            style: TypeRamp.title(p.ink).copyWith(fontSize: 24),
                          ),
                          Text(label, style: TypeRamp.caption(p.inkSoft)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              for (final r in results)
                ListRow(
                  title: r.label,
                  detail:
                      '${r.right} of ${r.total}, ${r.percent}%. '
                      '${r.kindLabel}, ${shortDate(r.at)}',
                  leading: Icon(
                    r.score >= 0.8
                        ? CupertinoIcons.checkmark_seal_fill
                        : r.score >= 0.5
                        ? CupertinoIcons.circle_lefthalf_fill
                        : CupertinoIcons.exclamationmark_circle,
                    size: 20,
                    color: r.score >= 0.8
                        ? p.done
                        : r.score >= 0.5
                        ? p.doing
                        : p.accentWarm,
                  ),
                  trailing: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: p.inkFaint,
                  ),
                  onTap: () => unawaited(
                    showGlassSheet<void>(
                      context,
                      (_) => _ResultDetail(
                        backend: backend,
                        classroom: classroom,
                        result: r,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ResultDetail extends StatefulWidget {
  const _ResultDetail({
    required this.backend,
    required this.classroom,
    required this.result,
  });

  final Backend backend;
  final Classroom classroom;
  final TestResult result;

  @override
  State<_ResultDetail> createState() => _ResultDetailState();
}

class _ResultDetailState extends State<_ResultDetail> {
  /// What happened to the last share, to say so.
  String? _said;
  var _failed = false;
  var _sending = false;

  Backend get backend => widget.backend;
  TestResult get result => widget.result;

  /// What others are told: the score, never the questions missed.
  String get _line {
    final r = result;
    return 'I scored ${r.right} of ${r.total} (${r.percent}%) on '
        '“${r.label}”. ${r.kindLabel}.';
  }

  Future<void> _share({required bool everyone}) async {
    final room = widget.classroom;
    setState(() {
      _sending = true;
      _said = null;
    });
    try {
      if (everyone) {
        await backend.sendChat(room.id, _line);
      } else {
        final thread = await backend.openThread(room.id, [room.masterUid]);
        await backend.sendThreadMessage(room.id, thread, _line);
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failed = false;
        _said = everyone
            ? 'Posted in the class chat.'
            : 'Sent to the master, privately.';
      });
    } on BackendFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failed = true;
        _said = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = result;
    final room = widget.classroom;
    final me = backend.currentUser?.uid ?? '';
    return SheetFrame(
      title: r.label,
      action: PressButton(
        label: 'Remove this result',
        icon: CupertinoIcons.trash,
        quiet: true,
        height: 44,
        expand: true,
        onTap: () {
          unawaited(backend.deleteResult(r.id).catchError((Object _) {}));
          Navigator.of(context).pop();
        },
      ),
      children: [
        Text(
          '${r.right} of ${r.total}, ${r.percent}%. '
          '${r.kindLabel}, ${shortDate(r.at)}.',
          style: TypeRamp.label(p.inkSoft),
        ),
        if (!room.individual && room.memberUids.length > 1) ...[
          const StepSectionTitle('Share the score', top: 16),
          Text(
            'Only the score is shared, never what you missed.',
            style: TypeRamp.caption(p.inkSoft),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PressButton(
                label: 'Post in class chat',
                icon: CupertinoIcons.chat_bubble_2,
                height: 40,
                onTap: _sending
                    ? null
                    : () => unawaited(_share(everyone: true)),
              ),
              if (room.masterUid != me)
                PressButton(
                  label: 'Send to the master',
                  icon: CupertinoIcons.lock,
                  height: 40,
                  onTap: _sending
                      ? null
                      : () => unawaited(_share(everyone: false)),
                ),
            ],
          ),
          if (_said != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _said!,
                style: TypeRamp.label(_failed ? p.blocked : p.ink),
              ),
            ),
        ],
        if (r.missed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Nothing missed. Every answer was right.',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          )
        else ...[
          const StepSectionTitle('What you missed', top: 16),
          for (final m in r.missed)
            ListRow(
              title: m,
              lines: 8,
              leading: Icon(
                CupertinoIcons.arrow_counterclockwise,
                size: 18,
                color: p.accentWarm,
              ),
            ),
          Text(
            'The next practice on this comes back to these.',
            style: TypeRamp.caption(p.inkSoft),
          ),
        ],
      ],
    );
  }
}

// One person's part of a point --------------------------------------------------

/// Someone's own part of a mock test or checklist point: their test, their
/// checklist, and marking it done. Everyone else's progress shows too.
class MyPartSheet extends StatefulWidget {
  const MyPartSheet({
    super.key,
    required this.backend,
    required this.classroom,
    required this.plan,
    required this.stepId,
    required this.onMark,
    this.onSaveTicks,
    this.uid,
  });

  /// Keeps what this person has ticked on their checklist.
  final void Function(String stepId, List<String> ticked)? onSaveTicks;

  final Backend backend;
  final Classroom classroom;
  final Plan plan;
  final String stepId;

  /// Whose part to show; this person's when left out.
  final String? uid;

  /// Marks this person's part done, or not.
  final void Function(String stepId, bool done) onMark;

  @override
  State<MyPartSheet> createState() => _MyPartSheetState();
}

class _MyPartSheetState extends State<MyPartSheet> {
  late final Set<String> _ticked = {
    ...?widget.plan.steps[widget.stepId]?.ticks[widget.uid ?? widget.plan.meId],
  };

  /// What was last saved, to tell whether there's anything new to save.
  late Set<String> _saved = {..._ticked};

  void _save() {
    widget.onSaveTicks?.call(widget.stepId, _ticked.toList());
    setState(() => _saved = {..._ticked});
  }

  bool get _unsaved =>
      _ticked.length != _saved.length || !_ticked.every(_saved.contains);
  double? _score;

  var _level = QuizLevel.standard;

  /// What they got wrong last time on this point, for the next test.
  var _missedBefore = const <String>[];
  StreamSubscription<List<TestResult>>? _resultsSub;

  @override
  void initState() {
    super.initState();
    if (!_mine) return;
    _resultsSub = widget.backend.results().listen((all) {
      final last = all
          .where(
            (r) =>
                r.classroomId == widget.classroom.id &&
                r.targetId == widget.stepId,
          )
          .firstOrNull;
      if (last == null || !mounted) return;
      setState(() {
        _score = last.score;
        _missedBefore = last.missed;
      });
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    unawaited(_resultsSub?.cancel());
    super.dispose();
  }

  late var _done =
      widget.plan.steps[widget.stepId]?.doneFor(widget.plan.meId) ?? false;

  String get _who => widget.uid ?? widget.plan.meId;
  bool get _mine => _who == widget.plan.meId;

  Future<void> _test(PlanStep point, List<PlanStep> mine) async {
    final score = await showGlassSheet<double>(
      context,
      (_) => QuizSheet(
        backend: widget.backend,
        title: point.title,
        classroomId: _mine ? widget.classroom.id : '',
        targetId: point.id,
        brief: QuizBrief(
          subject: widget.classroom.title,
          topics: topicsOf(mine),
          mock: true,
          count: 10,
          focus: _missedBefore,
          level: _level,
        ),
      ),
    );
    if (score != null && mounted) setState(() => _score = score);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final plan = widget.plan;
    final point = plan.steps[widget.stepId];
    if (point == null) {
      return const SheetFrame(
        title: 'Gone',
        children: [Text('This was removed.')],
      );
    }
    final mine = stepsBehind(plan, point, owner: _who);
    final joint = point.kind == StepKind.joint;
    final testing = point.kind == StepKind.test || point.kind == StepKind.both;
    final checking = point.kind != StepKind.test;
    // Joint work: the step's own checklist, for each person to tick.
    final items = joint
        ? [
            if (point.checklist.isEmpty) point.title,
            for (final c in point.checklist) c.title,
          ]
        : [
            for (final s in mine) ...[
              s.title,
              for (final c in s.checklist) '${s.title}: ${c.title}',
            ],
          ];
    final allTicked = items.every(_ticked.contains);
    return SheetFrame(
      title: _mine ? 'Your part' : '${nameIn(plan, _who)}’s part',
      action: _mine
          ? PressButton(
              label: _done ? 'Mark my part not done' : 'Mark my part done',
              icon: _done
                  ? CupertinoIcons.arrow_uturn_left
                  : CupertinoIcons.checkmark_alt,
              prominent: !_done,
              height: 46,
              expand: true,
              onTap: () {
                // Ticks go with it, so nothing is lost.
                if (_unsaved) _save();
                widget.onMark(point.id, !_done);
                setState(() => _done = !_done);
              },
            )
          : null,
      children: [
        Text(point.title, style: TypeRamp.heading(p.ink)),
        const SizedBox(height: 4),
        Text(
          _done && _mine
              ? 'You’ve finished your part. It’s done once everyone has.'
              : joint
              ? 'Shared work: each person does their own part and marks it '
                    'done. It’s finished once everyone has.'
              : 'Covers ${mine.isEmpty ? 'this phase' : '${mine.length} ${mine.length == 1 ? 'step' : 'steps'}'}'
                    '${_mine ? ' of yours' : ''} in this phase.',
          style: TypeRamp.caption(p.inkSoft),
        ),
        if (testing) ...[
          const StepSectionTitle('Mock test'),
          if (_score != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Last try: ${(_score! * 100).round()}%',
                style: TypeRamp.label(p.ink),
              ),
            ),
          if (_mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LevelChips(
                level: _level,
                onChanged: (l) => setState(() => _level = l),
              ),
            ),
          if (_mine)
            PressButton(
              label: _score == null ? 'Take my mock test' : 'Take it again',
              icon: CupertinoIcons.doc_text,
              prominent: _score == null,
              height: 44,
              expand: true,
              onTap: () => unawaited(_test(point, mine)),
            )
          else
            Text(
              'Only ${nameIn(plan, _who)} can take this test.',
              style: TypeRamp.caption(p.inkSoft),
            ),
        ],
        if (checking) ...[
          StepSectionTitle(
            allTicked && items.isNotEmpty
                ? 'Checklist · all ticked'
                : 'Checklist',
          ),
          if (items.isEmpty)
            Text(
              'Nothing to check in this phase.',
              style: TypeRamp.caption(p.inkSoft),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_ticked.where(items.contains).length} of ${items.length} '
                'ticked${_unsaved ? ', not saved yet' : ''}.',
                style: TypeRamp.caption(_unsaved ? p.accentWarm : p.inkSoft),
              ),
            ),
          for (final item in items)
            ListRow(
              title: item,
              leading: Icon(
                _ticked.contains(item)
                    ? CupertinoIcons.checkmark_square_fill
                    : CupertinoIcons.square,
                size: 20,
                color: _ticked.contains(item) ? p.done : p.inkFaint,
              ),
              onTap: _mine
                  ? () => setState(() {
                      _ticked.contains(item)
                          ? _ticked.remove(item)
                          : _ticked.add(item);
                    })
                  : null,
            ),
          if (_mine && items.isNotEmpty && widget.onSaveTicks != null)
            PressButton(
              label: _unsaved ? 'Save checklist' : 'Checklist saved',
              icon: _unsaved
                  ? CupertinoIcons.tray_arrow_down
                  : CupertinoIcons.checkmark_alt,
              prominent: _unsaved,
              height: 44,
              expand: true,
              onTap: _unsaved ? _save : null,
            ),
        ],
        const StepSectionTitle('Everyone in it'),
        for (final u in point.participants)
          ListRow(
            title: u == plan.meId ? 'You' : nameIn(plan, u),
            detail: point.doneFor(u) ? 'Finished their part' : 'Not yet',
            leading: Icon(
              point.doneFor(u)
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 18,
              color: point.doneFor(u) ? p.done : p.inkFaint,
            ),
          ),
      ],
    );
  }
}

/// A point's parts on its step panel: one row per person, and this person's
/// own part to open.
class SharedPartPanel extends StatelessWidget {
  const SharedPartPanel({
    super.key,
    required this.plan,
    required this.step,
    required this.onOpenPart,
  });

  final Plan plan;
  final PlanStep step;
  final ValueChanged<String> onOpenPart;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final word = switch (step.kind) {
      StepKind.test => 'mock test',
      StepKind.check => 'checklist',
      StepKind.joint => 'part',
      _ => 'mock test and checklist',
    };
    final done = step.doneBy.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          done == step.participants.length
              ? 'Everyone has finished their part.'
              : done == 0
              ? 'Each person does their own $word here.'
              : 'Partly done: $done of ${step.participants.length} have '
                    'finished their part.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 10),
        for (final u in step.participants)
          ListRow(
            title: u == plan.meId ? 'Your $word' : '${nameIn(plan, u)}’s $word',
            detail: step.doneFor(u)
                ? 'Done'
                : u == plan.meId
                ? 'Open it to begin'
                : 'Not done yet',
            leading: Icon(
              step.doneFor(u)
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 20,
              color: step.doneFor(u) ? p.done : p.inkFaint,
            ),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: p.inkFaint,
            ),
            onTap: () => onOpenPart(u),
          ),
      ],
    );
  }
}

/// The classroom's tab of points: the mock tests or checklists this person
/// has to do, with their own part marked.
class PointsSheet extends StatelessWidget {
  const PointsSheet({
    super.key,
    required this.classroom,
    required this.plan,
    required this.onOpen,
    this.onAddPoints,
  });

  final Classroom classroom;
  final Plan plan;
  final ValueChanged<String> onOpen;

  /// Adds a point after every phase that hasn't one. For managers.
  final VoidCallback? onAddPoints;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = plan.meId;
    final points = plan.steps.values.where((s) => s.isPoint).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    final mine = points.where((s) => s.participants.contains(me)).toList();
    final others = points.where((s) => !s.participants.contains(me)).toList();
    final missing = plan.phases.where(
      (ph) =>
          plan.stepsIn(ph.id).any((s) => !s.isPoint) &&
          !plan.stepsIn(ph.id).any((s) => s.isPoint),
    );
    return SheetFrame(
      title: classroom.checkLabel.isEmpty ? 'Mock tests' : classroom.checkLabel,
      action: onAddPoints != null && missing.isNotEmpty
          ? PressButton(
              label: 'Add one after each phase',
              icon: CupertinoIcons.plus,
              prominent: points.isEmpty,
              height: 46,
              expand: true,
              onTap: () {
                Navigator.of(context).pop();
                onAddPoints!();
              },
            )
          : null,
      children: [
        Text(
          'After each phase, everyone does their own part here and marks it '
          'done. The same tick shows on the map.',
          style: TypeRamp.caption(p.inkSoft),
        ),
        const StepSectionTitle('Yours', top: 14),
        if (mine.isEmpty)
          Text(
            points.isEmpty ? 'None yet.' : 'None of these are yours to do.',
            style: TypeRamp.caption(p.inkSoft),
          ),
        for (final s in mine)
          ListRow(
            title: s.title,
            detail: [
              s.doneFor(me) ? 'Your part is done' : 'Your part to do',
              '${s.doneBy.length} of ${s.participants.length} done',
              'due ${shortDate(s.due)}',
            ].join(' · '),
            leading: Icon(
              s.doneFor(me)
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 20,
              color: s.doneFor(me) ? p.done : p.accent,
            ),
            onTap: () {
              Navigator.of(context).pop();
              onOpen(s.id);
            },
          ),
        if (others.isNotEmpty) ...[
          const StepSectionTitle('Everyone else’s'),
          for (final s in others)
            ListRow(
              title: s.title,
              detail: '${s.doneBy.length} of ${s.participants.length} done',
              leading: Icon(
                CupertinoIcons.person_2,
                size: 18,
                color: p.inkSoft,
              ),
              onTap: () {
                Navigator.of(context).pop();
                onOpen(s.id);
              },
            ),
        ],
      ],
    );
  }
}
