import 'package:flutter/cupertino.dart';

import '../graph/graph_painter.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/spring_sheet.dart';

/// Everything about one step. Used in the side panel and the bottom sheet.
class StepPanel extends StatelessWidget {
  const StepPanel({
    super.key,
    required this.plan,
    required this.step,
    required this.touch,
    required this.header,
    required this.onClose,
    required this.onMarkDone,
    required this.onStart,
    required this.onReopen,
    required this.onHandOver,
    required this.onOpenStep,
    required this.onRemoveDependency,
    required this.onToggleChecklist,
    required this.onDelete,
  });

  final Plan plan;
  final PlanStep step;
  final bool touch;
  final Widget? header;
  final VoidCallback onClose;
  final VoidCallback onMarkDone;
  final VoidCallback onStart;
  final VoidCallback onReopen;
  final ValueChanged<String> onHandOver;
  final ValueChanged<String> onOpenStep;
  final ValueChanged<String> onRemoveDependency;
  final ValueChanged<int> onToggleChecklist;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final standing = plan.standing(step);
    final open = plan.openDependencies(step);
    final dependents = plan.dependents(step);
    final needs = step.dependsOn
        .map((id) => plan.steps[id])
        .whereType<PlanStep>()
        .toList();
    final isDone = step.status == StepStatus.done;

    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: TypeRamp.label(p.inkSoft)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 0),
          child: Row(
            children: [
              StandingMark(standing, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  standingLabel(standing),
                  style: TypeRamp.label(p.inkSoft),
                ),
              ),
              PressButton(
                label: 'Close',
                icon: CupertinoIcons.xmark,
                iconOnly: true,
                quiet: true,
                height: 44,
                onTap: onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            // A different step starts from the top of its details.
            key: ValueKey(step.id),
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
            children: [
              Text(step.title, style: TypeRamp.title(p.ink)),
              const SizedBox(height: 6),
              Text(
                '${plan.phase(step.phaseId).title} · Due ${shortDate(step.due)} · '
                '${_hours(step.estimateHours)} estimated',
                style: TypeRamp.caption(
                  plan.isOverdue(step) ? p.blocked : p.inkSoft,
                ),
              ),
              if (step.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(step.description, style: TypeRamp.body(p.ink)),
              ],
              const SizedBox(height: 18),
              if (!isDone && step.status == StepStatus.todo && open.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${_names(open)} ${open.length == 1 ? "isn’t" : "aren’t"} done yet. '
                    'You can still start, but you may need to redo some work.',
                    style: TypeRamp.label(p.inkSoft),
                  ),
                ),
              if (!isDone && step.status == StepStatus.todo) ...[
                PressButton(
                  label: open.isEmpty ? 'Start step' : 'Start anyway',
                  prominent: true,
                  selectedColor: p.ink,
                  height: 44,
                  expand: true,
                  onTap: onStart,
                ),
                const SizedBox(height: 4),
                PressButton(
                  label: 'Mark done',
                  quiet: true,
                  height: 44,
                  expand: true,
                  onTap: onMarkDone,
                ),
              ],
              if (!isDone && step.status != StepStatus.todo)
                touch
                    ? SwipeToDone(
                        label: 'Slide to mark done',
                        trackColor: p.control,
                        thumbColor: p.done,
                        thumb: Icon(
                          CupertinoIcons.checkmark_alt,
                          color: p.ground,
                          size: 22,
                        ),
                        textStyle: TypeRamp.label(p.inkSoft),
                        onCommit: onMarkDone,
                      )
                    : PressButton(
                        label: 'Mark done',
                        icon: CupertinoIcons.checkmark_alt,
                        height: 44,
                        expand: true,
                        onTap: onMarkDone,
                      ),
              if (isDone)
                PressButton(
                  label: 'Reopen step',
                  height: 44,
                  expand: true,
                  onTap: onReopen,
                ),
              if (needs.isNotEmpty) ...[
                sectionLabel('Needs'),
                for (final d in needs)
                  _LinkRow(
                    plan: plan,
                    step: d,
                    onOpen: () => onOpenStep(d.id),
                    onRemove: () => onRemoveDependency(d.id),
                  ),
              ],
              if (step.checklist.isNotEmpty) ...[
                sectionLabel(
                  'Checklist · ${step.checklistDone} of ${step.checklist.length}',
                ),
                for (var i = 0; i < step.checklist.length; i++)
                  _ChecklistRow(
                    item: step.checklist[i],
                    onToggle: () => onToggleChecklist(i),
                  ),
              ],
              sectionLabel('Study materials'),
              if (step.resources.isEmpty)
                Text(
                  'Nothing here yet. Files, links, videos and notes for this '
                  'step will appear here.',
                  style: TypeRamp.label(p.inkSoft),
                )
              else ...[
                for (final r in step.resources) _ResourceRow(resource: r),
                const SizedBox(height: 4),
                Text(
                  'Sample materials. Opening them arrives with the library.',
                  style: TypeRamp.caption(p.inkFaint),
                ),
              ],
              if (step.skills.isNotEmpty) ...[
                sectionLabel('Skills'),
                Text(step.skills.join(' · '), style: TypeRamp.body(p.ink)),
              ],
              if (step.comments > 0 || step.newSuggestions > 0) ...[
                sectionLabel('Discussion'),
                Text(
                  [
                    if (step.comments > 0) _count(step.comments, 'comment'),
                    if (step.newSuggestions > 0)
                      _count(step.newSuggestions, 'new suggestion'),
                  ].join(' · '),
                  style: TypeRamp.body(p.ink),
                ),
              ],
              sectionLabel('Owner'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in plan.members)
                    SelectChip(
                      label: m.name,
                      selected: m.id == step.ownerId,
                      onTap: () => onHandOver(m.id),
                    ),
                ],
              ),
              if (dependents.isNotEmpty) ...[
                sectionLabel('Unblocks'),
                for (final d in dependents)
                  _LinkRow(plan: plan, step: d, onOpen: () => onOpenStep(d.id)),
              ],
              // Kept apart on purpose: nothing common sits near this.
              const SizedBox(height: 56),
              Align(
                alignment: Alignment.centerLeft,
                child: PressButton(
                  label: 'Delete step',
                  destructive: true,
                  quiet: true,
                  onTap: onDelete,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _hours(double h) =>
      '${h == h.roundToDouble() ? h.round() : h} ${h == 1 ? "hour" : "hours"}';

  String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  String _names(List<PlanStep> steps) {
    if (steps.length == 1) return '“${steps.first.title}”';
    return '${steps.length} steps it needs';
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item, required this.onToggle});

  final ChecklistItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      checked: item.done,
      label: item.title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Icon(
                item.done
                    ? CupertinoIcons.checkmark_square_fill
                    : CupertinoIcons.square,
                size: 20,
                color: item.done ? p.done : p.inkSoft,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  style: TypeRamp.body(item.done ? p.inkSoft : p.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.resource});

  final StepResource resource;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (icon, kind) = switch (resource.type) {
      ResourceType.file => (CupertinoIcons.doc_text, 'File'),
      ResourceType.link => (CupertinoIcons.link, 'Link'),
      ResourceType.video => (CupertinoIcons.play_rectangle, 'Video'),
      ResourceType.note => (CupertinoIcons.square_pencil, 'Note'),
    };
    return Semantics(
      label: '$kind: ${resource.title}. ${resource.detail}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 19, color: p.inkSoft),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(resource.title, style: TypeRamp.body(p.ink)),
                  if (resource.detail.isNotEmpty)
                    Text(
                      '$kind · ${resource.detail}',
                      style: TypeRamp.caption(p.inkSoft),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.plan,
    required this.step,
    required this.onOpen,
    this.onRemove,
  });

  final Plan plan;
  final PlanStep step;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Go to ${step.title}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    StandingMark(plan.standing(step), size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TypeRamp.body(p.ink),
                      ),
                    ),
                    const SizedBox(width: 6),
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
        if (onRemove != null)
          PressButton(
            label: 'Remove dependency on ${step.title}',
            icon: CupertinoIcons.minus_circle,
            iconOnly: true,
            quiet: true,
            height: 44,
            onTap: onRemove,
          ),
      ],
    );
  }
}
