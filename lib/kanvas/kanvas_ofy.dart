/// Ofy on a Kanvas board: it reads what's written there and summarises it,
/// suggests what's missing, or turns it into steps. What it says can be put
/// on the board as notes or a checklist.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../ai/ai.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../screens/classroom_forms.dart';
import '../screens/room_lists.dart';
import '../screens/step_panel.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'kanvas_model.dart';

/// What to put on the board from Ofy's help.
class BoardAddition {
  const BoardAddition({required this.task, required this.help});

  final BoardTask task;
  final BoardHelp help;
}

/// The shapes for [add], placed in a column to the right of everything in
/// [around], or at the origin on an empty board. [newId] makes each id.
List<KShape> shapesFor(
  BoardAddition add, {
  required Rect? around,
  required String Function() newId,
}) {
  final left = around == null ? 0.0 : around.right + 60;
  final top = around?.top ?? 0.0;
  final help = add.help;
  switch (add.task) {
    case BoardTask.summary:
      final text = [
        help.summary,
        for (final i in help.items) '• $i',
      ].where((x) => x.trim().isNotEmpty).join('\n');
      // Tall enough for its lines: about 42 characters fit across.
      final lines = text
          .split('\n')
          .fold<int>(0, (n, l) => n + (l.length / 42).ceil().clamp(1, 20));
      return [
        KShape(
          id: newId(),
          kind: ShapeKind.sticky,
          rect: Rect.fromLTWH(left, top, 340, (60 + lines * 22).toDouble()),
          colour: KColour.blue,
          text: text,
        ),
      ];
    case BoardTask.ideas:
      return [
        for (final (i, idea) in help.items.indexed)
          KShape(
            id: newId(),
            kind: ShapeKind.sticky,
            rect: Rect.fromLTWH(
              left + (i % 2) * 200,
              top + (i ~/ 2) * 140,
              180,
              120,
            ),
            colour: KColour.purple,
            text: idea,
          ),
      ];
    case BoardTask.steps:
      return [
        KShape(
          id: newId(),
          kind: ShapeKind.checklist,
          rect: Rect.fromLTWH(
            left,
            top,
            320,
            (56 + help.items.length * 34).toDouble(),
          ),
          text: 'Steps',
          items: [for (final s in help.items) CheckItem(s)],
        ),
      ];
  }
}

class BoardOfySheet extends StatefulWidget {
  const BoardOfySheet({
    super.key,
    required this.backend,
    required this.title,
    required this.shapes,
    required this.canEdit,
  });

  final Backend backend;
  final String title;
  final List<KShape> shapes;

  /// Whether this person may add to the board.
  final bool canEdit;

  @override
  State<BoardOfySheet> createState() => _BoardOfySheetState();
}

class _BoardOfySheetState extends State<BoardOfySheet> {
  BoardTask? _task;
  BoardHelp? _help;
  String? _problem;
  var _asking = false;

  late final _lines = boardLines(widget.shapes);

  Future<void> _ask(BoardTask task) async {
    setState(() {
      _task = task;
      _help = null;
      _problem = null;
      _asking = true;
    });
    try {
      final help = await widget.backend.ai.helpWithBoard(
        BoardBrief(title: widget.title, lines: _lines, task: task),
      );
      if (mounted) {
        setState(() {
          _help = help;
          _asking = false;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final help = _help;
    final task = _task;
    if (_lines.isEmpty) {
      return SheetFrame(
        title: 'Ofy on this board',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'There are no words on this board yet. Add a few notes, and '
              'Ofy can summarise them, suggest what’s missing, or turn them '
              'into steps.',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          ),
        ],
      );
    }
    if (_asking) {
      return SheetFrame(
        title: task!.label,
        children: [
          const SizedBox(height: 24),
          const Center(child: CupertinoActivityIndicator(radius: 13)),
          const SizedBox(height: 12),
          Text(
            task.waiting,
            textAlign: TextAlign.center,
            style: TypeRamp.body(p.inkSoft),
          ),
          const SizedBox(height: 24),
        ],
      );
    }
    if (help != null && task != null) {
      final what = switch (task) {
        BoardTask.summary => 'Put it on the board as a note',
        BoardTask.ideas =>
          'Add ${help.items.length} ${help.items.length == 1 ? 'note' : 'notes'} to the board',
        BoardTask.steps => 'Add them as a checklist',
      };
      final nothing = task != BoardTask.summary && help.items.isEmpty;
      return SheetFrame(
        title: task.label,
        action: widget.canEdit && !nothing
            ? PressButton(
                label: what,
                icon: CupertinoIcons.plus_square_on_square,
                prominent: true,
                height: 46,
                expand: true,
                onTap: () =>
                    Navigator.of(context)
                        .pop(BoardAddition(task: task, help: help)),
              )
            : null,
        children: [
          if (help.summary.isNotEmpty)
            Text(help.summary, style: TypeRamp.body(p.ink)),
          if (help.items.isNotEmpty)
            StepSectionTitle(switch (task) {
              BoardTask.summary => 'Key points',
              BoardTask.ideas => 'Worth adding',
              BoardTask.steps => 'Steps, in order',
            }, top: 16),
          for (final (i, item) in help.items.indexed)
            ListRow(
              lines: 4,
              title: item,
              leading: task == BoardTask.steps
                  ? SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.center,
                        style: TypeRamp.label(p.accent),
                      ),
                    )
                  : Icon(
                      task == BoardTask.ideas
                          ? CupertinoIcons.lightbulb
                          : CupertinoIcons.circle_fill,
                      size: task == BoardTask.ideas ? 18 : 7,
                      color: p.accent,
                    ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: PressButton(
              label: 'Ask for something else',
              icon: CupertinoIcons.chevron_left,
              quiet: true,
              onTap: () => setState(() {
                _help = null;
                _task = null;
              }),
            ),
          ),
          if (!widget.canEdit)
            Text(
              'You can look at this board but not change it, so Ofy’s answer '
              'stays here.',
              style: TypeRamp.caption(p.inkFaint),
            ),
          const SizedBox(height: 6),
        ],
      );
    }
    return SheetFrame(
      title: 'Ofy on this board',
      message: _problem,
      children: [
        Text(
          'Ofy reads the words on “${widget.title}”: its notes, text, '
          'checklists and labels. It can’t see drawings or what’s inside '
          'files.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 12),
        for (final (t, icon, detail) in const [
          (
            BoardTask.summary,
            CupertinoIcons.text_alignleft,
            'What the board is about, and its key points.',
          ),
          (
            BoardTask.ideas,
            CupertinoIcons.lightbulb,
            'Gaps and questions, as notes you can add.',
          ),
          (
            BoardTask.steps,
            CupertinoIcons.list_number,
            'What’s here, as an ordered checklist.',
          ),
        ])
          ListRow(
            title: t.label,
            detail: detail,
            leading: Icon(icon, size: 20, color: p.accentViolet),
            trailing: Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: p.inkFaint,
            ),
            onTap: () => unawaited(_ask(t)),
          ),
        Text(
          'Each one uses one of your Ofy requests for today.',
          style: TypeRamp.caption(p.inkFaint),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
