import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/glass_menu.dart';
import 'classroom_forms.dart';
import 'step_collab.dart';

/// Names of everyone in a chat but this person.
String threadTitle(ChatThread t, Plan plan) {
  final others = [
    for (final uid in t.participants)
      if (uid != plan.meId) nameIn(plan, uid),
  ];
  return others.isEmpty ? 'Just you' : others.join(', ');
}

/// This person's private chats in the classroom, and a way to start one.
class ChatsSheet extends StatelessWidget {
  const ChatsSheet({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.plan,
    required this.masterUid,
    required this.onOpen,
    required this.onNewGroup,
  });

  final Backend backend;
  final String classroomId;
  final Plan plan;
  final String masterUid;
  final ValueChanged<List<String>> onOpen;
  final VoidCallback onNewGroup;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final others = plan.members.where((m) => m.id != plan.meId).toList();
    return StreamBuilder<List<ChatThread>>(
      stream: backend.threads(classroomId),
      builder: (context, snap) {
        final threads = snap.data ?? const <ChatThread>[];
        return SheetFrame(
          title: 'Private chats',
          action: PressButton(
            label: 'New group chat',
            icon: CupertinoIcons.person_3,
            prominent: true,
            height: 48,
            expand: true,
            onTap: () {
              Navigator.of(context).pop();
              onNewGroup();
            },
          ),
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.lock, size: 13, color: p.inkFaint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Only the people in a chat can read it.',
                    style: TypeRamp.caption(p.inkSoft),
                  ),
                ),
              ],
            ),
            if (others.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  'Message one person',
                  style: TypeRamp.label(p.inkSoft),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in others)
                    PressButton(
                      label: m.id == masterUid ? '${m.name} · master' : m.name,
                      icon: CupertinoIcons.chat_bubble,
                      height: 36,
                      onTap: () {
                        Navigator.of(context).pop();
                        onOpen([m.id]);
                      },
                    ),
                ],
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text('Your chats', style: TypeRamp.label(p.inkSoft)),
            ),
            if (snap.hasData && threads.isEmpty)
              Text(
                'None yet. Tap someone above, or their round icon beside the '
                'plan, to start.',
                style: TypeRamp.caption(p.inkSoft),
              ),
            for (final t in threads)
              Semantics(
                button: true,
                label:
                    'Chat with ${threadTitle(t, plan)}'
                    '${t.unreadFor(plan.meId) ? ', new messages' : ''}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpen([
                      for (final uid in t.participants)
                        if (uid != plan.meId) uid,
                    ]);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: p.panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.rimBottom),
                    ),
                    child: Row(
                      children: [
                        _Faces(
                          names: [
                            for (final uid in t.participants)
                              if (uid != plan.meId) nameIn(plan, uid),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                threadTitle(t, plan),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TypeRamp.body(p.ink).weighted(
                                  t.unreadFor(plan.meId)
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              if (t.lastText.isNotEmpty)
                                Text(
                                  '${t.lastBy == plan.meId ? 'You: ' : ''}'
                                  '${t.lastText}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TypeRamp.caption(p.inkSoft),
                                ),
                            ],
                          ),
                        ),
                        if (t.unreadFor(plan.meId))
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE5262B),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Picks two or more people for a private group chat.
class GroupPickerSheet extends StatefulWidget {
  const GroupPickerSheet({super.key, required this.plan});

  final Plan plan;

  @override
  State<GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<GroupPickerSheet> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final others = widget.plan.members
        .where((m) => m.id != widget.plan.meId)
        .toList();
    return SheetFrame(
      title: 'New group chat',
      action: PressButton(
        label: _picked.length < 2
            ? 'Pick at least two people'
            : 'Start chat with ${_picked.length}',
        prominent: true,
        height: 48,
        expand: true,
        onTap: _picked.length < 2
            ? null
            : () => Navigator.of(context).pop(_picked.toList()),
      ),
      children: [
        Text(
          'Only you and the people you pick can read it. For one person, '
          'tap their name in Private chats instead.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 12),
        for (final m in others)
          Semantics(
            button: true,
            checked: _picked.contains(m.id),
            label: m.name,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                if (!_picked.remove(m.id)) _picked.add(m.id);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                decoration: _picked.contains(m.id)
                    ? glassTint(p, p.accent, radius: 16)
                    : BoxDecoration(
                        color: p.panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.rimBottom),
                      ),
                child: Row(
                  children: [
                    GlassAvatar(name: m.name, size: 34),
                    const SizedBox(width: 12),
                    Expanded(child: Text(m.name, style: TypeRamp.body(p.ink))),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        _picked.contains(m.id)
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        key: ValueKey(_picked.contains(m.id)),
                        size: 22,
                        color: _picked.contains(m.id) ? p.accent : p.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One private conversation, newest at the bottom.
class ThreadSheet extends StatefulWidget {
  const ThreadSheet({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.threadId,
    required this.plan,
    required this.participants,
  });

  final Backend backend;
  final String classroomId;
  final String threadId;
  final Plan plan;
  final List<String> participants;

  @override
  State<ThreadSheet> createState() => _ThreadSheetState();
}

class _ThreadSheetState extends State<ThreadSheet> {
  late final Stream<List<ChatMessage>> _messages = widget.backend
      .threadMessages(widget.classroomId, widget.threadId);
  final _text = TextEditingController();
  var _sending = false;
  String? _message;

  String get _me => widget.plan.meId;

  void _read() => unawaited(
    widget.backend
        .markThreadRead(widget.classroomId, widget.threadId)
        .catchError((Object _) {}),
  );

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _read();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await widget.backend.sendThreadMessage(
        widget.classroomId,
        widget.threadId,
        text,
      );
      _text.clear();
    } on BackendFailure catch (e) {
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final media = MediaQuery.of(context);
    final height = (media.size.height - media.padding.vertical - 40).clamp(
      320.0,
      680.0,
    );
    final now = DateTime.now();
    final names = [
      for (final uid in widget.participants)
        if (uid != _me) nameIn(widget.plan, uid),
    ].join(', ');
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
            child: Row(
              children: [
                sheetBackButton(context),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      names,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeRamp.title(p.ink),
                    ),
                  ),
                ),
                PressButton(
                  label: 'Close',
                  icon: CupertinoIcons.xmark,
                  iconOnly: true,
                  quiet: true,
                  height: 44,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Icon(CupertinoIcons.lock, size: 13, color: p.inkFaint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Private: only you and $names can read this.',
                    style: TypeRamp.caption(p.inkSoft),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snap) {
                final list = (snap.data ?? const <ChatMessage>[]).reversed
                    .toList();
                if (snap.hasData && list.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.',
                      style: TypeRamp.label(p.inkSoft),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final mine = m.authorUid == _me;
                    final name = nameIn(widget.plan, m.authorUid);
                    final bubble = ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                        decoration: mine
                            ? glassTint(p, p.accent, radius: 18)
                            : BoxDecoration(
                                color: p.panel,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: p.rimBottom),
                              ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${mine ? 'You' : name}'
                              ' · ${whenShort(m.createdAt, now)}',
                              style: TypeRamp.caption(p.inkSoft),
                            ),
                            Text(m.text, style: TypeRamp.body(p.ink)),
                          ],
                        ),
                      ),
                    );
                    return Row(
                      mainAxisAlignment: mine
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!mine) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassAvatar(name: name, size: 26),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(child: bubble),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(_message!, style: TypeRamp.label(p.blocked)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: GlassField(
                    label: 'Message',
                    controller: _text,
                    maxLines: 3,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                PressButton(
                  label: 'Send',
                  icon: CupertinoIcons.paperplane,
                  iconOnly: true,
                  prominent: true,
                  height: 48,
                  onTap: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Up to three overlapping faces for the people in a chat.
class _Faces extends StatelessWidget {
  const _Faces({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final shown = names.take(3).toList();
    const size = 32.0;
    return SizedBox(
      width: size + (shown.length - 1).clamp(0, 2) * 14,
      height: size,
      child: Stack(
        children: [
          for (final (i, n) in shown.indexed)
            Positioned(
              left: i * 14.0,
              child: GlassAvatar(name: n, size: size),
            ),
        ],
      ),
    );
  }
}
