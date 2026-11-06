import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../data/overview.dart';
import '../model/plan.dart';
import '../screens/classroom_forms.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/glass_motion.dart';
import '../widgets/motion.dart';
import 'kanvas_model.dart';
import 'kanvas_painter.dart';
import 'kanvas_screen.dart';

/// Opens a board full screen, with sharing and "make a classroom" wired up.
Future<void> openBoard(
  BuildContext context, {
  required Backend backend,
  required String ownerUid,
  required String boardId,
  Overview? overview,
  ValueChanged<String>? onOpenClassroom,
  bool inClassroom = false,
}) => Navigator.of(context).push(
  GlassRoute<void>(
    builder: (route) => KanvasScreen(
      backend: backend,
      ownerUid: ownerUid,
      boardId: boardId,
      inClassroom: inClassroom,
      onShare: overview == null
          ? null
          : (board) => showGlassSheet<void>(
              route,
              (_) => ShareBoardSheet(
                backend: backend,
                board: board,
                overview: overview,
              ),
            ),
      onMakeClassroom: onOpenClassroom == null
          ? null
          : (notes) => makeClassroomFromNotes(
              route,
              backend: backend,
              notes: notes,
              onOpen: (id) {
                Navigator.of(route).pop();
                onOpenClassroom(id);
              },
            ),
    ),
  ),
);

/// Turns notes from a board into a new classroom: one phase of ideas, one step
/// for each note. The AI planner shapes it properly from build phase 4.
Future<void> makeClassroomFromNotes(
  BuildContext context, {
  required Backend backend,
  required List<IdeaNote> notes,
  required ValueChanged<String> onOpen,
}) async {
  final made = await showGlassSheet<(String, bool)>(
    context,
    (_) => _IdeaClassroomSheet(count: notes.length),
  );
  if (made == null) return;
  final me = backend.currentUser?.uid ?? '';
  final id = await backend.createClassroom(
    title: made.$1,
    description: 'Made from a Kanvas board.',
    taskType: TaskType.other,
    individual: made.$2,
  );
  const phase = PhaseRecord(id: 'ideas', title: 'Ideas', order: 0);
  await backend.savePhase(id, phase);
  final today = DateTime.now();
  for (var i = 0; i < notes.length; i++) {
    final due = DateTime(today.year, today.month, today.day + 7 + i);
    await backend.saveStep(
      id,
      PlanStep(
        id: backend.newId(),
        phaseId: phase.id,
        ownerId: me,
        title: notes[i].title,
        description: notes[i].detail,
        estimateHours: 1,
        start: DateTime(today.year, today.month, today.day),
        due: due,
        order: i,
      ),
    );
  }
  onOpen(id);
}

/// The Kanvas tab: this person's boards, by folder, and boards shared with them.
class KanvasHome extends StatefulWidget {
  const KanvasHome({
    super.key,
    required this.backend,
    required this.overview,
    required this.insets,
    required this.onOpenClassroom,
  });

  final Backend backend;
  final Overview overview;
  final EdgeInsets insets;
  final ValueChanged<String> onOpenClassroom;

  @override
  State<KanvasHome> createState() => _KanvasHomeState();
}

class _KanvasHomeState extends State<KanvasHome> {
  late final Stream<List<KanvasBoard>> _mine = widget.backend.myBoards();
  late final Stream<List<KanvasBoard>> _shared = widget.backend
      .boardsSharedWithMe();
  final _search = TextEditingController();

  /// Empty for all of them; null for "Shared with me".
  String? _folder = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _new() async {
    final title = await showGlassSheet<String>(
      context,
      (_) => const KanvasNameSheet(
        title: 'New board',
        action: 'Create',
        label: 'What is it for?',
      ),
    );
    if (title == null || !mounted) return;
    final KanvasBoard board;
    try {
      board = await widget.backend.createBoard(
        title: title,
        folder: _folder ?? '',
      );
    } on BackendFailure catch (e) {
      _notice(e.message);
      return;
    }
    if (!mounted) return;
    await _open(board);
  }

  Future<void> _open(KanvasBoard b) => openBoard(
    context,
    backend: widget.backend,
    ownerUid: b.ownerUid,
    boardId: b.id,
    overview: b.ownerUid == widget.backend.currentUser?.uid
        ? widget.overview
        : null,
    onOpenClassroom: widget.onOpenClassroom,
  );

