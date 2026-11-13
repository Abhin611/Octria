/// Lists that gather things up by classroom: chats, finished work, deleted
/// work, and who does what. Each works for one classroom, and the home pages
/// show them for every classroom at once.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../data/overview.dart';
import '../data/plan_sync.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/motion.dart';
import 'classroom_forms.dart';
import 'step_collab.dart';
import 'threads_sheet.dart';

/// One colour per classroom, the same everywhere it's shown, in the order
/// the classrooms are listed.
Color roomColour(Palette p, int index) {
  final colours = [
    p.accent,
    p.accentWarm,
    p.accentTeal,
    p.accentViolet,
    p.done,
    p.route,
  ];
  return colours[index % colours.length];
}

Set<String> _words(String s) => {
  for (final w in s.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
    if (w.length > 2 && !_common.contains(w)) w,
};

const _common = {'the', 'and', 'for', 'with', 'your', 'from', 'into', 'all'};

/// A step already in [plan] that [title] seems to repeat, if there is one:
/// the same words, or nearly.
PlanStep? similarStep(Plan plan, String title, {String? except}) {
  final want = _words(title);
  if (want.isEmpty) return null;
  PlanStep? best;
  var bestScore = 0.0;
  for (final s in plan.steps.values) {
    if (s.id == except) continue;
    final have = _words(s.title);
    if (have.isEmpty) continue;
    final shared = have.intersection(want).length;
    final score =
        shared / (have.length < want.length ? have.length : want.length);
    if (shared > 0 && score >= 0.75 && score > bestScore) {
      best = s;
      bestScore = score;
    }
  }
  return best;
}

/// A few choices, one of which is returned. Closing returns null.
class ChoiceSheet<T> extends StatelessWidget {
  const ChoiceSheet({
    super.key,
    required this.title,
    required this.message,
    required this.choices,
  });

  final String title;
  final String message;

  /// Label, value, and whether it's the main choice.
  final List<(String, T, bool)> choices;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: title,
      children: [
        Text(message, style: TypeRamp.body(p.ink)),
        const SizedBox(height: 18),
        for (final (label, value, main) in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PressButton(
              label: label,
              prominent: main,
              height: 46,
              expand: true,
              onTap: () => Navigator.of(context).pop(value),
            ),
          ),
      ],
    );
  }
}

/// A heading for one classroom, in its colour.
class RoomHeading extends StatelessWidget {
  const RoomHeading({
    super.key,
    required this.title,
    required this.colour,
    this.detail,
  });

  final String title;
  final Color colour;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeRamp.heading(p.ink),
              ),
            ),
          ),
          if (detail != null) Text(detail!, style: TypeRamp.caption(p.inkSoft)),
        ],
      ),
    );
  }
}

/// A plain row: a mark, a title, a line under it, and something at the end.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.detail,
    this.leading,
    this.trailing,
    this.onTap,
    this.colour,
    this.lines = 2,
  });

  /// How many lines the title may run to before it's cut short.
  final int lines;

  final String title;
  final String? detail;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// A thin bar down the left edge, in the classroom's colour.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          if (colour != null) ...[
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (leading != null) ...[leading!, const SizedBox(width: 11)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: TypeRamp.label(p.ink).weighted(FontWeight.w600),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.caption(p.inkSoft),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return Pressable(
      label: detail == null ? title : '$title. $detail',
      onTap: onTap!,
      child: row,
    );
  }
}

Widget _empty(Palette p, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
  child: Text(text, style: TypeRamp.caption(p.inkSoft)),
);

// Done -------------------------------------------------------------------------

/// What's finished in one classroom: whole phases, then each finished step,
/// latest first.
class DoneList extends StatelessWidget {
  const DoneList({
    super.key,
    required this.plan,
    this.colour,
    this.onOpen,
    this.onlyMine = false,
  });

  final Plan plan;
  final Color? colour;
  final ValueChanged<PlanStep>? onOpen;

