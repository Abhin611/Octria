import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart' show sheetBackButton;
import 'step_collab.dart';

/// The classroom chat: messages for everyone in it, suggestions for the whole
/// group that each person can mark as done, and step suggestions someone has
/// chosen to show to everyone.
class ChatSheet extends StatefulWidget {
  const ChatSheet({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.plan,
    required this.isMaster,
  });

  final Backend backend;
  final String classroomId;
  final Plan plan;
  final bool isMaster;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  late final Stream<List<ChatMessage>> _chat = widget.backend.chat(
    widget.classroomId,
  );
  late final Stream<List<Suggestion>> _suggestions = widget.backend.suggestions(
    widget.classroomId,
  );
  final _text = TextEditingController();
  var _forEveryone = false;
  var _sending = false;
  String? _message;

  String get _me => widget.plan.meId;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.backend.markChatSeen(widget.classroomId).catchError((_) {}),
    );
  }

  @override
  void dispose() {
    // Anything that arrived while it was open counts as seen too.
    unawaited(
      widget.backend.markChatSeen(widget.classroomId).catchError((_) {}),
    );
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
      await widget.backend.sendChat(
        widget.classroomId,
        text,
        forEveryone: _forEveryone,
      );
      _text.clear();
      setState(() => _forEveryone = false);
    } on BackendFailure catch (e) {
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final media = MediaQuery.of(context);
    final height = (media.size.height - media.padding.vertical - 40).clamp(
      320.0,
      720.0,
    );
    final now = DateTime.now();
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
                    child: Text('Class chat', style: TypeRamp.title(p.ink)),
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
            child: Text(
              'Everyone in this classroom can read this.',
              style: TypeRamp.caption(p.inkSoft),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chat,
              builder: (context, chat) => StreamBuilder<List<Suggestion>>(
                stream: _suggestions,
                builder: (context, sugg) {
                  final messages = chat.data ?? const <ChatMessage>[];
                  final items =
                      <(DateTime, int, Widget)>[
                        // The order they were sent breaks ties in time.
                        for (final (i, m) in messages.indexed)
                          (
                            m.createdAt,
                            i,
                            _Bubble(
                              message: m,
                              author: nameIn(widget.plan, m.authorUid),
                              when: whenShort(m.createdAt, now),
                              mine: m.authorUid == _me,
                              members: widget.plan.members.length,
                              names: [
                                for (final uid in m.appliedBy)
                                  nameIn(widget.plan, uid),
                              ],
                              done: m.appliedBy.contains(_me),
                              onApplied: m.forEveryone
                                  ? (v) => _run(
                                      () => widget.backend.setApplied(
                                        widget.classroomId,
                                        m.id,
                                        v,
                                      ),
                                    )
                                  : null,
                              onRemove: m.authorUid == _me || widget.isMaster
                                  ? () => _run(
                                      () => widget.backend.deleteChat(
                                        widget.classroomId,
                                        m.id,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        for (final s in sugg.data ?? const <Suggestion>[])
                          if (s.public)
                            (
                              s.publicAt ?? s.createdAt,
                              -1,
                              _SharedSuggestion(
                                suggestion: s,
                                from: nameIn(widget.plan, s.fromUid),
                                to: nameIn(widget.plan, s.toUid),
                                step:
                                    widget.plan.steps[s.stepId]?.title ??
                                    'a step',
                                when: whenShort(s.publicAt ?? s.createdAt, now),
                              ),
                            ),
                      ]..sort((a, b) {
                        final byTime = b.$1.compareTo(a.$1);
                        return byTime != 0 ? byTime : b.$2.compareTo(a.$2);
                      });
                  if (chat.hasData && items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No messages yet. Say hello, or share a suggestion '
                          'for everyone.',
                          textAlign: TextAlign.center,
                          style: TypeRamp.label(p.inkSoft),
                        ),
                      ),
                    );
                  }
                  // Newest at the bottom, where the eye and the field are.
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    itemCount: items.length,
                    itemBuilder: (context, i) => items[i].$3,
                  );
                },
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Semantics(
                liveRegion: true,
                child: Text(_message!, style: TypeRamp.label(p.blocked)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  label: _forEveryone
                      ? 'A suggestion for everyone'
                      : 'Message the class',
                  controller: _text,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectChip(
                          label: 'Suggestion for everyone',
                          selected: _forEveryone,
                          onTap: () =>
                              setState(() => _forEveryone = !_forEveryone),
                        ),
                      ),
                    ),
                    PressButton(
                      label: _sending ? 'Sending' : 'Send',
                      icon: CupertinoIcons.paperplane,
                      prominent: true,
                      onTap: _sending ? null : _send,
                    ),
                  ],
                ),
                if (_forEveryone)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Each person can mark that they’ve made this change, so '
                      'you can see who has.',
                      style: TypeRamp.caption(p.inkSoft),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.author,
    required this.when,
    required this.mine,
    required this.members,
    required this.names,
    required this.done,
    this.onApplied,
    this.onRemove,
  });

  final ChatMessage message;
  final String author;
  final String when;
  final bool mine;
  final int members;
  final List<String> names;
  final bool done;
  final ValueChanged<bool>? onApplied;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final m = message;
    final group = m.forEveryone;
    final fill = group
        ? p.accentWarm.withValues(alpha: 0.12)
        : (mine ? p.accent.withValues(alpha: 0.16) : p.panel);
    final edge = group ? p.accentWarm.withValues(alpha: 0.5) : p.hairline;
    return Align(
      alignment: mine && !group ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: group ? 560 : 420),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: edge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (group) ...[
                    Icon(
                      CupertinoIcons.lightbulb,
                      size: 13,
                      color: p.accentWarm,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      group
                          ? '$author · suggestion for everyone · $when'
                          : '$author · $when',
                      style: TypeRamp.caption(p.inkSoft),
                    ),
                  ),
                  if (onRemove != null)
                    PressButton(
                      label: 'Remove message',
                      icon: CupertinoIcons.xmark,
                      iconOnly: true,
                      quiet: true,
                      height: 28,
                      onTap: onRemove,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(m.text, style: TypeRamp.body(p.ink)),
              ),
              if (group) ...[
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    PressButton(
                      label: done ? 'I’ve made this change' : 'Mark as done',
                      icon: done
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      selected: done,
                      height: 34,
                      onTap: onApplied == null ? null : () => onApplied!(!done),
                    ),
                    Text(
                      names.isEmpty
                          ? 'Nobody has yet'
                          : '${names.length} of $members done: '
                                '${names.join(', ')}',
                      style: TypeRamp.caption(p.inkSoft),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A suggestion on someone's step that one of the two chose to show everyone.
class _SharedSuggestion extends StatelessWidget {
  const _SharedSuggestion({
    required this.suggestion,
    required this.from,
    required this.to,
    required this.step,
    required this.when,
  });

  final Suggestion suggestion;
  final String from;
  final String to;
  final String step;
  final String when;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = suggestion;
    final outcome = switch (s.status) {
      SuggestionStatus.open => 'Waiting for $to',
      SuggestionStatus.accepted => '$to accepted it',
      SuggestionStatus.dismissed => '$to dismissed it',
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: p.review.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.review.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$from suggested on $to’s step “$step” · $when',
              style: TypeRamp.caption(p.inkSoft),
            ),
            const SizedBox(height: 2),
            Text(s.text, style: TypeRamp.body(p.ink)),
            const SizedBox(height: 4),
            Text(
              outcome,
              style: TypeRamp.caption(p.ink).weighted(FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
