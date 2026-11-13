/// Re-planning: what's left of a plan, laid out again from today. It shows
/// whether the plan still fits its deadline, the ways to make it fit (more
/// hours, a later deadline, or what Ofy would cut), and every step that moves,
/// before anything is changed.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../ai/ai.dart';
import '../ai/replan.dart';
import '../ai/schedule.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart';
import 'room_lists.dart';
import 'step_panel.dart';

String _number(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

String _days(int n) => n == 1 ? '1 day' : '$n days';

/// What a re-plan changed, for the graph to play back.
class ReplanOutcome {
  const ReplanOutcome({
    required this.what,
    this.moves = const [],
    this.dropped = const [],
  });

  /// "4 steps moved, 1 left out", or empty when only the settings changed.
  final String what;
  final List<StepMove> moves;
  final List<PlanStep> dropped;
}

class ReplanSheet extends StatefulWidget {
  const ReplanSheet({
    super.key,
    required this.backend,
    required this.classroom,
    required this.plan,
  });

  final Backend backend;
  final Classroom classroom;
  final Plan plan;

  @override
  State<ReplanSheet> createState() => _ReplanSheetState();
}

class _ReplanSheetState extends State<ReplanSheet> {
  late final _hours = TextEditingController(
    text: _number(widget.classroom.hoursPerWeek),
  );
  var _perDay = false;
  late DateTime? _deadline = widget.classroom.deadline;

  ReplanAdvice? _advice;

  /// Which of Ofy's changes are taken up, by step id.
  final _taken = <String>{};
  var _asking = false;
  var _saving = false;
  String? _problem;

  Plan get _plan => widget.plan;
  String get _me => _plan.meId;
  bool get _manages => widget.classroom.canManage(_me);
  bool get _isMaster => widget.classroom.masterUid == _me;
  bool _canChange(PlanStep s) => _manages || s.ownerId == _me;

  @override
  void initState() {
    super.initState();
    _hours.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  double? get _hoursPerWeek {
    final v = double.tryParse(_hours.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return (_perDay ? v * 7 : v).clamp(0.5, 120).toDouble();
  }

  /// Ofy's refs for the steps still to do: s1, s2 and so on.
  late final Map<String, PlanStep> _byRef = () {
    final left =
        _plan.steps.values.where((s) => s.status != StepStatus.done).toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    return {for (final (i, s) in left.indexed) 's${i + 1}': s};
  }();

  Set<String> get _drop => {
    for (final c in _advice?.cuts ?? const <Cut>[])
      if (c.drops && _taken.contains(_byRef[c.ref]?.id)) _byRef[c.ref]!.id,
  };

  Map<String, double> get _shorter => {
    for (final c in _advice?.cuts ?? const <Cut>[])
      if (!c.drops && _taken.contains(_byRef[c.ref]?.id))
        _byRef[c.ref]!.id: c.hours!,
  };

  Replan _work({bool plain = false}) => replan(
    _plan,
    today: _plan.today,
    hoursPerWeek: _hoursPerWeek,
    deadline: _deadline,
    drop: plain ? const {} : _drop,
    hours: plain ? const {} : _shorter,
    canChange: _canChange,
  );

  Future<void> _ask(Replan now) async {
    setState(() {
      _asking = true;
      _problem = null;
    });
    final waits = <String, int>{};
    for (final s in _plan.steps.values) {
      for (final n in s.dependsOn) {
        waits[n] = (waits[n] ?? 0) + 1;
      }
    }
    try {
      final advice = await widget.backend.ai.advise(
        ReplanBrief(
          subject: widget.classroom.title,
          deadline: _deadline,
          daysOver: now.daysOver,
          hoursPerWeek: now.schedule.hoursPerWeek,
          constraints: widget.classroom.constraints,
          steps: [
            for (final e in _byRef.entries)
              ReplanStep(
                ref: e.key,
                title: e.value.title,
                phase: _plan.phase(e.value.phaseId).title,
                hours: e.value.estimateHours,
                owner: e.value.shared ? '' : _plan.member(e.value.ownerId).name,
                started: e.value.status == StepStatus.doing,
                neededBy: waits[e.value.id] ?? 0,
                // Someone else's step is theirs to change.
                point: e.value.shared || !_canChange(e.value),
              ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        _advice = advice;
        _taken
          ..clear()
          ..addAll([for (final c in advice.cuts) ?_byRef[c.ref]?.id]);
        _asking = false;
      });
    } on AiFailure catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.message;
          _asking = false;
        });
      }
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.message;
          _asking = false;
        });
      }
    }
  }

  bool get _settingsChanged =>
      _isMaster &&
      (_deadline != widget.classroom.deadline ||
          (_hoursPerWeek != null &&
              _hoursPerWeek != widget.classroom.hoursPerWeek));

  Future<void> _apply(Replan now) async {
    setState(() {
      _saving = true;
      _problem = null;
    });
    final b = widget.backend;
    final cid = widget.classroom.id;
    try {
      if (_settingsChanged) {
        await b.updateClassroom(
          widget.classroom.copyWith(
            deadline: _deadline,
            hoursPerWeek: _hoursPerWeek,
          ),
        );
      }
      final gone = {for (final s in now.dropped) s.id};
      await Future.wait([
        for (final m in now.moves)
          b.saveStep(
            cid,
            m.step.copyWith(
              start: m.start,
              due: m.due,
              estimateHours: m.hours,
              // What it waited for may have been left out.
              dependsOn: [
                for (final n in m.step.dependsOn)
                  if (!gone.contains(n)) n,
              ],
            ),
          ),
      ]);
      for (final s in now.dropped) {
        await b.deleteStep(cid, s.id);
      }
      final name = _plan.member(_me).name;
      final what = [
        if (now.moves.isNotEmpty)
          '${now.moves.length} ${now.moves.length == 1 ? 'step' : 'steps'} moved',
        if (now.dropped.isNotEmpty) '${now.dropped.length} left out',
      ].join(', ');
      try {
        await b.logActivity(
          cid,
          ActivityEntry(
            id: b.newId(),
            actorUid: _me,
            kind: ActivityKind.stepEdited,
            summary: '$name re-planned what’s left: $what',
            createdAt: DateTime.now(),
          ),
        );
      } on BackendFailure {
        // The log is a nicety; the new dates are in.
      }
      if (mounted) {
        Navigator.of(context).pop(
          ReplanOutcome(what: what, moves: now.moves, dropped: now.dropped),
        );
      }
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.message;
          _saving = false;
        });
      }
    }
  }

  Widget _summary(Palette p, Replan now) {
    final d = now.schedule.deadline;
    final pace =
        '${_number(now.schedule.hoursPerWeek)} hours a week'
        '${widget.classroom.individual ? '' : ' each'}';
    final ends = 'At $pace, what’s left ends ${shortDate(now.finish)}.';
    final String verdict;
    if (d == null) {
      verdict = 'No deadline is set.';
    } else if (now.fits) {
      final spare = d.difference(now.finish).inDays;
      verdict = spare == 0
          ? 'That’s the deadline itself.'
          : 'That’s ${_days(spare)} before the deadline, ${shortDate(d)}.';
    } else {
      verdict =
          'That’s ${_days(now.daysOver)} after the deadline, '
          '${shortDate(d)}.';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: glassTint(p, now.fits ? p.done : p.accentWarm, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${now.left} ${now.left == 1 ? 'step' : 'steps'} left'
            '${now.overdue == 0 ? '' : ', ${now.overdue} overdue'}',
            style: TypeRamp.title(p.ink).copyWith(fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text('$ends $verdict', style: TypeRamp.label(p.ink)),
          if (now.schedule.assumedHours)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No hours were given, so this assumes '
                '${_number(kDefaultHoursPerWeek)} a week.',
                style: TypeRamp.caption(p.inkSoft),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = _work();
    final plain = _work(plain: true);
    if (now.left == 0) {
      return SheetFrame(
        title: 'Re-plan',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'Nothing is left to do, so there’s nothing to re-plan.',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          ),
        ],
      );
    }
    final need = now.fits
        ? null
        : hoursToFit(
            _plan,
            today: _plan.today,
            deadline: _deadline,
            drop: _drop,
            hours: _shorter,
          );
    final changes = now.moves.length + now.dropped.length;
    final cuts = [
      for (final c in _advice?.cuts ?? const <Cut>[])
        if (_byRef[c.ref] case final s?) (c, s),
    ];
    return SheetFrame(
      title: 'Re-plan',
      message: _problem,
      action: PressButton(
        label: _saving
            ? 'Saving…'
            : changes == 0
            ? (_settingsChanged ? 'Save the new settings' : 'Nothing to move')
            : 'Apply: ${[if (now.moves.isNotEmpty) 'move ${now.moves.length}', if (now.dropped.isNotEmpty) 'leave out ${now.dropped.length}'].join(', ')}',
        icon: CupertinoIcons.arrow_2_circlepath,
        prominent: true,
        height: 46,
        expand: true,
        onTap: _saving || (changes == 0 && !_settingsChanged)
            ? null
            : () => unawaited(_apply(now)),
      ),
      children: [
        Text(
          'What’s left is laid out again from today, in the same order. '
          'Nothing changes until you apply it.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 12),
        _summary(p, now),
        const StepSectionTitle('Time'),
        GlassField(
          label: _perDay
              ? 'Hours each day${widget.classroom.individual ? '' : ' each person can give'}'
              : 'Hours each week${widget.classroom.individual ? '' : ' each person can give'}',
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
        if (_isMaster) ...[
          const SizedBox(height: 10),
          GlassDateField(
            label: 'Deadline',
            value: _deadline,
            onChanged: (d) => setState(() => _deadline = d),
          ),
        ],
        if (!now.fits) ...[
          const StepSectionTitle('Ways to make it fit'),
          if (need != null && need > now.schedule.hoursPerWeek)
            ListRow(
              title: 'Give it ${_number(need)} hours a week',
              detail:
                  'Up from ${_number(now.schedule.hoursPerWeek)}. Then it '
                  'ends by the deadline.',
              leading: Icon(CupertinoIcons.clock, size: 20, color: p.accent),
              onTap: () => setState(() {
                _perDay = false;
                _hours.text = _number(need);
              }),
            ),
          if (_isMaster)
            ListRow(
              title: 'Move the deadline to ${shortDate(now.finish)}',
              detail: '${_days(now.daysOver)} later than it is now.',
              leading: Icon(CupertinoIcons.calendar, size: 20, color: p.accent),
              onTap: () => setState(() => _deadline = now.finish),
            ),
          ListRow(
            title: _asking
                ? 'Ofy is looking at what’s left…'
                : _advice == null
                ? 'Ask Ofy what to cut'
                : 'Ask Ofy again',
            detail: 'Ofy suggests steps to shorten or leave out. You choose.',
            leading: _asking
                ? const CupertinoActivityIndicator(radius: 9)
                : Icon(
                    CupertinoIcons.sparkles,
                    size: 20,
                    color: p.accentViolet,
                  ),
            onTap: _asking ? null : () => unawaited(_ask(plain)),
          ),
        ],
        if (_advice != null) ...[
          const StepSectionTitle('What Ofy would change'),
          if (_advice!.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_advice!.note, style: TypeRamp.label(p.ink)),
            ),
          if (cuts.isEmpty)
            Text(
              'Ofy found nothing that can safely give. More hours or a later '
              'deadline are the ways left.',
              style: TypeRamp.label(p.inkSoft),
            ),
          for (final (c, s) in cuts)
            ListRow(
              lines: 3,
              title: c.drops
                  ? 'Leave out “${s.title}”'
                  : 'Shorten “${s.title}” from ${_number(s.estimateHours)} '
                        'to ${_number(c.hours)} hours',
              detail: c.why,
              leading: Icon(
                _taken.contains(s.id)
                    ? CupertinoIcons.checkmark_square_fill
                    : CupertinoIcons.square,
                size: 22,
                color: _taken.contains(s.id) ? p.accent : p.inkFaint,
              ),
              onTap: () => setState(() {
                if (!_taken.remove(s.id)) _taken.add(s.id);
              }),
            ),
        ],
        StepSectionTitle(changes == 0 ? 'Nothing moves' : 'What changes'),
        if (changes == 0)
          Text(
            'Every step you can change already sits where this puts it.',
            style: TypeRamp.label(p.inkSoft),
          ),
        for (final s in now.dropped)
          ListRow(
            title: s.title,
            detail:
                'Left out. It goes to Deleted, where you can bring it back.',
            leading: Icon(
              CupertinoIcons.minus_circle,
              size: 20,
              color: p.blocked,
            ),
          ),
        for (final m in now.moves.take(40))
          ListRow(
            title: m.step.title,
            detail: sentences([
              m.days == 0
                  ? 'Still due ${shortDate(m.due)}'
                  : 'Due ${shortDate(m.step.due)} → ${shortDate(m.due)}, '
                        '${_days(m.days.abs())} ${m.days > 0 ? 'later' : 'sooner'}',
              if (m.hours != null)
                '${_number(m.step.estimateHours)} → ${_number(m.hours)} hours',
              if (m.step.ownerId != _me && !m.step.shared)
                _plan.member(m.step.ownerId).name,
            ]),
            leading: Icon(
              m.days > 0
                  ? CupertinoIcons.arrow_right_circle
                  : CupertinoIcons.arrow_left_circle,
              size: 20,
              color: m.days > 0 ? p.accentWarm : p.done,
            ),
          ),
        if (now.moves.length > 40)
          Text(
            'And ${now.moves.length - 40} more.',
            style: TypeRamp.caption(p.inkSoft),
          ),
        if (!_manages)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Only your own steps move. The master or a co-master can '
              're-plan everyone’s.',
              style: TypeRamp.caption(p.inkSoft),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}