  /// Only this person's own steps, as on the home timeline.
  final bool onlyMine;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final done =
        plan.steps.values
            .where(
              (s) =>
                  s.status == StepStatus.done &&
                  (!onlyMine || s.ownerId == plan.meId),
            )
            .toList()
          ..sort((a, b) => b.due.compareTo(a.due));
    final phases = [
      for (final ph in plan.phases)
        if (plan.stepsIn(ph.id).isNotEmpty && plan.phaseProgress(ph.id) == 1)
          ph,
    ];
    if (done.isEmpty) return _empty(p, 'Nothing finished here yet.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phases.isNotEmpty && !onlyMine) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Phases', style: TypeRamp.caption(p.inkSoft)),
          ),
          for (final ph in phases)
            ListRow(
              title: ph.title,
              detail: 'All ${plan.stepsIn(ph.id).length} steps done',
              colour: colour,
              leading: Icon(
                CupertinoIcons.square_stack_3d_up_fill,
                size: 18,
                color: p.done,
              ),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Steps', style: TypeRamp.caption(p.inkSoft)),
          ),
        ],
        for (final s in done)
          ListRow(
            title: s.title,
            detail: [
              plan.phases
                      .where((ph) => ph.id == s.phaseId)
                      .firstOrNull
                      ?.title ??
                  '',
              if (!onlyMine) nameIn(plan, s.ownerId),
              'due ${shortDate(s.due)}',
            ].where((x) => x.isNotEmpty).join(' · '),
            colour: colour,
            leading: Icon(
              CupertinoIcons.checkmark_circle_fill,
              size: 18,
              color: p.done,
            ),
            onTap: onOpen == null ? null : () => onOpen!(s),
          ),
      ],
    );
  }
}

// Deleted ----------------------------------------------------------------------

enum DeletedKind { steps, phases, chats }

/// What's been deleted in one classroom, of one kind, with a way back.
class DeletedList extends StatelessWidget {
  const DeletedList({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.plan,
    required this.kind,
    this.colour,
    this.onNotice,
    this.dense = false,
  });

  final Backend backend;
  final String classroomId;
  final Plan plan;
  final DeletedKind kind;
  final Color? colour;
  final ValueChanged<String>? onNotice;

