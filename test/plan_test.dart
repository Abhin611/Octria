import 'package:flutter_test/flutter_test.dart';
import 'package:octria/graph/layout.dart';
import 'package:octria/model/plan.dart';
import 'package:octria/model/sample_plans.dart';

void main() {
  group('Plan', () {
    final plan = campusEventsPlan();

    test('next step is ready, mine and on the critical path', () {
      expect(plan.nextStepFor('me')?.id, 'list');
    });

    test('a step with an unfinished dependency is waiting, not ready', () {
      expect(plan.standing(plan.steps['test']!), Standing.waiting);
    });

    test('an overdue dependency blocks the step after it', () {
      final late = plan.replacing(
        PlanStep(
          id: 'card',
          phaseId: 'design',
          ownerId: 'ben',
          title: 'Design event card',
          status: StepStatus.doing,
          estimateHours: 8,
          start: plan.today.subtract(const Duration(days: 9)),
          due: plan.today.subtract(const Duration(days: 1)),
        ),
      );
      expect(late.standing(late.steps['detail']!), Standing.blocked);
    });

    test('critical path skips finished work and ends at the plan end', () {
      final path = plan.criticalPath();
      expect(path, contains('publish'));
      expect(path, isNot(contains('firebase')));
    });

    test('circular dependencies are detected', () {
      expect(plan.wouldCycle('list', 'publish'), isTrue);
      expect(plan.wouldCycle('list', 'list'), isTrue);
      expect(plan.wouldCycle('publish', 'list'), isFalse);
    });
  });

  group('Layout', () {
    test('every step gets a place, in its phase and lane', () {
      final plan = campusEventsPlan();
      final layout = computeLayout(plan);
      for (final step in plan.steps.values) {
        final at = layout.positions[step.id]!;
        expect(layout.phaseBands[step.phaseId]!.contains(at), isTrue);
        expect(layout.laneBands[step.ownerId]!.contains(at), isTrue);
      }
    });

    test('a same-phase dependency sits to the left', () {
      final plan = campusEventsPlan();
      final layout = computeLayout(plan);
      expect(
        layout.positions['firebase']!.dx,
        lessThan(layout.positions['list']!.dx),
      );
    });

    test('your route never doubles back along your lane', () {
      final plan = stressPlan();
      final layout = computeLayout(plan);
      final route = plan.routeFor('me');
      for (var i = 1; i < route.length; i++) {
        expect(
          layout.positions[route[i].id]!.dx,
          greaterThanOrEqualTo(layout.positions[route[i - 1].id]!.dx),
        );
      }
    });

    test('everyone\'s steps run along the flow, in both directions', () {
      final plan = stressPlan();
      final across = computeLayout(plan);
      final down = computeLayout(
        plan,
        options: const LayoutOptions(direction: GraphDirection.topToBottom),
      );
      for (final member in plan.members) {
        final route = plan.routeFor(member.id);
        for (var i = 1; i < route.length; i++) {
          if (route[i].phaseId != route[i - 1].phaseId) continue;
          expect(
            across.positions[route[i].id]!.dx,
            greaterThan(across.positions[route[i - 1].id]!.dx),
          );
          expect(
            down.positions[route[i].id]!.dy,
            greaterThan(down.positions[route[i - 1].id]!.dy),
          );
        }
      }
    });

    test('arrows into a step get their own entry points and tracks', () {
      final plan = campusEventsPlan();
      final layout = computeLayout(plan);
      final into = layout.edgeRoutes['firebase>list']!;
      final other = layout.edgeRoutes['flows>list']!;
      expect(into.endDy, isNot(other.endDy));
      expect(into.track, isNot(other.track));
      for (final to in plan.steps.values) {
        for (final from in to.dependsOn) {
          expect(layout.edgeRoutes['$from>${to.id}'], isNotNull);
        }
      }
    });

    test('top to bottom makes phases rows and members columns', () {
      final plan = campusEventsPlan();
      final layout = computeLayout(
        plan,
        options: const LayoutOptions(
          direction: GraphDirection.topToBottom,
          cellWidth: 200,
          rowHeight: 196,
        ),
      );
      for (final step in plan.steps.values) {
        final at = layout.positions[step.id]!;
        expect(layout.phaseBands[step.phaseId]!.contains(at), isTrue);
        expect(layout.laneBands[step.ownerId]!.contains(at), isTrue);
        for (final id in step.dependsOn) {
          expect(layout.positions[id]!.dy, lessThan(at.dy), reason: step.title);
        }
      }
      expect(layout.cellAt(layout.positions['detail']!), ('build', 'ben'));
    });

    test('no two steps overlap, even in a 600-step plan', () {
      final plan = stressPlan();
      final layout = computeLayout(plan);
      final seen = <String>{};
      for (final at in layout.positions.values) {
        expect(seen.add('${at.dx.round()},${at.dy.round()}'), isTrue);
      }
      expect(layout.positions.length, 600);
    });
  });
}
