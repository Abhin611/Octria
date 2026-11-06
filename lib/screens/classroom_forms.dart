import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/glass_menu.dart';
import '../widgets/glass_motion.dart';
import 'profile_stats.dart';

/// Opens a form as a sheet of thick glass: rising from the bottom on a phone,
/// centred on anything wider.
Future<T?> showGlassSheet<T>(BuildContext context, WidgetBuilder builder) {
  final back = SheetBack.take();
  return showCupertinoModalPopup<T>(
    context: context,
    // A soft tint, not a blur: blurring the whole screen lingers and lags.
    barrierColor: const Color(0x33000000),
    builder: (context) {
      final media = MediaQuery.of(context);
      final wide = media.size.width >= 600;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? 24 : 8,
          media.padding.top + 12,
          wide ? 24 : 8,
          media.viewInsets.bottom + media.padding.bottom + 8,
        ),
        child: Align(
          alignment: wide ? Alignment.center : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassArrival(
              child: GlassPanel(
                radius: 28,
                weight: GlassWeight.thick,
                child: DefaultTextStyle(
                  style: TypeRamp.body(Palette.of(context).ink),
                  child: back == null
                      ? builder(context)
                      : SheetBackScope(onBack: back, child: builder(context)),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Where a sheet opened from a menu goes back to. The menu arms it as it
/// closes, and the next sheet to open takes it.
abstract final class SheetBack {
  static VoidCallback? _pending;
  static DateTime? _at;

  static void arm(VoidCallback back) {
    _pending = back;
    _at = DateTime.now();
  }

  static VoidCallback? take() {
    final back = _pending;
    final at = _at;
    _pending = null;
    _at = null;
    if (back == null || at == null) return null;
    // Only a sheet opened straight from the menu goes back to it.
    if (DateTime.now().difference(at) > const Duration(seconds: 4)) return null;
    return back;
  }
}

/// Lets a sheet offer a Back button to the menu it came from.
class SheetBackScope extends InheritedWidget {
  const SheetBackScope({super.key, required this.onBack, required super.child});

  final VoidCallback onBack;

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetBackScope>()?.onBack;

  @override
  bool updateShouldNotify(SheetBackScope old) => false;
}

/// A Back button for a sheet opened from a menu; nothing otherwise.
Widget sheetBackButton(BuildContext context) {
  final back = SheetBackScope.of(context);
  if (back == null) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(right: 2),
    child: PressButton(
      label: 'Back',
      icon: CupertinoIcons.chevron_left,
      iconOnly: true,
      quiet: true,
      height: 44,
      onTap: () {
        Navigator.of(context).pop();
        back();
      },
    ),
  );
}

/// A sheet's title, close button, scrolling body and message line.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.children,
    this.action,
    this.message,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            SheetBackScope.of(context) == null ? 20 : 8,
            10,
            8,
            2,
          ),
          child: Row(
            children: [
              sheetBackButton(context),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: TypeRamp.title(p.ink)),
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
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            children: children,
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Semantics(
              liveRegion: true,
              child: Text(message!, style: TypeRamp.label(p.blocked)),
            ),
          ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: action!,
          ),
      ],
    );
  }
}

/// Asks before something that can't be undone.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
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
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Widget _label(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 7),
  child: Text(text, style: TypeRamp.label(Palette.of(context).inkSoft)),
);

/// A date shown as a button, opening a wheel beneath it.
class _DateField extends StatefulWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onClear;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final now = DateTime.now();
    final earliest = DateTime(now.year - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: PressButton(
                label: value == null
                    ? widget.label
                    : '${widget.label}: ${shortDate(value)}',
                icon: CupertinoIcons.calendar,
                height: 44,
                expand: true,
                onTap: () => setState(() => _open = !_open),
              ),
            ),
            if (value != null && widget.onClear != null)
              PressButton(
                label: 'Clear ${widget.label.toLowerCase()}',
                icon: CupertinoIcons.xmark_circle,
                iconOnly: true,
                quiet: true,
                height: 44,
                onTap: () {
                  widget.onClear!();
                  setState(() => _open = false);
                },
              ),
          ],
        ),
        if (_open)
          SizedBox(
            height: 160,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: value ?? now,
              minimumDate: value != null && value.isBefore(earliest)
                  ? value
                  : earliest,
              onDateTimeChanged: widget.onChanged,
            ),
          ),
      ],
    );
  }
}

// Classrooms ------------------------------------------------------------------

class CreateClassroomSheet extends StatefulWidget {
  const CreateClassroomSheet({super.key, required this.backend});
  final Backend backend;

  @override
  State<CreateClassroomSheet> createState() => _CreateClassroomSheetState();
}

