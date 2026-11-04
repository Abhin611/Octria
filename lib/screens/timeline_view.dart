import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../graph/graph_painter.dart';
import '../graph/plan_controller.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';

const double _minDayWidth = 14;
const double _maxDayWidth = 30;
const double _headerHeight = 42;

/// The same plan as a timeline, with dates to scale. The whole plan fits on
/// screen when it can; otherwise names stay pinned while dates scroll, opening
/// on today. Every row states its due date, so nothing looks undated.
class PlanTimelineView extends StatefulWidget {
  const PlanTimelineView({
    super.key,
    required this.plan,
    required this.filter,
    required this.selectedId,
    required this.onOpen,
  });

  final Plan plan;
  final GraphFilter filter;
  final String? selectedId;
  final ValueChanged<String> onOpen;

  @override
  State<PlanTimelineView> createState() => _PlanTimelineViewState();
}

class _PlanTimelineViewState extends State<PlanTimelineView> {
  ScrollController? _dates;

  List<PlanStep> get _ordered {
    final plan = widget.plan;
    final index = {
      for (var i = 0; i < plan.members.length; i++) plan.members[i].id: i,
    };
    return plan.steps.values.toList()..sort((a, b) {
      final byLane = index[a.ownerId]!.compareTo(index[b.ownerId]!);
      return byLane != 0 ? byLane : a.start.compareTo(b.start);
    });
  }

  DateTime get _first => widget.plan.steps.values
      .map((s) => s.start)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  DateTime get _last => widget.plan.steps.values
      .map((s) => s.due)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  @override
  void dispose() {
    _dates?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _ordered;
    final p = Palette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final first = _first;
    final last = _last;
    final days = last.difference(first).inDays + 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = constraints.maxWidth < 600 ? 136.0 : 200.0;
        // Tall enough for the name and date at the system's font size, with
        // names wrapping to two lines on a narrow column.
        final titleLines = labelWidth < 150 ? 2 : 1;
        final row = scaler.scale(16.25 * titleLines + 15) + 16;
        final height = _headerHeight + steps.length * row + 24;
        final room = constraints.maxWidth - labelWidth - 1;
        final dayWidth = (room / days).clamp(_minDayWidth, _maxDayWidth);
        final bodyHeight = math.max(height, constraints.maxHeight);
        final width = math.max(days * dayWidth, room);
        final dates = _dates ??= ScrollController(
          initialScrollOffset: math.max(
            0.0,
            (widget.plan.today.difference(first).inDays - 3) * dayWidth,
          ),
        );
        return Semantics(
          label:
              'Timeline of ${steps.length} steps, from ${monthDay(first)} to '
              '${monthDay(last)}. Use the List view with a screen reader.',
          child: SingleChildScrollView(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final index = ((d.localPosition.dy - _headerHeight) / row)
                    .floor();
                if (index >= 0 && index < steps.length) {
                  widget.onOpen(steps[index].id);
                }
              },
              child: SizedBox(
                height: bodyHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: CustomPaint(
                        painter: _LabelPainter(
                          widget.plan,
                          steps,
                          widget.filter,
                          p,
                          scaler,
                          row,
                          titleLines,
                        ),
                      ),
                    ),
                    Container(width: 1, color: p.hairline),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: dates,
                        scrollDirection: Axis.horizontal,
                        child: CustomPaint(
                          size: Size(width, bodyHeight),
                          painter: _BarPainter(
                            widget.plan,
                            steps,
                            widget.filter,
                            widget.selectedId,
                            p,
                            first,
                            days,
                            scaler,
                            row,
                            dayWidth,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints one line of text and returns its height.
double _text(
  Canvas c,
  String s,
  TextStyle st,
  Offset at,
  double w,
  TextScaler scaler, {
  int maxLines = 1,
}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
    textScaler: scaler,
  )..layout(maxWidth: w);
  tp.paint(c, at);
  final height = tp.height;
  tp.dispose();
  return height;
}

class _LabelPainter extends CustomPainter {
  _LabelPainter(
    this.plan,
    this.steps,
    this.filter,
    this.p,
    this.scaler,
    this.row,
    this.titleLines,
  );

  final Plan plan;
  final List<PlanStep> steps;
  final GraphFilter filter;
  final Palette p;
  final TextScaler scaler;
  final double row;
  final int titleLines;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()..color = p.hairline;
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final y = _headerHeight + i * row;
      final a = filter.matches(plan, s) ? 1.0 : 0.25;
      if (i > 0 && steps[i - 1].ownerId != s.ownerId) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
      }
      final mine = s.ownerId == plan.meId;
      final top = y + 8;
      final used = _text(
        canvas,
        s.title,
        TypeRamp.label(p.ink.withValues(alpha: a))
            .weighted(mine ? FontWeight.w600 : FontWeight.w400),
        Offset(16, top),
        size.width - 24,
        scaler,
        maxLines: titleLines,
      );
      _text(
        canvas,
        '${plan.member(s.ownerId).name} · ${monthDay(s.due)}',
        TypeRamp.caption(p.inkFaint.withValues(alpha: a)),
        Offset(16, top + used + 1),
        size.width - 24,
        scaler,
      );
    }
  }

  @override
  bool shouldRepaint(_LabelPainter old) => true;
}

class _BarPainter extends CustomPainter {
  _BarPainter(
    this.plan,
    this.steps,
    this.filter,
    this.selectedId,
    this.p,
    this.first,
    this.days,
    this.scaler,
    this.row,
    this.dayWidth,
  );

  final Plan plan;
  final List<PlanStep> steps;
  final GraphFilter filter;
  final String? selectedId;
  final Palette p;
  final DateTime first;
  final int days;
  final TextScaler scaler;
  final double row;
  final double dayWidth;

  double _x(DateTime d) => d.difference(first).inDays * dayWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()..color = p.hairline;
    for (var i = 0; i <= days; i += 7) {
      final date = first.add(Duration(days: i));
      final x = _x(date);
      canvas.drawLine(Offset(x, 30), Offset(x, size.height), tick);
      _text(
        canvas,
        monthDay(date),
        TypeRamp.caption(p.inkFaint),
        Offset(x + 4, 12),
        dayWidth * 7 - 6,
        scaler,
      );
    }
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final y = _headerHeight + i * row;
      final a = filter.matches(plan, s) ? 1.0 : 0.2;
      if (i > 0 && steps[i - 1].ownerId != s.ownerId) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), tick);
      }
      final mine = s.ownerId == plan.meId;
      final standing = plan.standing(s);
      final colour = p.standing(standing);
      final left = _x(s.start);
      final centre = y + row / 2;
      final rect = RRect.fromLTRBR(
        left,
        centre - 12,
        math.max(_x(s.due), left + 26),
        centre + 12,
        const Radius.circular(6),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = colour.withValues(alpha: 0.2 * a),
      );
      final selected = s.id == selectedId;
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : (mine ? 2 : 1.2)
          ..color = (selected ? p.ink : (mine ? p.route : colour)).withValues(
            alpha: a,
          ),
      );
      // Status is a drawn mark first, so your own bars still differ.
      paintStandingMark(
        canvas,
        Offset(left + 13, centre),
        7,
        standing,
        p,
        alpha: a,
      );
    }
    final now = _x(plan.today);
    canvas.drawLine(
      Offset(now, 30),
      Offset(now, size.height),
      Paint()
        ..color = p.ink
        ..strokeWidth = 1.5,
    );
    _text(
      canvas,
      'Today',
      TypeRamp.caption(p.ink),
      Offset(now + 4, 28),
      50,
      scaler,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}
