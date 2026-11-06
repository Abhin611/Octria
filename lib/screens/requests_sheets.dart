import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../kanvas/kanvas_home.dart';
import '../kanvas/kanvas_model.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart';
import 'step_collab.dart';

/// What the request sheets need to know about one classroom.
class RoomContext {
  const RoomContext({
    required this.id,
    required this.title,
    required this.names,
    required this.steps,
    required this.manages,
  });

  factory RoomContext.of(ClassroomState s, String me) => RoomContext(
    id: s.classroom.id,
    title: s.classroom.title,
    names: {for (final m in s.members) m.uid: m.name},
    steps: {for (final st in s.steps) st.id: st.title},
    manages: s.classroom.canManage(me),
  );

  final String id;
  final String title;
  final Map<String, String> names;
  final Map<String, String> steps;
  final bool manages;

  String name(String uid) => names[uid] ?? 'Someone who left';
  String step(String id) => steps[id] ?? 'a step';
}

/// A small coloured label for where a request has got to.
class StatusTag extends StatelessWidget {
  const StatusTag(this.text, {super.key, this.done = false, this.off = false});

  final String text;
  final bool done;
  final bool off;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final colour = done ? p.done : (off ? p.waiting : p.review);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TypeRamp.caption(p.ink).weighted(FontWeight.w700),
      ),
    );
  }
}

Widget _row(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? detail,
  Widget? trailing,
  VoidCallback? onTap,
}) {
  final p = Palette.of(context);
  final body = Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
    decoration: BoxDecoration(
      color: p.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: p.hairline),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: p.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TypeRamp.body(p.ink)),
              if (detail != null && detail.isNotEmpty)
                Text(detail, style: TypeRamp.caption(p.inkSoft)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );
  if (onTap == null) return body;
  return Semantics(
    button: true,
    label: '$title. ${detail ?? ''}',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: body,
    ),
  );
}

Future<void> _tell(
  Backend backend,
  String classroomId,
  String uid,
  ActivityKind kind,
  String summary, {
  String targetId = '',
}) async {
  final me = backend.currentUser?.uid ?? '';
  if (uid.isEmpty || uid == me) return;
  try {
    await backend.notify(
      uid,
      Notice(
        classroomId: classroomId,
        entry: ActivityEntry(
          id: '',
          actorUid: me,
          kind: kind,
          summary: summary,
          targetId: targetId,
          affectsUid: uid,
          createdAt: DateTime.now(),
        ),
      ),
    );
  } on Object {
    // A missed note isn't worth stopping for.
  }
}

// Shared boards ---------------------------------------------------------------

/// Boards shared in a classroom: those for the whole class, which everyone
/// sees, and those shared with chosen people, which only those people see.
class SharedBoardsSheet extends StatelessWidget {
  const SharedBoardsSheet({
    super.key,
    required this.backend,
    required this.room,
  });

  final Backend backend;
  final RoomContext room;

  String get _me => backend.currentUser?.uid ?? '';