class _CreateClassroomSheetState extends State<CreateClassroomSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _hours = TextEditingController();
  final _constraints = TextEditingController();
  var _type = TaskType.build;
  var _individual = false;
  DateTime? _deadline;
  String? _message;
  var _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hours.dispose();
    _constraints.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _message = 'Give the classroom a name.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await widget.backend.createClassroom(
        title: _title.text,
        description: _description.text,
        constraints: _constraints.text,
        taskType: _type,
        individual: _individual,
        deadline: _deadline,
        hoursPerWeek: double.tryParse(_hours.text.trim()),
      );
      if (mounted) Navigator.of(context).pop(id);
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
    return SheetFrame(
      title: 'New classroom',
      message: _message,
      action: PressButton(
        label: 'Create classroom',
        prominent: true,
        height: 44,
        expand: true,
        onTap: _busy ? null : _submit,
      ),
      children: [
        GlassField(label: 'What do you need to finish?', controller: _title),
        const SizedBox(height: 10),
        GlassField(
          label: 'Details (optional)',
          controller: _description,
          maxLines: 3,
        ),
        _label(context, 'Type of task'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in TaskType.values)
              SelectChip(
                label: t.label,
                selected: t == _type,
                onTap: () => setState(() => _type = t),
              ),
          ],
        ),
        _label(context, 'Who’s working on it'),
        Wrap(
          spacing: 6,
          children: [
            SelectChip(
              label: 'A group',
              selected: !_individual,
              onTap: () => setState(() => _individual = false),
            ),
            SelectChip(
              label: 'Just me',
              selected: _individual,
              onTap: () => setState(() => _individual = true),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DateField(
          label: 'Deadline',
          value: _deadline,
          onChanged: (d) => setState(() => _deadline = d),
          onClear: () => setState(() => _deadline = null),
        ),
        const SizedBox(height: 10),
        GlassField(
          label: 'Hours per week (optional)',
          controller: _hours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 10),
        _ConstraintField(controller: _constraints),
      ],
    );
  }
}

/// Anything the plan has to respect, in the person's own words. Optional.
class _ConstraintField extends StatelessWidget {
  const _ConstraintField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassField(
          label: 'Constraint description (optional)',
          controller: controller,
          maxLines: 3,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 5, 14, 0),
          child: Text(
            'Anything the plan must respect. For example: I have to study '
            'thermodynamics before waves.',
            style: TypeRamp.caption(p.inkSoft),
          ),
        ),
      ],
    );
  }
}

class JoinClassroomSheet extends StatefulWidget {
  const JoinClassroomSheet({
    super.key,
    required this.backend,
    this.initialCode,
  });

  final Backend backend;

  /// Filled in when someone arrives through an invite link.
  final String? initialCode;

  @override
  State<JoinClassroomSheet> createState() => _JoinClassroomSheetState();
}

class _JoinClassroomSheetState extends State<JoinClassroomSheet> {
  late final _code = TextEditingController(text: widget.initialCode);
  String? _message;
  var _busy = false;
  var _asked = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _message = 'Enter the code your master shared.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await widget.backend.joinWithCode(_code.text);
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _asked = true;
          _busy = false;
        });
      } else {
        Navigator.of(context).pop(id);
      }
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
    if (_asked) {
      return SheetFrame(
        title: 'Request sent',
        children: [
          Text(
            'The master needs to accept you. The classroom appears here once '
            'they have.',
            style: TypeRamp.body(Palette.of(context).ink),
          ),
        ],
      );
    }
    return SheetFrame(
      title: 'Join a classroom',
      message: _message,
      action: PressButton(
        label: 'Join',
        prominent: true,
        height: 44,
        expand: true,
        onTap: _busy ? null : _submit,
      ),
      children: [
        GlassField(
          label: 'Invite code',
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key, required this.backend, this.showStats = true});
  final Backend backend;

  /// Left out where the numbers are already on the page behind.
  final bool showStats;

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  late final _name = TextEditingController(
    text: widget.backend.currentUser?.name,
  );
  late final _bio = TextEditingController(
    text: widget.backend.currentUser?.bio,
  );
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _message = 'Your name can’t be empty.');
      return;
    }
    try {
      await widget.backend.saveProfile(name: _name.text, bio: _bio.text);
      if (mounted) Navigator.of(context).pop();
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final sure = await _confirm(
      context,
      title: 'Delete your account?',
      body:
          'This removes your profile and takes you out of every classroom. '
          'Classrooms where you’re the only member are deleted. Other classrooms '
          'keep your steps and past activity. It can’t be undone.',
      action: 'Delete account',
    );
    if (!sure) return;
    try {
      await widget.backend.deleteAccount();
      navigator.popUntil((route) => route.isFirst);
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final email = widget.backend.currentUser?.email ?? '';
    return SheetFrame(
      title: 'Your profile',
      message: _message,
      action: PressButton(
        label: 'Save',
        prominent: true,
        height: 44,
        expand: true,
        onTap: _save,
      ),
      children: [
        if (email.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(email, style: TypeRamp.label(p.inkSoft)),
          ),
        if (widget.showStats) ...[
          ProfileStats(backend: widget.backend),
          const SizedBox(height: 18),
        ],
        GlassField(label: 'Name', controller: _name),
        const SizedBox(height: 10),
        GlassField(label: 'About you', controller: _bio, maxLines: 3),
        const SizedBox(height: 18),
        PressButton(
          label: 'Sign out',
          height: 44,
          expand: true,
          onTap: () {
            // Out of any classroom too, back to where signing in happens.
            Navigator.of(context).popUntil((route) => route.isFirst);
            unawaited(widget.backend.signOut());
          },
        ),
        // Kept apart on purpose: nothing common sits near this.
        const SizedBox(height: 56),
        Align(
          alignment: Alignment.centerLeft,
          child: PressButton(
            label: 'Delete my account',
            destructive: true,
            quiet: true,
            onTap: _delete,
          ),
        ),
        const SizedBox(height: 10),
        Text('Version $kAppVersion', style: TypeRamp.caption(p.inkFaint)),
      ],
    );
  }
}

