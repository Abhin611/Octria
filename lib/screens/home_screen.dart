import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../data/overview.dart';
import '../data/reminder_prefs.dart';
import '../model/reminders.dart';
import 'reminder_settings.dart';
import '../graph/graph_painter.dart';
import '../model/calendar.dart';
import '../model/plan.dart';
import 'calendar_sheet.dart';
import '../kanvas/kanvas_home.dart';
import 'requests_sheets.dart';
import '../platform/app_badge.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/glass_motion.dart';
import '../ofy/ofy.dart';
import '../widgets/hover_hint.dart';
import '../widgets/motion.dart';
import '../widgets/wide_page.dart';
import 'classroom_forms.dart';
import 'classroom_screen.dart';
import 'profile_stats.dart';
import 'room_lists.dart';

/// The code from an invite link, kept until someone is signed in to use it.
String? pendingJoinCode;

/// A screen wider than this gets a side rail instead of a bottom bar.
const double _railWidth = 840;
const double _railSize = 216;

enum _Tab {
  dashboard(
    'Dashboard',
    CupertinoIcons.square_grid_2x2,
    CupertinoIcons.square_grid_2x2_fill,
  ),
  activity(
    'Activity',
    CupertinoIcons.waveform_path_ecg,
    CupertinoIcons.waveform_path_ecg,
  ),
  chats(
    'Chats',
    CupertinoIcons.chat_bubble_2,
    CupertinoIcons.chat_bubble_2_fill,
  ),
  kanvas('Kanvas', CupertinoIcons.paintbrush, CupertinoIcons.paintbrush_fill),
  timeline('Timeline', CupertinoIcons.calendar, CupertinoIcons.calendar_today),
  done(
    'Done',
    CupertinoIcons.checkmark_seal,
    CupertinoIcons.checkmark_seal_fill,
  ),
  deleted('Deleted', CupertinoIcons.trash, CupertinoIcons.trash_fill),
  profile(
    'Profile',
    CupertinoIcons.person_crop_circle,
    CupertinoIcons.person_crop_circle_fill,
  );

  const _Tab(this.label, this.icon, this.iconOn);
  final String label;
  final IconData icon;
  final IconData iconOn;
}

