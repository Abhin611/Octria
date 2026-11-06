import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/drive.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart';
import 'step_collab.dart';

/// Picks a file, asks who it's for, puts it in the person's own Drive and
/// adds it to the classroom's library. Returns a message to show, or null.
Future<String?> addLibraryFile(
  BuildContext context, {
  required Backend backend,
  required String classroomId,
  required String folder,
  required Plan plan,
  String stepId = '',
}) async {
  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(dialogTitle: 'Add a file');
  } on Object {
    return 'Files couldn’t be opened on this device.';
  }
  if (picked == null || !context.mounted) return null;
  final size = await picked.length() ?? 0;
  if (size > kMaxUploadBytes) return tooBig;
  if (!context.mounted) return null;
  final choice = await showGlassSheet<({bool shared, String stepId})>(
    context,
    (_) => _AddFileSheet(
      name: picked!.name,
      size: size,
      plan: plan,
      stepId: stepId,
    ),
  );
  if (choice == null) return null;
  try {
    final bytes = await picked.readAsBytes();
    final made = await backend.drive.upload(
      name: picked.name,
      mimeType: mimeTypeFor(picked.name),
      bytes: bytes,
      folder: folder,
      anyoneWithLink: choice.shared,
    );
    await backend.addFile(
      classroomId,
      LibraryFile(
        id: made.id,
        name: made.name,
        mimeType: made.mimeType,
        size: made.size,
        url: made.url,
        ownerUid: plan.meId,
        createdAt: DateTime.now(),
        stepId: choice.stepId,
        shared: choice.shared,
      ),
    );
    return null;
  } on DriveFailure catch (e) {
    return e.cancelled ? null : e.message;
  } on BackendFailure catch (e) {
    return e.message;
  } on Object {
    return 'The file couldn’t be sent to Drive. Check your connection and '
        'try again.';
  }
}

/// Who a new file is for, and which step, before it goes to Drive.
class _AddFileSheet extends StatefulWidget {
  const _AddFileSheet({
    required this.name,
    required this.size,
    required this.plan,
    required this.stepId,
  });

  final String name;
  final int size;
  final Plan plan;
  final String stepId;

  @override
  State<_AddFileSheet> createState() => _AddFileSheetState();
}