class ClassroomSettingsSheet extends StatefulWidget {
  const ClassroomSettingsSheet({
    super.key,
    required this.backend,
    required this.classroom,
  });

  final Backend backend;
  final Classroom classroom;

  @override
  State<ClassroomSettingsSheet> createState() => _ClassroomSettingsSheetState();
}

class _ClassroomSettingsSheetState extends State<ClassroomSettingsSheet> {
  late final _title = TextEditingController(text: widget.classroom.title);
  late final _description = TextEditingController(
    text: widget.classroom.description,
  );
  late final _hours = TextEditingController(
    text: widget.classroom.hoursPerWeek?.toString() ?? '',
  );
  late final _constraints = TextEditingController(
    text: widget.classroom.constraints,
  );
  late var _approval = widget.classroom.approvalRequired;
  late var _joinApproval = widget.classroom.joinApprovalRequired;
  late var _deadline = widget.classroom.deadline;
  String? _message;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hours.dispose();
    _constraints.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _message = 'Give the classroom a name.');
      return;
    }
    final c = widget.classroom;
    try {
      await widget.backend.updateClassroom(
        Classroom(
          id: c.id,
          title: _title.text.trim(),
          description: _description.text.trim(),
          constraints: _constraints.text.trim(),
          taskType: c.taskType,
          individual: c.individual,
          masterUid: c.masterUid,
          coMasterUids: c.coMasterUids,
          memberUids: c.memberUids,
          deadline: _deadline,
          hoursPerWeek: double.tryParse(_hours.text.trim()),
          inviteCode: c.inviteCode,
          approvalRequired: _approval,
          joinApprovalRequired: _joinApproval,
          createdAt: c.createdAt,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  Future<void> _deleteClassroom() async {
    final navigator = Navigator.of(context);
    final sure = await _confirm(
      context,
      title: 'Delete “${widget.classroom.title}”?',
      body:
          'This deletes its plan and activity for everyone in it. It can’t be '
          'undone.',
      action: 'Delete classroom',
    );
    if (!sure) return;
    try {
      await widget.backend.deleteClassroom(widget.classroom.id);
      // Out of the settings, and out of the classroom that no longer exists.
      navigator
        ..pop()
        ..pop();
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Classroom settings',
      message: _message,
      action: PressButton(
        label: 'Save',
        prominent: true,
        height: 44,
        expand: true,
        onTap: _save,
      ),
      children: [
        GlassField(label: 'Name', controller: _title),
        const SizedBox(height: 10),
        GlassField(label: 'Details', controller: _description, maxLines: 3),
        const SizedBox(height: 10),
        _DateField(
          label: 'Deadline',
          value: _deadline,
          onChanged: (d) => setState(() => _deadline = d),
          onClear: () => setState(() => _deadline = null),
        ),
        const SizedBox(height: 10),
        GlassField(
          label: 'Hours per week',
          controller: _hours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 10),
        _ConstraintField(controller: _constraints),
        if (!widget.classroom.individual) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Finished steps need approval from you or the co-master',
                  style: TypeRamp.body(p.ink),
                ),
              ),
              const SizedBox(width: 10),
              CupertinoSwitch(
                value: _approval,
                onChanged: (v) => setState(() => _approval = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'People with the code need your approval to join',
                  style: TypeRamp.body(p.ink),
                ),
              ),
              const SizedBox(width: 10),
              CupertinoSwitch(
                value: _joinApproval,
                onChanged: (v) => setState(() => _joinApproval = v),
              ),
            ],
          ),
        ],
        // Kept apart on purpose: nothing common sits near this.
        const SizedBox(height: 56),
        Align(
          alignment: Alignment.centerLeft,
          child: PressButton(
            label: 'Delete classroom',
            destructive: true,
            quiet: true,
            onTap: _deleteClassroom,
          ),
        ),
      ],
    );
  }
}

// People ----------------------------------------------------------------------

/// Who's in the classroom, its invite code, and the master's controls for both.
class MembersSheet extends StatefulWidget {
  const MembersSheet({super.key, required this.backend, required this.state});

  final Backend backend;
  final ClassroomState state;

