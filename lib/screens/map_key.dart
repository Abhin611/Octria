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
            'Your route, where one step needs the next',
          ),
          row(
            line((c, s) {
              final y = s.height / 2;
              final dash = Paint()
                ..color = p.route
                ..strokeWidth = 3.2
                ..strokeCap = StrokeCap.round;
              for (var x = 2.0; x < s.width; x += 12) {
                c.drawLine(Offset(x, y), Offset(x + 4, y), dash);
              }
            }),
            'Order of work, in your colour for you: an order, not a link',
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
          row(const StatusSwatch(Standing.ready), 'Ready to start: grey'),
          row(const StatusSwatch(Standing.doing), 'In progress: blue'),
          row(
            const StatusSwatch(Standing.review),
            'Waiting for approval: amber',
          ),
          row(const StatusSwatch(Standing.done), 'Done: green'),
          row(
            const StatusSwatch(Standing.waiting),
            'Waiting on another step: plain and dimmed',
          ),
          row(
            const StatusSwatch(Standing.blocked),
            'Blocked by an overdue step: red',
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
