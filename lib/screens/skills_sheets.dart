/// Skills: reading them from a resume for someone's profile, and sharing a
/// group's steps out by who is best suited to each.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../ai/ai.dart';
import '../ai/split.dart';
import '../data/backend.dart';
import '../data/drive.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart';
import 'room_lists.dart';
import 'step_collab.dart';
import 'step_panel.dart';

String _number(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// A resume this size or smaller can be sent to Ofy.
const int kMaxResumeBytes = 4 * 1024 * 1024;

/// Ofy reads a resume, pasted or as a file, and lists the skills in it. Pops
/// the ones the person keeps.
class ResumeSkillsSheet extends StatefulWidget {
  const ResumeSkillsSheet({super.key, required this.backend});

  final Backend backend;

  @override
  State<ResumeSkillsSheet> createState() => _ResumeSkillsSheetState();
}

class _ResumeSkillsSheetState extends State<ResumeSkillsSheet> {
  final _text = TextEditingController();
  String? _fileName;
  Uint8List? _file;
  String _mime = '';
  String? _problem;
  var _reading = false;
  List<String>? _found;
  final _kept = <String>{};

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(dialogTitle: 'Choose your resume');
    } on Object {
      setState(() => _problem = 'Files couldn’t be opened on this device.');
      return;
    }
    if (picked == null || !mounted) return;
    final mime = mimeTypeFor(picked.name);
    final plain = picked.name.toLowerCase().endsWith('.txt');
    if (mime != 'application/pdf' && !plain) {
      setState(
        () => _problem =
            'Choose a PDF or a .txt file, or paste the text instead.',
      );
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > kMaxResumeBytes) {
      setState(
        () => _problem = 'That file is over 4 MB. Paste the text instead.',
      );
      return;
    }
    setState(() {
      _problem = null;
      if (plain) {
        // A text file is just text: it goes in the box, to be looked over.
        _text.text = utf8.decode(bytes, allowMalformed: true);
        _file = null;
        _fileName = null;
      } else {
        _file = bytes;
        _mime = mime;
        _fileName = picked!.name;
      }
    });
  }

  Future<void> _read() async {
    setState(() {
      _reading = true;
      _problem = null;
    });
    try {
      final skills = await widget.backend.ai.readSkills(
        text: _text.text,
        file: _file,
        mime: _mime,
      );
      if (!mounted) return;
      setState(() {
        _reading = false;
        _found = skills;
        _kept
          ..clear()
          ..addAll(skills);
      });
    } on AiFailure catch (e) {
      if (mounted) {
        setState(() {
          _reading = false;
          _problem = e.message;
        });
      }
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _reading = false;
          _problem = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final found = _found;
    if (found != null) {
      return SheetFrame(
        title: 'Skills Ofy found',
        action: PressButton(
          label: _kept.isEmpty
              ? 'Add none'
              : 'Add ${_kept.length} ${_kept.length == 1 ? 'skill' : 'skills'}',
          prominent: _kept.isNotEmpty,
          height: 46,
          expand: true,
          onTap: () => Navigator.of(context).pop([
            for (final s in found)
              if (_kept.contains(s)) s,
          ]),
        ),
        children: [
          Text(
            found.isEmpty
                ? 'Ofy found no skills in that. Try pasting more of it.'
                : 'Tap any that aren’t right to leave them out.',
            style: TypeRamp.label(p.inkSoft),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in found)
                SelectChip(
                  label: s,
                  selected: _kept.contains(s),
                  onTap: () => setState(() {
                    if (!_kept.remove(s)) _kept.add(s);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      );
    }
    final ready = _file != null || _text.text.trim().length >= 20;
    return SheetFrame(
      title: 'Read skills from a resume',
      message: _problem,
      action: PressButton(
        label: _reading ? 'Ofy is reading…' : 'Find my skills',
        icon: CupertinoIcons.sparkles,
        prominent: true,
        height: 46,
        expand: true,
        onTap: _reading || !ready ? null : () => unawaited(_read()),
      ),
      children: [
        Text(
          'Paste your resume, or a few lines about what you can do, or '
          'choose a PDF.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 12),
        GlassField(
          label: 'Resume text',
          controller: _text,
          maxLines: 8,
          minLines: 4,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            PressButton(
              label: _fileName == null ? 'Choose a PDF' : 'Choose another',
              icon: CupertinoIcons.doc,
              height: 40,
              onTap: _reading ? null : () => unawaited(_pick()),
            ),
            if (_fileName != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _fileName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeRamp.label(p.ink),
                ),
              ),
              PressButton(
                label: 'Remove the file',
                icon: CupertinoIcons.xmark,
                iconOnly: true,
                quiet: true,
                height: 40,
                onTap: () => setState(() {
                  _file = null;
                  _fileName = null;
                }),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Ofy runs on Google’s Gemini, which reads this once to list the '
          'skills. Octria doesn’t keep the resume; only the skills you add '
          'are saved, and people in your classrooms can see those.',
          style: TypeRamp.caption(p.inkFaint),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Shares the steps that haven't started out between a group's people, by
/// their skills and roles, for a master or co-master to look over and apply.
class SplitSheet extends StatefulWidget {
  const SplitSheet({
    super.key,
    required this.backend,
    required this.classroom,
    required this.plan,
  });

  final Backend backend;
  final Classroom classroom;
  final Plan plan;

  @override
  State<SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<SplitSheet> {
  List<Person>? _people;

  /// Who each step goes to, and why, by step id.
  var _to = <String, Assignment>{};
  var _asking = false;
  var _saving = false;
  var _byOfy = false;
  String? _problem;

  Plan get _plan => widget.plan;

  /// Work that hasn't started: what's under way or done stays with its owner.
  late final List<PlanStep> _steps =
      _plan.steps.values
          .where((s) => !s.shared && s.status == StepStatus.todo)
          .toList()
        ..sort((a, b) => a.due.compareTo(b.due));

  List<SplitStep> get _asSplit => [
    for (final s in _steps)
      SplitStep(
        id: s.id,
        title: s.title,
        hours: s.estimateHours,
        skills: s.skills,
        ownerId: s.ownerId,
      ),
  ];

  /// Hours each person already has under way, which the split works around.
  Map<String, double> get _busy {
    final out = <String, double>{};
    for (final s in _plan.steps.values) {
      if (!s.shared && s.status == StepStatus.doing) {
        out[s.ownerId] = (out[s.ownerId] ?? 0) + s.estimateHours;
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final profiles = await Future.wait([
      for (final m in _plan.members)
        widget.backend.profileOf(m.id).catchError((Object _) => null),
    ]);
    if (!mounted) return;
    final people = [
      for (final (i, m) in _plan.members.indexed)
        Person(
          id: m.id,
          name: m.name,
          role: widget.classroom.roles[m.id] ?? '',
          skills: profiles[i]?.skills ?? const [],
        ),
    ];
    setState(() {
      _people = people;
      _to = {
        for (final a in matchBySkills(_asSplit, people, load: _busy))
          a.stepId: a,
      };
    });
  }

  Future<void> _ask() async {
    final people = _people!;
    setState(() {
      _asking = true;
      _problem = null;
    });
    try {
      final got = await widget.backend.ai.splitBySkills(
        SplitBrief(
          subject: widget.classroom.title,
          people: people,
          steps: _asSplit,
        ),
      );
      if (!mounted) return;
      setState(() {
        _asking = false;
        _byOfy = true;
        // A step Ofy said nothing about keeps the match it had.
        _to = {..._to, for (final a in got) a.stepId: a};
      });
    } on AiFailure catch (e) {
      if (mounted) {
        setState(() {
          _asking = false;
          _problem = e.message;
        });
      }
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _asking = false;
          _problem = e.message;
        });
      }
    }
  }

  Future<void> _choose(PlanStep step) async {
    final uid = await showGlassSheet<String>(
      context,
      (_) => ChoiceSheet<String>(
        title: 'Who takes it?',
        message: '“${step.title}”',
        choices: [
          for (final p in _people!)
            (
              p.id == step.ownerId ? '${p.name} (has it now)' : p.name,
              p.id,
              p.id == _to[step.id]?.toId,
            ),
        ],
      ),
    );
    if (uid == null || !mounted) return;
    setState(
      () => _to[step.id] = Assignment(
        stepId: step.id,
        toId: uid,
        why: 'Your choice',
      ),
    );
  }

  List<PlanStep> get _changed => [
    for (final s in _steps)
      if (_to[s.id] case final a? when a.toId != s.ownerId) s,
  ];

  Future<void> _apply() async {
    final changed = _changed;
    setState(() {
      _saving = true;
      _problem = null;
    });
    final b = widget.backend;
    final cid = widget.classroom.id;
    try {
      await Future.wait([
        for (final s in changed)
          b.saveStep(cid, s.copyWith(ownerId: _to[s.id]!.toId)),
      ]);
      try {
        await b.logActivity(
          cid,
          ActivityEntry(
            id: b.newId(),
            actorUid: _plan.meId,
            kind: ActivityKind.stepHandedOver,
            summary:
                '${nameIn(_plan, _plan.meId)} shared out '
                '${changed.length} ${changed.length == 1 ? 'step' : 'steps'} '
                'by skills',
            createdAt: DateTime.now(),
          ),
        );
      } on BackendFailure {
        // The log is a nicety; the steps have moved.
      }
      if (mounted) Navigator.of(context).pop(changed.length);
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final people = _people;
    if (people == null) {
      return const SheetFrame(
        title: 'Share out by skills',
        children: [
          SizedBox(height: 24),
          Center(child: CupertinoActivityIndicator(radius: 13)),
          SizedBox(height: 24),
        ],
      );
    }
    if (_steps.isEmpty) {
      return SheetFrame(
        title: 'Share out by skills',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'Every step has started or is done, so there’s nothing left '
              'to share out.',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          ),
        ],
      );
    }
    final changed = _changed;
    final busy = _busy;
    final after = <String, double>{
      for (final person in people) person.id: busy[person.id] ?? 0,
    };
    for (final s in _steps) {
      final to = _to[s.id]?.toId ?? s.ownerId;
      after[to] = (after[to] ?? 0) + s.estimateHours;
    }
    final noSkills = people.every((x) => x.skills.isEmpty && x.role.isEmpty);
    return SheetFrame(
      title: 'Share out by skills',
      message: _problem,
      action: PressButton(
        label: _saving
            ? 'Saving…'
            : changed.isEmpty
            ? 'Nothing changes hands'
            : 'Apply: ${changed.length} ${changed.length == 1 ? 'step changes' : 'steps change'} hands',
        prominent: true,
        height: 46,
        expand: true,
        onTap: _saving || changed.isEmpty ? null : () => unawaited(_apply()),
      ),
      children: [
        Text(
          'Steps that haven’t started go to whoever suits them best, with '
          'the hours kept even. Nothing changes until you apply it.',
          style: TypeRamp.label(p.inkSoft),
        ),
        if (noSkills)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: glassTint(p, p.accentWarm, radius: 14),
            child: Text(
              'Nobody here has added skills or a role yet, so this only '
              'evens out the hours. Each person adds skills under Profile, '
              'then Edit profile.',
              style: TypeRamp.label(p.ink),
            ),
          ),
        const StepSectionTitle('People'),
        for (final person in people)
          ListRow(
            lines: 1,
            title: person.name,
            detail: sentences([
              if (person.role.isNotEmpty) person.role,
              person.skills.isEmpty
                  ? 'No skills added'
                  : person.skills.take(8).join(', '),
              '${_number(after[person.id] ?? 0)} hours after this',
            ]),
            leading: Icon(
              CupertinoIcons.person,
              size: 20,
              color: person.skills.isEmpty ? p.inkFaint : p.accent,
            ),
          ),
        PressButton(
          label: _asking
              ? 'Ofy is weighing it up…'
              : _byOfy
              ? 'Ask Ofy again'
              : 'Ask Ofy to weigh it up',
          icon: CupertinoIcons.sparkles,
          quiet: true,
          height: 40,
          onTap: _asking ? null : () => unawaited(_ask()),
        ),
        const StepSectionTitle('Steps'),
        for (final s in _steps)
          ListRow(
            lines: 2,
            title: s.title,
            detail: () {
              final a = _to[s.id];
              final to = a?.toId ?? s.ownerId;
              final who = to == s.ownerId
                  ? 'Stays with ${nameIn(_plan, s.ownerId)}'
                  : '${nameIn(_plan, s.ownerId)} → ${nameIn(_plan, to)}';
              return sentences([
                who,
                if ((a?.why ?? '').isNotEmpty) a!.why,
                '${_number(s.estimateHours)} hours',
              ]);
            }(),
            leading: Icon(
              (_to[s.id]?.toId ?? s.ownerId) == s.ownerId
                  ? CupertinoIcons.equal_circle
                  : CupertinoIcons.arrow_right_arrow_left_circle,
              size: 20,
              color: (_to[s.id]?.toId ?? s.ownerId) == s.ownerId
                  ? p.inkFaint
                  : p.accent,
            ),
            trailing: Icon(
              CupertinoIcons.chevron_down,
              size: 14,
              color: p.inkFaint,
            ),
            onTap: () => unawaited(_choose(s)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Tap a step to choose someone yourself. Afterwards, Re-plan '
            'works the dates out again for the new owners.',
            style: TypeRamp.caption(p.inkFaint),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