  @override
  State<MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<MembersSheet> {
  late var _classroom = widget.state.classroom;
  late var _members = widget.state.members;
  String? _message;
  var _copied = false;
  var _linkCopied = false;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    }
  }

  Future<void> _remove(ClassroomMember m) async {
    final sure = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Remove ${m.name}?'),
        content: const Text(
          'They lose access to this classroom. Their steps stay in the plan, '
          'under you, until you hand them to someone else.',
        ),
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
    );
    if (sure != true) return;
    await _run(() async {
      await widget.backend.removeMember(_classroom.id, m.uid);
      if (mounted) {
        setState(() {
          _members = _members.where((x) => x.uid != m.uid).toList();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final me = widget.backend.currentUser?.uid ?? '';
    final isMaster = _classroom.masterUid == me;
    final code = _classroom.inviteCode;
    return SheetFrame(
      title: 'Members',
      message: _message,
      children: [
        if (!_classroom.individual) ...[
          Text(
            'Share this code. People enter it under Join.',
            style: TypeRamp.label(p.inkSoft),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Invite code ${code.split('').join(' ')}',
                  excludeSemantics: true,
                  child: Text(
                    code,
                    style: TypeRamp.title(p.ink).copyWith(letterSpacing: 2),
                  ),
                ),
              ),
              PressButton(
                label: _copied ? 'Copied' : 'Copy code',
                icon: _copied
                    ? CupertinoIcons.checkmark_alt
                    : CupertinoIcons.doc_on_doc,
                height: 36,
                onTap: () {
                  unawaited(Clipboard.setData(ClipboardData(text: code)));
                  setState(() => _copied = true);
                },
              ),
              const SizedBox(width: 6),
              PressButton(
                label: _linkCopied ? 'Copied' : 'Copy link',
                icon: _linkCopied
                    ? CupertinoIcons.checkmark_alt
                    : CupertinoIcons.link,
                height: 36,
                onTap: () {
                  unawaited(
                    Clipboard.setData(
                      ClipboardData(text: '$kAppUrl/?join=$code'),
                    ),
                  );
                  setState(() => _linkCopied = true);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_members.length} of $kMaxMembers places taken.',
            style: TypeRamp.caption(p.inkFaint),
          ),
          const SizedBox(height: 12),
        ],
        if (!_classroom.individual && _classroom.canManage(me))
          StreamBuilder<List<JoinRequest>>(
            stream: widget.backend.joinRequests(_classroom.id),
            builder: (context, snapshot) {
              final waiting = snapshot.data ?? const <JoinRequest>[];
              if (waiting.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Asking to join', style: TypeRamp.label(p.inkSoft)),
                  for (final r in waiting)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(r.name, style: TypeRamp.body(p.ink)),
                          ),
                          if (isMaster) ...[
                            PressButton(
                              label: 'Accept ${r.name}',
                              icon: CupertinoIcons.checkmark_alt,
                              iconOnly: true,
                              height: 36,
                              onTap: () => _run(() async {
                                await widget.backend.approveJoin(
                                  _classroom.id,
                                  r,
                                );
                                if (mounted) {
                                  setState(() {
                                    _members = [
                                      ..._members,
                                      ClassroomMember(uid: r.uid, name: r.name),
                                    ];
                                  });
                                }
                              }),
                            ),
                            const SizedBox(width: 6),
                            PressButton(
                              label: 'Decline ${r.name}',
                              icon: CupertinoIcons.xmark,
                              iconOnly: true,
                              quiet: true,
                              height: 36,
                              onTap: () => _run(
                                () => widget.backend.declineJoin(
                                  _classroom.id,
                                  r.uid,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              );
            },
          ),
        for (final m in _members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: TypeRamp.body(p.ink)),
                      Text(switch (_classroom.roleOf(m.uid)) {
                        MemberRole.master => 'Master',
                        MemberRole.coMaster => 'Co-master',
                        MemberRole.member => 'Member',
                      }, style: TypeRamp.caption(p.inkSoft)),
                    ],
                  ),
                ),
                if (isMaster && m.uid != me) ...[
                  PressButton(
                    label: _classroom.coMasterUids.contains(m.uid)
                        ? 'Make member'
                        : 'Make co-master',
                    quiet: true,
                    height: 36,
                    onTap: () {
                      final next = !_classroom.coMasterUids.contains(m.uid);
                      _run(() async {
                        await widget.backend.setCoMaster(
                          _classroom.id,
                          m.uid,
                          next,
                        );
                        if (!mounted) return;
                        final others = _classroom.coMasterUids.where(
                          (u) => u != m.uid,
                        );
                        setState(() {
                          _classroom = _classroom.copyWith(
                            coMasterUids: [...others, if (next) m.uid],
                          );
                        });
                      });
                    },
                  ),
                  PressButton(
                    label: 'Remove ${m.name}',
                    icon: CupertinoIcons.minus_circle,
                    iconOnly: true,
                    quiet: true,
                    destructive: true,
                    height: 36,
                    onTap: () => _remove(m),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// Phases ----------------------------------------------------------------------

class PhasesSheet extends StatefulWidget {
  const PhasesSheet({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.phases,
    required this.steps,
  });

  final Backend backend;
  final String classroomId;
  final List<PhaseRecord> phases;
  final List<PlanStep> steps;

  @override
  State<PhasesSheet> createState() => _PhasesSheetState();
}

class _PhasesSheetState extends State<PhasesSheet> {
  late var _phases = [...widget.phases];
  late var _steps = widget.steps;
  final _name = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _guard(Future<void> write) {
    unawaited(
      write.catchError((Object e) {
        if (mounted) setState(() => _message = '$e');
      }),
    );
  }

  void _add() {
    final title = _name.text.trim();
    if (title.isEmpty) {
      setState(() => _message = 'Name the phase first.');
      return;
    }
    final last = _phases.isEmpty ? 0 : _phases.last.order;
    final phase = PhaseRecord(
      id: widget.backend.newId(),
      title: title,
      order: last + 1,
    );
    _guard(widget.backend.savePhase(widget.classroomId, phase));
    setState(() {
      _phases = [..._phases, phase];
      _name.clear();
      _message = null;
    });
  }

  /// Swaps a phase with its neighbour, which is all reordering needs.
  void _move(int index, int by) {
    final a = _phases[index];
    final b = _phases[index + by];
    final movedA = PhaseRecord(id: a.id, title: a.title, order: b.order);
    final movedB = PhaseRecord(id: b.id, title: b.title, order: a.order);
    // Older phases may share an order; keep them apart.
    final fixedB = movedA.order == movedB.order
        ? PhaseRecord(id: b.id, title: b.title, order: a.order - by)
        : movedB;
    _guard(widget.backend.savePhase(widget.classroomId, movedA));
    _guard(widget.backend.savePhase(widget.classroomId, fixedB));
    setState(() {
      final next = [..._phases];
      next[index] = fixedB;
      next[index + by] = movedA;
      _phases = next;
    });
  }

  Future<void> _rename(PhaseRecord phase) async {
    final controller = TextEditingController(text: phase.title);
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Rename phase'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(controller: controller, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final next = PhaseRecord(id: phase.id, title: name, order: phase.order);
    _guard(widget.backend.savePhase(widget.classroomId, next));
    setState(() {
      _phases = [for (final p in _phases) p.id == phase.id ? next : p];
    });
  }

  Future<void> _delete(PhaseRecord phase) async {
    final count = _steps.where((s) => s.phaseId == phase.id).length;
    final sure = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete “${phase.title}”?'),
        content: Text(
          count == 0
              ? 'This phase has no steps.'
              : 'This also deletes its $count '
                    '${count == 1 ? "step" : "steps"}. It can’t be undone.',
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
    if (sure != true || !mounted) return;
    _guard(widget.backend.deletePhase(widget.classroomId, phase.id));
    setState(() {
      _phases = _phases.where((p) => p.id != phase.id).toList();
      _steps = _steps.where((s) => s.phaseId != phase.id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: 'Phases',
      message: _message,
      children: [
        if (_phases.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Phases are the big stages of the work, in order. Add the first.',
              style: TypeRamp.label(p.inkSoft),
            ),
          ),
        for (var i = 0; i < _phases.length; i++)
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Rename ${_phases[i].title}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _rename(_phases[i]),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _phases[i].title,
                          style: TypeRamp.body(p.ink),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (i > 0)
                PressButton(
                  label: 'Move ${_phases[i].title} earlier',
                  icon: CupertinoIcons.chevron_up,
                  iconOnly: true,
                  quiet: true,
                  height: 36,
                  onTap: () => _move(i, -1),
                ),
              if (i < _phases.length - 1)
                PressButton(
                  label: 'Move ${_phases[i].title} later',
                  icon: CupertinoIcons.chevron_down,
                  iconOnly: true,
                  quiet: true,
                  height: 36,
                  onTap: () => _move(i, 1),
                ),
              PressButton(
                label: 'Delete ${_phases[i].title}',
                icon: CupertinoIcons.minus_circle,
                iconOnly: true,
                quiet: true,
                destructive: true,
                height: 36,
                onTap: () => _delete(_phases[i]),
              ),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GlassField(
                label: 'New phase name',
                controller: _name,
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            PressButton(label: 'Add phase', height: 44, onTap: _add),
          ],
        ),
      ],
    );
  }
}

// Steps -----------------------------------------------------------------------

/// Adds a step when [step] is null, otherwise edits it. Pops with the result.
class StepEditorSheet extends StatefulWidget {
  const StepEditorSheet({
    super.key,
    required this.plan,
    required this.newId,
    required this.canAssignOthers,
    this.step,
    this.defaultPhaseId,
    this.defaultDue,
  });

  final Plan plan;
  final String Function() newId;
  final bool canAssignOthers;
  final PlanStep? step;
  final String? defaultPhaseId;
  final DateTime? defaultDue;

  @override
  State<StepEditorSheet> createState() => _StepEditorSheetState();
}

class _StepEditorSheetState extends State<StepEditorSheet> {
  late final _title = TextEditingController(text: widget.step?.title);
  late final _description = TextEditingController(
    text: widget.step?.description,
  );
  late final _hours = TextEditingController(
    text: _hoursText(widget.step?.estimateHours ?? 2),
  );
  late final _checklist = TextEditingController(
    text: widget.step?.checklist.map((c) => c.title).join('\n'),
  );
  late var _phaseId =
      widget.step?.phaseId ??
      widget.defaultPhaseId ??
      widget.plan.phases.first.id;
  late var _ownerId = widget.step?.ownerId ?? widget.plan.meId;
  late var _due =
      widget.step?.due ??
      widget.defaultDue ??
      DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 7));
  String? _message;

  /// Only the person whose step it is writes its description.
  bool get _writesDescription =>
      (widget.step?.ownerId ?? _ownerId) == widget.plan.meId;

  static String _hoursText(double h) =>
      h == h.roundToDouble() ? '${h.round()}' : '$h';

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hours.dispose();
    _checklist.dispose();
    super.dispose();
  }

  List<ChecklistItem> _items() {
    final before = widget.step?.checklist ?? const <ChecklistItem>[];
    return [
      for (final line in _checklist.text.split('\n'))
        if (line.trim().isNotEmpty)
          ChecklistItem(
            title: line.trim(),
            // Rewording the list keeps what's already ticked off.
            done: before.any((c) => c.title == line.trim() && c.done),
          ),
    ];
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _message = 'Give the step a name.');
      return;
    }
    final hours = double.tryParse(_hours.text.trim());
    if (hours == null || hours <= 0) {
      setState(() => _message = 'Estimate the hours as a number above 0.');
      return;
    }
    final existing = widget.step;
    final today = DateUtils.dateOnly(DateTime.now());
    final start = existing?.start ?? today;
    final result = existing == null
        ? PlanStep(
            id: widget.newId(),
            phaseId: _phaseId,
            ownerId: _ownerId,
            title: title,
            description: _writesDescription ? _description.text.trim() : '',
            estimateHours: hours,
            start: start.isAfter(_due) ? _due : start,
            due: _due,
            checklist: _items(),
            order: DateTime.now().millisecondsSinceEpoch,
          )
        : existing.copyWith(
            phaseId: _phaseId,
            ownerId: _ownerId,
            title: title,
            description: _writesDescription
                ? _description.text.trim()
                : existing.description,
            estimateHours: hours,
            start: start.isAfter(_due) ? _due : start,
            due: _due,
            checklist: _items(),
          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return SheetFrame(
      title: widget.step == null ? 'New step' : 'Edit step',
      message: _message,
      action: PressButton(
        label: widget.step == null ? 'Add step' : 'Save step',
        prominent: true,
        height: 44,
        expand: true,
        onTap: _save,
      ),
      children: [
        GlassField(label: 'What needs doing?', controller: _title),
        const SizedBox(height: 10),
        if (_writesDescription)
          GlassField(
            label: 'Description (optional)',
            controller: _description,
            maxLines: 3,
          )
        else
          Text(
            'Only the person whose step it is can write its description.',
            style: TypeRamp.caption(Palette.of(context).inkSoft),
          ),
        _label(context, 'Phase'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final phase in plan.phases)
              SelectChip(
                label: phase.title,
                selected: phase.id == _phaseId,
                onTap: () => setState(() => _phaseId = phase.id),
              ),
          ],
        ),
        if (widget.canAssignOthers && plan.members.length > 1) ...[
          _label(context, 'Owner'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in plan.members)
                SelectChip(
                  label: m.name,
                  selected: m.id == _ownerId,
                  onTap: () => setState(() => _ownerId = m.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _DateField(
          label: 'Due',
          value: _due,
          onChanged: (d) => setState(() => _due = DateUtils.dateOnly(d)),
        ),
        const SizedBox(height: 10),
        GlassField(
          label: 'Estimated hours',
          controller: _hours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 10),
        GlassField(
          label: 'Checklist, one item per line (optional)',
          controller: _checklist,
          maxLines: 4,
        ),
      ],
    );
  }
}

// Activity --------------------------------------------------------------------

/// What happened in a classroom, grouped by day. With [backend] and
/// [classroomId] set, the master can delete entries or clear the log.
class ActivitySheet extends StatefulWidget {
  const ActivitySheet({
    super.key,
    required this.title,
    required this.entries,
    this.intro,
    this.empty = 'Nothing has happened here yet.',
    this.newCount = 0,
    this.backend,
    this.classroomId,
    this.detailOf,
  });

  final String title;
  final String? intro;
  final String empty;
  final List<ActivityEntry> entries;
  final int newCount;
  final Backend? backend;
  final String? classroomId;

  /// A second line for an entry, such as which classroom it was in.
  final String? Function(ActivityEntry)? detailOf;

  @override
  State<ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<ActivitySheet> {
  late var _entries = widget.entries;
  String? _message;

  bool get _editable => widget.backend != null && widget.classroomId != null;

  Future<void> _delete(ActivityEntry entry) async {
    final before = _entries;
    setState(() {
      _entries = _entries.where((e) => e.id != entry.id).toList();
      _message = null;
    });
    try {
      await widget.backend!.deleteActivity(widget.classroomId!, entry.id);
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _entries = before;
          _message = e.message;
        });
      }
    }
  }

  Future<void> _clear() async {
    final sure = await _confirm(
      context,
      title: 'Clear all activity?',
      body:
          'This removes the whole log for everyone in this classroom. Steps '
          'and plans aren’t affected. It can’t be undone.',
      action: 'Clear',
    );
    if (!sure || !mounted) return;
    final before = _entries;
    setState(() => _entries = const []);
    try {
      await widget.backend!.clearActivity(widget.classroomId!);
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _entries = before;
          _message = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: widget.title,
      message: _message,
      children: [
        if (widget.intro != null && _entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(widget.intro!, style: TypeRamp.label(p.inkSoft)),
          ),
        ActivityGroups(
          entries: _entries,
          empty: widget.empty,
          newCount: widget.newCount,
          detailOf: widget.detailOf,
          onDelete: _editable ? _delete : null,
        ),
        if (_editable && _entries.isNotEmpty) ...[
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: PressButton(
              label: 'Clear all activity',
              destructive: true,
              quiet: true,
              onTap: _clear,
            ),
          ),
        ],
      ],
    );
  }
}

/// Entries under a heading for each day, newest day first. Only the latest day
/// starts open, so a long history stays out of the way until it's wanted.
class ActivityGroups extends StatefulWidget {
  const ActivityGroups({
    super.key,
    required this.entries,
    required this.empty,
    this.newCount = 0,
    this.detailOf,
    this.onDelete,
  });

  final List<ActivityEntry> entries;
  final String empty;
  final int newCount;

  /// A second line for an entry, such as which classroom it was in.
  final String? Function(ActivityEntry)? detailOf;
  final ValueChanged<ActivityEntry>? onDelete;

  @override
  State<ActivityGroups> createState() => _ActivityGroupsState();
}

class _ActivityGroupsState extends State<ActivityGroups> {
  final _toggled = <DateTime>{};

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// A day's entries by the hour they happened in, latest hour first.
  static List<(int, List<ActivityEntry>)> _byHour(List<ActivityEntry> items) {
    final hours = <int, List<ActivityEntry>>{};
    for (final e in items) {
      (hours[e.createdAt.hour] ??= []).add(e);
    }
    final ordered = hours.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final h in ordered) (h, hours[h]!)];
  }

  String _label(DateTime day) {
    final today = _day(DateTime.now());
    final difference = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return shortDate(day);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (widget.entries.isEmpty) {
      return Text(widget.empty, style: TypeRamp.body(p.inkSoft));
    }
    final days = <DateTime, List<ActivityEntry>>{};
    for (final e in widget.entries) {
      (days[_day(e.createdAt)] ??= []).add(e);
    }
    final fresh = widget.entries.take(widget.newCount).toSet();
    final ordered = days.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in ordered)
          () {
            final items = days[day]!;
            final hasNew = items.any(fresh.contains);
            final startsOpen = day == ordered.first || hasNew;
            final open = startsOpen != _toggled.contains(day);
            final count = items.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  expanded: open,
                  label:
                      '${_label(day)}, $count '
                      '${count == 1 ? 'activity' : 'activities'}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      if (!_toggled.remove(day)) _toggled.add(day);
                    }),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _label(day),
                              style: TypeRamp.heading(p.ink),
                            ),
                          ),
                          Text('$count', style: TypeRamp.caption(p.inkSoft)),
                          const SizedBox(width: 8),
                          AnimatedRotation(
                            turns: open ? 0.25 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: p.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: open
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (hour, inHour) in _byHour(items))
                              _HourGroup(
                                hour: hour,
                                count: inHour.length,
                                children: [
                                  for (final e in inHour)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _ActivityCard(
                                        entry: e,
                                        isNew: fresh.contains(e),
                                        detail: widget.detailOf?.call(e),
                                        onDelete: widget.onDelete == null
                                            ? null
                                            : () => widget.onDelete!(e),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            );
          }(),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.entry,
    required this.isNew,
    this.detail,
    this.onDelete,
  });

  final ActivityEntry entry;
  final bool isNew;
  final String? detail;
  final VoidCallback? onDelete;

  Color _colour(Palette p) => switch (entry.kind) {
    ActivityKind.stepFinished || ActivityKind.stepApproved => p.done,
    ActivityKind.stepStarted => p.doing,
    ActivityKind.stepSentForApproval => p.review,
    ActivityKind.stepRemoved || ActivityKind.stepSentBack => p.blocked,
    ActivityKind.memberJoined => p.accentTeal,
    ActivityKind.suggested || ActivityKind.suggestionAnswered => p.review,
    ActivityKind.stepHandedOver ||
    ActivityKind.dependencyChanged => p.accentViolet,
    _ => p.accent,
  };

  IconData get _icon => switch (entry.kind) {
    ActivityKind.stepAdded => CupertinoIcons.plus_circle,
    ActivityKind.stepEdited => CupertinoIcons.pencil,
    ActivityKind.stepRemoved => CupertinoIcons.trash,
    ActivityKind.stepStarted => CupertinoIcons.play_circle,
    ActivityKind.stepFinished => CupertinoIcons.checkmark_circle,
    ActivityKind.stepReopened => CupertinoIcons.arrow_counterclockwise,
    ActivityKind.stepSentForApproval => CupertinoIcons.hourglass,
    ActivityKind.stepApproved => CupertinoIcons.checkmark_seal,
    ActivityKind.stepSentBack => CupertinoIcons.arrow_uturn_left,
    ActivityKind.stepHandedOver => CupertinoIcons.arrow_right_arrow_left,
    ActivityKind.dependencyChanged => CupertinoIcons.link,
    ActivityKind.phaseChanged => CupertinoIcons.square_stack_3d_up,
    ActivityKind.memberJoined => CupertinoIcons.person,
    ActivityKind.commented => CupertinoIcons.chat_bubble,
    ActivityKind.suggested => CupertinoIcons.lightbulb,
    ActivityKind.suggestionAnswered => CupertinoIcons.hand_thumbsup,
    ActivityKind.materialAdded => CupertinoIcons.paperclip,
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final when = _clockTime(entry.createdAt);
    return Semantics(
      label: '${isNew ? 'New. ' : ''}${entry.summary}. $when',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isNew ? p.accent : p.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _colour(p).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_icon, size: 16, color: _colour(p)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.summary, style: TypeRamp.body(p.ink)),
                    const SizedBox(height: 3),
                    Text(
                      detail == null ? when : '$when · $detail',
                      style: TypeRamp.caption(p.inkSoft),
                    ),
                  ],
                ),
              ),
              if (isNew) ...[
                const SizedBox(width: 8),
                Text(
                  'New',
                  style: TypeRamp.caption(p.ink).weighted(FontWeight.w700),
                ),
              ],
              if (onDelete != null)
                SizedBox(
                  width: 36,
                  height: 24,
                  child: PressButton(
                    label: 'Delete this activity',
                    icon: CupertinoIcons.xmark,
                    iconOnly: true,
                    quiet: true,
                    height: 24,
                    onTap: onDelete,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "9 pm", for the hour an activity group covers.
String hourLabel(int hour) {
  final twelve = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelve ${hour < 12 ? 'am' : 'pm'}';
}

/// One hour of a day: a label and a line down the side tying its entries together.
class _HourGroup extends StatefulWidget {
  const _HourGroup({
    required this.hour,
    required this.count,
    required this.children,
  });

  final int hour;
  final int count;
  final List<Widget> children;

  @override
  State<_HourGroup> createState() => _HourGroupState();
}

class _HourGroupState extends State<_HourGroup> {
  var _open = true;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final words = widget.count == 1
        ? '1 activity'
        : '${widget.count} activities';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label:
              '${hourLabel(widget.hour)}, $words. '
              '${_open ? 'Tap to fold away' : 'Tap to show'}',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 7),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    hourLabel(widget.hour),
                    style: TypeRamp.label(p.ink).weighted(FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(words, style: TypeRamp.caption(p.inkSoft)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _open ? 0 : -0.25,
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 14,
                      color: p.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 1.5,
                        margin: const EdgeInsets.only(
                          left: 3.75,
                          right: 11,
                          bottom: 8,
                        ),
                        color: p.hairline,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: widget.children,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// The time of day, since the heading above already gives the date.
String _clockTime(DateTime d) {
  final full = exactTime(d);
  return full.substring(full.indexOf(', ') + 2);
}

/// A list of things to open, some with a red count. Used for the "More" tab.
class ActionListSheet extends StatelessWidget {
  const ActionListSheet({super.key, required this.title, required this.items});

  final String title;
  final List<(String, int, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SheetFrame(
      title: title,
      children: [
        GlassPanel(
          radius: 18,
          weight: GlassWeight.thin,
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (label, count, action)) in items.indexed) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Container(height: 0.5, color: p.hairline),
                  ),
                Semantics(
                  button: true,
                  label: count > 0 ? '$label, $count new' : label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).pop();
                      action();
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(label, style: TypeRamp.body(p.ink)),
                            ),
                            if (count > 0) ...[
                              CountBadge(
                                count: count,
                                child: const SizedBox(width: 15),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: p.inkFaint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A menu of grouped sections, each a pane of glass with icon rows.
class GlassMenuSheet extends StatelessWidget {
  const GlassMenuSheet({
    super.key,
    required this.title,
    required this.sections,
    this.onReopen,
  });

  final String title;
  final List<MenuSection> sections;

  /// Opens this menu again, for the Back button of whatever it opens.
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: title,
    children: [
      GlassMenuList(
        sections: sections,
        onDone: () {
          Navigator.of(context).pop();
          final reopen = onReopen;
          if (reopen != null) SheetBack.arm(reopen);
        },
      ),
    ],
  );
}

/// The people's view of [DateUtils] without pulling in Material.
abstract final class DateUtils {
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