  /// Says nothing when there's nothing, for lists of many classrooms.
  final bool dense;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() job,
    String done,
  ) async {
    try {
      await job();
      onNotice?.call(done);
    } on BackendFailure catch (e) {
      onNotice?.call(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (kind == DeletedKind.chats) {
      return StreamBuilder<List<ChatThread>>(
        stream: backend.threads(classroomId),
        builder: (context, snap) {
          final hidden = [
            for (final t in snap.data ?? const <ChatThread>[])
              if (t.hiddenFor(plan.meId)) t,
          ];
          if (hidden.isEmpty) {
            return dense || !snap.hasData
                ? const SizedBox.shrink()
                : _empty(p, 'No deleted chats.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final t in hidden)
                ListRow(
                  title: threadTitle(t, plan),
                  detail: t.lastText.isEmpty
                      ? 'No messages'
                      : '${t.lastBy == plan.meId ? 'You: ' : ''}${t.lastText}',
                  colour: colour,
                  leading: Icon(
                    t.participants.length > 2
                        ? CupertinoIcons.person_3
                        : CupertinoIcons.chat_bubble,
                    size: 18,
                    color: p.inkSoft,
                  ),
                  trailing: PressButton(
                    label: 'Bring back',
                    height: 34,
                    onTap: () => _run(
                      context,
                      () => backend.hideThread(classroomId, t.id, false),
                      'The chat is back.',
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }
    return StreamBuilder<List<TrashItem>>(
      stream: backend.trash(classroomId),
      builder: (context, snap) {
        final want = kind == DeletedKind.steps
            ? TrashKind.step
            : TrashKind.phase;
        final items = [
          for (final x in snap.data ?? const <TrashItem>[])
            if (x.kind == want) x,
        ];
        if (items.isEmpty) {
          return dense || !snap.hasData
              ? const SizedBox.shrink()
              : _empty(
                  p,
                  kind == DeletedKind.steps
                      ? 'No deleted steps.'
                      : 'No deleted phases.',
                );
        }
        final manages = plan.members.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final x in items)
              ListRow(
                title: x.title,
                detail: [
                  if (x.kind == TrashKind.phase)
                    '${x.steps.length} ${x.steps.length == 1 ? 'step' : 'steps'}',
                  'Deleted ${shortDate(x.deletedAt)}',
                  if (x.deletedBy != plan.meId)
                    'by ${nameIn(plan, x.deletedBy)}',
                ].join(' · '),
                colour: colour,
                leading: Icon(
                  x.kind == TrashKind.phase
                      ? CupertinoIcons.square_stack_3d_up
                      : CupertinoIcons.circle,
                  size: 18,
                  color: p.inkSoft,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PressButton(
                      label: 'Bring back',
                      height: 34,
                      onTap: () => _run(
                        context,
                        () => backend.restoreTrash(classroomId, x),
                        '“${x.title}” is back.',
                      ),
                    ),
                    if (manages || x.deletedBy == plan.meId)
                      PressButton(
                        label: 'Forget it for good',
                        icon: CupertinoIcons.trash,
                        iconOnly: true,
                        quiet: true,
                        destructive: true,
                        height: 34,
                        onTap: () => _run(
                          context,
                          () => backend.purgeTrash(classroomId, x.id),
                          '“${x.title}” is gone for good.',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Steps, phases or chats, picked at the top.
class DeletedKindPicker extends StatelessWidget {
  const DeletedKindPicker({
    super.key,
    required this.kind,
    required this.onChanged,
  });

  final DeletedKind kind;
  final ValueChanged<DeletedKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (k, label) in const [
          (DeletedKind.steps, 'Deleted steps'),
          (DeletedKind.phases, 'Deleted phases'),
          (DeletedKind.chats, 'Deleted chats'),
        ])
          SelectChip(
            label: label,
            selected: k == kind,
            onTap: () => onChanged(k),
          ),
      ],
    );
  }
}

/// One classroom's Deleted, as a sheet.
class DeletedSheet extends StatefulWidget {
  const DeletedSheet({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.plan,
  });

  final Backend backend;
  final String classroomId;
  final Plan plan;

  @override
  State<DeletedSheet> createState() => _DeletedSheetState();
}

class _DeletedSheetState extends State<DeletedSheet> {
  var _kind = DeletedKind.steps;
  String? _notice;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Deleted',
      message: _notice,
      children: [
        Text(
          'Deleted steps and phases stay here for everyone, ready to bring '
          'back. Deleted chats are only gone from your own lists.',
          style: TypeRamp.caption(p.inkSoft),
        ),
        const SizedBox(height: 12),
        DeletedKindPicker(
          kind: _kind,
          onChanged: (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: 12),
        DeletedList(
          backend: widget.backend,
          classroomId: widget.classroomId,
          plan: widget.plan,
          kind: _kind,
          onNotice: (m) {
            if (mounted) setState(() => _notice = m);
          },
        ),
      ],
    );
  }
}

/// One classroom's finished work, as a sheet.
class DoneSheet extends StatelessWidget {
  const DoneSheet({super.key, required this.plan, this.onOpen});

  final Plan plan;
  final ValueChanged<PlanStep>? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final done = plan.steps.values.where((s) => s.status == StepStatus.done);
    return SheetFrame(
      title: 'Done',
      children: [
        Text(
          '${done.length} of ${plan.steps.length} steps finished.',
          style: TypeRamp.caption(p.inkSoft),
        ),
        const SizedBox(height: 12),
        DoneList(
          plan: plan,
          onOpen: onOpen == null
              ? null
              : (s) {
                  Navigator.of(context).pop();
                  onOpen!(s);
                },
        ),
      ],
    );
  }
}

// Roles ------------------------------------------------------------------------

/// Who does what in a group, and whether it learns together. The master
/// changes them; everyone else can look.
class RolesSheet extends StatefulWidget {
  const RolesSheet({
    super.key,
    required this.backend,
    required this.classroom,
    required this.plan,
  });

  final Backend backend;
  final Classroom classroom;
  final Plan plan;

  @override
  State<RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<RolesSheet> {
  late final Map<String, TextEditingController> _roles = {
    for (final m in widget.plan.members)
      m.id: TextEditingController(text: widget.classroom.roles[m.id] ?? ''),
  };
  late var _linked = widget.classroom.linked;
  String? _message;
  var _busy = false;

  bool get _master => widget.classroom.masterUid == widget.plan.meId;

  @override
  void dispose() {
    for (final c in _roles.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.backend.updateClassroom(
        widget.classroom.copyWith(
          linked: _linked,
          roles: {
            for (final e in _roles.entries)
              if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
          },
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _message = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Roles',
      message: _message,
      action: _master
          ? PressButton(
              label: 'Save roles',
              prominent: true,
              height: 46,
              expand: true,
              onTap: _busy ? null : _save,
            )
          : null,
      children: [
        Text(
          _master
              ? 'Say what each person does. Ofy gives steps to the person whose '
                    'role fits. You can also move anyone’s steps on the map.'
              : 'What each person does. The master sets these.',
          style: TypeRamp.caption(p.inkSoft),
        ),
        const SizedBox(height: 14),
        Text(
          'How the group works',
          style: TypeRamp.label(p.ink).weighted(FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SelectChip(
              label: 'Together: learn parts, teach each other',
              selected: _linked,
              onTap: _master ? () => setState(() => _linked = true) : () {},
            ),
            SelectChip(
              label: 'Separate roles',
              selected: !_linked,
              onTap: _master ? () => setState(() => _linked = false) : () {},
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (final m in widget.plan.members)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    m.id == widget.plan.meId ? '${m.name} (you)' : m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.label(p.ink),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _master
                      ? GlassField(
                          label: 'Role, such as Back end',
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
      ],
    );
  }
}

// Across classrooms --------------------------------------------------------------

/// Every classroom's plan, as this person sees it, with its colour.
List<(RoomSummary, Plan, Color)> roomPlans(Overview o, String me, Palette p) =>
    [
      for (final (i, r) in o.rooms.indexed)
        (r, planFrom(r.state, me, DateTime.now()), roomColour(p, i)),
    ];

/// Private chats and group chats, classroom by classroom.
class AllChats extends StatelessWidget {
  const AllChats({super.key, required this.backend, required this.overview});

  final Backend backend;
  final Overview overview;

  void _open(BuildContext context, String cid, Plan plan, List<String> others) {
    unawaited(() async {
      final String id;
      try {
        id = await backend.openThread(cid, others);
      } on BackendFailure {
        return;
      }
      if (!context.mounted) return;
      await showGlassSheet<void>(
        context,
        (_) => ThreadSheet(
          backend: backend,
          classroomId: cid,
          threadId: id,
          plan: plan,
          participants: [plan.meId, ...others],
        ),
      );
    }());
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = backend.currentUser?.uid ?? '';
    final rooms = [
      for (final r in roomPlans(overview, me, p))
        if (!r.$1.classroom.individual) r,
    ];
    if (rooms.isEmpty) {
      return _empty(
        p,
        'Chats live in group classrooms. Create one, or join with a code, to '
        'talk with people.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (room, plan, colour) in rooms)
          StreamBuilder<List<ChatThread>>(
            stream: backend.threads(room.classroom.id),
            builder: (context, snap) {
              final threads = [
                for (final t in snap.data ?? const <ChatThread>[])
                  if (!t.hiddenFor(me)) t,
              ];
              final people = [
                for (final t in threads)
                  if (t.participants.length == 2) t,
              ];
              final groups = [
                for (final t in threads)
                  if (t.participants.length > 2) t,
              ];
              final talkedTo = {for (final t in people) ...t.participants};
              final others = [
                for (final m in plan.members)
                  if (m.id != me && !talkedTo.contains(m.id)) m,
              ];
              Widget thread(ChatThread t) => ListRow(
                title: threadTitle(t, plan),
                detail: t.lastText.isEmpty
                    ? 'No messages yet'
                    : '${t.lastBy == me ? 'You: ' : ''}${t.lastText}',
                colour: colour,
                leading: Icon(
                  t.participants.length > 2
                      ? CupertinoIcons.person_3_fill
                      : CupertinoIcons.person_crop_circle_fill,
                  size: 22,
                  color: colour,
                ),
                trailing: t.unreadFor(me)
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE5262B),
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
                onTap: () => _open(context, room.classroom.id, plan, [
                  for (final u in t.participants)
                    if (u != me) u,
                ]),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RoomHeading(
                    title: room.classroom.title,
                    colour: colour,
                    detail:
                        '${threads.length} ${threads.length == 1 ? 'chat' : 'chats'}',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('People', style: TypeRamp.caption(p.inkSoft)),
                  ),
                  if (people.isEmpty && others.isEmpty)
                    _empty(p, 'Nobody else here yet.'),
                  for (final t in people) thread(t),
                  if (others.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in others)
                          PressButton(
                            label: 'Message ${m.name}',
                            icon: CupertinoIcons.chat_bubble,
                            height: 34,
                            onTap: () =>
                                _open(context, room.classroom.id, plan, [m.id]),
                          ),
                      ],
                    ),
                  if (groups.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text('Groups', style: TypeRamp.caption(p.inkSoft)),
                    ),
                    for (final t in groups) thread(t),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Finished work, classroom by classroom.
class AllDone extends StatelessWidget {
  const AllDone({
    super.key,
    required this.backend,
    required this.overview,
    this.onOpen,
    this.onlyMine = false,
  });

  final Backend backend;
  final Overview overview;
  final ValueChanged<String>? onOpen;
  final bool onlyMine;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = backend.currentUser?.uid ?? '';
    final rooms = roomPlans(overview, me, p);
    final any = rooms.any(
      (r) => r.$2.steps.values.any(
        (s) => s.status == StepStatus.done && (!onlyMine || s.ownerId == me),
      ),
    );
    if (!any) return _empty(p, 'Nothing finished yet. Done steps gather here.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (room, plan, colour) in rooms)
          if (plan.steps.values.any(
            (s) =>
                s.status == StepStatus.done && (!onlyMine || s.ownerId == me),
          )) ...[
            RoomHeading(
              title: room.classroom.title,
              colour: colour,
              detail:
                  '${plan.steps.values.where((s) => s.status == StepStatus.done && (!onlyMine || s.ownerId == me)).length} done',
            ),
            DoneList(
              plan: plan,
              colour: colour,
              onlyMine: onlyMine,
              onOpen: onOpen == null ? null : (_) => onOpen!(room.classroom.id),
            ),
          ],
      ],
    );
  }
}

/// Deleted work and chats, classroom by classroom.
class AllDeleted extends StatefulWidget {
  const AllDeleted({super.key, required this.backend, required this.overview});

  final Backend backend;
  final Overview overview;

  @override
  State<AllDeleted> createState() => _AllDeletedState();
}

class _AllDeletedState extends State<AllDeleted> {
  var _kind = DeletedKind.steps;
  String? _notice;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = widget.backend.currentUser?.uid ?? '';
    final rooms = [
      for (final r in roomPlans(widget.overview, me, p))
        if (_kind != DeletedKind.chats || !r.$1.classroom.individual) r,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeletedKindPicker(
          kind: _kind,
          onChanged: (k) => setState(() => _kind = k),
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_notice!, style: TypeRamp.label(p.ink)),
          ),
        const SizedBox(height: 4),
        for (final (room, plan, colour) in rooms) ...[
          RoomHeading(title: room.classroom.title, colour: colour),
          DeletedList(
            backend: widget.backend,
            classroomId: room.classroom.id,
            plan: plan,
            kind: _kind,
            colour: colour,
            onNotice: (m) {
              if (mounted) setState(() => _notice = m);
            },
          ),
        ],
        if (rooms.isEmpty) _empty(p, 'Nothing deleted.'),
      ],
    );
  }
}

// A person ---------------------------------------------------------------------

/// Someone in the classroom: chat with them, or see more about them.
class MemberSheet extends StatefulWidget {
  const MemberSheet({
    super.key,
    required this.backend,
    required this.classroom,
    required this.plan,
    required this.uid,
    required this.onChat,
  });

  final Backend backend;
  final Classroom classroom;
  final Plan plan;
  final String uid;
  final VoidCallback onChat;

  @override
  State<MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<MemberSheet> {
  var _more = false;
  late final Future<AppUser?> _profile = widget.backend.profileOf(widget.uid);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final plan = widget.plan;
    final me = widget.uid == plan.meId;
    final name = nameIn(plan, widget.uid);
    final role = widget.classroom.roles[widget.uid] ?? '';
    final standing = switch (widget.classroom.roleOf(widget.uid)) {
      MemberRole.master => 'Master',
      MemberRole.coMaster => 'Co-master',
      MemberRole.member => 'Member',
    };
    final mine = plan.steps.values.where((s) => s.ownerId == widget.uid);
    final done = mine.where((s) => s.status == StepStatus.done).length;
    final doing = mine.where((s) => s.status == StepStatus.doing).length;
    final next = plan.nextStepFor(widget.uid);
    return SheetFrame(
      title: me ? '$name (you)' : name,
      children: [
        Text(
          [standing, if (role.isNotEmpty) role].join(' · '),
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (!me) ...[
              Expanded(
                child: PressButton(
                  label: 'Chat',
                  icon: CupertinoIcons.chat_bubble_2,
                  prominent: true,
                  height: 46,
                  expand: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onChat();
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: PressButton(
                label: _more ? 'Less' : 'More info',
                icon: CupertinoIcons.person_crop_circle,
                selected: _more,
                height: 46,
                expand: true,
                onTap: () => setState(() => _more = !_more),
              ),
            ),
          ],
        ),
        if (_more) ...[
          const SizedBox(height: 18),
          FutureBuilder<AppUser?>(
            future: _profile,
            builder: (context, snap) {
              final bio = snap.data?.bio.trim() ?? '';
              final skills = snap.data?.skills ?? const <String>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snap.connectionState != ConnectionState.done
                        ? 'Loading…'
                        : bio.isEmpty
                        ? 'No bio yet.'
                        : bio,
                    style: TypeRamp.body(bio.isEmpty ? p.inkSoft : p.ink),
                  ),
                  if (skills.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Skills', style: TypeRamp.caption(p.inkSoft)),
                    const SizedBox(height: 2),
                    Text(skills.join(' · '), style: TypeRamp.label(p.ink)),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          ListRow(
            title: '$done of ${mine.length} steps done',
            detail: doing == 0 ? 'Nothing in progress' : '$doing in progress',
            leading: Icon(
              CupertinoIcons.checkmark_seal,
              size: 18,
              color: p.done,
            ),
          ),
          if (next != null)
            ListRow(
              title: 'Next: ${next.title}',
              detail: 'Due ${shortDate(next.due)}',
              leading: Icon(CupertinoIcons.scope, size: 18, color: p.route),
            ),
        ],
      ],
    );
  }
}

// In progress ------------------------------------------------------------------

/// A small tab under the phase names: how many steps are under way, with a
/// slow pulse. Tapping it drops down the list of them.
class InProgressTab extends StatefulWidget {
  const InProgressTab({super.key, required this.plan, required this.onOpen});

  final Plan plan;
  final ValueChanged<String> onOpen;

  @override
  State<InProgressTab> createState() => _InProgressTabState();
}

class _InProgressTabState extends State<InProgressTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  var _open = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0.5;
    } else if (!_pulse.isAnimating) {
      unawaited(_pulse.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _row(Palette p, PlanStep s) => Pressable(
    label: s.title,
    onTap: () {
      setState(() => _open = false);
      widget.onOpen(s.id);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TypeRamp.label(p.ink),
          ),
          Text(
            [
              nameIn(widget.plan, s.ownerId),
              s.status == StepStatus.review
                  ? 'waiting for approval'
                  : 'due ${shortDate(s.due)}',
            ].join(' · '),
            style: TypeRamp.caption(p.inkSoft),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final going =
        widget.plan.steps.values
            .where(
              (s) =>
                  s.status == StepStatus.doing || s.status == StepStatus.review,
            )
            .toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    final n = going.length;
    final label = n == 0 ? 'Nothing in progress' : '$n in progress';
    final list = n == 0
        ? Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Nobody has started a step yet. A step you start shows up here.',
              style: TypeRamp.caption(p.inkSoft),
            ),
          )
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [for (final s in going) _row(p, s)],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Pressable(
          label: '$label. ${_open ? 'Hide' : 'Show'} them.',
          onTap: () => setState(() => _open = !_open),
          child: GlassPanel(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: n == 0 ? p.inkFaint : p.doing,
                      shape: BoxShape.circle,
                      boxShadow: n == 0
                          ? null
                          : [
                              BoxShadow(
                                color: p.doing.withValues(
                                  alpha: 0.25 + 0.45 * _pulse.value,
                                ),
                                blurRadius: 4 + 8 * _pulse.value,
                                spreadRadius: 1 + 2 * _pulse.value,
                              ),
                            ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TypeRamp.caption(p.ink).weighted(FontWeight.w600),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 12,
                    color: p.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: !_open
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 300,
                      maxHeight: 320,
                    ),
                    child: GlassPanel(
                      radius: 16,
                      weight: GlassWeight.thick,
                      padding: const EdgeInsets.all(6),
                      child: list,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
