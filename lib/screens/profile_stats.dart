import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/user_stats.dart';
import '../theme/tokens.dart';

/// The profile's numbers: classrooms, work, activity and growth.
class ProfileStats extends StatefulWidget {
  const ProfileStats({super.key, required this.backend});

  final Backend backend;

  @override
  State<ProfileStats> createState() => _ProfileStatsState();
}

class _ProfileStatsState extends State<ProfileStats> {
  late final _stats = loadUserStats(widget.backend);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return FutureBuilder<UserStats>(
      future: _stats,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (snapshot.hasError) {
          return Text(
            'Your numbers couldn’t load. Check your connection and try again.',
            style: TypeRamp.label(p.inkSoft),
          );
        }
        if (stats == null) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: CupertinoActivityIndicator(),
          );
        }
        final hours = stats.hoursDone == stats.hoursDone.roundToDouble()
            ? '${stats.hoursDone.round()}'
            : stats.hoursDone.toStringAsFixed(1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row([
              _Tile(
                '${stats.classrooms}',
                stats.classrooms == 1 ? 'Classroom' : 'Classrooms',
                detail: stats.leading == 0
                    ? null
                    : 'Master of ${stats.leading}',
              ),
              _Tile(
                '${stats.stepsDone} of ${stats.stepsTotal}',
                'Your steps done',
                detail: '${stats.stepsInProgress} in progress',
              ),
            ]),
            const SizedBox(height: 8),
            _row([
              _Tile(
                '${stats.actionsThisWeek}',
                'Actions this week',
                detail: 'Things you did in Octria',
              ),
              _Tile(hours, 'Hours of work done', detail: 'From step estimates'),
            ]),
            const SizedBox(height: 8),
            _Tile(
              stats.growth,
              'Growth this week',
              detail:
                  '${stats.finishedThisWeek} finished, '
                  'against ${stats.finishedLastWeek} last week',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.hairline),
              ),
              child: WeeklyBars(stats: stats),
            ),
          ],
        );
      },
    );
  }

  Widget _row(List<Widget> tiles) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: tiles[0]),
        const SizedBox(width: 8),
        Expanded(child: tiles[1]),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile(this.value, this.label, {this.detail});

  final String value;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: '$label: $value. ${detail ?? ''}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TypeRamp.title(p.ink)),
              const SizedBox(height: 2),
              Text(label, style: TypeRamp.label(p.ink)),
              if (detail != null)
                Text(detail!, style: TypeRamp.caption(p.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Steps finished per week: one series, so the title names it and no legend is
/// needed. Hover or tap a week to read its number.
class WeeklyBars extends StatefulWidget {
  const WeeklyBars({super.key, required this.stats});

  final UserStats stats;

  @override
  State<WeeklyBars> createState() => WeeklyBarsState();
}

class WeeklyBarsState extends State<WeeklyBars> {
  int? _picked;

  String _line(int i) {
    final n = widget.stats.finishedPerWeek[i];
    final steps = n == 1 ? '1 step' : '$n steps';
    final last = widget.stats.weeks.length - 1;
    final when = i == last
        ? 'This week'
        : 'Week of ${monthDay(widget.stats.weeks[i])}';
    return '$when: $steps finished';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final counts = widget.stats.finishedPerWeek;
    final highest = counts.fold(0, (a, b) => a > b ? a : b);
    final shown = _picked ?? counts.length - 1;
    const height = 72.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Steps finished, last 8 weeks', style: TypeRamp.label(p.inkSoft)),
        const SizedBox(height: 10),
        CustomPaint(
          painter: _DashedGrid(p.hairline),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < counts.length; i++)
                  Expanded(
                    child: Semantics(
                      label: _line(i),
                      excludeSemantics: true,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _picked = i),
                        onExit: (_) => setState(() => _picked = null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _picked = i),
                          // The whole column responds, not just the thin bar.
                          child: SizedBox(
                            height: height,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 18,
                                height: counts[i] == 0
                                    ? 2
                                    : 4 + (height - 4) * counts[i] / highest,
                                decoration: BoxDecoration(
                                  color: counts[i] == 0
                                      ? p.hairline
                                      : p.accent.withValues(
                                          alpha: i == shown ? 1 : 0.5,
                                        ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: p.hairline),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Text(_line(shown), style: TypeRamp.caption(p.ink)),
        ),
      ],
    );
  }
}

class _DashedGrid extends CustomPainter {
  const _DashedGrid(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1;
    for (final part in const [0.0, 1 / 3, 2 / 3]) {
      final y = size.height * part;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedGrid old) => old.colour != colour;
}