  Future<void> _share(BuildContext context) async {
    final choice = await showGlassSheet<_ShareChoice>(
      context,
      (_) => _ShareBoardPicker(backend: backend, room: room),
    );
    if (choice == null) return;
    final b = choice.board;
    final myName = room.name(_me);
    try {
      if (choice.everyone) {
        await backend.shareBoard(
          b.id,
          people: b.people,
          classroomId: room.id,
          classroomMode: choice.edit ? ShareMode.edit : ShareMode.view,
        );
      } else {
        for (final uid in choice.people) {
          await backend.makeOffer(
            room.id,
            Offer(
              id: backend.newId(),
              kind: OfferKind.board,
              fromUid: _me,
              toUid: uid,
              createdAt: DateTime.now(),
              title: b.title,
              boardOwner: _me,
              boardId: b.id,
              edit: choice.edit,
            ),
          );
          await _tell(
            backend,
            room.id,
            uid,
            ActivityKind.stepHandedOver,
            '$myName shared the board “${b.title}” with you. Accept it in '
            'Important.',
          );
        }
      }
    } on BackendFailure catch (e) {
      if (context.mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (c) => CupertinoAlertDialog(
            content: Text(e.message),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<ClassroomBoard>>(
      stream: backend.classroomBoards(room.id),
      builder: (context, boards) => StreamBuilder<List<Offer>>(
        stream: backend.offers(room.id),
        builder: (context, offers) {
          final forClass = boards.data ?? const <ClassroomBoard>[];
          final withPeople = (offers.data ?? const <Offer>[])
              .where((o) => o.kind == OfferKind.board)
              .toList();
          return SheetFrame(
            title: 'Shared boards',
            action: PressButton(
              label: 'Share a board',
              icon: CupertinoIcons.plus,
              prominent: true,
              height: 48,
              expand: true,
              onTap: () => _share(context),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'With the whole class',
                  style: TypeRamp.label(p.inkSoft),
                ),
              ),
              if (boards.hasData && forClass.isEmpty)
                Text(
                  'None yet. Everyone here sees boards shared with the class.',
                  style: TypeRamp.caption(p.inkSoft),
                ),
              for (final b in forClass)
                _row(
                  context,
                  icon: CupertinoIcons.person_3,
                  title: b.title,
                  detail:
                      'From ${room.name(b.ownerUid)}'
                      '${b.stepId.isEmpty ? '' : ' · on “${room.step(b.stepId)}”'}',
                  trailing: const StatusTag('Visible to all', done: true),
                  onTap: () => openBoard(
                    context,
                    backend: backend,
                    ownerUid: b.ownerUid,
                    boardId: b.boardId,
                    inClassroom: true,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.lock, size: 13, color: p.inkFaint),
                    const SizedBox(width: 5),
                    Text(
                      'With chosen people · only they see these',
                      style: TypeRamp.label(p.inkSoft),
                    ),
                  ],
                ),
              ),
              if (offers.hasData && withPeople.isEmpty)
                Text(
                  'Nothing shared with you or by you yet.',
                  style: TypeRamp.caption(p.inkSoft),
                ),
              for (final o in withPeople)
                _row(
                  context,
                  icon: CupertinoIcons.paintbrush,
                  title: o.title,
                  detail:
                      '${o.fromUid == _me ? 'You' : room.name(o.fromUid)} to '
                      '${o.toUid == _me ? 'you' : room.name(o.toUid)} · '
                      '${o.edit ? 'can edit' : 'can look'}',
                  trailing: StatusTag(
                    o.statusLabel,
                    done: o.status == OfferStatus.accepted,
                    off: o.status == OfferStatus.declined,
                  ),
                  onTap: o.status == OfferStatus.declined
                      ? null
                      : () => openBoard(
                          context,
                          backend: backend,
                          ownerUid: o.boardOwner,
                          boardId: o.boardId,
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ShareChoice {
  const _ShareChoice(this.board, this.everyone, this.people, this.edit);

  final KanvasBoard board;
  final bool everyone;
  final List<String> people;
  final bool edit;
}

class _ShareBoardPicker extends StatefulWidget {
  const _ShareBoardPicker({required this.backend, required this.room});

  final Backend backend;
  final RoomContext room;

  @override
  State<_ShareBoardPicker> createState() => _ShareBoardPickerState();
}

class _ShareBoardPickerState extends State<_ShareBoardPicker> {
  late final Stream<List<KanvasBoard>> _boards = widget.backend.myBoards();
  KanvasBoard? _board;
  var _everyone = false;
  final _people = <String>{};
  var _edit = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = widget.backend.currentUser?.uid ?? '';
    final others = widget.room.names.entries.where((e) => e.key != me).toList();
    return StreamBuilder<List<KanvasBoard>>(
      stream: _boards,
      builder: (context, snap) {
        final boards = snap.data ?? const <KanvasBoard>[];
        return SheetFrame(
          title: 'Share a board',
          message: _message,
          action: PressButton(
            label: 'Share',
            prominent: true,
            height: 48,
            expand: true,
            onTap: () {
              final b = _board;
              if (b == null) {
                setState(() => _message = 'Pick one of your boards.');
                return;
              }
              if (!_everyone && _people.isEmpty) {
                setState(() => _message = 'Pick who to share it with.');
                return;
              }
              Navigator.of(context)
                  .pop(_ShareChoice(b, _everyone, _people.toList(), _edit));
            },
          ),
          children: [
            Text('Which board', style: TypeRamp.label(p.inkSoft)),
            const SizedBox(height: 7),
            if (snap.hasData && boards.isEmpty)
              Text(
                'You have no boards yet. Make one in the Kanvas tab.',
                style: TypeRamp.caption(p.inkSoft),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in boards)
                  SelectChip(
                    label: b.title,
                    selected: _board?.id == b.id,
                    onTap: () => setState(() => _board = b),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 7),
              child: Text('Visible to', style: TypeRamp.label(p.inkSoft)),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                SelectChip(
                  label: 'Specific people',
                  selected: !_everyone,
                  onTap: () => setState(() => _everyone = false),
                ),
                SelectChip(
                  label: 'Everyone in the class',
                  selected: _everyone,
                  onTap: () => setState(() => _everyone = true),
                ),
              ],
            ),
            if (!_everyone) ...[
              const SizedBox(height: 8),
              for (final e in others)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    if (!_people.remove(e.key)) _people.add(e.key);
                  }),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 42),
                    child: Row(
                      children: [
                        Icon(
                          _people.contains(e.key)
                              ? CupertinoIcons.checkmark_square_fill
                              : CupertinoIcons.square,
                          size: 20,
                          color: _people.contains(e.key) ? p.accent : p.inkSoft,
                        ),
                        const SizedBox(width: 10),
                        Text(e.value, style: TypeRamp.body(p.ink)),
                      ],
                    ),
                  ),
                ),
              Text(
                'Each person accepts it in their Important notes. Only they '
                'and you see it listed.',
                style: TypeRamp.caption(p.inkSoft),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Everyone in the class sees it straight away. A board can '
                  'be shared with one class at a time.',
                  style: TypeRamp.caption(p.inkSoft),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 7),
              child: Text('They can', style: TypeRamp.label(p.inkSoft)),
            ),
            Wrap(
              spacing: 6,
              children: [
                SelectChip(
                  label: 'Look',
                  selected: !_edit,
                  onTap: () => setState(() => _edit = false),
                ),
                SelectChip(
                  label: 'Edit',
                  selected: _edit,
                  onTap: () => setState(() => _edit = true),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// Handovers -----------------------------------------------------------------

/// Every handover in the classroom, for everyone to see. Only the people in
/// one, and the master, can open it.
class HandoversSheet extends StatelessWidget {
  const HandoversSheet({
    super.key,
    required this.backend,
    required this.room,
    required this.onOpenStep,
    required this.onNew,
  });

  final Backend backend;
  final RoomContext room;
  final ValueChanged<String> onOpenStep;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = backend.currentUser?.uid ?? '';
    return StreamBuilder<List<Handover>>(
      stream: backend.handovers(room.id),
      builder: (context, snap) {
        final list = snap.data ?? const <Handover>[];
        return SheetFrame(
          title: 'Handovers',
          action: PressButton(
            label: 'Hand over one of your steps',
            icon: CupertinoIcons.plus,
            prominent: true,
            height: 48,
            expand: true,
            onTap: () {
              Navigator.of(context).pop();
              onNew();
            },
          ),
          children: [
            Text(
              'Everyone in the class sees who is handing what to whom. Only '
              'the people in a handover, and the master, can open it.',
              style: TypeRamp.caption(p.inkSoft),
            ),
            const SizedBox(height: 10),
            if (snap.hasData && list.isEmpty)
              Text('No handovers yet.', style: TypeRamp.label(p.inkSoft)),
            for (final h in list)
              _row(
                context,
                icon: CupertinoIcons.arrow_right_arrow_left,
                title: '“${room.step(h.stepId)}”',
                detail:
                    '${h.fromUid == me ? 'You' : room.name(h.fromUid)} to '
                    '${h.toUid == me ? 'you' : room.name(h.toUid)}',
                trailing: StatusTag(
                  handoverLabel(h.status),
                  done: h.status == HandoverStatus.accepted,
                  off: h.status == HandoverStatus.declined,
                ),
                onTap: h.fromUid == me || h.toUid == me || room.manages
                    ? () {
                        Navigator.of(context).pop();
                        onOpenStep(h.stepId);
                      }
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// Picks one of this person's steps, who to give it to, and why.
class NewHandoverSheet extends StatefulWidget {
  const NewHandoverSheet({
    super.key,
    required this.plan,
    required this.viaMaster,
  });

  final Plan plan;
  final bool viaMaster;

  @override
  State<NewHandoverSheet> createState() => _NewHandoverSheetState();
}

class _NewHandoverSheetState extends State<NewHandoverSheet> {
  String? _step;
  String? _to;
  final _note = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = widget.plan.meId;
    final mine = widget.plan.steps.values
        .where((s) => s.ownerId == me && s.status != StepStatus.done)
        .toList();
    final others = widget.plan.members.where((m) => m.id != me).toList();
    return SheetFrame(
      title: 'New handover',
      message: _message,
      action: PressButton(
        label: 'Proceed with handover',
        prominent: true,
        height: 48,
        expand: true,
        onTap: () {
          if (_step == null || _to == null) {
            setState(() => _message = 'Pick a step and who it goes to.');
            return;
          }
          Navigator.of(context).pop((_step!, _to!, _note.text.trim()));
        },
      ),
      children: [
        Text('Your step', style: TypeRamp.label(p.inkSoft)),
        const SizedBox(height: 7),
        if (mine.isEmpty)
          Text(
            'You have no unfinished steps to hand over.',
            style: TypeRamp.caption(p.inkSoft),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in mine)
              SelectChip(
                label: s.title,
                selected: _step == s.id,
                onTap: () => setState(() => _step = s.id),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 7),
          child: Text('Hand it to', style: TypeRamp.label(p.inkSoft)),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in others)
              SelectChip(
                label: m.name,
                selected: _to == m.id,
                onTap: () => setState(() => _to = m.id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GlassField(
          label: 'Why, or what they should know (optional)',
          controller: _note,
          maxLines: 3,
        ),
        const SizedBox(height: 6),
        Text(
          widget.viaMaster
              ? 'The master sees it first, then the person decides. It shows '
                    'as Request pending, then Acceptance pending. Only they see '
                    'your note.'
              : 'The person decides. It shows as Acceptance pending until '
                    'then. Only they see your note.',
          style: TypeRamp.caption(p.inkSoft),
        ),
      ],
    );
  }
}

// Important notes --------------------------------------------------------------

/// One thing waiting on this person.
class _Item {
  const _Item(this.room, this.icon, this.title, this.detail, this.actions);

  final RoomContext room;
  final IconData icon;
  final String title;
  final String detail;

  /// Labels and what they do; the first is the main one.
  final List<(String, Future<void> Function())> actions;
}

/// Counts what's waiting on this person across these classrooms.
Future<int> importantCount(Backend backend, List<RoomContext> rooms) async =>
    (await _gather(backend, rooms, null)).length;

Future<List<_Item>> _gather(
  Backend backend,
  List<RoomContext> rooms,
  BuildContext? context,
) async {
  final me = backend.currentUser?.uid ?? '';
  final myName = rooms.isEmpty ? '' : rooms.first.name(me);
  final items = <_Item>[];
  for (final r in rooms) {
    List<Handover> handovers = const [];
    List<Offer> offers = const [];
    List<Suggestion> suggestions = const [];
    try {
      handovers = await backend.handovers(r.id).first;
      offers = await backend.offers(r.id).first;
      suggestions = await backend.suggestions(r.id).first;
    } on Object {
      continue;
    }
    for (final h in handovers) {
      final step = r.step(h.stepId);
      if (h.status == HandoverStatus.needsMaster && r.manages) {
        items.add(
          _Item(
            r,
            CupertinoIcons.arrow_right_arrow_left,
            '${r.name(h.fromUid)} asks to hand “$step” to ${r.name(h.toUid)}',
            'Handover · needs you as master',
            [
              (
                'Agree',
                () async {
                  await backend.reviewHandover(r.id, h.stepId, true);
                  await _tell(
                    backend,
                    r.id,
                    h.toUid,
                    ActivityKind.stepHandedOver,
                    '${r.name(h.fromUid)} wants to hand you “$step”. Accept '
                    'it in Important.',
                    targetId: h.stepId,
                  );
                  await _tell(
                    backend,
                    r.id,
                    h.fromUid,
                    ActivityKind.stepHandedOver,
                    '$myName agreed to hand “$step” to ${r.name(h.toUid)}.',
                    targetId: h.stepId,
                  );
                },
              ),
              (
                'Say no',
                () async {
                  await backend.reviewHandover(r.id, h.stepId, false);
                  await _tell(
                    backend,
                    r.id,
                    h.fromUid,
                    ActivityKind.stepHandedOver,
                    '$myName said no to handing “$step” to ${r.name(h.toUid)}.',
                    targetId: h.stepId,
                  );
                },
              ),
            ],
          ),
        );
      }
      if (h.status == HandoverStatus.needsReceiver && h.toUid == me) {
        items.add(
          _Item(
            r,
            CupertinoIcons.arrow_right_arrow_left,
            '${r.name(h.fromUid)} wants to hand you “$step”',
            'Handover · the step becomes yours if you accept',
            [
              (
                'Accept',
                () async {
                  await backend.answerHandover(r.id, h.stepId, true);
                  await _tell(
                    backend,
                    r.id,
                    h.fromUid,
                    ActivityKind.stepHandedOver,
                    '$myName took on “$step” from you.',
                    targetId: h.stepId,
                  );
                },
              ),
              (
                'Decline',
                () async {
                  await backend.answerHandover(r.id, h.stepId, false);
                  await _tell(
                    backend,
                    r.id,
                    h.fromUid,
                    ActivityKind.stepHandedOver,
                    '$myName declined to take on “$step”.',
                    targetId: h.stepId,
                  );
                },
              ),
            ],
          ),
        );
      }
    }
    for (final o in offers) {
      if (o.toUid != me || o.status != OfferStatus.pending) continue;
      final board = o.kind == OfferKind.board;
      items.add(
        _Item(
          r,
          board ? CupertinoIcons.paintbrush : CupertinoIcons.paperclip,
          board
              ? '${r.name(o.fromUid)} shared the board “${o.title}” with you'
              : '${r.name(o.fromUid)} sent “${o.title}” for your step '
                    '“${r.step(o.stepId)}”',
          board
              ? 'Board · ${o.edit ? 'you can edit it' : 'you can look'}'
              : '${o.materialKind.label}'
                    '${o.url.isEmpty ? '' : ' · ${Uri.tryParse(o.url)?.host ?? ''}'}'
                    ' · joins your study materials if you accept',
          [
            (
              'Accept',
              () async {
                await backend.answerOffer(r.id, o, true);
                await _tell(
                  backend,
                  r.id,
                  o.fromUid,
                  ActivityKind.materialAdded,
                  '$myName accepted “${o.title}”.',
                  targetId: o.stepId,
                );
              },
            ),
            (
              'Decline',
              () async {
                await backend.answerOffer(r.id, o, false);
                await _tell(
                  backend,
                  r.id,
                  o.fromUid,
                  ActivityKind.materialAdded,
                  '$myName declined “${o.title}”.',
                  targetId: o.stepId,
                );
              },
            ),
            if (board && context != null)
              (
                'Look first',
                () => openBoard(
                  context,
                  backend: backend,
                  ownerUid: o.boardOwner,
                  boardId: o.boardId,
                ),
              ),
          ],
        ),
      );
    }
    for (final s in suggestions) {
      if (s.toUid != me || s.status != SuggestionStatus.open) continue;
      final step = r.step(s.stepId);
      Future<void> answer(SuggestionStatus to) async {
        await backend.answerSuggestion(r.id, s.id, to);
        await _tell(
          backend,
          r.id,
          s.fromUid,
          ActivityKind.suggestionAnswered,
          '$myName ${to == SuggestionStatus.accepted ? 'accepted' : 'dismissed'}'
          ' your suggestion on “$step”.',
          targetId: s.stepId,
        );
      }

      items.add(
        _Item(
          r,
          CupertinoIcons.lightbulb,
          '${r.name(s.fromUid)} suggests on “$step”: ${clipLine(s.text, 70)}',
          'Suggestion · ${s.public ? 'everyone can see it' : 'private'}',
          [
            ('Accept', () => answer(SuggestionStatus.accepted)),
            ('Dismiss', () => answer(SuggestionStatus.dismissed)),
          ],
        ),
      );
    }
  }
  return items;
}

/// Requests waiting on this person to accept or decline: handovers, boards,
/// study materials and suggestions. Private to them.
class ImportantSheet extends StatefulWidget {
  const ImportantSheet({super.key, required this.backend, required this.rooms});

  final Backend backend;
  final List<RoomContext> rooms;

  @override
  State<ImportantSheet> createState() => _ImportantSheetState();
}

class _ImportantSheetState extends State<ImportantSheet> {
  late Future<List<_Item>> _items = _gather(
    widget.backend,
    widget.rooms,
    context,
  );
  String? _message;
  var _busy = false;

  Future<void> _do(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on BackendFailure catch (e) {
      _message = e.message;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _items = _gather(widget.backend, widget.rooms, context);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final many = widget.rooms.length > 1;
    return FutureBuilder<List<_Item>>(
      future: _items,
      builder: (context, snap) {
        final items = snap.data ?? const <_Item>[];
        return SheetFrame(
          title: 'Important',
          message: _message,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.lock, size: 13, color: p.inkFaint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Things waiting for you to accept. Only you can see these.',
                    style: TypeRamp.caption(p.inkSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!snap.hasData)
              const CupertinoActivityIndicator()
            else if (items.isEmpty)
              Text(
                'Nothing waiting. Handovers, boards and materials sent to you, '
                'and suggestions on your steps, appear here.',
                style: TypeRamp.label(p.inkSoft),
              ),
            for (final item in items)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  color: p.accentWarm.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: p.accentWarm.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.icon, size: 17, color: p.accentWarm),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(item.title, style: TypeRamp.body(p.ink)),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 25, top: 2),
                      child: Text(
                        many
                            ? '${item.detail} · ${item.room.title}'
                            : item.detail,
                        style: TypeRamp.caption(p.inkSoft),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 25, top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final (i, (label, run)) in item.actions.indexed)
                            PressButton(
                              label: label,
                              icon: i == 0
                                  ? CupertinoIcons.checkmark_alt
                                  : null,
                              quiet: i != 0,
                              height: 36,
                              onTap: _busy ? null : () => _do(run),
                            ),
                        ],
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

// From a step's + ----------------------------------------------------------

/// Sends a study material to a step's owner, to accept into their materials.
Future<void> offerMaterial(
  BuildContext context, {
  required Backend backend,
  required RoomContext room,
  required PlanStep step,
}) async {
  final me = backend.currentUser?.uid ?? '';
  final made = await showGlassSheet<StudyMaterial>(
    context,
    (_) => MaterialEditorSheet(
      newId: backend.newId,
      ownerUid: me,
      stepId: step.id,
    ),
  );
  if (made == null) return;
  await backend.makeOffer(
    room.id,
    Offer(
      id: backend.newId(),
      kind: OfferKind.material,
      fromUid: me,
      toUid: step.ownerId,
      createdAt: DateTime.now(),
      stepId: step.id,
      title: made.title,
      materialKind: made.kind,
      url: made.url,
      note: made.note,
    ),
  );
  await _tell(
    backend,
    room.id,
    step.ownerId,
    ActivityKind.materialAdded,
    '${room.name(me)} sent “${made.title}” for your step “${step.title}”. '
    'Accept it in Important.',
    targetId: step.id,
  );
}

/// Shares one of this person's boards with a step's owner, to accept.
Future<void> offerBoard(
  BuildContext context, {
  required Backend backend,
  required RoomContext room,
  required PlanStep step,
}) async {
  final me = backend.currentUser?.uid ?? '';
  final boards = await backend.myBoards().first;
  if (!context.mounted) return;
  if (boards.isEmpty) {
    await showCupertinoDialog<void>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        content: const Text('Make a board in the Kanvas tab first.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  KanvasBoard? picked;
  await showGlassSheet<void>(
    context,
    (_) => ActionListSheet(
      title: 'Share a board with ${room.name(step.ownerId)}',
      items: [for (final b in boards) (b.title, 0, () => picked = b)],
    ),
  );
  final b = picked;
  if (b == null) return;
  await backend.makeOffer(
    room.id,
    Offer(
      id: backend.newId(),
      kind: OfferKind.board,
      fromUid: me,
      toUid: step.ownerId,
      createdAt: DateTime.now(),
      stepId: step.id,
      title: b.title,
      boardOwner: me,
      boardId: b.id,
    ),
  );
  await _tell(
    backend,
    room.id,
    step.ownerId,
    ActivityKind.stepHandedOver,
    '${room.name(me)} shared the board “${b.title}” with you for '
    '“${step.title}”. Accept it in Important.',
    targetId: step.id,
  );
}
