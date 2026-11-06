import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../data/backend.dart';
import '../data/drive.dart';
import '../data/models.dart';
import '../screens/classroom_forms.dart';
import '../screens/step_collab.dart' show openLink;
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/hover_hint.dart';
import 'kanvas_files.dart';
import 'kanvas_model.dart';
import 'kanvas_painter.dart';

enum KTool {
  select('Select', CupertinoIcons.cursor_rays),
  hand('Move around', CupertinoIcons.hand_raised),
  pen('Pen', CupertinoIcons.pencil),
  sticky('Sticky note', CupertinoIcons.square_fill_on_square_fill),
  text('Text', CupertinoIcons.textformat),
  checklist('Checklist', CupertinoIcons.checkmark_square),
  box('Box', CupertinoIcons.square),
  ellipse('Ellipse', CupertinoIcons.circle),
  arrow('Arrow', CupertinoIcons.arrow_up_right),
  link('Link', CupertinoIcons.link),
  file('Image, PDF or video', CupertinoIcons.photo_on_rectangle),
  eraser('Eraser', CupertinoIcons.delete_left);

  const KTool(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _Op { none, pan, pinch, draw, erase, arrow, move, resize, marquee, create }

/// A note on a board, ready to become a step.
typedef IdeaNote = ({String title, String detail});

/// One Kanvas board, full screen. Its owner, and anyone it's shared with to
/// edit, can change it; everyone else it's shared with can look.
class KanvasScreen extends StatefulWidget {
  const KanvasScreen({
    super.key,
    required this.backend,
    required this.ownerUid,
    required this.boardId,
    this.onShare,
    this.onMakeClassroom,
    this.inClassroom = false,
  });

  final Backend backend;
  final String ownerUid;
  final String boardId;

  /// Opens the board's sharing settings. Only for its owner.
  final void Function(KanvasBoard board)? onShare;

  /// Turns the chosen notes into a new classroom.
  final Future<void> Function(List<IdeaNote> notes)? onMakeClassroom;

  /// Opened from a classroom the board is shared with.
  final bool inClassroom;

  @override
  State<KanvasScreen> createState() => _KanvasScreenState();
}

class _KanvasScreenState extends State<KanvasScreen> {
  final _camera = KanvasCamera();
  final _focus = FocusNode();
  StreamSubscription<KanvasBoard?>? _sub;
  KanvasBoard? _board;
  var _gone = false;
  List<KShape> _shapes = const [];
  final _undo = <List<KShape>>[];
  final _redo = <List<KShape>>[];
  var _tool = KTool.select;
  var _colour = KColour.yellow;
  var _selected = <String>{};
  var _framed = false;
  Size _viewport = Size.zero;

  // Gestures in progress.
  final _pointers = <int, Offset>{};
  var _op = _Op.none;
  Offset? _downWorld;
  Offset? _downScreen;
  List<KShape>? _before;
  final _stroke = <Offset>[];
  var _strokeWidth = 3.0;
  String? _arrowFrom;
  Offset? _arrowStart;
  Offset? _arrowEnd;
  String? _snap;
  Rect? _marquee;
  double? _pinchDistance;
  Offset? _pinchFocal;
  var _space = false;
  DateTime? _lastTapAt;
  Offset? _lastTapAt_;

  // Typing on a shape.
  String? _editingId;
  final _editor = TextEditingController();
  final _editorFocus = FocusNode();

  // Saving.
  Timer? _saveTimer;
  var _dirty = false;
  var _saving = false;
  String? _problem;
  DateTime? _lastVersion;

  /// What's under way, such as a file going to Drive.
  String? _working;

  /// Pictures of the board's image cards.
  late final _pictures = BoardPictures(widget.backend);

  String get _me => widget.backend.currentUser?.uid ?? '';
  bool get _canEdit =>
      _board?.canEdit(_me, inClassroom: widget.inClassroom) ?? false;
  bool get _owner => _board?.ownerUid == _me;

  @override
  void initState() {
    super.initState();
    _sub = widget.backend.watchBoard(widget.ownerUid, widget.boardId).listen((
      board,
    ) {
      if (!mounted) return;
      if (board == null) {
        setState(() => _gone = true);
        return;
      }
      final first = _board == null;
      setState(() {
        _board = board;
        // Someone else's change comes in when nothing of ours is waiting.
        if (first ||
            (!_dirty && _op == _Op.none && _editingId == null && !_saving)) {
          _shapes = board.shapes;
        }
      });
      if (first) _frame();
    }, onError: (Object _) => setState(() => _gone = true));
    _editorFocus.addListener(() {
      if (!_editorFocus.hasFocus && _editingId != null) _finishEditing();
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) unawaited(_save());
    unawaited(_sub?.cancel());
    _camera.dispose();
    _pictures.dispose();
    _focus.dispose();
    _editor.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  void _frame() {
    if (_viewport.isEmpty) return;
    final byId = {for (final s in _shapes) s.id: s};
    Rect? all;
    for (final s in _shapes) {
      final b = boundsOf(s, byId);
      all = all == null ? b : all.expandToInclude(b);
    }
    _camera.fit(
      all ?? Rect.zero,
      _viewport,
      padding: const EdgeInsets.fromLTRB(40, 100, 40, 120),
    );
    _framed = true;
  }

  // Changes and saving -------------------------------------------------------

  void _change(List<KShape> next, {List<KShape>? from}) {
    _undo.add(from ?? _shapes);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    setState(() => _shapes = next);
    _scheduleSave();
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), _save);
    setState(() {});
  }

  Future<void> _save() async {
    if (!_dirty || !_canEdit) return;
    _dirty = false;
    final shapes = _shapes;
    setState(() => _saving = true);
    try {
      await widget.backend.saveBoardShapes(
        widget.ownerUid,
        widget.boardId,
        shapes,
      );
      _problem = null;
      // A copy to go back to, at most every ten minutes of work.
      final now = DateTime.now();
      if (_lastVersion == null ||
          now.difference(_lastVersion!) > const Duration(minutes: 10)) {
        _lastVersion = now;
        unawaited(
          widget.backend
              .saveBoardVersion(widget.ownerUid, widget.boardId, shapes)
              .catchError((Object _) {}),
        );
      }
    } on BackendFailure catch (e) {
      _problem = e.message;
      _dirty = true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    _redo.add(_shapes);
    setState(() {
      _shapes = _undo.removeLast();
      _selected = _selected.intersection({for (final s in _shapes) s.id});
    });
    _scheduleSave();
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    _undo.add(_shapes);
    setState(() => _shapes = _redo.removeLast());
    _scheduleSave();
  }

  String _newId() =>
      's${DateTime.now().microsecondsSinceEpoch}'
      '${math.Random().nextInt(999)}';

  Map<String, KShape> get _byId => {for (final s in _shapes) s.id: s};

  KShape? _hit(Offset world) {
    final byId = _byId;
    final slop = 6 / _camera.scale;
    for (final s in _shapes.reversed) {
      if (hits(s, world, byId, slop: slop)) return s;
    }
    return null;
  }

  // Pointers -----------------------------------------------------------------

  void _onDown(PointerDownEvent e) {
    _focus.requestFocus();
    if (_editingId != null) _finishEditing();
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _cancelOp();
      _op = _Op.pinch;
      final pts = _pointers.values.toList();
      _pinchDistance = (pts[0] - pts[1]).distance;
      _pinchFocal = (pts[0] + pts[1]) / 2;
      return;
    }
    if (_pointers.length > 2) return;
    final world = _camera.toWorld(e.localPosition);
    _downWorld = world;
    _downScreen = e.localPosition;
    final middle = e.buttons & kMiddleMouseButton != 0;
    if (middle || _space || _tool == KTool.hand || !_canEdit) {
      _op = _Op.pan;
      if (!_canEdit && _tool == KTool.select) {
        final hit = _hit(world);
        if (hit?.opens ?? false) unawaited(_openLinkShape(hit!));
      }
      return;
    }
    switch (_tool) {
      case KTool.pen:
        _op = _Op.draw;
        _stroke
          ..clear()
          ..add(world);
        final pressure = e.kind == PointerDeviceKind.stylus
            ? (e.pressure.isFinite ? e.pressure : 0.5)
            : 0.5;
        _strokeWidth = 1.5 + 3.5 * pressure.clamp(0.0, 1.0);
      case KTool.eraser:
        _op = _Op.erase;
        _before = _shapes;
        _eraseAt(world);
      case KTool.arrow:
        _op = _Op.arrow;
        final from = shapeAt(_shapes, world);
        _arrowFrom = from?.id;
        _arrowStart = world;
        _arrowEnd = world;
      case KTool.select:
        _selectDown(world, e);
      case KTool.hand:
        _op = _Op.pan;
      default:
        _op = _Op.create;
    }
    setState(() {});
  }

  void _selectDown(Offset world, PointerDownEvent e) {
    final now = DateTime.now();
    final again =
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < const Duration(milliseconds: 320) &&
        _lastTapAt_ != null &&
        (_lastTapAt_! - e.localPosition).distance < 16;
    _lastTapAt = now;
    _lastTapAt_ = e.localPosition;
    // Dragging the handle of the one shape selected resizes it.
    if (_selected.length == 1) {
      final s = _byId[_selected.first];
      if (s != null &&
          s.isRect &&
          handleRect(
            s.rect,
            _camera.scale,
          ).inflate(6 / _camera.scale).contains(world)) {
        _op = _Op.resize;
        _before = _shapes;
        return;
      }
    }
    final hit = _hit(world);
    if (again && hit != null) {
      _op = _Op.none;
      if (hit.opens) {
        unawaited(_openLinkShape(hit));
      } else if (hit.holdsText) {
        _startEditing(hit.id);
      }
      return;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (hit != null) {
      if (shift) {
        final next = {..._selected};
        if (!next.remove(hit.id)) next.add(hit.id);
        _selected = next;
      } else if (!_selected.contains(hit.id)) {
        _selected = {hit.id};
      }
      _op = _Op.move;
      _before = _shapes;
    } else {
      if (!shift) _selected = {};
      _op = _Op.marquee;
      _marquee = Rect.fromPoints(world, world);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_op == _Op.pinch && _pointers.length >= 2) {
      final pts = _pointers.values.take(2).toList();
      final distance = (pts[0] - pts[1]).distance;
      final focal = (pts[0] + pts[1]) / 2;
      if (_pinchFocal != null) _camera.panBy(focal - _pinchFocal!);
      if (_pinchDistance != null && _pinchDistance! > 0) {
        _camera.zoomAround(focal, distance / _pinchDistance!);
      }
      _pinchDistance = distance;
      _pinchFocal = focal;
      return;
    }
    final world = _camera.toWorld(e.localPosition);
    switch (_op) {
      case _Op.pan:
        _camera.panBy(e.delta);
      case _Op.draw:
        if ((world - _stroke.last).distance > 0.6 / _camera.scale) {
          setState(() => _stroke.add(world));
        }
      case _Op.erase:
        _eraseAt(world);
      case _Op.arrow:
        setState(() {
          _arrowEnd = world;
          _snap = shapeAt(_shapes, world, except: _arrowFrom ?? '')?.id;
        });
      case _Op.move:
        final d = world - _downWorld!;
        setState(() {
          _shapes = [
            for (final s in _before!) _selected.contains(s.id) ? s.moved(d) : s,
          ];
        });
      case _Op.resize:
        final id = _selected.first;
        setState(() {
          _shapes = [
            for (final s in _before!)
              if (s.id == id)
                s.copyWith(
                  rect: Rect.fromLTRB(
                    s.rect.left,
                    s.rect.top,
                    math.max(world.dx, s.rect.left + 40),
                    math.max(world.dy, s.rect.top + 30),
                  ),
                )
              else
                s,
          ];
        });
      case _Op.marquee || _Op.create:
        setState(() => _marquee = Rect.fromPoints(_downWorld!, world));
      default:
        break;
    }
  }

  void _onUp(PointerEvent e) {
    final was = _pointers.remove(e.pointer);
    if (was == null) return;
    if (_op == _Op.pinch) {
      if (_pointers.length < 2) {
        _op = _Op.none;
        _pinchDistance = null;
        _pinchFocal = null;
      }
      return;
    }
    final world = _camera.toWorld(e.localPosition);
    final moved =
        _downScreen != null && (e.localPosition - _downScreen!).distance > 4;
    switch (_op) {
      case _Op.draw:
        final points = simplify(List.of(_stroke), 0.6 / _camera.scale);
        _change([
          ..._shapes,
          KShape(
            id: _newId(),
            kind: ShapeKind.stroke,
            points: points,
            width: _strokeWidth,
            colour: _penColour,
          ),
        ]);
        _stroke.clear();
      case _Op.erase:
        if (!identical(_before, _shapes)) {
          _undo.add(_before!);
          _redo.clear();
          _scheduleSave();
        }
      case _Op.arrow:
        final a = _arrowStart!;
        final b = _arrowEnd!;
        if ((b - a).distance > 12 / _camera.scale) {
          _change([
            ..._shapes,
            KShape(
              id: _newId(),
              kind: ShapeKind.arrow,
              start: a,
              end: b,
              fromId: _arrowFrom ?? '',
              toId: _snap ?? '',
              colour: _penColour,
              width: 2.5,
            ),
          ]);
        }
        _arrowFrom = null;
        _arrowStart = null;
        _arrowEnd = null;
        _snap = null;
      case _Op.move:
        if (moved) {
          _undo.add(_before!);
          _redo.clear();
          _scheduleSave();
        } else {
          _tapChecklist(world);
        }
      case _Op.resize:
        _undo.add(_before!);
        _redo.clear();
        _scheduleSave();
      case _Op.marquee:
        final m = _marquee;
        if (m != null && moved) {
          final byId = _byId;
          _selected = {
            ..._selected,
            for (final s in _shapes)
              if (m.overlaps(boundsOf(s, byId))) s.id,
          };
        }
        _marquee = null;
      case _Op.create:
        final drag = moved ? _marquee : null;
        _marquee = null;
        unawaited(_create(_downWorld!, drag));
      default:
        break;
    }
    _op = _Op.none;
    _before = null;
    setState(() {});
  }

  void _cancelOp() {
    if (_before != null) _shapes = _before!;
    _before = null;
    _stroke.clear();
    _marquee = null;
    _arrowStart = null;
    _arrowEnd = null;
    _snap = null;
    _op = _Op.none;
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      _camera.zoomAround(e.localPosition, math.exp(-e.scrollDelta.dy / 300));
    } else {
      _camera.panBy(-e.scrollDelta);
    }
  }

  double _lastPadScale = 1;

  void _onPadStart(PointerPanZoomStartEvent e) => _lastPadScale = 1;

  void _onPadUpdate(PointerPanZoomUpdateEvent e) {
    _camera.panBy(e.panDelta);
    if (e.scale != _lastPadScale && _lastPadScale > 0) {
      _camera.zoomAround(e.localPosition, e.scale / _lastPadScale);
      _lastPadScale = e.scale;
    }
  }

  KColour get _penColour => _colour == KColour.yellow && _tool != KTool.sticky
      ? KColour.ink
      : _colour;

  void _eraseAt(Offset world) {
    final byId = _byId;
    final slop = 10 / _camera.scale;
    final gone = {
      for (final s in _shapes)
        if (hits(s, world, byId, slop: slop)) s.id,
    };
    if (gone.isEmpty) return;
    setState(() {
      _shapes = [
        // An arrow joined to something erased keeps its free end there.
        for (final s in _shapes)
          if (!gone.contains(s.id)) s,
      ];
      _selected = _selected.difference(gone);
    });
  }

  void _tapChecklist(Offset world) {
    final hit = _hit(world);
    if (hit == null || hit.kind != ShapeKind.checklist) return;
    final row = ((world.dy - hit.rect.top - 10) / checklistRow).floor();
    if (row < 0 || row >= hit.items.length) return;
    if (world.dx > hit.rect.left + 34) return;
    final items = [
      for (var i = 0; i < hit.items.length; i++)
        i == row
            ? CheckItem(hit.items[i].text, done: !hit.items[i].done)
            : hit.items[i],
    ];
    _change([
      for (final s in _shapes) s.id == hit.id ? s.copyWith(items: items) : s,
    ]);
  }

  Future<void> _create(Offset at, Rect? drag) async {
    final tool = _tool;
    Size size(double w, double h) => Size(w, h);
    final base = switch (tool) {
      KTool.sticky => size(180, 150),
      KTool.text => size(240, 44),
      KTool.checklist => size(240, 12 + 3 * checklistRow + 10),
      KTool.box => size(180, 100),
      KTool.ellipse => size(160, 110),
      KTool.link => size(260, 64),
      _ => size(160, 100),
    };
    final rect = drag != null && drag.width > 20 && drag.height > 20
        ? drag
        : Rect.fromLTWH(at.dx, at.dy, base.width, base.height);
    final id = _newId();
    KShape shape;
    switch (tool) {
      case KTool.sticky:
        shape = KShape(
          id: id,
          kind: ShapeKind.sticky,
          rect: rect,
          colour: _colour == KColour.ink ? KColour.yellow : _colour,
        );
      case KTool.text:
        shape = KShape(
          id: id,
          kind: ShapeKind.text,
          rect: rect,
          colour: _penColour,
        );
      case KTool.checklist:
        shape = KShape(
          id: id,
          kind: ShapeKind.checklist,
          rect: rect,
          items: const [CheckItem(''), CheckItem(''), CheckItem('')],
        );
      case KTool.box:
        shape = KShape(
          id: id,
          kind: ShapeKind.box,
          rect: rect,
          colour: _penColour,
          width: 2,
        );
      case KTool.ellipse:
        shape = KShape(
          id: id,
          kind: ShapeKind.ellipse,
          rect: rect,
          colour: _penColour,
          width: 2,
        );
      case KTool.link:
        final made = await showGlassSheet<(String, String)>(
          context,
          (_) => const _LinkSheet(),
        );
        if (made == null || !mounted) return;
        shape = KShape(
          id: id,
          kind: ShapeKind.link,
          rect: rect,
          url: made.$1,
          text: made.$2,
        );
      case KTool.file:
        final card = await _fileCard(id, at);
        if (card == null || !mounted) return;
        shape = card;
      default:
        return;
    }
    _change([..._shapes, shape]);
    setState(() {
      _selected = {id};
      _tool = KTool.select;
    });
    if (shape.holdsText) _startEditing(id);
  }

  // Typing -----------------------------------------------------------------

  void _startEditing(String id) {
    final s = _byId[id];
    if (s == null || !_canEdit) return;
    _editor.text = s.kind == ShapeKind.checklist
        ? s.items.map((i) => i.text).join('\n')
        : s.text;
    setState(() {
      _editingId = id;
      _selected = {id};
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocus.requestFocus();
    });
  }

  void _finishEditing() {
    final id = _editingId;
    if (id == null) return;
    final s = _byId[id];
    _editingId = null;
    if (s == null) {
      setState(() {});
      return;
    }
    final text = _editor.text;
    KShape? next;
    if (s.kind == ShapeKind.checklist) {
      final lines = text.split('\n').map((l) => l.trim()).toList();
      while (lines.isNotEmpty && lines.last.isEmpty) {
        lines.removeLast();
      }
      final items = [
        for (final line in lines)
          CheckItem(
            line,
            done: s.items.any(
              (i) => i.text == line && i.done && line.isNotEmpty,
            ),
          ),
      ];
      final rows = math.max(items.length, 1);
      next = s.copyWith(
        items: items.isEmpty ? const [CheckItem('')] : items,
        rect: Rect.fromLTWH(
          s.rect.left,
          s.rect.top,
          s.rect.width,
          math.max(s.rect.height, 12 + rows * checklistRow + 10),
        ),
      );
    } else if (s.kind == ShapeKind.text && text.trim().isEmpty) {
      next = null;
    } else {
      next = s.copyWith(text: text.trimRight());
    }
    final same =
        next != null &&
        next.text == s.text &&
        encodeShapes([next]) == encodeShapes([s]);
    if (same) {
      setState(() {});
      return;
    }
    _change([
      for (final x in _shapes)
        if (x.id != id) x else ?next,
    ]);
  }

  // Selection actions --------------------------------------------------------

  void _deleteSelected() {
    if (_selected.isEmpty || !_canEdit) return;
    final gone = _selected;
    _change([
      for (final s in _shapes)
        if (!gone.contains(s.id)) s,
    ]);
    setState(() => _selected = {});
  }

  void _duplicateSelected() {
    if (_selected.isEmpty || !_canEdit) return;
    final copies = <KShape>[];
    final ids = <String>{};
    for (final s in _shapes) {
      if (!_selected.contains(s.id)) continue;
      final id = _newId() + copies.length.toString();
      ids.add(id);
      copies.add(s.moved(const Offset(24, 24)).copyWith(id: id));
    }
    _change([..._shapes, ...copies]);
    setState(() => _selected = ids);
  }

  void _toFront() {
    final picked = [
      for (final s in _shapes)
        if (_selected.contains(s.id)) s,
    ];
    _change([
      for (final s in _shapes)
        if (!_selected.contains(s.id)) s,
      ...picked,
    ]);
  }

  void _recolour(KColour c) {
    setState(() => _colour = c);
    if (_selected.isEmpty) return;
    _change([
      for (final s in _shapes)
        _selected.contains(s.id) ? s.copyWith(colour: c) : s,
    ]);
  }

  /// Picks an image, PDF or video, puts it in the person's Drive and makes a
  /// card for it. An image keeps a small picture with the board.
  Future<KShape?> _fileCard(String id, Offset at) async {
    final board = _board;
    if (board == null) return null;
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: 'Add an image, PDF or video',
      );
    } on Object {
      setState(() => _problem = 'Files couldn’t be opened on this device.');
      return null;
    }
    if (picked == null || !mounted) return null;
    final size = await picked.length() ?? 0;
    if (size > kMaxUploadBytes) {
      setState(() => _problem = tooBig);
      return null;
    }
    if (!mounted) return null;
    final shared = board.classroomId.isNotEmpty || board.people.isNotEmpty;
    final open = await showGlassSheet<bool>(
      context,
      (_) =>
          _FileCardSheet(name: picked!.name, size: size, sharedBoard: shared),
    );
    if (open == null || !mounted) return null;
    setState(() {
      _problem = null;
      _working = 'Sending ${picked!.name} to your Drive…';
    });
    try {
      final bytes = await picked.readAsBytes();
      final mime = mimeTypeFor(picked.name);
      final preview = showsPicture(mime) ? await makePreview(bytes) : null;
      final up = await widget.backend.drive.upload(
        name: picked.name,
        mimeType: mime,
        bytes: bytes,
        folder: 'Kanvas',
        anyoneWithLink: open,
      );
      if (preview != null) {
        await _pictures.put(up.id, preview.jpeg);
        try {
          await widget.backend.saveBoardPreview(
            widget.ownerUid,
            widget.boardId,
            up.id,
            preview.jpeg,
          );
        } on BackendFailure {
          // The card still works; others see its icon instead of a picture.
        }
      }
      return KShape(
        id: id,
        kind: ShapeKind.file,
        rect: cardRect(
          at,
          mime,
          width: preview?.width,
          height: preview?.height,
        ),
        url: up.url,
        text: up.name,
        fileId: up.id,
        mime: up.mimeType,
        bytes: up.size,
      );
    } on DriveFailure catch (e) {
      if (mounted && !e.cancelled) setState(() => _problem = e.message);
      return null;
    } on Object {
      if (mounted) {
        setState(
          () => _problem =
              'The file couldn’t be sent to Drive. Check your connection.',
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _openLinkShape(KShape s) async {
    final ok = await openLink(s.url);
    if (!ok && mounted) {
      setState(() => _problem = 'That link couldn’t be opened.');
    }
  }

  /// Each written note becomes a step: its first line the title, the rest the
  /// description. Each checklist item becomes a step of its own.
  List<IdeaNote> get _selectedNotes {
    final notes = <IdeaNote>[];
    for (final s in _shapes) {
      if (!_selected.contains(s.id)) continue;
      if (s.kind == ShapeKind.checklist) {
        for (final i in s.items) {
          if (i.text.trim().isNotEmpty) {
            notes.add((title: i.text.trim(), detail: ''));
          }
        }
      } else if (s.holdsText && s.text.trim().isNotEmpty) {
        final lines = s.text.trim().split('\n');
        notes.add((
          title: lines.first.trim(),
          detail: lines.skip(1).join('\n').trim(),
        ));
      }
    }
    return notes;
  }

  Future<void> _makeClassroom() async {
    final notes = _selectedNotes;
    final make = widget.onMakeClassroom;
    if (make == null) return;
    if (notes.isEmpty) {
      setState(
        () => _problem = 'Select notes with writing on them to make steps.',
      );
      return;
    }
    await make(notes);
  }

  Future<void> _showVersions() async {
    final shapes = await showGlassSheet<List<KShape>>(
      context,
      (_) => _VersionsSheet(
        backend: widget.backend,
        ownerUid: widget.ownerUid,
        boardId: widget.boardId,
        me: _me,
        canRestore: _canEdit,
      ),
    );
    if (shapes == null || !mounted) return;
    _change(shapes);
    setState(() => _selected = {});
  }

  Future<void> _rename() async {
    final board = _board;
    if (board == null || !_owner) return;
    final title = await showGlassSheet<String>(
      context,
      (_) => KanvasNameSheet(title: 'Rename board', initial: board.title),
    );
    if (title == null) return;
    try {
      await widget.backend.updateBoardInfo(board.id, title: title);
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (_editingId != null) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _space = e is! KeyUpEvent;
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final command = keys.isControlPressed || keys.isMetaPressed;
    if (command && key == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? _redoOnce() : _undoOnce();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      _redoOnce();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyD) {
      _duplicateSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _deleteSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _selected = {};
        _tool = KTool.select;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final media = MediaQuery.of(context);
    final board = _board;
    _pictures.want(widget.ownerUid, widget.boardId, _shapes);
    final status = !_canEdit
        ? 'Shared with you to read'
        : (_problem ?? _working ?? (_saving || _dirty ? 'Saving…' : 'Saved'));
    final live = _op == _Op.draw && _stroke.isNotEmpty
        ? KShape(
            id: '_live',
            kind: ShapeKind.stroke,
            points: List.of(_stroke),
            width: _strokeWidth,
            colour: _penColour,
          )
        : null;
    final liveArrow = _arrowStart != null && _arrowEnd != null
        ? KShape(
            id: '_arrow',
            kind: ShapeKind.arrow,
            start: _arrowStart!,
            end: _arrowEnd!,
            fromId: _arrowFrom ?? '',
            toId: _snap ?? '',
            colour: _penColour,
            width: 2.5,
          )
        : null;
    return CupertinoPageScaffold(
      backgroundColor: p.ground,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, box) {
            _viewport = box.biggest;
            if (!_framed && board != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_framed) setState(_frame);
              });
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onDown,
                    onPointerMove: _onMove,
                    onPointerUp: _onUp,
                    onPointerCancel: _onUp,
                    onPointerSignal: _onSignal,
                    onPointerPanZoomStart: _onPadStart,
                    onPointerPanZoomUpdate: _onPadUpdate,
                    child: MouseRegion(
                      cursor: _tool == KTool.hand || _space
                          ? SystemMouseCursors.grab
                          : (_tool == KTool.select
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.precise),
                      child: Semantics(
                        label:
                            'Board ${board?.title ?? ''}, '
                            '${_shapes.length} items',
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: KanvasPainter(
                            shapes: _shapes,
                            camera: _camera,
                            palette: p,
                            pictures: _pictures,
                            overlay: KanvasOverlay(
                              selected: _selected,
                              marquee: _marquee,
                              liveStroke: live,
                              liveArrow: liveArrow,
                              snapTarget: _snap,
                              editingId: _editingId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (board != null && _shapes.isEmpty && _canEdit)
                  Center(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'An empty board. Pick a tool below: draw, add a '
                          'sticky note, or link a video. Double-tap a note to '
                          'write on it.',
                          textAlign: TextAlign.center,
                          style: TypeRamp.label(p.inkSoft),
                        ),
                      ),
                    ),
                  ),
                if (_gone)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'This board isn’t here any more, or isn’t shared with '
                        'you.',
                        textAlign: TextAlign.center,
                        style: TypeRamp.body(p.inkSoft),
                      ),
                    ),
                  ),
                if (_editingId != null) _editorField(p),
                Positioned(
                  left: 12,
                  right: 12,
                  top: media.padding.top + 10,
                  child: _header(p, board, status),
                ),
                if (_selected.isNotEmpty && _canEdit && _editingId == null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: media.padding.top + 72,
                    child: Center(child: _selectionBar(p)),
                  ),
                if (_canEdit)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: media.padding.bottom + 10,
                    child: Center(child: _toolbar(p)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(Palette p, KanvasBoard? board, String status) {
    return GlassPanel(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          PressButton(
            label: 'Back',
            icon: CupertinoIcons.chevron_left,
            iconOnly: true,
            quiet: true,
            height: 44,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _owner ? _rename : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    board?.title ?? 'Board',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.heading(p.ink),
                  ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.caption(
                      _problem != null && _canEdit ? p.blocked : p.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_canEdit) ...[
            PressButton(
              label: 'Undo',
              icon: CupertinoIcons.arrow_uturn_left,
              iconOnly: true,
              quiet: true,
              height: 44,
              onTap: _undo.isEmpty ? null : _undoOnce,
            ),
            PressButton(
              label: 'Redo',
              icon: CupertinoIcons.arrow_uturn_right,
              iconOnly: true,
              quiet: true,
              height: 44,
              onTap: _redo.isEmpty ? null : _redoOnce,
            ),
          ],
          PressButton(
            label: 'Fit the whole board',
            icon: CupertinoIcons.arrow_up_left_arrow_down_right,
            iconOnly: true,
            quiet: true,
            height: 44,
            onTap: () => setState(_frame),
          ),
          PressButton(
            label: 'Version history',
            icon: CupertinoIcons.clock,
            iconOnly: true,
            quiet: true,
            height: 44,
            onTap: _showVersions,
          ),
          if (_owner && widget.onShare != null && board != null)
            PressButton(
              label: 'Share',
              icon: CupertinoIcons.person_add,
              iconOnly: true,
              quiet: true,
              height: 44,
              onTap: () => widget.onShare!(board),
            ),
        ],
      ),
    );
  }

  Widget _swatches(Palette p) => Wrap(
    spacing: 4,
    children: [
      for (final c in KColour.values)
        HoverHint(
          message: c == KColour.ink
              ? 'Ink colour'
              : '${c.name[0].toUpperCase()}${c.name.substring(1)}',
          child: Semantics(
            button: true,
            selected: c == _colour,
            label: 'Colour ${c.name}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => _recolour(c),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _tool == KTool.sticky ? paperOf(c) : inkOf(c, p),
                  border: Border.all(
                    color: c == _colour ? p.accent : p.hairline,
                    width: c == _colour ? 2.5 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _toolbar(Palette p) {
    final colourful =
        _tool != KTool.select &&
        _tool != KTool.hand &&
        _tool != KTool.eraser &&
        _tool != KTool.link &&
        _tool != KTool.file &&
        _tool != KTool.checklist;
    return GlassPanel(
      radius: 24,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (colourful)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
              child: _swatches(p),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in KTool.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: PressButton(
                      label: t.label,
                      icon: t.icon,
                      iconOnly: true,
                      selected: t == _tool,
                      quiet: t != _tool,
                      height: 42,
                      onTap: () => setState(() {
                        _tool = t;
                        if (t == KTool.sticky && _colour == KColour.ink) {
                          _colour = KColour.yellow;
                        }
                        if (t != KTool.select) _selected = {};
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar(Palette p) {
    final selected = [
      for (final s in _shapes)
        if (_selected.contains(s.id)) s,
    ];
    final link = selected.length == 1 && selected.first.opens
        ? selected.first
        : null;
    final canWrite = selected.length == 1 && selected.first.holdsText;
    return GlassPanel(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _swatches(p),
            const SizedBox(width: 6),
            if (canWrite)
              PressButton(
                label: 'Write',
                icon: CupertinoIcons.pencil,
                iconOnly: true,
                quiet: true,
                height: 38,
                onTap: () => _startEditing(selected.first.id),
              ),
            if (link != null)
              PressButton(
                label: link.kind == ShapeKind.file
                    ? 'Open in Drive'
                    : 'Open link',
                icon: CupertinoIcons.arrow_up_right_square,
                iconOnly: true,
                quiet: true,
                height: 38,
                onTap: () => _openLinkShape(link),
              ),
            PressButton(
              label: 'Duplicate',
              icon: CupertinoIcons.plus_square_on_square,
              iconOnly: true,
              quiet: true,
              height: 38,
              onTap: _duplicateSelected,
            ),
            PressButton(
              label: 'Bring to front',
              icon: CupertinoIcons.square_stack_3d_up,
              iconOnly: true,
              quiet: true,
              height: 38,
              onTap: _toFront,
            ),
            if (widget.onMakeClassroom != null)
              PressButton(
                label: 'Make a classroom from these notes',
                icon: CupertinoIcons.rectangle_stack_badge_plus,
                iconOnly: true,
                quiet: true,
                height: 38,
                onTap: _makeClassroom,
              ),
            PressButton(
              label: 'Delete',
              icon: CupertinoIcons.trash,
              iconOnly: true,
              quiet: true,
              destructive: true,
              height: 38,
              onTap: _deleteSelected,
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorField(Palette p) {
    return AnimatedBuilder(
      animation: _camera,
      builder: (context, _) {
        final s = _byId[_editingId];
        if (s == null) return const SizedBox.shrink();
        final r = Rect.fromPoints(
          _camera.toScreen(s.rect.topLeft),
          _camera.toScreen(s.rect.bottomRight),
        );
        final checklist = s.kind == ShapeKind.checklist;
        final size = switch (s.kind) {
          ShapeKind.text => 18.0,
          ShapeKind.checklist => 14.0,
          _ => 15.0,
        };
        final ink = s.kind == ShapeKind.sticky
            ? const Color(0xFF2A2118)
            : p.ink;
        return Positioned(
          left: r.left,
          top: r.top,
          width: math.max(r.width, 120),
          height: math.max(r.height + (checklist ? 60 * _camera.scale : 0), 40),
          child: Container(
            decoration: BoxDecoration(
              color: checklist ? p.panel : null,
              borderRadius: BorderRadius.circular(10 * _camera.scale),
              border: Border.all(color: p.accent, width: 1.5),
            ),
            child: CupertinoTextField(
              controller: _editor,
              focusNode: _editorFocus,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              textAlign: s.kind == ShapeKind.box || s.kind == ShapeKind.ellipse
                  ? TextAlign.center
                  : TextAlign.start,
              placeholder: checklist ? 'One item per line' : 'Write here',
              padding: EdgeInsets.all(
                (s.kind == ShapeKind.text ? 4 : 12) * _camera.scale,
              ),
              decoration: null,
              style: TextStyle(
                fontFamily: TypeRamp.family,
                fontSize: size * _camera.scale,
                height: 1.3,
                color: ink,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Who can open a file put on a board, before it goes to Drive.
class _FileCardSheet extends StatefulWidget {
  const _FileCardSheet({
    required this.name,
    required this.size,
    required this.sharedBoard,
  });

  final String name;
  final int size;
  final bool sharedBoard;

  @override
  State<_FileCardSheet> createState() => _FileCardSheetState();
}

class _FileCardSheetState extends State<_FileCardSheet> {
  late var _open = widget.sharedBoard;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final picture = showsPicture(mimeTypeFor(widget.name));
    return SheetFrame(
      title: 'Add to the board',
      action: PressButton(
        label: 'Add to Drive and the board',
        icon: CupertinoIcons.cloud_upload,
        prominent: true,
        height: 48,
        expand: true,
        onTap: () => Navigator.of(context).pop(_open),
      ),
      children: [
        Text(widget.name, style: TypeRamp.body(p.ink)),
        Text(sizeLabel(widget.size), style: TypeRamp.caption(p.inkSoft)),
        const SizedBox(height: 14),
        Text('Who can open the file', style: TypeRamp.label(p.inkSoft)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SelectChip(
              label: 'Anyone who can see this board',
              selected: _open,
              onTap: () => setState(() => _open = true),
            ),
            SelectChip(
              label: 'Only me',
              selected: !_open,
              onTap: () => setState(() => _open = false),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          [
            'It goes in a Kanvas folder in your own Google Drive.',
            if (_open)
              'Anyone with its link can view it; the link is only on this '
                  'board.'
            else
              'Only you can open it.',
            if (picture)
              'A small picture of it stays with the board, so everyone who '
                  'can see the board sees it.',
          ].join(' '),
          style: TypeRamp.caption(p.inkFaint),
        ),
      ],
    );
  }
}

/// Adds a link, video or PDF card. Returns the address and a title.
class _LinkSheet extends StatefulWidget {
  const _LinkSheet();

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Add a link',
      message: _message,
      action: PressButton(
        label: 'Add to board',
        prominent: true,
        height: 48,
        expand: true,
        onTap: () {
          final address = webAddress(_url.text);
          if (address == null) {
            setState(
              () => _message = 'Paste a web address, starting with https.',
            );
            return;
          }
          Navigator.of(context).pop((address, _title.text.trim()));
        },
      ),
      children: [
        GlassField(
          label: 'Web address',
          controller: _url,
          keyboardType: TextInputType.url,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: 10),
        GlassField(label: 'Title (optional)', controller: _title),
        const SizedBox(height: 8),
        Text(
          'Videos, PDFs and pages open in their own app or tab. Uploading '
          'images and files arrives with Google Drive.',
          style: TypeRamp.caption(p.inkSoft),
        ),
      ],
    );
  }
}

/// A name for a board or folder.
class KanvasNameSheet extends StatefulWidget {
  const KanvasNameSheet({
    super.key,
    required this.title,
    this.initial = '',
    this.action = 'Save',
    this.label = 'Name',
  });

  final String title;
  final String initial;
  final String action;
  final String label;

  @override
  State<KanvasNameSheet> createState() => _KanvasNameSheetState();
}

class _KanvasNameSheetState extends State<KanvasNameSheet> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: widget.title,
    action: PressButton(
      label: widget.action,
      prominent: true,
      height: 48,
      expand: true,
      onTap: () => Navigator.of(context).pop(_name.text.trim()),
    ),
    children: [
      GlassField(
        label: widget.label,
        controller: _name,
        onSubmitted: (_) => Navigator.of(context).pop(_name.text.trim()),
      ),
    ],
  );
}

class _VersionsSheet extends StatelessWidget {
  const _VersionsSheet({
    required this.backend,
    required this.ownerUid,
    required this.boardId,
    required this.me,
    required this.canRestore,
  });

  final Backend backend;
  final String ownerUid;
  final String boardId;
  final String me;
  final bool canRestore;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return FutureBuilder<List<KanvasVersion>>(
      future: backend.boardVersions(ownerUid, boardId),
      builder: (context, snap) {
        final versions = snap.data ?? const <KanvasVersion>[];
        return SheetFrame(
          title: 'Version history',
          children: [
            Text(
              'A copy is kept every ten minutes or so while the board changes.',
              style: TypeRamp.caption(p.inkSoft),
            ),
            const SizedBox(height: 10),
            if (snap.connectionState != ConnectionState.done)
              const CupertinoActivityIndicator()
            else if (versions.isEmpty)
              Text('No saved copies yet.', style: TypeRamp.label(p.inkSoft))
            else
              for (final v in versions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exactTime(v.savedAt),
                              style: TypeRamp.body(p.ink),
                            ),
                            Text(
                              '${v.shapes.length} items · '
                              '${v.savedBy == me ? 'by you' : 'by someone it’s shared with'}',
                              style: TypeRamp.caption(p.inkSoft),
                            ),
                          ],
                        ),
                      ),
                      if (canRestore)
                        PressButton(
                          label: 'Go back to this',
                          height: 36,
                          onTap: () => Navigator.of(context).pop(v.shapes),
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