class _AddFileSheetState extends State<_AddFileSheet> {
  var _shared = true;
  late var _stepId = widget.stepId;
  var _sending = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mine = widget.plan.steps.values
        .where((s) => s.ownerId == widget.plan.meId)
        .toList();
    return SheetFrame(
      title: 'Add a file',
      action: PressButton(
        label: _sending ? 'Sending to your Drive…' : 'Add to Drive',
        icon: CupertinoIcons.cloud_upload,
        prominent: true,
        height: 48,
        expand: true,
        onTap: _sending
            ? null
            : () {
                setState(() => _sending = true);
                Navigator.of(context).pop((shared: _shared, stepId: _stepId));
              },
      ),
      children: [
        FileRow(
          name: widget.name,
          detail: sizeLabel(widget.size),
          mimeType: mimeTypeFor(widget.name),
        ),
        const SizedBox(height: 14),
        Text('Who can open it', style: TypeRamp.label(p.inkSoft)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SelectChip(
              label: 'Everyone in the classroom',
              selected: _shared,
              onTap: () => setState(() => _shared = true),
            ),
            SelectChip(
              label: 'Only me',
              selected: !_shared,
              onTap: () => setState(() => _shared = false),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _shared
              ? 'It goes in an Octria folder in your own Google Drive, and '
                    'anyone with its link can view it. The link is only shown '
                    'inside this classroom.'
              : 'It goes in an Octria folder in your own Google Drive, and '
                    'only you can open it.',
          style: TypeRamp.caption(p.inkFaint),
        ),
        if (widget.stepId.isEmpty && mine.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('For', style: TypeRamp.label(p.inkSoft)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SelectChip(
                label: 'The whole classroom',
                selected: _stepId.isEmpty,
                onTap: () => setState(() => _stepId = ''),
              ),
              for (final s in mine)
                SelectChip(
                  label: s.title,
                  selected: _stepId == s.id,
                  onTap: () => setState(() => _stepId = s.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

IconData _iconFor(FileKind kind) => switch (kind) {
  FileKind.pdf => CupertinoIcons.doc_richtext,
  FileKind.image => CupertinoIcons.photo,
  FileKind.video => CupertinoIcons.film,
  FileKind.audio => CupertinoIcons.music_note,
  FileKind.document => CupertinoIcons.doc_text,
  FileKind.sheet => CupertinoIcons.table,
  FileKind.slides => CupertinoIcons.rectangle_on_rectangle,
  FileKind.archive => CupertinoIcons.archivebox,
  FileKind.other => CupertinoIcons.doc,
};

Color _colourFor(Palette p, FileKind kind) => switch (kind) {
  FileKind.pdf => p.accentWarm,
  FileKind.image => p.accentTeal,
  FileKind.video => p.accentViolet,
  FileKind.audio => p.accentViolet,
  FileKind.sheet => p.done,
  FileKind.slides => p.accentWarm,
  _ => p.accent,
};

/// One file: its kind, name and a line about it. Tapping opens it in Drive.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.name,
    required this.detail,
    required this.mimeType,
    this.onOpen,
    this.trailing,
  });

  final String name;
  final String detail;
  final String mimeType;
  final VoidCallback? onOpen;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final kind = fileKindOf(mimeType);
    final colour = _colourFor(p, kind);
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
                button: onOpen != null,
                label: onOpen == null
                    ? '$name. $detail'
                    : 'Open $name. $detail',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: glassTint(p, colour, radius: 9),
                          child: Icon(_iconFor(kind), size: 16, color: colour),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TypeRamp.body(p.ink),
                              ),
                              Text(
                                detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TypeRamp.caption(p.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        if (onOpen != null)
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

/// The line under a file's name: who added it, its size and when.
String fileDetail(LibraryFile f, Plan plan, {bool withStep = true}) {
  final step = plan.steps[f.stepId];
  return [
    if (f.ownerUid == plan.meId) 'You' else nameIn(plan, f.ownerUid),
    sizeLabel(f.size),
    whenShort(f.createdAt, DateTime.now()),
    if (withStep && step != null) step.title,
    if (!f.shared) 'Only you',
  ].join(' · ');
}

/// What can be done with a file: open it, share or unshare it, remove it.
Future<String?> fileActions(
  BuildContext context, {
  required Backend backend,
  required String classroomId,
  required LibraryFile file,
  required Plan plan,
  required bool canManage,
}) async {
  final mine = file.ownerUid == plan.meId;
  String? message;
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } on DriveFailure catch (e) {
      if (!e.cancelled) message = e.message;
    } on BackendFailure catch (e) {
      message = e.message;
    }
  }

  await showGlassSheet<void>(
    context,
    (sheet) => ActionListSheet(
      title: file.name,
      items: [
        ('Open in Drive', 0, () => unawaited(openLink(file.url))),
        if (mine && !file.shared)
          (
            'Show to everyone in the classroom',
            0,
            () => run(() async {
              await backend.drive.setLinkSharing(file.id, on: true);
              await backend.updateFile(
                classroomId,
                file.copyWith(shared: true),
              );
            }),
          ),
        if (mine && file.shared)
          (
            'Keep it to myself',
            0,
            () => run(() async {
              await backend.updateFile(
                classroomId,
                file.copyWith(shared: false),
              );
              await backend.drive.setLinkSharing(file.id, on: false);
            }),
          ),
        if (mine || canManage)
          (
            'Remove from the library',
            0,
            () => run(() async {
              await backend.removeFile(classroomId, file.id);
              // Its owner's link stops working too; the file stays in Drive.
              if (mine && file.shared) {
                await backend.drive.setLinkSharing(file.id, on: false);
              }
            }),
          ),
      ],
    ),
  );
  return message;
}

/// The classroom's files, kept in each person's own Google Drive.
class FilesSheet extends StatefulWidget {
  const FilesSheet({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.classroomTitle,
    required this.plan,
    required this.canManage,
  });

  final Backend backend;
  final String classroomId;
  final String classroomTitle;
  final Plan plan;
  final bool canManage;

  @override
  State<FilesSheet> createState() => _FilesSheetState();
}

class _FilesSheetState extends State<FilesSheet> {
  late final Stream<List<LibraryFile>> _files = widget.backend.files(
    widget.classroomId,
  );
  String? _message;
  var _adding = false;
  var _query = '';

  Future<void> _add() async {
    setState(() {
      _adding = true;
      _message = null;
    });
    final said = await addLibraryFile(
      context,
      backend: widget.backend,
      classroomId: widget.classroomId,
      folder: widget.classroomTitle,
      plan: widget.plan,
    );
    if (mounted) {
      setState(() {
        _adding = false;
        _message = said;
      });
    }
  }

  Future<void> _actions(LibraryFile f) async {
    final said = await fileActions(
      context,
      backend: widget.backend,
      classroomId: widget.classroomId,
      file: f,
      plan: widget.plan,
      canManage: widget.canManage,
    );
    if (mounted && said != null) setState(() => _message = said);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<LibraryFile>>(
      stream: _files,
      builder: (context, snap) {
        final all = snap.data ?? const <LibraryFile>[];
        final q = _query.trim().toLowerCase();
        final shown = q.isEmpty
            ? all
            : all.where((f) => f.name.toLowerCase().contains(q)).toList();
        return SheetFrame(
          title: 'Files',
          message: _message,
          action: PressButton(
            label: _adding ? 'Adding…' : 'Add a file',
            icon: CupertinoIcons.plus,
            prominent: true,
            height: 48,
            expand: true,
            onTap: _adding ? null : _add,
          ),
          children: [
            Text(
              'Everyone’s files for this classroom. Each one stays in the '
              'Google Drive of whoever added it; Octria keeps only the link.',
              style: TypeRamp.label(p.inkSoft),
            ),
            if (all.length > 5) ...[
              const SizedBox(height: 12),
              CupertinoSearchTextField(
                placeholder: 'Search files',
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
            const SizedBox(height: 14),
            if (snap.hasData && all.isEmpty)
              Text(
                'No files yet. Add notes, slides, PDFs or pictures, and they '
                'go in your own Drive.',
                style: TypeRamp.caption(p.inkSoft),
              )
            else if (snap.hasData && shown.isEmpty)
              Text('Nothing matches.', style: TypeRamp.caption(p.inkSoft)),
            for (final f in shown)
              FileRow(
                name: f.name,
                detail: fileDetail(f, widget.plan),
                mimeType: f.mimeType,
                onOpen: () => unawaited(openLink(f.url)),
                trailing: PressButton(
                  label: 'More for ${f.name}',
                  icon: CupertinoIcons.ellipsis,
                  iconOnly: true,
                  quiet: true,
                  height: 44,
                  onTap: () => _actions(f),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A step's files, in the step's details. Everyone sees the shared ones; the
/// step's owner can add more.
class StepFiles extends StatefulWidget {
  const StepFiles({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.classroomTitle,
    required this.plan,
    required this.step,
    required this.canManage,
    required this.onNotice,
  });

  final Backend backend;
  final String classroomId;
  final String classroomTitle;
  final Plan plan;
  final PlanStep step;
  final bool canManage;
  final ValueChanged<String> onNotice;

  @override
  State<StepFiles> createState() => _StepFilesState();
}

class _StepFilesState extends State<StepFiles> {
  late final Stream<List<LibraryFile>> _files = widget.backend.files(
    widget.classroomId,
  );
  var _adding = false;

  bool get _mine => widget.step.ownerId == widget.plan.meId;

  Future<void> _add() async {
    setState(() => _adding = true);
    final said = await addLibraryFile(
      context,
      backend: widget.backend,
      classroomId: widget.classroomId,
      folder: widget.classroomTitle,
      plan: widget.plan,
      stepId: widget.step.id,
    );
    if (!mounted) return;
    setState(() => _adding = false);
    if (said != null) widget.onNotice(said);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<LibraryFile>>(
      stream: _files,
      builder: (context, snap) {
        final here = (snap.data ?? const <LibraryFile>[])
            .where((f) => f.stepId == widget.step.id)
            .toList();
        if (here.isEmpty && !_mine) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 8),
              child: Semantics(
                header: true,
                child: Text('Files', style: TypeRamp.label(p.inkSoft)),
              ),
            ),
            for (final f in here)
              FileRow(
                name: f.name,
                detail: fileDetail(f, widget.plan, withStep: false),
                mimeType: f.mimeType,
                onOpen: () => unawaited(openLink(f.url)),
                trailing: PressButton(
                  label: 'More for ${f.name}',
                  icon: CupertinoIcons.ellipsis,
                  iconOnly: true,
                  quiet: true,
                  height: 44,
                  onTap: () async {
                    final said = await fileActions(
                      context,
                      backend: widget.backend,
                      classroomId: widget.classroomId,
                      file: f,
                      plan: widget.plan,
                      canManage: widget.canManage,
                    );
                    if (said != null) widget.onNotice(said);
                  },
                ),
              ),
            if (_mine)
              Align(
                alignment: Alignment.centerLeft,
                child: PressButton(
                  label: _adding ? 'Adding…' : 'Add a file from your device',
                  icon: CupertinoIcons.paperclip,
                  quiet: true,
                  onTap: _adding ? null : _add,
                ),
              ),
            if (_mine && here.isEmpty)
              Text(
                'It goes in your own Google Drive, and everyone in the '
                'classroom can open it here.',
                style: TypeRamp.caption(p.inkFaint),
              ),
          ],
        );
      },
    );
  }
}
