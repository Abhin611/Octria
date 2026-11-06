import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../kanvas/kanvas_home.dart';
import '../kanvas/kanvas_model.dart';
import 'classroom_forms.dart';
import 'files_sheet.dart';

/// A person's name in this plan, or a plain stand-in once they've left.
String nameIn(Plan plan, String uid) =>
    plan.members.where((m) => m.id == uid).firstOrNull?.name ??
    'Someone who left';

/// When a comment or suggestion was made: the time today, or the date.
String whenShort(DateTime d, DateTime now) {
  final today = d.year == now.year && d.month == now.month && d.day == now.day;
  if (!today) return shortDate(d);
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$hour:${d.minute.toString().padLeft(2, '0')} '
      '${d.hour < 12 ? 'am' : 'pm'}';
}

/// Opens a stored web link in the browser or the right app. Only http and
/// https ever reach here; anything else is refused before it's saved.
Future<bool> openLink(String url) async {
  final safe = webAddress(url);
  if (safe == null) return false;
  return launchUrl(
    Uri.parse(safe),
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
}

IconData materialIcon(MaterialKind kind) => switch (kind) {
  MaterialKind.link => CupertinoIcons.link,
  MaterialKind.video => CupertinoIcons.play_rectangle,
  MaterialKind.note => CupertinoIcons.square_pencil,
  MaterialKind.repo => CupertinoIcons.chevron_left_slash_chevron_right,
  MaterialKind.practice => CupertinoIcons.flag,
};

/// Writes a suggestion for someone's step and sends it to them, from anywhere.
Future<void> suggestChange(
  BuildContext context, {
  required Backend backend,
  required String classroomId,
  required Plan plan,
  required PlanStep step,
  required ValueChanged<String> onNotice,
}) async {
  final made = await showGlassSheet<(String, bool)>(
    context,
    (_) => _SuggestSheet(owner: nameIn(plan, step.ownerId)),
  );
  if (made == null || made.$1.trim().isEmpty) return;
  final me = plan.meId;
  try {
    await backend.addSuggestion(
      classroomId,
      Suggestion(
        id: backend.newId(),
        stepId: step.id,
        fromUid: me,
        toUid: step.ownerId,
        text: made.$1,
        public: made.$2,
        createdAt: DateTime.now(),
      ),
    );
    await backend.notify(
      step.ownerId,
      Notice(
        classroomId: classroomId,
        entry: ActivityEntry(
          id: '',
          actorUid: me,
          kind: ActivityKind.suggested,
          summary:
              '${nameIn(plan, me)} suggested a change to your step '
              '“${step.title}”: ${clipLine(made.$1)}',
          targetId: step.id,
          affectsUid: step.ownerId,
          createdAt: DateTime.now(),
        ),
      ),
    );
    onNotice('Suggestion sent to ${nameIn(plan, step.ownerId)}');
  } on BackendFailure catch (e) {
    onNotice(e.message);
  }
}

/// Clips text to one short line, for a notification.
String clipLine(String text, [int max = 80]) {
  final line = text.replaceAll('\n', ' ');
  return line.length <= max ? line : '${line.substring(0, max - 1)}…';
}

/// Study materials, suggestions and private comments for one step, all live.
class StepCollab extends StatefulWidget {
  const StepCollab({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.plan,
    required this.step,
    required this.canManage,
    required this.onNotice,
    this.masterUid = '',
    this.classroomTitle = '',
  });

  /// Who to ask when a member wants to hand a step over.
  final String masterUid;

  /// Names the classroom's folder in the person's Drive.
  final String classroomTitle;

  final Backend backend;
  final String classroomId;
  final Plan plan;
  final PlanStep step;

  /// The master or a co-master, who can remove any study material.
  final bool canManage;
  final ValueChanged<String> onNotice;

  @override
  State<StepCollab> createState() => _StepCollabState();
}

class _StepCollabState extends State<StepCollab> {
  late final Stream<List<StudyMaterial>> _materials = widget.backend.materials(
    widget.classroomId,
  );
  late final Stream<List<Suggestion>> _suggestions = widget.backend.suggestions(
    widget.classroomId,
  );
  late final Stream<List<Handover>> _handovers = widget.backend.handovers(
    widget.classroomId,
  );
  late final Stream<List<ClassroomBoard>> _boards = widget.backend
      .classroomBoards(widget.classroomId);
  late final Stream<List<StepComment>> _comments = widget.backend.comments(
    widget.classroomId,
    widget.step.id,
  );
  final _comment = TextEditingController();
  final _openNotes = <String>{};
  var _sending = false;

  /// For the owner: whose private thread is open.
  String? _thread;

  String get _me => widget.plan.meId;
  PlanStep get _step => widget.step;
  bool get _mine => _step.ownerId == _me;
  String get _myName => nameIn(widget.plan, _me);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// A note only [uid] can read, in their own inbox.
  void _tell(String uid, ActivityKind kind, String summary) {
    if (uid == _me) return;
    unawaited(
      widget.backend
          .notify(
            uid,
            Notice(
              classroomId: widget.classroomId,
              entry: ActivityEntry(
                id: '',
                actorUid: _me,
                kind: kind,
                summary: summary,
                targetId: _step.id,
                affectsUid: uid,
                createdAt: DateTime.now(),
              ),
            ),
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on BackendFailure catch (e) {
      widget.onNotice(e.message);
    }
  }

  Future<void> _review(Handover h, bool approve) => _run(() async {
    await widget.backend.reviewHandover(widget.classroomId, h.stepId, approve);
    final to = nameIn(widget.plan, h.toUid);
    if (approve) {
      _tell(
        h.toUid,
        ActivityKind.stepHandedOver,
        '${nameIn(widget.plan, h.fromUid)} wants to hand you '
        '“${_step.title}”. Accept or decline it on the step.',
      );
    }
    _tell(
      h.fromUid,
      ActivityKind.stepHandedOver,
      approve
          ? '$_myName agreed to hand “${_step.title}” to $to. Now $to decides.'
          : '$_myName said no to handing “${_step.title}” to $to.',
    );
  });

  Future<void> _answerHandover(Handover h, bool accept) => _run(() async {
    await widget.backend.answerHandover(widget.classroomId, h.stepId, accept);
    _tell(
      h.fromUid,
      ActivityKind.stepHandedOver,
      accept
          ? '$_myName took on “${_step.title}” from you.'
          : '$_myName declined to take on “${_step.title}”.',
    );
    if (widget.masterUid.isNotEmpty && widget.masterUid != h.fromUid) {
      _tell(
        widget.masterUid,
        ActivityKind.stepHandedOver,
        accept
            ? '$_myName took on “${_step.title}” from '
                  '${nameIn(widget.plan, h.fromUid)}.'
            : '$_myName declined “${_step.title}” from '
                  '${nameIn(widget.plan, h.fromUid)}.',
      );
    }
  });

  Future<void> _pinBoard() async {
    final boards = await widget.backend.myBoards().first;
    if (!mounted) return;
    if (boards.isEmpty) {
      widget.onNotice('Make a board in Kanvas first, then pin it here.');
      return;
    }
    await showGlassSheet<void>(
      context,
      (_) => ActionListSheet(
        title: 'Pin a board',
        items: [
          for (final b in boards)
            (
              b.title,
              0,
              () => _run(
                () =>
                    widget.backend.pinBoard(widget.classroomId, b.id, _step.id),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addMaterial() async {
    final made = await showGlassSheet<StudyMaterial>(
      context,
      (_) => MaterialEditorSheet(
        newId: widget.backend.newId,
        stepId: _step.id,
        ownerUid: _me,
      ),
    );
    if (made == null || !mounted) return;
    await _run(() async {
      await widget.backend.saveMaterial(widget.classroomId, made);
      if (!_mine && made.kind == MaterialKind.practice) {
        unawaited(
          widget.backend
              .logActivity(
                widget.classroomId,
                ActivityEntry(
                  id: widget.backend.newId(),
                  actorUid: _me,
                  kind: ActivityKind.materialAdded,
                  summary: '$_myName added “${made.title}” to “${_step.title}”',
                  targetId: _step.id,
                  affectsUid: _step.ownerId,
                  createdAt: DateTime.now(),
                ),
              )
              .catchError((Object _) {}),
        );
      }
    });
  }

  Future<void> _removeMaterial(StudyMaterial m) async {
    final sure = await _askToRemove(
      'Remove “${m.title}”?',
      'It goes for everyone in the classroom.',
    );
    if (!sure) return;
    await _run(() => widget.backend.deleteMaterial(widget.classroomId, m.id));
  }

  Future<bool> _askToRemove(String title, String body) async =>
      await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _open(StudyMaterial m) async {
    if (m.kind == MaterialKind.note) {
      setState(() {
        if (!_openNotes.remove(m.id)) _openNotes.add(m.id);
      });
      return;
    }
    final opened = await openLink(m.url);
    if (!opened) widget.onNotice('That link couldn’t be opened.');
  }

  Future<void> _sendComment(String withUid) async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.backend.addComment(
        widget.classroomId,
        _step.id,
        text,
        ownerUid: _step.ownerId,
        withUid: withUid,
      );
      _comment.clear();
      final to = _mine ? withUid : _step.ownerId;
      _tell(
        to,
        ActivityKind.commented,
        _mine
            ? '$_myName replied on “${_step.title}”: ${clipLine(text)}'
            : '$_myName commented on your step “${_step.title}”: '
                  '${clipLine(text)}',
      );
    } on BackendFailure catch (e) {
      widget.onNotice(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _suggest() async {
    final made = await showGlassSheet<(String, bool)>(
      context,
      (_) => _SuggestSheet(owner: nameIn(widget.plan, _step.ownerId)),
    );
    if (made == null || made.$1.trim().isEmpty || !mounted) return;
    final (text, public) = made;
    await _run(() async {
      await widget.backend.addSuggestion(
        widget.classroomId,
        Suggestion(
          id: widget.backend.newId(),
          stepId: _step.id,
          fromUid: _me,
          toUid: _step.ownerId,
          text: text,
          public: public,
          createdAt: DateTime.now(),
        ),
      );
      _tell(
        _step.ownerId,
        ActivityKind.suggested,
        '$_myName suggested a change to your step “${_step.title}”: '
        '${clipLine(text)}',
      );
    });
  }

  Future<void> _answer(Suggestion s, SuggestionStatus to) async {
    await _run(() async {
      await widget.backend.answerSuggestion(widget.classroomId, s.id, to);
      final word = to == SuggestionStatus.accepted ? 'accepted' : 'dismissed';
      _tell(
        s.fromUid,
        ActivityKind.suggestionAnswered,
        '$_myName $word your suggestion on “${_step.title}”: '
        '${clipLine(s.text, 60)}',
      );
    });
  }

  Future<void> _share(Suggestion s, bool public) async {
    await _run(() async {
      await widget.backend.setSuggestionPublic(
        widget.classroomId,
        s.id,
        public,
      );
      final other = s.fromUid == _me ? s.toUid : s.fromUid;
      _tell(
        other,
        ActivityKind.suggested,
        public
            ? '$_myName showed your suggestion on “${_step.title}” to everyone'
            : '$_myName made the suggestion on “${_step.title}” private again',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = DateTime.now();

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: TypeRamp.label(p.inkSoft)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamBuilder<List<Handover>>(
          stream: _handovers,
          builder: (context, snap) {
            final h = (snap.data ?? const <Handover>[])
                .where((h) => h.stepId == _step.id)
                .firstOrNull;
            // Everyone sees handovers listed; only the people in one, and
            // the managers, see its card on the step.
            if (h == null ||
                !(h.fromUid == _me || h.toUid == _me || widget.canManage)) {
              return const SizedBox.shrink();
            }
            return _HandoverCard(
              handover: h,
              plan: widget.plan,
              me: _me,
              manages: widget.canManage,
              onReview: (ok) => _review(h, ok),
              onAnswer: (ok) => _answerHandover(h, ok),
              onCancel: () => _run(
                () =>
                    widget.backend.cancelHandover(widget.classroomId, h.stepId),
              ),
            );
          },
        ),
        StreamBuilder<List<ClassroomBoard>>(
          stream: _boards,
          builder: (context, snap) {
            final pinned = (snap.data ?? const <ClassroomBoard>[])
                .where((b) => b.stepId == _step.id)
                .toList();
            if (pinned.isEmpty && !_mine) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label('Kanvas boards'),
                for (final b in pinned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: PressButton(
                            label:
                                '${b.title} · '
                                '${nameIn(widget.plan, b.ownerUid)}',
                            icon: CupertinoIcons.paintbrush,
                            height: 40,
                            onTap: () => openBoard(
                              context,
                              backend: widget.backend,
                              ownerUid: b.ownerUid,
                              boardId: b.boardId,
                              inClassroom: true,
                            ),
                          ),
                        ),
                        if (b.ownerUid == _me)
                          PressButton(
                            label: 'Unpin ${b.title}',
                            icon: CupertinoIcons.pin_slash,
                            iconOnly: true,
                            quiet: true,
                            height: 40,
                            onTap: () => _run(
                              () => widget.backend.unpinBoard(
                                widget.classroomId,
                                b.boardId,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_mine)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PressButton(
                      label: 'Pin one of your boards',
                      icon: CupertinoIcons.pin,
                      quiet: true,
                      onTap: _pinBoard,
                    ),
                  ),
                if (pinned.isNotEmpty || _mine)
                  Text(
                    'A pinned board shows the thinking behind this step. '
                    'Everyone in the classroom can look at it.',
                    style: TypeRamp.caption(p.inkFaint),
                  ),
              ],
            );
          },
        ),
        StepFiles(
          backend: widget.backend,
          classroomId: widget.classroomId,
          classroomTitle: widget.classroomTitle,
          plan: widget.plan,
          step: _step,
          canManage: widget.canManage,
          onNotice: widget.onNotice,
        ),
        if (_mine) ...[
          label('Study materials'),
          StreamBuilder<List<StudyMaterial>>(
            stream: _materials,
            builder: (context, snap) {
              final here = (snap.data ?? const <StudyMaterial>[])
                  .where((m) => m.stepId == _step.id)
                  .toList()
                  .reversed
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snap.hasData && here.isEmpty)
                    Text(
                      'Nothing here yet. Add a link, video, note or repository '
                      'that helps with this step.',
                      style: TypeRamp.label(p.inkSoft),
                    ),
                  for (final m in here)
                    _MaterialRow(
                      material: m,
                      by: nameIn(widget.plan, m.ownerUid),
                      open: _openNotes.contains(m.id),
                      onOpen: () => _open(m),
                      onRemove: m.ownerUid == _me || widget.canManage
                          ? () => _removeMaterial(m)
                          : null,
                    ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PressButton(
                      label: 'Add material',
                      icon: CupertinoIcons.plus,
                      quiet: true,
                      onTap: _addMaterial,
                    ),
                  ),
                  Text(
                    'Only you can see your study materials.',
                    style: TypeRamp.caption(p.inkFaint),
                  ),
                ],
              );
            },
          ),
        ],
        StreamBuilder<List<Suggestion>>(
          stream: _suggestions,
          builder: (context, snap) {
            final here = (snap.data ?? const <Suggestion>[])
                .where((s) => s.stepId == _step.id)
                .toList();
            final open = here
                .where((s) => s.status == SuggestionStatus.open)
                .toList();
            // Answered ones stay in view for the two people in them.
            final answered = here
                .where(
                  (s) => s.status != SuggestionStatus.open && s.involves(_me),
                )
                .take(5)
                .toList();
            if (here.isEmpty && _mine) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label(
                  open.isEmpty ? 'Suggestions' : 'Suggestions · ${open.length}',
                ),
                for (final s in [...open, ...answered])
                  _SuggestionCard(
                    suggestion: s,
                    from: nameIn(widget.plan, s.fromUid),
                    to: nameIn(widget.plan, s.toUid),
                    when: whenShort(s.createdAt, now),
                    me: _me,
                    onAnswer: (to) => _answer(s, to),
                    onShare: (public) => _share(s, public),
                  ),
                if (open.any((s) => s.toUid == _me))
                  Text(
                    'Accepting doesn’t change the step. Make the change '
                    'yourself, then accept so they know.',
                    style: TypeRamp.caption(p.inkSoft),
                  ),
                if (!_mine)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PressButton(
                      label: 'Suggest a change',
                      icon: CupertinoIcons.lightbulb,
                      quiet: true,
                      onTap: _suggest,
                    ),
                  ),
              ],
            );
          },
        ),
        StreamBuilder<List<StepComment>>(
          stream: _comments,
          builder: (context, snap) =>
              _threadSection(p, now, snap.data ?? const []),
        ),
      ],
    );
  }

  /// The owner picks whose private thread to read; anyone else sees their own.
  Widget _threadSection(Palette p, DateTime now, List<StepComment> all) {
    final owner = _step.ownerId;
    final others = <String>[];
    for (final c in all) {
      final other = c.other(owner);
      if (other != owner && !others.contains(other)) others.add(other);
    }
    final String? withUid;
    if (_mine) {
      withUid = _thread ?? (others.isNotEmpty ? others.last : null);
    } else {
      withUid = _me;
    }
    final shown = withUid == null
        ? const <StepComment>[]
        : all.where((c) => c.participants.contains(withUid)).toList();
    final members = widget.plan.members.where((m) => m.id != owner).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 4),
          child: Semantics(
            header: true,
            child: Text(
              _mine
                  ? 'Private comments'
                  : 'Private comments with '
                        '${nameIn(widget.plan, owner)}',
              style: TypeRamp.label(p.inkSoft),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(CupertinoIcons.lock, size: 13, color: p.inkFaint),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _mine
                      ? 'Each conversation is only between you and that '
                            'person.'
                      : 'Only you and ${nameIn(widget.plan, owner)} can see '
                            'these.',
                  style: TypeRamp.caption(p.inkSoft),
                ),
              ),
            ],
          ),
        ),
        if (_mine) ...[
          if (members.isEmpty)
            Text(
              'Nobody else is in this classroom yet.',
              style: TypeRamp.caption(p.inkSoft),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in members)
                    SelectChip(
                      label: others.contains(m.id)
                          ? '${m.name} · '
                                '${all.where((c) => c.participants.contains(m.id)).length}'
                          : m.name,
                      selected: m.id == withUid,
                      onTap: () => setState(() => _thread = m.id),
                    ),
                ],
              ),
            ),
        ],
        for (final c in shown)
          _CommentRow(
            name: nameIn(widget.plan, c.authorUid),
            when: whenShort(c.createdAt, now),
            text: c.text,
            mine: c.authorUid == _me,
            onRemove: c.authorUid == _me
                ? () async {
                    if (!await _askToRemove(
                      'Remove this comment?',
                      'It goes for both of you.',
                    )) {
                      return;
                    }
                    await _run(
                      () => widget.backend.deleteComment(
                        widget.classroomId,
                        _step.id,
                        c.id,
                      ),
                    );
                  }
                : null,
          ),
        if (withUid != null) ...[
          const SizedBox(height: 4),
          GlassField(
            label: _mine
                ? 'Write to ${nameIn(widget.plan, withUid)}'
                : 'Write to ${nameIn(widget.plan, owner)}',
            controller: _comment,
            maxLines: 3,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: PressButton(
              label: _sending ? 'Sending' : 'Send',
              icon: CupertinoIcons.paperplane,
              prominent: true,
              onTap: _sending ? null : () => _sendComment(withUid!),
            ),
          ),
        ] else if (_mine && members.isNotEmpty)
          Text(
            'Pick someone to write to them about this step.',
            style: TypeRamp.caption(p.inkSoft),
          ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.from,
    required this.to,
    required this.when,
    required this.me,
    required this.onAnswer,
    required this.onShare,
  });

  final Suggestion suggestion;
  final String from;
  final String to;
  final String when;
  final String me;
  final ValueChanged<SuggestionStatus> onAnswer;
  final ValueChanged<bool> onShare;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = suggestion;
    final open = s.status == SuggestionStatus.open;
    final colour = switch (s.status) {
      SuggestionStatus.open => p.review,
      SuggestionStatus.accepted => p.done,
      SuggestionStatus.dismissed => p.waiting,
    };
    final outcome = switch (s.status) {
      SuggestionStatus.open => null,
      SuggestionStatus.accepted => '$to accepted this',
      SuggestionStatus.dismissed => '$to dismissed this',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                s.public ? CupertinoIcons.person_3 : CupertinoIcons.lock,
                size: 13,
                color: p.inkSoft,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '$from to $to · $when · '
                  '${s.public ? 'Everyone can see' : 'Private'}',
                  style: TypeRamp.caption(p.inkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(s.text, style: TypeRamp.body(p.ink)),
          if (outcome != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                outcome,
                style: TypeRamp.caption(colour).weighted(FontWeight.w700),
              ),
            ),
          if ((open && s.toUid == me) || s.involves(me))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (open && s.toUid == me) ...[
                    PressButton(
                      label: 'Accept',
                      icon: CupertinoIcons.checkmark_alt,
                      height: 36,
                      onTap: () => onAnswer(SuggestionStatus.accepted),
                    ),
                    PressButton(
                      label: 'Dismiss',
                      quiet: true,
                      height: 36,
                      onTap: () => onAnswer(SuggestionStatus.dismissed),
                    ),
                  ],
                  if (s.involves(me))
                    PressButton(
                      label: s.public ? 'Make private' : 'Show to everyone',
                      icon: s.public
                          ? CupertinoIcons.lock
                          : CupertinoIcons.person_3,
                      quiet: true,
                      height: 36,
                      onTap: () => onShare(!s.public),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.material,
    required this.by,
    required this.open,
    required this.onOpen,
    this.onRemove,
  });

  final StudyMaterial material;
  final String by;
  final bool open;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final m = material;
    final isNote = m.kind == MaterialKind.note;
    final where = isNote ? 'Note' : '${m.kind.label} · ${m.site}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: isNote
                    ? '${open ? 'Hide' : 'Show'} note ${m.title}'
                    : 'Open ${m.title}, ${m.kind.label} on ${m.site}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            materialIcon(m.kind),
                            size: 16,
                            color: p.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.title, style: TypeRamp.body(p.ink)),
                              Text(
                                '$where · $by',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TypeRamp.caption(p.inkSoft),
                              ),
                              if (isNote && open && m.note.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(m.note, style: TypeRamp.body(p.ink)),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Icon(
                            isNote
                                ? (open
                                      ? CupertinoIcons.chevron_up
                                      : CupertinoIcons.chevron_down)
                                : CupertinoIcons.arrow_up_right,
                            size: 14,
                            color: p.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              PressButton(
                label: 'Remove ${m.title}',
                icon: CupertinoIcons.minus_circle,
                iconOnly: true,
                quiet: true,
                height: 44,
                onTap: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.name,
    required this.when,
    required this.text,
    required this.mine,
    this.onRemove,
  });

  final String name;
  final String when;
  final String text;
  final bool mine;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: mine ? p.accent.withValues(alpha: 0.18) : p.control,
              shape: BoxShape.circle,
            ),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TypeRamp.caption(p.ink).weighted(FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name · $when', style: TypeRamp.caption(p.inkSoft)),
                const SizedBox(height: 2),
                Text(text, style: TypeRamp.body(p.ink)),
              ],
            ),
          ),
          if (onRemove != null)
            PressButton(
              label: 'Remove your comment',
              icon: CupertinoIcons.minus_circle,
              iconOnly: true,
              quiet: true,
              height: 36,
              onTap: onRemove,
            ),
        ],
      ),
    );
  }
}

