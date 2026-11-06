import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../data/overview.dart';
import '../graph/graph_painter.dart';
import '../model/plan.dart';
import '../kanvas/kanvas_home.dart';
import 'requests_sheets.dart';
import '../platform/app_badge.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/glass_motion.dart';
import '../widgets/hover_hint.dart';
import '../widgets/motion.dart';
import 'classroom_forms.dart';
import 'classroom_screen.dart';
import 'profile_stats.dart';

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
  kanvas('Kanvas', CupertinoIcons.paintbrush, CupertinoIcons.paintbrush_fill),
  timeline('Timeline', CupertinoIcons.calendar, CupertinoIcons.calendar_today),
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
    unawaited(_rooms?.cancel());
    super.dispose();
  }

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
      final n = await importantCount(widget.backend, _roomContexts(o));
      if (mounted && n != _important) setState(() => _important = n);
      // The same two numbers as the bubble and the bell, on the app's icon.
      unawaited(setAppBadge(n + o.unreadNotices));
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
                onAdd: _showAdd,
                onNotifications: () => _showNotifications(data),
                important: _important,
                onImportant: () => _showImportant(data),
              ),
              _Tab.activity => _ActivityPage(
                overview: data!,
                insets: insets,
                onOpen: _open,
              ),
              _Tab.kanvas => KanvasHome(
                backend: widget.backend,
                overview: data!,
                insets: insets,
                onOpenClassroom: _open,
              ),
              _Tab.timeline => _TimelinePage(
                overview: data!,
                insets: insets,
                onOpen: _open,
              ),
              _Tab.profile => _ProfilePage(
                backend: widget.backend,
                insets: insets,
                onToggleTheme: _toggleTheme,
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
        child: Pressable(
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
      );
    }

    return GlassPanel(
      radius: 32,
      weight: GlassWeight.thin,
      child: Row(
        children: [
          item(_Tab.dashboard),
          item(_Tab.activity),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
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
          item(_Tab.kanvas),
          item(_Tab.timeline),
          item(_Tab.profile),
        ],
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
          for (final t in _Tab.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Pressable(
                label: t.label,
                onTap: () => onSelect(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: t == tab
                      ? glassTint(p, p.accent, radius: 13)
                      : BoxDecoration(
                          border: Border.all(color: const Color(0x00000000)),
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
                        style: TypeRamp.label(t == tab ? p.ink : p.inkSoft)
                            .weighted(
                              t == tab ? FontWeight.w600 : FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Spacer(),
          PressButton(
            label: 'Add a classroom',
            icon: CupertinoIcons.plus,
            prominent: true,
            height: 44,
            expand: true,
            onTap: onAdd,
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
    return Padding(
      padding: EdgeInsets.only(left: insets.left, right: insets.right),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(
            padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
            children: children,
          ),
        ),
      ),
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
  color: p.panel,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: p.hairline),
  boxShadow: [
    BoxShadow(color: p.shadow, blurRadius: 18, offset: const Offset(0, 6)),
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
  const _Stat(this.value, this.label, this.icon, this.colour);

  final String value;
  final String label;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 11, 8, 11),
        decoration: _panel(p, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconChip(icon, colour, size: 28),
            const SizedBox(height: 8),
            Text(value, style: TypeRamp.title(p.ink).copyWith(fontSize: 22)),
            const SizedBox(height: 1),
            Text(label, maxLines: 2, style: TypeRamp.caption(p.inkSoft)),
          ],
        ),
      ),
    );
  }
}

/// A step of someone's, coloured by its status like on the graph.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.item, required this.onOpen});

  final MyStep item;
  final ValueChanged<String> onOpen;

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
    required this.onAdd,
    required this.onNotifications,
    required this.important,
    required this.onImportant,
  });

  /// Requests waiting on this person.
  final int important;
  final VoidCallback onImportant;

  final Backend backend;
  final Overview overview;
  final EdgeInsets insets;
  final ValueChanged<String> onOpen;
  final VoidCallback onToggleTheme;
  final VoidCallback onAdd;
  final VoidCallback onNotifications;

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  final _search = TextEditingController();

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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _Heading(
                            _greeting,
                            detail: 'Here’s where your work stands.',
                          ),
                        ),
                        CountBadge(
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
                        PressButton(
                          label: dark
                              ? 'Switch to white background'
                              : 'Switch to dark background',
                          icon: dark
                              ? CupertinoIcons.sun_max
                              : CupertinoIcons.moon,
                          iconOnly: true,
                          quiet: true,
                          height: 44,
                          onTap: widget.onToggleTheme,
                        ),
                      ],
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
                        child: _Stat(
                          '${o.rooms.length}',
                          'Classrooms',
                          CupertinoIcons.square_stack_3d_up,
                          p.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Stat(
                          '${o.dueWithin(DateTime.now(), 7)}',
                          'Due in 7 days',
                          CupertinoIcons.clock,
                          p.accentWarm,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Stat(
                          '${o.stats.finishedThisWeek}',
                          'Done this week',
                          CupertinoIcons.checkmark_seal,
                          p.done,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
              SliverToBoxAdapter(
                child: Rise(
                  index: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Section('Your classrooms'),
                      GlassField(
                        label: 'Search classrooms',
                        controller: _search,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (o.rooms.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
                    child: Column(
                      children: [
                        Text(
                          'Nothing here yet. Start a classroom for something '
                          'you need to finish, or join one with a code.',
                          textAlign: TextAlign.center,
                          style: TypeRamp.body(p.inkSoft),
                        ),
                        const SizedBox(height: 14),
                        PressButton(
                          label: 'Add a classroom',
                          icon: CupertinoIcons.plus,
                          prominent: true,
                          height: 44,
                          onTap: widget.onAdd,
                        ),
                      ],
                    ),
                  ),
                )
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
                      child: _RoomCard(
                        room: rooms[i],
                        me: widget.backend.currentUser?.uid ?? '',
                        onOpen: () => widget.onOpen(rooms[i].classroom.id),
                      ),
                    ),
                    childCount: rooms.length,
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: insets.bottom)),
            ],
          ),
        ),
      ),
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
    required this.overview,
    required this.insets,
    required this.onOpen,
  });

  final Overview overview;
  final EdgeInsets insets;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final roomOf = {for (final a in overview.actions) a.entry.id: a.room.title};
    return _Page(
      insets: insets,
      maxWidth: 760,
      children: [
        Rise(
          child: _Heading(
            'Your activity',
            detail: 'What you’ve done, by day and hour.',
            icon: CupertinoIcons.waveform_path_ecg,
          ),
        ),
        Rise(
          index: 1,
          child: ActivityGroups(
            entries: [for (final a in overview.actions) a.entry],
            detailOf: (e) => roomOf[e.id],
            empty: 'Nothing yet. What you do in your classrooms shows up here.',
          ),
        ),
      ],
    );
  }
}

// Timeline --------------------------------------------------------------------

class _TimelinePage extends StatelessWidget {
  const _TimelinePage({
    required this.overview,
    required this.insets,
    required this.onOpen,
  });

  final Overview overview;
  final EdgeInsets insets;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
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
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      '${stats.stepsInProgress}',
                      'In progress',
                      CupertinoIcons.play_circle,
                      p.doing,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      '${stats.actionsThisWeek}',
                      'Actions this week',
                      CupertinoIcons.waveform_path_ecg,
                      p.accent,
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
        for (final (title, steps) in groups)
          if (steps.isNotEmpty)
            Rise(
              index: order++,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(title),
                  for (final s in steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _StepCard(item: s, onOpen: onOpen),
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
  });

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