  void _notice(String text) {
    if (!mounted) return;
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          content: Text(text),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  void _actions(KanvasBoard b, List<String> folders) {
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ActionListSheet(
          title: b.title,
          items: [
            ('Open', 0, () => _open(b)),
            ('Rename', 0, () => _rename(b)),
            ('Move to a folder', 0, () => _move(b, folders)),
            (
              'Share',
              0,
              () => showGlassSheet<void>(
                context,
                (_) => ShareBoardSheet(
                  backend: widget.backend,
                  board: b,
                  overview: widget.overview,
                ),
              ),
            ),
            ('Delete', 0, () => _delete(b)),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(KanvasBoard b) async {
    final title = await showGlassSheet<String>(
      context,
      (_) => KanvasNameSheet(title: 'Rename board', initial: b.title),
    );
    if (title == null) return;
    try {
      await widget.backend.updateBoardInfo(b.id, title: title);
    } on BackendFailure catch (e) {
      _notice(e.message);
    }
  }

  Future<void> _move(KanvasBoard b, List<String> folders) async {
    final folder = await showGlassSheet<String>(
      context,
      (_) => _FolderSheet(folders: folders, current: b.folder),
    );
    if (folder == null) return;
    try {
      await widget.backend.updateBoardInfo(b.id, folder: folder);
    } on BackendFailure catch (e) {
      _notice(e.message);
    }
  }

  Future<void> _delete(KanvasBoard b) async {
    final sure = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete “${b.title}”?'),
        content: const Text(
          'The board and its saved copies go for good, for everyone it’s '
          'shared with.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.backend.deleteBoard(b.id);
    } on BackendFailure catch (e) {
      _notice(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final insets = widget.insets;
    return StreamBuilder<List<KanvasBoard>>(
      stream: _mine,
      builder: (context, mine) => StreamBuilder<List<KanvasBoard>>(
        stream: _shared,
        builder: (context, shared) {
          final own = mine.data ?? const <KanvasBoard>[];
          final others = shared.data ?? const <KanvasBoard>[];
          final folders = {
            for (final b in own)
              if (b.folder.isNotEmpty) b.folder,
          }.toList()..sort();
          final query = _search.text.trim().toLowerCase();
          final source = _folder == null ? others : own;
          final shown = [
            for (final b in source)
              if ((_folder == null ||
                      _folder!.isEmpty ||
                      b.folder == _folder) &&
                  (query.isEmpty || b.searchText.contains(query)))
                b,
          ];
          return Padding(
            padding: EdgeInsets.only(left: insets.left, right: insets.right),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.only(top: insets.top),
                      sliver: SliverToBoxAdapter(
                        child: Rise(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: p.accentWarm.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.paintbrush,
                                    color: p.accentWarm,
                                    size: 23,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Semantics(
                                        header: true,
                                        child: Text(
                                          'Kanvas',
                                          style: TypeRamp.title(p.ink).copyWith(
                                            fontSize: 30,
                                            letterSpacing: -1,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Your own boards for ideas, notes and '
                                        'diagrams. Private until you share.',
                                        style: TypeRamp.body(p.inkSoft),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Rise(
                        index: 1,
                        child: Row(
                          children: [
                            Expanded(
                              child: GlassField(
                                label: 'Search boards and what’s on them',
                                controller: _search,
                              ),
                            ),
                            const SizedBox(width: 8),
                            PressButton(
                              label: 'New board',
                              icon: CupertinoIcons.plus,
                              prominent: true,
                              height: 48,
                              onTap: _new,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 12),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            SelectChip(
                              label: 'All my boards',
                              selected: _folder == '',
                              onTap: () => setState(() => _folder = ''),
                            ),
                            for (final f in folders)
                              SelectChip(
                                label: f,
                                selected: _folder == f,
                                onTap: () => setState(() => _folder = f),
                              ),
                            SelectChip(
                              label: others.isEmpty
                                  ? 'Shared with me'
                                  : 'Shared with me · ${others.length}',
                              selected: _folder == null,
                              onTap: () => setState(() => _folder = null),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (mine.hasData && shown.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            _folder == null
                                ? 'Nobody has shared a board with you yet.'
                                : (query.isNotEmpty
                                      ? 'No board matches “$query”.'
                                      : 'No boards here yet. Start one for '
                                            'an idea, a plan or a sketch.'),
                            textAlign: TextAlign.center,
                            style: TypeRamp.body(p.inkSoft),
                          ),
                        ),
                      )
                    else
                      SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.95,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          childCount: shown.length,
                          (context, i) => Rise(
                            index: 3 + i,
                            child: _BoardCard(
                              board: shown[i],
                              mine:
                                  shown[i].ownerUid ==
                                  widget.backend.currentUser?.uid,
                              onOpen: () => _open(shown[i]),
                              onMore:
                                  shown[i].ownerUid ==
                                      widget.backend.currentUser?.uid
                                  ? () => _actions(shown[i], folders)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(child: SizedBox(height: insets.bottom)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BoardCard extends StatefulWidget {
  const _BoardCard({
    required this.board,
    required this.mine,
    required this.onOpen,
    this.onMore,
  });

  final KanvasBoard board;
  final bool mine;
  final VoidCallback onOpen;
  final VoidCallback? onMore;

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  final _camera = KanvasCamera();

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final b = widget.board;
    final shared = b.people.isNotEmpty || b.classroomId.isNotEmpty;
    final updated = b.updatedAt;
    return Pressable(
      label:
          '${b.title}. ${b.shapes.length} items.'
          '${b.folder.isEmpty ? '' : ' In ${b.folder}.'}'
          '${shared ? ' Shared.' : ''}',
      onTap: widget.onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.hairline),
          boxShadow: [
            BoxShadow(
              color: p.shadow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  // A small picture of the board itself.
                  final byId = {for (final s in b.shapes) s.id: s};
                  Rect? all;
                  for (final s in b.shapes) {
                    final r = boundsOf(s, byId);
                    all = all == null ? r : all.expandToInclude(r);
                  }
                  if (all != null) {
                    _camera.fit(
                      all,
                      box.biggest,
                      padding: const EdgeInsets.all(12),
                    );
                  }
                  return Container(
                    color: p.ground.withValues(alpha: 0.5),
                    child: all == null
                        ? Center(
                            child: Icon(
                              CupertinoIcons.paintbrush,
                              size: 30,
                              color: p.inkFaint,
                            ),
                          )
                        : CustomPaint(
                            painter: KanvasPainter(
                              shapes: b.shapes,
                              camera: _camera,
                              palette: p,
                              showGrid: false,
                            ),
                          ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeRamp.heading(p.ink)
                              .weighted(FontWeight.w700),
                        ),
                        Text(
                          [
                            if (b.folder.isNotEmpty) b.folder,
                            if (shared) 'Shared',
                            if (!widget.mine) 'Shared with you',
                            if (updated != null) shortDate(updated),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeRamp.caption(p.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onMore != null)
                    PressButton(
                      label: 'More for ${b.title}',
                      icon: CupertinoIcons.ellipsis,
                      iconOnly: true,
                      quiet: true,
                      height: 36,
                      onTap: widget.onMore,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderSheet extends StatefulWidget {
  const _FolderSheet({required this.folders, required this.current});

  final List<String> folders;
  final String current;

  @override
  State<_FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends State<_FolderSheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Move to a folder',
      action: PressButton(
        label: 'Move to a new folder',
        prominent: true,
        height: 48,
        expand: true,
        onTap: () {
          final name = _name.text.trim();
          if (name.isNotEmpty) Navigator.of(context).pop(name);
        },
      ),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SelectChip(
              label: 'No folder',
              selected: widget.current.isEmpty,
              onTap: () => Navigator.of(context).pop(''),
            ),
            for (final f in widget.folders)
              SelectChip(
                label: f,
                selected: widget.current == f,
                onTap: () => Navigator.of(context).pop(f),
              ),
          ],
        ),
        const SizedBox(height: 14),
        GlassField(label: 'Or name a new folder', controller: _name),
        const SizedBox(height: 6),
        Text(
          'Folders are just for you; sharing doesn’t show them.',
          style: TypeRamp.caption(p.inkSoft),
        ),
      ],
    );
  }
}

/// Who besides its owner can see or change a board.
class ShareBoardSheet extends StatefulWidget {
  const ShareBoardSheet({
    super.key,
    required this.backend,
    required this.board,
    required this.overview,
  });

  final Backend backend;
  final KanvasBoard board;
  final Overview overview;

  @override
  State<ShareBoardSheet> createState() => _ShareBoardSheetState();
}

class _ShareBoardSheetState extends State<ShareBoardSheet> {
  late final _people = Map<String, ShareMode>.of(widget.board.people);
  late var _classroomId = widget.board.classroomId;
  late var _classroomMode = widget.board.classroomMode;
  var _saving = false;
  String? _message;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.backend.shareBoard(
        widget.board.id,
        people: _people,
        classroomId: _classroomId,
        classroomMode: _classroomMode,
      );
      if (mounted) Navigator.of(context).pop();
    } on BackendFailure catch (e) {
      setState(() {
        _saving = false;
        _message = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = widget.backend.currentUser?.uid ?? '';
    // People this person shares a classroom with.
    final names = <String, String>{};
    for (final r in widget.overview.rooms) {
      for (final m in r.state.members) {
        if (m.uid != me) names[m.uid] = m.name;
      }
    }
    final people = names.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final rooms = [
      for (final r in widget.overview.rooms)
        if (!r.classroom.individual) r.classroom,
    ];
    Widget modeChips(ShareMode? mode, ValueChanged<ShareMode?> onChange) =>
        Wrap(
          spacing: 4,
          children: [
            SelectChip(
              label: 'No',
              selected: mode == null,
              onTap: () => onChange(null),
            ),
            SelectChip(
              label: 'Can look',
              selected: mode == ShareMode.view,
              onTap: () => onChange(ShareMode.view),
            ),
            SelectChip(
              label: 'Can edit',
              selected: mode == ShareMode.edit,
              onTap: () => onChange(ShareMode.edit),
            ),
          ],
        );
    return SheetFrame(
      title: 'Share “${widget.board.title}”',
      message: _message,
      action: PressButton(
        label: _saving ? 'Saving' : 'Save sharing',
        prominent: true,
        height: 48,
        expand: true,
        onTap: _saving ? null : _save,
      ),
      children: [
        Text(
          'Private to you unless you choose someone here. Only you can change '
          'who it’s shared with.',
          style: TypeRamp.label(p.inkSoft),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text('A classroom', style: TypeRamp.label(p.inkSoft)),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SelectChip(
              label: 'None',
              selected: _classroomId.isEmpty,
              onTap: () => setState(() => _classroomId = ''),
            ),
            for (final c in rooms)
              SelectChip(
                label: c.title,
                selected: _classroomId == c.id,
                onTap: () => setState(() => _classroomId = c.id),
              ),
          ],
        ),
        if (_classroomId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 4,
              children: [
                SelectChip(
                  label: 'Everyone can look',
                  selected: _classroomMode == ShareMode.view,
                  onTap: () => setState(() => _classroomMode = ShareMode.view),
                ),
                SelectChip(
                  label: 'Everyone can edit',
                  selected: _classroomMode == ShareMode.edit,
                  onTap: () => setState(() => _classroomMode = ShareMode.edit),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text('People', style: TypeRamp.label(p.inkSoft)),
        ),
        if (people.isEmpty)
          Text(
            'Join a classroom with others to share boards with them.',
            style: TypeRamp.caption(p.inkSoft),
          ),
        for (final person in people)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(person.value, style: TypeRamp.body(p.ink)),
                ),
                modeChips(
                  _people[person.key],
                  (m) => setState(() {
                    if (m == null) {
                      _people.remove(person.key);
                    } else {
                      _people[person.key] = m;
                    }
                  }),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _IdeaClassroomSheet extends StatefulWidget {
  const _IdeaClassroomSheet({required this.count});

  final int count;

  @override
  State<_IdeaClassroomSheet> createState() => _IdeaClassroomSheetState();
}

class _IdeaClassroomSheetState extends State<_IdeaClassroomSheet> {
  final _title = TextEditingController();
  var _alone = true;
  String? _message;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Make a classroom',
      message: _message,
      action: PressButton(
        label:
            'Make it, with ${widget.count} '
            '${widget.count == 1 ? 'step' : 'steps'}',
        prominent: true,
        height: 48,
        expand: true,
        onTap: () {
          final title = _title.text.trim();
          if (title.isEmpty) {
            setState(() => _message = 'Give the classroom a name.');
            return;
          }
          Navigator.of(context).pop((title, _alone));
        },
      ),
      children: [
        Text(
          'Each note you picked becomes a step in an Ideas phase, yours to '
          'shape. The board stays as it is.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 12),
        GlassField(label: 'What do you need to finish?', controller: _title),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 7),
          child: Text('Who’s working on it', style: TypeRamp.label(p.inkSoft)),
        ),
        Wrap(
          spacing: 6,
          children: [
            SelectChip(
              label: 'Just me',
              selected: _alone,
              onTap: () => setState(() => _alone = true),
            ),
            SelectChip(
              label: 'A group',
              selected: !_alone,
              onTap: () => setState(() => _alone = false),
            ),
          ],
        ),
      ],
    );
  }
}
