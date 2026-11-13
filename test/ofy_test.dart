import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/ai/sample_ai.dart';
import 'package:octria/ofy/app_guide.dart';
import 'package:octria/ofy/ofy.dart';
import 'package:octria/ofy/ofy_host.dart';

void main() {
  final ai = SampleAi(delay: Duration.zero);

  test('Ofy knows how things are done in Octria', () async {
    final a = await ai.chat(
      const OfyQuestion(text: 'How do I add files to a step?'),
    );
    expect(a.howTo, 'add-file-to-step');
    expect(a.answer, contains('Google Drive'));
    expect(guessHowTo('how can I invite my friends')?.id, 'invite');
    expect(guessHowTo('what is the weather'), isNull);
  });

  test('Ofy offers to do what the screen allows, and only that', () async {
    final here = await ai.chat(
      const OfyQuestion(
        text: 'Mark Set up Firebase done',
        actions: [
          ('mark-done', 'Mark a step done', ['step']),
        ],
      ),
    );
    expect(here.action, 'mark-done');
    expect(here.args['step'], 'Set up Firebase');
    final elsewhere = await ai.chat(
      const OfyQuestion(text: 'Mark Set up Firebase done'),
    );
    expect(elsewhere.action, isNull);
  });

  test('changes wait for approval; looking around does not', () async {
    final ofy = Ofy(ai: ai);
    var marked = '';
    var opened = '';
    final owner = Object();
    ofy.enter(
      owner,
      OfyScreen(
        name: 'classroom',
        summary: () => 'Your next step: “Write tests”, due 9/11.',
        actions: [
          OfyAction(
            id: 'mark-done',
            description: 'Mark a step done',
            params: const ['step'],
            needsApproval: true,
            run: (args) async {
              marked = args['step']!;
              return 'Done.';
            },
          ),
          OfyAction(
            id: 'open-menu',
            description: 'Open a menu item',
            params: const ['item'],
            run: (args) async {
              opened = args['item']!;
              return 'Opened.';
            },
          ),
        ],
      ),
    );
    await ofy.ask('mark write tests done');
    final proposal = ofy.messages.last.proposal!;
    expect(proposal.state, ProposalState.waiting);
    expect(marked, isEmpty);
    await ofy.approve(proposal);
    expect(marked, 'write tests');
    expect(proposal.state, ProposalState.done);

    await ofy.ask('open files');
    expect(opened, 'files');

    await ofy.ask('What should I do next?');
    expect(ofy.messages.last.text, contains('Write tests'));
  });

  testWidgets('a spoken how-to runs on screen and moves on when tapped', (
    tester,
  ) async {
    final ofy = Ofy(ai: ai);
    final navigator = GlobalKey<NavigatorState>();
    var tapped = 0;
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            OfyHost(ofy: ofy, navigator: navigator, child: child!),
        home: CupertinoPageScaffold(
          child: Center(
            child: OfyTarget(
              id: 'step:add-file',
              child: CupertinoButton(
                onPressed: () => tapped++,
                child: const Text('Add a file from your device'),
              ),
            ),
          ),
        ),
      ),
    );
    unawaited(ofy.ask('how do I attach a pdf to my step', voice: true));
    await tester.pump();
    // Nothing to open first here, so the guide reaches the button.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(ofy.guide, isNotNull);
    expect(find.text('Tap Add a file from your device.'), findsOneWidget);
    await tester.tap(find.text('Add a file from your device'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, 1);
    expect(ofy.guide, isNull);
    ofy.dispose();
  });

  testWidgets('Show me does each step itself and waits at the last', (
    tester,
  ) async {
    final ofy = Ofy(ai: ai);
    final navigator = GlobalKey<NavigatorState>();
    final opened = ValueNotifier(false);
    final owner = Object();
    ofy.enter(
      owner,
      OfyScreen(
        name: 'home',
        summary: () => '',
        actions: [
          OfyAction(
            id: 'open-classroom',
            description: 'Open a classroom',
            params: const ['name'],
            run: (args) async {
              opened.value = true;
              return 'Opened ${args['name']}.';
            },
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            OfyHost(ofy: ofy, navigator: navigator, child: child!),
        home: CupertinoPageScaffold(
          child: ValueListenableBuilder<bool>(
            valueListenable: opened,
            builder: (context, open, _) => Center(
              child: open
                  ? const OfyTarget(id: 'b', child: Text('Inside'))
                  : const OfyTarget(id: 'a', child: Text('Card')),
            ),
          ),
        ),
      ),
    );
    ofy.showGuide(
      const HowTo(
        id: 't',
        title: 'Test',
        answer: '',
        words: [],
        steps: [
          GuideStep(
            'a',
            'Open it.',
            doIt: 'open-classroom',
            args: {'name': '{classroom}'},
          ),
          GuideStep('b', 'Now tap this.'),
        ],
      ),
      {'classroom': 'Physics'},
    );
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(opened.value, isTrue);
    expect(ofy.guide?.index, 1);
    expect(find.text('Now tap this.'), findsOneWidget);
    // The last step stays until the person does it.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(ofy.guide?.index, 1);
    ofy.stopGuide();
    await tester.pump(const Duration(seconds: 7));
    ofy.dispose();
  });
}