/// Adds a link, video, note or repository, or a practice link.
class MaterialEditorSheet extends StatefulWidget {
  const MaterialEditorSheet({
    super.key,
    required this.newId,
    required this.ownerUid,
    this.stepId = '',
    this.practice = false,
  });

  final String Function() newId;
  final String ownerUid;
  final String stepId;

  /// A practice link for the classroom rather than a material on a step.
  final bool practice;

  @override
  State<MaterialEditorSheet> createState() => _MaterialEditorSheetState();
}

class _MaterialEditorSheetState extends State<MaterialEditorSheet> {
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _note = TextEditingController();
  late var _kind = widget.practice ? MaterialKind.practice : MaterialKind.link;
  var _kindChosen = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _url.addListener(() {
      if (widget.practice || _kindChosen) return;
      final guess = MaterialKind.guess(_url.text);
      if (guess != _kind) setState(() => _kind = guess);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final isNote = _kind == MaterialKind.note;
    final address = isNote ? '' : webAddress(_url.text);
    if (!isNote && address == null) {
      setState(() => _message = 'Paste a web address, starting with https.');
      return;
    }
    if (isNote && _note.text.trim().isEmpty) {
      setState(() => _message = 'Write the note first.');
      return;
    }
    var title = _title.text.trim();
    if (title.isEmpty) {
      title = isNote
          ? _note.text.trim().split('\n').first
          : (Uri.parse(address!).host.replaceFirst('www.', ''));
    }
    if (title.length > kMaxTitleLength) {
      title = title.substring(0, kMaxTitleLength);
    }
    if (_note.text.length > kMaxNoteLength) {
      setState(() => _message = 'That note is too long to save.');
      return;
    }
    Navigator.of(context).pop(
      StudyMaterial(
        id: widget.newId(),
        kind: _kind,
        title: title,
        url: address ?? '',
        note: isNote ? _note.text.trim() : '',
        ownerUid: widget.ownerUid,
        stepId: widget.stepId,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final isNote = _kind == MaterialKind.note;
    return SheetFrame(
      title: widget.practice ? 'Add a practice link' : 'Add material',
      message: _message,
      action: PressButton(
        label: 'Add',
        prominent: true,
        height: 48,
        expand: true,
        onTap: _save,
      ),
      children: [
        if (!widget.practice) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in const [
                MaterialKind.link,
                MaterialKind.video,
                MaterialKind.note,
                MaterialKind.repo,
              ])
                SelectChip(
                  label: k.label,
                  selected: k == _kind,
                  onTap: () => setState(() {
                    _kind = k;
                    _kindChosen = true;
                    _message = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (!isNote) ...[
          GlassField(
            label: 'Web address',
            controller: _url,
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
          ),
          const SizedBox(height: 10),
        ],
        GlassField(label: 'Title (optional)', controller: _title),
        if (isNote) ...[
          const SizedBox(height: 10),
          GlassField(label: 'Note', controller: _note, maxLines: 6),
        ],
        const SizedBox(height: 8),
        Text(
          widget.practice
              ? 'Everyone in the classroom can see and open it. Octria only '
                    'keeps the link.'
              : 'Everyone in the classroom can see it.',
          style: TypeRamp.caption(p.inkSoft),
        ),
      ],
    );
  }
}

/// Writes a suggestion and says who may see it. Returns the text and whether
/// it's public.
class _SuggestSheet extends StatefulWidget {
  const _SuggestSheet({required this.owner});

  final String owner;

  @override
  State<_SuggestSheet> createState() => _SuggestSheetState();
}

class _SuggestSheetState extends State<_SuggestSheet> {
  final _text = TextEditingController();
  var _public = false;
  String? _message;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Suggest a change',
      message: _message,
      action: PressButton(
        label: 'Send suggestion',
        prominent: true,
        height: 48,
        expand: true,
        onTap: () {
          final text = _text.text.trim();
          if (text.isEmpty) {
            setState(() => _message = 'Write what you’d change first.');
            return;
          }
          if (text.length > kMaxCommentLength) {
            setState(() => _message = 'Keep it under 2000 letters.');
            return;
          }
          Navigator.of(context).pop((text, _public));
        },
      ),
      children: [
        Text(
          '${widget.owner} decides whether to accept it, and you’ll hear '
          'which.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 12),
        GlassField(label: 'Your suggestion', controller: _text, maxLines: 5),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 7),
          child: Text('Who can see it', style: TypeRamp.label(p.inkSoft)),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SelectChip(
              label: 'Only ${widget.owner} and me',
              selected: !_public,
              onTap: () => setState(() => _public = false),
            ),
            SelectChip(
              label: 'Everyone in the classroom',
              selected: _public,
              onTap: () => setState(() => _public = true),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Either of you can change this later.',
          style: TypeRamp.caption(p.inkSoft),
        ),
      ],
    );
  }
}

/// Where a handover request has got to, with what this person can do about it.
class _HandoverCard extends StatelessWidget {
  const _HandoverCard({
    required this.handover,
    required this.plan,
    required this.me,
    required this.manages,
    required this.onReview,
    required this.onAnswer,
    required this.onCancel,
  });

  final Handover handover;
  final Plan plan;
  final String me;
  final bool manages;
  final ValueChanged<bool> onReview;
  final ValueChanged<bool> onAnswer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final h = handover;
    final from = h.fromUid == me ? 'You' : nameIn(plan, h.fromUid);
    final to = h.toUid == me ? 'you' : nameIn(plan, h.toUid);
    final line = switch (h.status) {
      HandoverStatus.needsMaster =>
        '$from asked to hand this to $to. Waiting for the master.',
      HandoverStatus.needsReceiver =>
        '$from wants to hand this to $to. Waiting for '
            '${h.toUid == me ? 'you' : nameIn(plan, h.toUid)} to accept.',
      HandoverStatus.accepted =>
        '${h.toUid == me ? 'You' : nameIn(plan, h.toUid)} took this on from ${h.fromUid == me ? 'you' : nameIn(plan, h.fromUid)}.',
      HandoverStatus.declined =>
        'The request to hand this to $to was declined.',
    };
    final colour = switch (h.status) {
      HandoverStatus.accepted => p.done,
      HandoverStatus.declined => p.waiting,
      _ => p.accentViolet,
    };
    final review = h.status == HandoverStatus.needsMaster && manages;
    final answer = h.status == HandoverStatus.needsReceiver && h.toUid == me;
    final withdraw = h.open && h.fromUid == me;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.arrow_right_arrow_left,
                size: 14,
                color: colour,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Handover',
                  style: TypeRamp.label(p.ink).weighted(FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(line, style: TypeRamp.body(p.ink)),
          if (h.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('“${h.note}”', style: TypeRamp.label(p.inkSoft)),
            ),
          if (review || answer || withdraw)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (review) ...[
                    PressButton(
                      label: 'Agree',
                      icon: CupertinoIcons.checkmark_alt,
                      height: 36,
                      onTap: () => onReview(true),
                    ),
                    PressButton(
                      label: 'Say no',
                      quiet: true,
                      height: 36,
                      onTap: () => onReview(false),
                    ),
                  ],
                  if (answer) ...[
                    PressButton(
                      label: 'Take it on',
                      icon: CupertinoIcons.checkmark_alt,
                      height: 36,
                      onTap: () => onAnswer(true),
                    ),
                    PressButton(
                      label: 'Decline',
                      quiet: true,
                      height: 36,
                      onTap: () => onAnswer(false),
                    ),
                  ],
                  if (withdraw)
                    PressButton(
                      label: 'Withdraw request',
                      quiet: true,
                      height: 36,
                      onTap: onCancel,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks who to hand a step to, and why. Returns the note.
class HandoverRequestSheet extends StatefulWidget {
  const HandoverRequestSheet({
    super.key,
    required this.stepTitle,
    required this.to,
    required this.viaMaster,
  });

  final String stepTitle;
  final String to;

  /// Whether the master has to agree first.
  final bool viaMaster;

  @override
  State<HandoverRequestSheet> createState() => _HandoverRequestSheetState();
}

class _HandoverRequestSheetState extends State<HandoverRequestSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Hand to ${widget.to}?',
      action: PressButton(
        label: widget.viaMaster ? 'Ask the master' : 'Ask ${widget.to}',
        prominent: true,
        height: 48,
        expand: true,
        onTap: () => Navigator.of(context).pop(_note.text.trim()),
      ),
      children: [
        Text(
          widget.viaMaster
              ? 'The master sees your request first. If they agree, '
                    '${widget.to} decides whether to take on '
                    '“${widget.stepTitle}”. It stays yours until then.'
              : '${widget.to} decides whether to take on '
                    '“${widget.stepTitle}”. It stays yours until then.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 12),
        GlassField(
          label: 'Why, or what they should know (optional)',
          controller: _note,
          maxLines: 4,
        ),
      ],
    );
  }
}