/// Where someone arrives after signing in: their classrooms, what they've done,
/// what's coming up, and who they are, a tab apart.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.backend,
    required this.onBrightnessChanged,
  });

  final Backend backend;
  final ValueChanged<Brightness> onBrightnessChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _tab = _Tab.dashboard;
  late Future<Overview> _overview = loadOverview(widget.backend);
  StreamSubscription<List<Classroom>>? _rooms;
  var _firstRooms = true;

  @override
  void initState() {
    super.initState();
    // A classroom someone was just accepted into appears by itself.
    _rooms = widget.backend.classrooms().listen((_) {
      if (_firstRooms) {
        _firstRooms = false;
        return;
      }
      _reload();
    }, onError: (Object _) {});
    unawaited(_countImportant());
    final code = pendingJoinCode;
    if (code != null && code.isNotEmpty) {
      pendingJoinCode = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _join(code: code);
      });
    }
  }

  @override
  void dispose() {
    _ofy?.leave(this);
    unawaited(_rooms?.cancel());
    super.dispose();
  }

  Overview? _seen;
  Ofy? _ofy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ofy = OfyScope.maybeOf(context)?..enter(this, _ofyScreen);
  }

  late final OfyScreen _ofyScreen = OfyScreen(
    name: 'home',
    summary: () {
      final o = _seen;
      if (o == null) return 'The home pages are loading.';
      final next = o.next;
      return [
        'Tab open: ${_tab.label}.',
        'Classrooms: ${o.rooms.isEmpty ? 'none yet' : o.rooms.map((r) => r.classroom.title).join(', ')}.',
        if (next != null)
          'Your next step: “${next.step.title}” in ${next.room.title}, due '
              '${next.step.due.day}/${next.step.due.month}.',
        'Waiting on you: $_important. Unread notifications: ${o.unreadNotices}.',
      ].join('\n');
    },
    actions: [
      OfyAction(
        id: 'switch-tab',
        description:
            'Open a home tab: dashboard, activity, chats, kanvas, timeline, '
            'done, deleted or profile',
        params: const ['tab'],
        run: (args) async {
          final name = (args['tab'] ?? '').toLowerCase().trim();
          final tab = _Tab.values
              .where(
                (t) => name.startsWith(t.name) || t.label.toLowerCase() == name,
              )
              .firstOrNull;
          if (tab == null) return 'There’s no $name tab.';
          _select(tab);
          return 'Opened ${tab.label}.';
        },
      ),
      OfyAction(
        id: 'open-classroom',
        description: 'Open one of the person’s classrooms by name',
        params: const ['name'],
        run: (args) async {
          final want = (args['name'] ?? '').toLowerCase().trim();
          final rooms = _seen?.rooms ?? const <RoomSummary>[];
          bool named(RoomSummary r, String w) {
            final title = r.classroom.title.toLowerCase();
            return title == w || title.contains(w) || w.contains(title);
          }

          // Unnamed (as in a guide), the first classroom will do.
          final room = want.isEmpty
              ? rooms.firstOrNull
              : rooms.where((r) => named(r, want)).firstOrNull;
          if (room == null) return 'You don’t have a classroom called “$want”.';
          unawaited(_open(room.classroom.id));
          return 'Opened ${room.classroom.title}.';
        },
      ),
      OfyAction(
        id: 'create-classroom',
        description: 'Create a new classroom',
        params: const [
          'title',
          'type (build, study, research, event, other)',
          'just me (yes or no)',
        ],
        needsApproval: true,
        run: (args) async {
          final title = (args['title'] ?? '').trim();
          if (title.isEmpty) return 'It needs a name first.';
          final kind =
              (args['type (build, study, research, event, other)'] ??
                      args['type'] ??
                      '')
                  .toLowerCase();
          final type = kind.contains('stud') || kind.contains('exam')
              ? TaskType.study
              : kind.contains('research')
              ? TaskType.research
              : kind.contains('event') || kind.contains('creat')
              ? TaskType.eventOrCreative
              : kind.contains('build')
              ? TaskType.build
              : TaskType.other;
          final solo = (args['just me (yes or no)'] ?? args['just me'] ?? '')
              .toLowerCase()
              .startsWith('y');
          final id = await widget.backend.createClassroom(
            title: title,
            description: '',
            taskType: type,
            individual: solo,
          );
          unawaited(_open(id));
          return 'Created “$title” and opened it.';
        },
      ),
      OfyAction(
        id: 'toggle-theme',
        description: 'Switch between the light and dark background',
        run: (_) async {
          _toggleTheme();
          return 'Switched the background.';
        },
      ),
    ],
  );

  void _reload() {
    if (!mounted) return;
    setState(() {
      _overview = loadOverview(widget.backend);
    });
    unawaited(_countImportant());
  }

  /// How many requests wait on this person, across their classrooms.
  int _important = 0;

  List<RoomContext> _roomContexts(Overview o) {
    final me = widget.backend.currentUser?.uid ?? '';
    return [
      for (final r in o.rooms)
        if (!r.classroom.individual) RoomContext.of(r.state, me),
    ];
  }

  Future<void> _countImportant() async {
    try {
      final o = await _overview;
      _seen = o;
      final n = await importantCount(widget.backend, _roomContexts(o));
      if (mounted && n != _important) setState(() => _important = n);
      // The same two numbers as the bubble and the bell, on the app's icon.
      unawaited(setAppBadge(n + o.unreadNotices));
      // And the device's reminders follow the plan as it now stands.
      unawaited(syncReminders(o));
    } on Object {
      // The badge can wait for the next load.
    }
  }

  Future<void> _showImportant(Overview o) async {
    await showGlassSheet<void>(
      context,
      (_) => ImportantSheet(backend: widget.backend, rooms: _roomContexts(o)),
    );
    _reload();
  }

  DateTime _loadedAt = DateTime.now();

  void _select(_Tab tab) {
    setState(() => _tab = tab);
    // Every classroom is read again only when the numbers may be stale;
    // switching tabs alone shouldn't wait on the network.
    if (DateTime.now().difference(_loadedAt) > const Duration(seconds: 30)) {
      _loadedAt = DateTime.now();
      _reload();
    }
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(
      GlassRoute<void>(
        builder: (_) => ClassroomScreen(
          onBrightnessChanged: widget.onBrightnessChanged,
          session: ClassroomSession(backend: widget.backend, classroomId: id),
        ),
      ),
    );
    _reload();
  }

  Future<void> _create() async {
    final id = await showGlassSheet<String>(
      context,
      (_) => CreateClassroomSheet(backend: widget.backend),
    );
    if (id != null && mounted) unawaited(_open(id));
  }

  Future<void> _join({String? code}) async {
    final id = await showGlassSheet<String>(
      context,
      (_) => JoinClassroomSheet(backend: widget.backend, initialCode: code),
    );
    if (id != null && mounted) unawaited(_open(id));
  }

  void _showAdd() {
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ActionListSheet(
          title: 'Add a classroom',
          items: [
            ('Create a classroom', 0, _create),
            ('Join with a code', 0, _join),
          ],
        ),
      ),
    );
  }

  /// Opening them is what clears the red count.
  Future<void> _showNotifications(Overview o) async {
    final fresh = o.unreadNotices;
    unawaited(widget.backend.markNotificationsSeen().catchError((Object _) {}));
    final roomOf = {for (final n in o.notices) n.entry.id: n.room.title};
    await showGlassSheet<void>(
      context,
      (_) => ActivitySheet(
        title: 'Notifications',
        intro: 'What others did that affects you, newest first.',
        empty:
            'Nothing yet. You’ll hear here when someone comments on your '
            'steps, suggests a change, hands you a step or approves your work.',
        entries: [for (final n in o.notices) n.entry],
        newCount: fresh,
        detailOf: (e) => roomOf[e.id],
      ),
    );
    _reload();
  }

  void _toggleTheme() {
    final dark = Palette.of(context).brightness == Brightness.dark;
    widget.onBrightnessChanged(dark ? Brightness.light : Brightness.dark);
  }

  Widget _page(EdgeInsets insets) {
    return FutureBuilder<Overview>(
      future: _overview,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.hasError && data == null) {
          return _Message(
            'Your classrooms couldn’t load. Check your connection and try '
            'again.',
            insets: insets,
          );
        }
        if (data == null && _tab != _Tab.profile) {
          return const Center(child: CupertinoActivityIndicator());
        }
        return AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260),
          switchInCurve: Curves.linear,
          switchOutCurve: Curves.linear,
          layoutBuilder: onlyNewest,
          transitionBuilder: (child, animation) =>
              glassSwitch(child, animation, drift: 18),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: switch (_tab) {
              _Tab.dashboard => _DashboardPage(
                backend: widget.backend,
                overview: data!,
                insets: insets,
                onOpen: _open,
                onToggleTheme: _toggleTheme,
                onCreate: () => unawaited(_create()),
                onJoin: () => unawaited(_join()),
                onNotifications: () => _showNotifications(data),
                important: _important,
                onImportant: () => _showImportant(data),
                onTab: _select,
              ),
              _Tab.activity => _ActivityPage(
                backend: widget.backend,
                overview: data!,
                insets: insets,
                onOpen: _open,
                onChanged: _reload,
              ),
              _Tab.chats => _ListPage(
                insets: insets,
                title: 'Chats',
                detail: 'People and groups you talk with, by classroom.',
                icon: CupertinoIcons.chat_bubble_2,
                child: AllChats(backend: widget.backend, overview: data!),
              ),
              _Tab.done => _ListPage(
                insets: insets,
                title: 'Done',
                detail: 'Finished phases and steps, by classroom.',
                icon: CupertinoIcons.checkmark_seal,
                child: AllDone(
                  backend: widget.backend,
                  overview: data!,
                  onOpen: _open,
                ),
              ),
              _Tab.deleted => _ListPage(
                insets: insets,
                title: 'Deleted',
                detail:
                    'Steps, phases and chats that were deleted, ready to '
                    'bring back.',
                icon: CupertinoIcons.trash,
                child: AllDeleted(backend: widget.backend, overview: data!),
              ),
              _Tab.kanvas => KanvasHome(
                backend: widget.backend,
                overview: data!,
                insets: insets,
                onOpenClassroom: _open,
              ),
              _Tab.timeline => _TimelinePage(
                backend: widget.backend,
                overview: data!,
                insets: insets,
                onOpen: _open,
                onTab: _select,
              ),
              _Tab.profile => _ProfilePage(
                backend: widget.backend,
                insets: insets,
                onToggleTheme: _toggleTheme,
                onReminders: () => unawaited(syncReminders(data!, force: true)),
              ),
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final safe = MediaQuery.paddingOf(context);
    final wide = MediaQuery.sizeOf(context).width >= _railWidth;
    final insets = wide
        ? EdgeInsets.fromLTRB(
            _railSize + 36,
            safe.top + 24,
            24,
            safe.bottom + 24,
          )
        : EdgeInsets.fromLTRB(14, safe.top + 14, 14, safe.bottom + 92);
    return Stack(
      fit: StackFit.expand,
      children: [
        const AmbientBackdrop(),
        BackdropGroup(
          child: DefaultTextStyle(
            style: TypeRamp.body(p.ink),
            child: Stack(
              children: [
                Positioned.fill(child: _page(insets)),
                if (wide)
                  Positioned(
                    left: 12,
                    top: safe.top + 12,
                    bottom: safe.bottom + 12,
                    width: _railSize,
                    child: _Rail(tab: _tab, onSelect: _select, onAdd: _showAdd),
                  )
                else
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: safe.bottom + 10,
                    height: 64,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 540),
                        child: _BottomBar(
                          tab: _tab,
                          onSelect: _select,
                          onAdd: _showAdd,
                        ),
                      ),
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

// Navigation ------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tab,
    required this.onSelect,
    required this.onAdd,
  });

  final _Tab tab;
  final ValueChanged<_Tab> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget item(_Tab t) {
      final on = t == tab;
      return Expanded(
        child: OfyTarget(
          id: 'tab:${t.name}',
          child: Pressable(
            radius: 24,
            label: t.label,
            onTap: () => onSelect(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.all(4),
              decoration: on
                  ? glassTint(p, p.accent, radius: 24)
                  : BoxDecoration(
                      color: const Color(0x00000000),
                      border: Border.all(color: const Color(0x00000000)),
                      borderRadius: BorderRadius.circular(24),
                    ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    on ? t.iconOn : t.icon,
                    size: 21,
                    color: on ? p.accent : p.inkSoft,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    t.label,
                    maxLines: 1,
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.1),
                    style: TypeRamp.caption(on ? p.ink : p.inkSoft)
                        .copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GlassPanel(
      radius: 32,
      weight: GlassWeight.thin,
      child: Row(
        children: [
          item(_Tab.dashboard),
          item(_Tab.chats),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: OfyTarget(
              id: 'home:add',
              child: HoverHint(
                message: 'Add a classroom',
                child: Pressable(
                  label: 'Add a classroom',
                  onTap: onAdd,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [p.accent, p.accentViolet],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: p.accent.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      CupertinoIcons.plus,
                      color: p.brightness == Brightness.dark
                          ? p.ground
                          : const Color(0xFFFFFFFF),
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
          item(_Tab.kanvas),
          item(_Tab.timeline),
          _moreItem(context, p),
        ],
      ),
    );
  }

  static const _more = [_Tab.activity, _Tab.done, _Tab.deleted, _Tab.profile];

  /// Activity, Done, Deleted and the profile, one tap further on a phone.
  Widget _moreItem(BuildContext context, Palette p) {
    final on = _more.contains(tab);
    return Expanded(
      child: Pressable(
        radius: 24,
        label: 'More: activity, done, deleted and your profile',
        onTap: () => unawaited(
          showGlassSheet<void>(
            context,
            (_) => ActionListSheet(
              title: 'More',
              items: [for (final t in _more) (t.label, 0, () => onSelect(t))],
            ),
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(4),
          decoration: on
              ? glassTint(p, p.accent, radius: 24)
              : BoxDecoration(
                  color: const Color(0x00000000),
                  border: Border.all(color: const Color(0x00000000)),
                  borderRadius: BorderRadius.circular(24),
                ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                on ? tab.iconOn : CupertinoIcons.ellipsis_circle,
                size: 21,
                color: on ? p.accent : p.inkSoft,
              ),
              const SizedBox(height: 1),
              Text(
                on ? tab.label : 'More',
                maxLines: 1,
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.1),
                style: TypeRamp.caption(on ? p.ink : p.inkSoft)
                    .copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.tab, required this.onSelect, required this.onAdd});

  final _Tab tab;
  final ValueChanged<_Tab> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GlassPanel(
      radius: 24,
      weight: GlassWeight.thin,
      padding: const EdgeInsets.fromLTRB(12, 22, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 22),
            child: Text(
              'Octria',
              style: TypeRamp.title(p.ink).copyWith(fontSize: 24),
            ),
          ),
          SizedBox(
            height: _Tab.values.length * 44,
            child: Stack(
              children: [
                // One highlight that slides to the tab chosen.
                AnimatedPositioned(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  curve: Motion.out,
                  top: tab.index * 44.0,
                  left: 0,
                  right: 0,
                  height: 42,
                  child: DecoratedBox(
                    decoration: glassTint(p, p.accent, radius: 13),
                  ),
                ),
                Column(
                  children: [
                    for (final t in _Tab.values)
                      SizedBox(
                        height: 44,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: OfyTarget(
                            id: 'tab:${t.name}',
                            child: Pressable(
                              label: t.label,
                              radius: 13,
                              onTap: () => onSelect(t),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                ),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      t == tab ? t.iconOn : t.icon,
                                      size: 19,
                                      color: t == tab ? p.accent : p.inkSoft,
                                    ),
                                    const SizedBox(width: 11),
                                    Text(
                                      t.label,
                                      textScaler: MediaQuery.textScalerOf(
                                        context,
                                      ).clamp(maxScaleFactor: 1.3),
                                      style:
                                          TypeRamp.label(
                                            t == tab ? p.ink : p.inkSoft,
                                          ).weighted(
                                            t == tab
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          OfyTarget(
            id: 'home:add',
            child: PressButton(
              label: 'Add a classroom',
              icon: CupertinoIcons.plus,
              prominent: true,
              height: 44,
              expand: true,
              onTap: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

// Shared pieces ---------------------------------------------------------------

class _Message extends StatelessWidget {
  const _Message(this.text, {required this.insets});

  final String text;
  final EdgeInsets insets;

  @override
  Widget build(BuildContext context) => Padding(
    padding: insets,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TypeRamp.body(Palette.of(context).inkSoft),
        ),
      ),
    ),
  );
}

/// A page's scrolling column, kept to a readable width on big screens.
class _Page extends StatelessWidget {
  const _Page({
    required this.insets,
    required this.children,
    this.maxWidth = 1040,
  });

  final EdgeInsets insets;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return WidePage(
      insets: insets,
      maxWidth: maxWidth,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
          sliver: SliverList.list(children: children),
        ),
      ],
    );
  }
}

/// A small icon in a soft square of its own colour.
class _IconChip extends StatelessWidget {
  const _IconChip(this.icon, this.colour, {this.size = 32});

  final IconData icon;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: glassTint(Palette.of(context), colour, radius: size * 0.32),
    child: Icon(icon, size: size * 0.56, color: colour),
  );
}

/// A solid card with a fine edge, the home pages' one surface.
BoxDecoration _panel(Palette p, {double radius = 18}) => BoxDecoration(
  // Lit from above: a touch lighter at the top, like the glass around it.
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.lerp(
        p.panel,
        const Color(0xFFFFFFFF),
        p.brightness == Brightness.dark ? 0.07 : 0.3,
      )!,
      p.panel,
    ],
  ),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: p.hairline),
  boxShadow: [
    BoxShadow(
      color: p.shadow.withValues(alpha: p.shadow.a * 0.4),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: p.shadow.withValues(alpha: p.shadow.a * 0.7),
      blurRadius: 22,
      spreadRadius: -4,
      offset: const Offset(0, 8),
    ),
  ],
);

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.detail, this.icon});

  final String title;
  final String? detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            _IconChip(icon!, p.accent, size: 42),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TypeRamp.title(p.ink)
                        .copyWith(fontSize: 30, letterSpacing: -1),
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 3),
                  Text(detail!, style: TypeRamp.body(p.inkSoft)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a new person sees in place of an empty dashboard: what Octria does,
/// in three steps, and the two ways to begin.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onCreate, required this.onJoin});

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  static const _steps = [
    (
      CupertinoIcons.square_stack_3d_up,
      'Make a classroom',
      'One for each thing you need to finish: an exam, a project, a course.',
    ),
    (
      CupertinoIcons.sparkles,
      'Tell Ofy about it',
      'Describe it in your own words. Ofy drafts the phases and steps, '
          'with dates that fit your hours.',
    ),
    (
      CupertinoIcons.checkmark_seal,
      'Work through the steps',
      'Mark each one done as you go. Octria shows what’s next and '
          'reminds you what’s due.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: _panel(p, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Welcome to Octria',
              style: TypeRamp.title(p.ink).copyWith(fontSize: 22),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Octria turns something you need to finish into a plan you can '
            'see, then keeps you on it.',
            style: TypeRamp.body(p.inkSoft),
          ),
          const SizedBox(height: 16),
          for (final (i, (icon, title, text)) in _steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconChip(icon, [p.accent, p.accentViolet, p.done][i]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. $title',
                          style: TypeRamp.label(p.ink)
                              .weighted(FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(text, style: TypeRamp.label(p.inkSoft)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PressButton(
                label: 'Make my first classroom',
                icon: CupertinoIcons.plus,
                prominent: true,
                height: 46,
                onTap: onCreate,
              ),
              PressButton(
                label: 'Join with a code',
                icon: CupertinoIcons.person_crop_circle_badge_plus,
                quiet: true,
                height: 46,
                onTap: onJoin,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 9),
    child: Semantics(
      header: true,
      child: Text(title, style: TypeRamp.heading(Palette.of(context).ink)),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.icon, this.colour, {this.onTap});

  final String value;
  final String label;
  final IconData icon;
  final Color colour;

  /// Shows what the number counts.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tile = _tile(p);
    if (onTap == null) {
      return Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: tile,
      );
    }
    return Pressable(
      label: '$label: $value. Show them.',
      onTap: onTap!,
      child: tile,
    );
  }

  Widget _tile(Palette p) {
    return Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(11, 11, 8, 11),
        decoration: _panel(p, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconChip(icon, colour, size: 28),
            const SizedBox(height: 8),
            Text(value, style: TypeRamp.title(p.ink).copyWith(fontSize: 22)),
            const SizedBox(height: 1),
            Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    style: TypeRamp.caption(p.inkSoft),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 2),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 11,
                    color: p.inkFaint,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A step of someone's, coloured by its status like on the graph.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.item, required this.onOpen, this.colour});

  final MyStep item;
  final ValueChanged<String> onOpen;

  /// The classroom's colour, as a bar down the left.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fill = statusFill(p, item.standing);
    final word = standingWord(item.standing);
    return Pressable(
      label:
          '${item.step.title}, in ${item.room.title}. $word. '
          'Due ${shortDate(item.step.due)}',
      onTap: () => onOpen(item.room.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          gradient: fill == null
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [fill.top, fill.bottom],
                ),
          color: fill == null ? p.glassRegular : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            if (colour != null) ...[
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
            ],
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: p.ground,
                shape: BoxShape.circle,
              ),
              child: StandingMark(item.standing, size: 18),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.step.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.label(p.ink).weighted(FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$word · In ${item.room.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeRamp.caption(p.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(monthDay(item.step.due), style: TypeRamp.caption(p.ink)),
          ],
        ),
      ),
    );
  }
}

// Dashboard -------------------------------------------------------------------

class _DashboardPage extends StatefulWidget {
  const _DashboardPage({
    required this.backend,
    required this.overview,
    required this.insets,
    required this.onOpen,
    required this.onToggleTheme,
    required this.onCreate,
    required this.onJoin,
    required this.onNotifications,
    required this.important,
    required this.onImportant,
    required this.onTab,
  });

  /// Opens another home tab.
  final ValueChanged<_Tab> onTab;

  /// Requests waiting on this person.
  final int important;
  final VoidCallback onImportant;

  final Backend backend;
  final Overview overview;
  final EdgeInsets insets;
  final ValueChanged<String> onOpen;
  final VoidCallback onToggleTheme;

  /// Straight to a new classroom, or to joining one, from the welcome.
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onNotifications;

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  final _search = TextEditingController();

  /// Whether this device reminds its owner. Null until known.
  bool? _remindersOn;

  /// Where the classrooms start, for the Classrooms number to scroll to.
  final _roomsKey = GlobalKey();

  void _showRooms() {
    final at = _roomsKey.currentContext;
    if (at == null) return;
    unawaited(
      Scrollable.ensureVisible(
        at,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(
      ReminderPrefs.load().then((prefs) {
        if (mounted) setState(() => _remindersOn = prefs.on);
      }),
    );
  }

  /// Today's and tomorrow's steps, and anything overdue, with a way to the
  /// timeline and, until they're on, to the reminders switch.
  Widget _dueCard(Palette p, DueSummary due) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: _panel(p),
      child: Row(
        children: [
          Icon(
            due.overdue.isEmpty
                ? CupertinoIcons.bell
                : CupertinoIcons.exclamationmark_circle,
            size: 22,
            color: due.overdue.isEmpty ? p.accentWarm : p.blocked,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  due.headline[0].toUpperCase() + due.headline.substring(1),
                  style: TypeRamp.label(p.ink).weighted(FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  due.names,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TypeRamp.caption(p.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_remindersOn == false)
            PressButton(
              label: 'Remind me',
              icon: CupertinoIcons.bell,
              iconOnly: true,
              quiet: true,
              height: 44,
              onTap: () => widget.onTab(_Tab.profile),
            ),
          PressButton(
            label: 'See them',
            height: 44,
            onTap: () => widget.onTab(_Tab.timeline),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _rings(Palette p, Overview o) {
    final s = o.stats;
    final total = s.stepsTotal;
    final due = o.dueWithin(DateTime.now(), 7);
    return ConcentricRings(
      centre: '${(s.stepsDone / total * 100).round()}%',
      caption: 'finished',
      values: [
        RingValue('Done', s.stepsDone / total, '${s.stepsDone}', p.done),
        RingValue(
          'In progress',
          s.stepsInProgress / total,
          '${s.stepsInProgress}',
          p.doing,
        ),
        RingValue('Due in 7 days', due / total, '$due', p.accentWarm),
      ],
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    final first = (widget.backend.currentUser?.name ?? '').split(' ').first;
    final part = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');
    return first.isEmpty ? part : '$part, $first';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final o = widget.overview;
    final query = _search.text.trim().toLowerCase();
    final rooms = o.rooms
        .where((r) => r.classroom.title.toLowerCase().contains(query))
        .toList();
    final dark = p.brightness == Brightness.dark;
    final next = o.next;
    final insets = widget.insets;
    final due = DueSummary(dueSteps(o), DateTime.now());
    final fresh = o.rooms.isEmpty;
    return WidePage(
      insets: insets,
      maxWidth: 1040,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: insets.top),
          sliver: SliverToBoxAdapter(
            child: Rise(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Heading(
                      _greeting,
                      detail: fresh
                          ? 'Let’s set up your first plan.'
                          : 'Here’s where your work stands.',
                    ),
                  ),
                  OfyTarget(
                    id: 'home:important',
                    child: CountBadge(
                      count: widget.important,
                      child: PressButton(
                        label: widget.important == 0
                            ? 'Important'
                            : 'Important, ${widget.important} waiting',
                        icon: CupertinoIcons.exclamationmark_bubble,
                        iconOnly: true,
                        quiet: true,
                        height: 44,
                        onTap: widget.onImportant,
                      ),
                    ),
                  ),
                  CountBadge(
                    count: o.unreadNotices,
                    child: PressButton(
                      label: o.unreadNotices == 0
                          ? 'Notifications'
                          : 'Notifications, ${o.unreadNotices} new',
                      icon: CupertinoIcons.bell,
                      iconOnly: true,
                      quiet: true,
                      height: 44,
                      onTap: widget.onNotifications,
                    ),
                  ),
                  OfyTarget(
                    id: 'theme',
                    child: PressButton(
                      label: dark
                          ? 'Switch to white background'
                          : 'Switch to dark background',
                      icon: dark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
                      iconOnly: true,
                      quiet: true,
                      height: 44,
                      onTap: widget.onToggleTheme,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (fresh)
          SliverToBoxAdapter(
            child: Rise(
              index: 1,
              child: _Welcome(onCreate: widget.onCreate, onJoin: widget.onJoin),
            ),
          ),
        if (!fresh)
          SliverToBoxAdapter(
            child: Rise(
              index: 1,
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      '${o.rooms.length}',
                      'Classrooms',
                      CupertinoIcons.square_stack_3d_up,
                      p.accent,
                      onTap: _showRooms,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      '${o.dueWithin(DateTime.now(), 7)}',
                      'Due in 7 days',
                      CupertinoIcons.clock,
                      p.accentWarm,
                      onTap: () => widget.onTab(_Tab.timeline),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      '${o.stats.finishedThisWeek}',
                      'Done this week',
                      CupertinoIcons.checkmark_seal,
                      p.done,
                      onTap: () => widget.onTab(_Tab.done),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!due.nothing)
          SliverToBoxAdapter(child: Rise(index: 2, child: _dueCard(p, due))),
        if (o.stats.stepsTotal > 0)
          SliverToBoxAdapter(
            child: Rise(
              index: 2,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: _panel(p),
                  child: _rings(p, o),
                ),
              ),
            ),
          ),
        if (next != null)
          SliverToBoxAdapter(
            child: Rise(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Section('Up next'),
                  _StepCard(item: next, onOpen: widget.onOpen),
                ],
              ),
            ),
          ),
        if (!fresh)
          SliverToBoxAdapter(
            child: Rise(
              index: 3,
              child: Column(
                key: _roomsKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Section('Your classrooms'),
                  GlassField(label: 'Search classrooms', controller: _search),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        if (fresh)
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (rooms.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No classroom matches “${_search.text.trim()}”.',
                textAlign: TextAlign.center,
                style: TypeRamp.body(p.inkSoft),
              ),
            ),
          )
        else
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => Rise(
                index: 4 + i,
                child: OfyTarget(
                  id: 'classroom-card',
                  child: _RoomCard(
                    room: rooms[i],
                    me: widget.backend.currentUser?.uid ?? '',
                    onOpen: () => widget.onOpen(rooms[i].classroom.id),
                  ),
                ),
              ),
              childCount: rooms.length,
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: insets.bottom)),
      ],
    );
  }
}

/// A classroom as a square: how far along it is, what it's called, and who and
/// when underneath.
class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.me, required this.onOpen});

  final RoomSummary room;
  final String me;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = room.classroom;
    final people = c.individual
        ? 'Just you'
        : '${c.memberUids.length} '
              '${c.memberUids.length == 1 ? 'member' : 'members'}';
    final deadline = c.deadline;
    final role = switch (c.roleOf(me)) {
      MemberRole.master => c.individual ? null : 'Master',
      MemberRole.coMaster => 'Co-master',
      MemberRole.member => null,
    };
    final steps = room.state.steps;
    final done = steps.where((s) => s.status == StepStatus.done).length;
    final (icon, colour) = switch (c.taskType) {
      TaskType.build => (CupertinoIcons.hammer, p.accent),
      TaskType.study => (CupertinoIcons.book, p.accentWarm),
      TaskType.research => (CupertinoIcons.lab_flask, p.accentTeal),
      TaskType.eventOrCreative => (CupertinoIcons.sparkles, p.accentViolet),
      TaskType.other => (CupertinoIcons.square_grid_2x2, p.inkSoft),
    };
    return Pressable(
      radius: 20,
      label:
          '${c.title}. ${c.taskType.label}. $people. '
          '$done of ${steps.length} steps done.'
          '${deadline == null ? '' : ' Due ${shortDate(deadline)}.'}',
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
        decoration: _panel(p, radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconChip(icon, colour, size: 38),
                const Spacer(),
                ProgressRing(value: room.progress, size: 44),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Text(
                c.title,
                overflow: TextOverflow.fade,
                style: TypeRamp.heading(p.ink)
                    .weighted(FontWeight.w700)
                    .copyWith(letterSpacing: -0.3),
              ),
            ),
            Text(
              role == null ? c.taskType.label : '${c.taskType.label} · $role',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeRamp.caption(p.inkSoft),
            ),
            Text(
              deadline == null ? people : '$people · ${monthDay(deadline)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeRamp.caption(p.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

// Activity --------------------------------------------------------------------

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({
    required this.backend,
    required this.overview,
    required this.insets,
    required this.onOpen,
    required this.onChanged,
  });

  final Backend backend;
  final Overview overview;
  final EdgeInsets insets;
  final ValueChanged<String> onOpen;
  final VoidCallback onChanged;

  Future<void> _hide(Iterable<String> ids) async {
    try {
      await backend.hideActivity(ids);
    } on BackendFailure {
      return;
    }
    onChanged();
  }

  Future<void> _clear(BuildContext context) async {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final rooms = {for (final a in overview.actions) a.room.id: a.room};
    final choice = await showGlassSheet<String>(
      context,
      (_) => ChoiceSheet<String>(
        title: 'Clear activity',
        message:
            'Clearing takes it off your activity page. Each classroom keeps '
            'its own log.',
        choices: [
          ('Clear all of it', 'all', true),
          ('Clear everything older than a week', 'week', false),
          for (final r in rooms.values)
            ('Clear what I did in ${r.title}', 'room:${r.id}', false),
          ('Cancel', '', false),
        ],
      ),
    );
    if (choice == null || choice.isEmpty) return;
    await _hide([
      for (final a in overview.actions)
        if (choice == 'all' ||
            (choice == 'week' && a.entry.createdAt.isBefore(weekAgo)) ||
            choice == 'room:${a.room.id}')
          a.entry.id,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final roomOf = {for (final a in overview.actions) a.entry.id: a.room.title};
    return _Page(
      insets: insets,
      maxWidth: 760,
      children: [
        Rise(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _Heading(
                  'Your activity',
                  detail: 'What you’ve done, by day and hour.',
                  icon: CupertinoIcons.waveform_path_ecg,
                ),
              ),
              if (overview.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: PressButton(
                    label: 'Clear',
                    icon: CupertinoIcons.trash,
                    height: 38,
                    onTap: () => unawaited(_clear(context)),
                  ),
                ),
            ],
          ),
        ),
        Rise(
          index: 1,
          child: ActivityGroups(
            entries: [for (final a in overview.actions) a.entry],
            detailOf: (e) => roomOf[e.id],
            onDelete: (e) => unawaited(_hide([e.id])),
            empty: 'Nothing yet. What you do in your classrooms shows up here.',
          ),
        ),
      ],
    );
  }
}

/// A home page that's a heading and one list.
class _ListPage extends StatelessWidget {
  const _ListPage({
    required this.insets,
    required this.title,
    required this.detail,
    required this.icon,
    required this.child,
  });

  final EdgeInsets insets;
  final String title;
  final String detail;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => _Page(
    insets: insets,
    maxWidth: 760,
    children: [
      Rise(
        child: _Heading(title, detail: detail, icon: icon),
      ),
      Rise(index: 1, child: child),
    ],
  );
}

// Timeline --------------------------------------------------------------------

class _TimelinePage extends StatefulWidget {
  const _TimelinePage({
    required this.backend,
    required this.overview,
    required this.insets,
    required this.onOpen,
    required this.onTab,
  });

  final Backend backend;
  final Overview overview;
  final EdgeInsets insets;
  final ValueChanged<String> onOpen;
  final ValueChanged<_Tab> onTab;

  @override
  State<_TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<_TimelinePage> {
  var _byRoom = false;

  Overview get overview => widget.overview;
  EdgeInsets get insets => widget.insets;
  ValueChanged<String> get onOpen => widget.onOpen;

  void _showMine({required bool done}) {
    final p = Palette.of(context);
    final colourOf = {
      for (final (i, r) in overview.rooms.indexed)
        r.classroom.id: roomColour(p, i),
    };
    final mine = [
      for (final s in overview.steps)
        if (done
            ? s.step.status == StepStatus.done
            : s.step.status == StepStatus.doing)
          s,
    ];
    unawaited(
      showGlassSheet<void>(
        context,
        (sheet) => SheetFrame(
          title: done ? 'Your finished steps' : 'Your steps in progress',
          children: [
            if (mine.isEmpty)
              Text(
                done ? 'None finished yet.' : 'Nothing in progress right now.',
                style: TypeRamp.body(p.inkSoft),
              ),
            for (final r in overview.rooms)
              if (mine.any((s) => s.room.id == r.classroom.id)) ...[
                RoomHeading(
                  title: r.classroom.title,
                  colour: colourOf[r.classroom.id]!,
                  detail:
                      '${mine.where((s) => s.room.id == r.classroom.id).length}',
                ),
                for (final s in mine)
                  if (s.room.id == r.classroom.id)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _StepCard(
                        item: s,
                        colour: colourOf[r.classroom.id],
                        onOpen: (id) {
                          Navigator.of(sheet).pop();
                          onOpen(id);
                        },
                      ),
                    ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _byClassroom(Palette p, Map<String, Color> colourOf) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in overview.rooms)
          if (overview.steps.any((s) => s.room.id == r.classroom.id)) ...[
            RoomHeading(
              title: r.classroom.title,
              colour: colourOf[r.classroom.id]!,
              detail:
                  '${overview.steps.where((s) => s.room.id == r.classroom.id && s.step.status != StepStatus.done).length} to do',
            ),
            for (final s in overview.steps)
              if (s.room.id == r.classroom.id &&
                  s.step.status != StepStatus.done)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _StepCard(
                    item: s,
                    onOpen: onOpen,
                    colour: colourOf[r.classroom.id],
                  ),
                ),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final colourOf = {
      for (final (i, r) in overview.rooms.indexed)
        r.classroom.id: roomColour(p, i),
    };
    final stats = overview.stats;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));
    final open = overview.steps
        .where((s) => s.step.status != StepStatus.done)
        .toList();
    final finished = overview.steps
        .where((s) => s.step.status == StepStatus.done)
        .toList()
        .reversed
        .take(5)
        .toList();
    final groups = [
      ('Overdue', open.where((s) => s.step.due.isBefore(today)).toList()),
      (
        'Next 7 days',
        open
            .where(
              (s) =>
                  !s.step.due.isBefore(today) && s.step.due.isBefore(weekEnd),
            )
            .toList(),
      ),
      ('Later', open.where((s) => !s.step.due.isBefore(weekEnd)).toList()),
      ('Recently finished', finished),
    ];
    var order = 2;
    return _Page(
      insets: insets,
      maxWidth: 760,
      children: [
        const Rise(
          child: _Heading(
            'Your timeline',
            detail: 'Everything of yours, across every classroom.',
            icon: CupertinoIcons.calendar,
          ),
        ),
        Rise(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      '${stats.stepsDone} of ${stats.stepsTotal}',
                      'Steps done',
                      CupertinoIcons.checkmark_seal,
                      p.done,
                      onTap: () => _showMine(done: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      '${stats.stepsInProgress}',
                      'In progress',
                      CupertinoIcons.play_circle,
                      p.doing,
                      onTap: () => _showMine(done: false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      '${stats.actionsThisWeek}',
                      'Actions this week',
                      CupertinoIcons.waveform_path_ecg,
                      p.accent,
                      onTap: () => widget.onTab(_Tab.activity),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _panel(p),
                child: WeeklyBars(stats: stats),
              ),
            ],
          ),
        ),
        if (overview.steps.isEmpty)
          Padding(
            padding: const EdgeInsets.all(26),
            child: Text(
              'No steps are yours yet. Steps you own in any classroom appear '
              'here by date.',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          ),
        if (overview.steps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectChip(
                  label: 'By date',
                  selected: !_byRoom,
                  onTap: () => setState(() => _byRoom = false),
                ),
                SelectChip(
                  label: 'By classroom',
                  selected: _byRoom,
                  onTap: () => setState(() => _byRoom = true),
                ),
                if (open.isNotEmpty)
                  PressButton(
                    label: 'Add to calendar',
                    icon: CupertinoIcons.calendar_badge_plus,
                    quiet: true,
                    height: 36,
                    onTap: () => showGlassSheet<void>(
                      context,
                      (_) => CalendarSheet(
                        fileName: calendarFileName('my steps'),
                        choices: [
                          (
                            'My steps in every classroom',
                            [
                              for (final s in open)
                                eventForStep(s.step, room: s.room.title),
                            ]..sort((a, b) => a.day.compareTo(b.day)),
                          ),
                          for (final r in overview.rooms)
                            if (overview.rooms.length > 1 &&
                                open.any((s) => s.room.id == r.classroom.id))
                              (
                                r.classroom.title,
                                [
                                  for (final s in open)
                                    if (s.room.id == r.classroom.id)
                                      eventForStep(s.step, room: s.room.title),
                                ]..sort((a, b) => a.day.compareTo(b.day)),
                              ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (_byRoom) _byClassroom(p, colourOf),
        for (final (title, steps) in groups)
          if (steps.isNotEmpty && !_byRoom)
            Rise(
              index: order++,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(title),
                  for (final s in steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _StepCard(
                        item: s,
                        onOpen: onOpen,
                        colour: colourOf[s.room.id],
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

// Profile ---------------------------------------------------------------------

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.backend,
    required this.insets,
    required this.onToggleTheme,
    required this.onReminders,
  });

  /// Sets this device's reminders again after their switch changed.
  final VoidCallback onReminders;

  final Backend backend;
  final EdgeInsets insets;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final user = backend.currentUser;
    final name = user?.name ?? '';
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    final dark = p.brightness == Brightness.dark;
    return _Page(
      insets: insets,
      maxWidth: 760,
      children: [
        Rise(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.route,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initials,
                    style: TypeRamp.title(p.onRoute).copyWith(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TypeRamp.title(p.ink)
                            .copyWith(fontSize: 24, letterSpacing: -0.5),
                      ),
                      if ((user?.email ?? '').isNotEmpty)
                        Text(user!.email, style: TypeRamp.label(p.inkSoft)),
                      if ((user?.bio ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(user!.bio, style: TypeRamp.label(p.ink)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Rise(index: 1, child: ProfileStats(backend: backend)),
        Rise(
          index: 2,
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: _panel(p),
              child: ReminderSettings(onChanged: onReminders),
            ),
          ),
        ),
        Rise(
          index: 3,
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PressButton(
                  label: 'Edit profile and account',
                  icon: CupertinoIcons.pencil,
                  height: 44,
                  expand: true,
                  onTap: () => showGlassSheet<void>(
                    context,
                    (_) => ProfileSheet(backend: backend, showStats: false),
                  ),
                ),
                const SizedBox(height: 8),
                PressButton(
                  label: dark ? 'Use white background' : 'Use dark background',
                  icon: dark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
                  height: 44,
                  expand: true,
                  onTap: onToggleTheme,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
