import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart';
import 'step_collab.dart';

/// A well-known practice site. Octria only links to these: it keeps no copied
/// questions and runs no code.
class PracticeSite {
  const PracticeSite(this.title, this.url, this.what);

  final String title;
  final String url;
  final String what;
}

const _interviews = [
  PracticeSite(
    'Interview Warmup',
    'https://grow.google/certificates/interview-warmup/',
    'Practise answering interview questions out loud, from Google',
  ),
  PracticeSite(
    'Exponent practice',
    'https://www.tryexponent.com/practice',
    'Mock interviews with other people, free to start',
  ),
];

/// Starting points for each kind of task, until Ofy suggests links of its own.
const Map<TaskType, List<PracticeSite>> practiceSites = {
  TaskType.build: [
    PracticeSite(
      'LeetCode',
      'https://leetcode.com/problemset/',
      'Coding problems, the kind asked in interviews',
    ),
    PracticeSite(
      'HackerRank',
      'https://www.hackerrank.com/dashboard',
      'Coding challenges by language and topic',
    ),
    PracticeSite(
      'Exercism',
      'https://exercism.org/tracks',
      'Free coding exercises with mentoring',
    ),
    PracticeSite(
      'Frontend Mentor',
      'https://www.frontendmentor.io/challenges',
      'Real front-end projects to build',
    ),
    ..._interviews,
  ],
  TaskType.study: [
    PracticeSite(
      'Khan Academy',
      'https://www.khanacademy.org',
      'Free lessons and practice questions',
    ),
    PracticeSite(
      'Quizlet',
      'https://quizlet.com',
      'Flashcards and practice tests',
    ),
    PracticeSite(
      'Anki',
      'https://apps.ankiweb.net',
      'Spaced-repetition flashcards, free',
    ),
    PracticeSite(
      'MIT OpenCourseWare',
      'https://ocw.mit.edu',
      'Course notes, problem sets and exams',
    ),
  ],
  TaskType.research: [
    PracticeSite(
      'Google Scholar',
      'https://scholar.google.com',
      'Search papers and see who cites them',
    ),
    PracticeSite('arXiv', 'https://arxiv.org', 'Free preprints of new papers'),
    PracticeSite(
      'Zotero',
      'https://www.zotero.org',
      'Collect, organise and cite sources',
    ),
  ],
  TaskType.eventOrCreative: [
    PracticeSite(
      'Behance',
      'https://www.behance.net',
      'Creative work to learn from',
    ),
    PracticeSite(
      'Canva',
      'https://www.canva.com',
      'Posters, slides and social posts',
    ),
  ],
  TaskType.other: [
    PracticeSite(
      'Khan Academy',
      'https://www.khanacademy.org',
      'Free lessons and practice questions',
    ),
    ..._interviews,
  ],
};

/// The classroom's Practice page: the group's own practice links, and
/// suggested sites for this kind of task. Reachable at any time.
class PracticeSheet extends StatefulWidget {
  const PracticeSheet({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.taskType,
    required this.plan,
    required this.canManage,
  });

  final Backend backend;
  final String classroomId;
  final TaskType taskType;
  final Plan plan;
  final bool canManage;

  @override
  State<PracticeSheet> createState() => _PracticeSheetState();
}

class _PracticeSheetState extends State<PracticeSheet> {
  late final Stream<List<StudyMaterial>> _materials = widget.backend.materials(
    widget.classroomId,
  );
  String? _message;

  String get _me => widget.plan.meId;

  Future<void> _add({PracticeSite? from}) async {
    final StudyMaterial? made;
    if (from != null) {
      made = StudyMaterial(
        id: widget.backend.newId(),
        kind: MaterialKind.practice,
        title: from.title,
        url: from.url,
        ownerUid: _me,
        createdAt: DateTime.now(),
      );
    } else {
      made = await showGlassSheet<StudyMaterial>(
        context,
        (_) => MaterialEditorSheet(
          newId: widget.backend.newId,
          ownerUid: _me,
          practice: true,
        ),
      );
    }
    if (made == null || !mounted) return;
    try {
      await widget.backend.saveMaterial(widget.classroomId, made);
      setState(() => _message = null);
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  Future<void> _remove(StudyMaterial m) async {
    try {
      await widget.backend.deleteMaterial(widget.classroomId, m.id);
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  Future<void> _open(String url) async {
    final opened = await openLink(url);
    if (!opened && mounted) {
      setState(() => _message = 'That link couldn’t be opened.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final suggested = practiceSites[widget.taskType] ?? const [];
    return StreamBuilder<List<StudyMaterial>>(
      stream: _materials,
      builder: (context, snap) {
        final ours = (snap.data ?? const <StudyMaterial>[])
            .where((m) => m.kind == MaterialKind.practice)
            .toList();
        final added = {for (final m in ours) m.url};
        return SheetFrame(
          title: 'Practice',
          message: _message,
          action: PressButton(
            label: 'Add a practice link',
            icon: CupertinoIcons.plus,
            prominent: true,
            height: 48,
            expand: true,
            onTap: _add,
          ),
          children: [
            Text(
              'Mock interviews, question banks and coding practice, a tap '
              'away. Links open the site itself.',
              style: TypeRamp.label(p.inkSoft),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(
                'From your classroom',
                style: TypeRamp.label(p.inkSoft),
              ),
            ),
            if (snap.hasData && ours.isEmpty)
              Text(
                'Nothing added yet. Add your own, or add one of the sites '
                'below so everyone has it.',
                style: TypeRamp.caption(p.inkSoft),
              ),
            for (final m in ours)
              _SiteRow(
                title: m.title,
                detail:
                    '${m.site} · added by ${nameIn(widget.plan, m.ownerUid)}',
                onOpen: () => _open(m.url),
                trailing: m.ownerUid == _me || widget.canManage
                    ? PressButton(
                        label: 'Remove ${m.title}',
                        icon: CupertinoIcons.minus_circle,
                        iconOnly: true,
                        quiet: true,
                        height: 44,
                        onTap: () => _remove(m),
                      )
                    : null,
              ),
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(
                'Suggested for ${widget.taskType.label.toLowerCase()} tasks',
                style: TypeRamp.label(p.inkSoft),
              ),
            ),
            for (final s in suggested)
              _SiteRow(
                title: s.title,
                detail: s.what,
                onOpen: () => _open(s.url),
                trailing: added.contains(s.url)
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 16,
                          color: p.done,
                          semanticLabel: 'Added',
                        ),
                      )
                    : PressButton(
                        label: 'Add ${s.title} to the classroom',
                        icon: CupertinoIcons.plus_circle,
                        iconOnly: true,
                        quiet: true,
                        height: 44,
                        onTap: () => unawaited(_add(from: s)),
                      ),
              ),
            const SizedBox(height: 6),
            Text(
              'Octria keeps only the links. It stores no questions and runs '
              'no code.',
              style: TypeRamp.caption(p.inkFaint),
            ),
          ],
        );
      },
    );
  }
}

class _SiteRow extends StatelessWidget {
  const _SiteRow({
    required this.title,
    required this.detail,
    required this.onOpen,
    this.trailing,
  });

  final String title;
  final String detail;
  final VoidCallback onOpen;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Open $title. $detail',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: p.accentTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            CupertinoIcons.flag,
                            size: 16,
                            color: p.accentTeal,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: TypeRamp.body(p.ink)),
                              Text(
                                detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TypeRamp.caption(p.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          CupertinoIcons.arrow_up_right,
                          size: 14,
                          color: p.inkFaint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
