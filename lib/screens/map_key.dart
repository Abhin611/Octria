import 'package:flutter/cupertino.dart';

import '../graph/graph_painter.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';

/// Names every mark and line on the graph, in one place.
class MapKey extends StatelessWidget {
  const MapKey({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    Widget row(Widget mark, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 34, child: Center(child: mark)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TypeRamp.label(p.ink))),
        ],
      ),
    );

    Widget line(void Function(Canvas, Size) draw) =>
        CustomPaint(size: const Size(30, 14), painter: _LinePainter(draw));

    return GlassPanel(
      weight: GlassWeight.thick,
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(
            line((c, s) {
              c.drawLine(
                Offset(0, s.height / 2),
                Offset(s.width, s.height / 2),
                Paint()
                  ..color = p.route
                  ..strokeWidth = 3.6
                  ..strokeCap = StrokeCap.round,
              );
            }),
            'Your route',
          ),
          row(
            line((c, s) {
              final y = s.height / 2;
              c.drawLine(
                Offset(0, y),
                Offset(s.width, y),
                Paint()
                  ..color = p.ink.withValues(alpha: 0.5)
                  ..strokeWidth = 4,
              );
              c.drawLine(
                Offset(0, y),
                Offset(s.width, y),
                Paint()
                  ..color = p.waiting
                  ..strokeWidth = 1.6,
              );
            }),
            'Critical path: decides the deadline',
          ),
          row(const StandingMark(Standing.ready), 'Ready to start'),
          row(const StandingMark(Standing.doing), 'In progress'),
          row(const StandingMark(Standing.review), 'In review'),
          row(const StandingMark(Standing.done), 'Done'),
          row(const StandingMark(Standing.waiting), 'Waiting on another step'),
          row(
            const StandingMark(Standing.blocked),
            'Blocked by an overdue step',
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.draw);
  final void Function(Canvas, Size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(_LinePainter old) => true;
}
