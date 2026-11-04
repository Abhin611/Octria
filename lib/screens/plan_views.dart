import 'package:flutter/cupertino.dart';

import '../graph/graph_painter.dart';
import '../graph/plan_controller.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';

/// The same plan as a grouped list: the accessible equivalent of the graph, and
/// the easier view on a small screen.
class PlanListView extends StatelessWidget {
  const PlanListView({
    super.key,
    required this.plan,
    required this.filter,
    required this.selectedId,
    required this.onOpen,
    required this.topInset,
    required this.bottomInset,
  });

  final Plan plan;
  final GraphFilter filter;
  final String? selectedId;
  final ValueChanged<String> onOpen;
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final next = plan.nextStepFor(plan.meId)?.id;
    final sections = <Widget>[];
    for (final phase in plan.phases) {
      final steps = plan
          .stepsIn(phase.id)
          .where((s) => filter.matches(plan, s))
          .toList();
      if (steps.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Semantics(
            header: true,
            child: Row(
              children: [
                Expanded(
                  child: Text(phase.title, style: TypeRamp.title(p.ink)),
                ),
                Text(
                  '${(plan.phaseProgress(phase.id) * 100).round()}% done',
                  style: TypeRamp.caption(p.inkFaint),
                ),
              ],
            ),
          ),
        ),
      );
      sections.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.glassRegular,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.rimBottom),
          ),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 48),
                    child: Container(height: 1, color: p.hairline),
                  ),
                _StepRow(
                  plan: plan,
                  step: steps[i],
                  isNext: steps[i].id == next,
                  onTap: () => onOpen(steps[i].id),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (sections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No steps match these filters. Clear a filter to see more of the plan.',
            textAlign: TextAlign.center,
            style: TypeRamp.body(p.inkSoft),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: EdgeInsets.only(top: topInset, bottom: bottomInset + 24),
          children: sections,
        ),
      ),
    );
  }
}

class _StepRow extends StatefulWidget {
  const _StepRow({
    required this.plan,
    required this.step,
    required this.isNext,
    required this.onTap,
  });

  final Plan plan;
  final PlanStep step;
  final bool isNext;
  final VoidCallback onTap;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final step = widget.step;
    final plan = widget.plan;
    final standing = plan.standing(step);
    final owner = plan.member(step.ownerId);
    return Semantics(
      button: true,
      label:
          '${step.title}. ${standingLabel(standing)}. ${owner.name}. Due ${shortDate(step.due)}.'
          '${widget.isNext ? ' Your next step.' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: Container(
          color: _down ? p.control : null,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              StandingMark(standing, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: TypeRamp.body(p.ink).weighted(
                        widget.isNext ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (widget.isNext)
                      Text('Your next step', style: TypeRamp.caption(p.route)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(owner.name, style: TypeRamp.caption(p.inkSoft)),
              const SizedBox(width: 12),
              SizedBox(
                width: 76,
                child: Text(
                  shortDate(step.due),
                  textAlign: TextAlign.right,
                  style: TypeRamp.caption(
                    plan.isOverdue(step) ? p.blocked : p.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
