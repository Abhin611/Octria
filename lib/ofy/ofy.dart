/// Ofy, everywhere in the app: what's on screen, what it can do there, the
/// conversation, and any guide it's walking someone through.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../ai/ai.dart';
import '../data/models.dart';
import 'app_guide.dart';

/// Something a screen lets Ofy do, such as open a step or add one.
class OfyAction {
  const OfyAction({
    required this.id,
    required this.description,
    required this.run,
    this.params = const [],
    this.needsApproval = false,
  });

  final String id;

  /// What it does, for the model and for the approval card.
  final String description;

  /// Names of what it needs, such as `step` or `title`.
  final List<String> params;

  /// Changes something the person would want to see first.
  final bool needsApproval;

  /// Does it, and says what happened.
  final Future<String> Function(Map<String, String> args) run;
}

/// What a screen tells Ofy about itself.
class OfyScreen {
  const OfyScreen({
    required this.name,
    required this.summary,
    this.actions = const [],
  });

  final String name;

  /// What's on screen now, worked out when Ofy is asked.
  final String Function() summary;
  final List<OfyAction> actions;

  OfyAction? action(String? id) => actions.where((a) => a.id == id).firstOrNull;
}

enum ProposalState { waiting, done, declined, failed }

/// Something Ofy offered to do, waiting on Approve or Deny.
class OfyProposal {
  OfyProposal(this.action, this.args);

  final OfyAction action;
  final Map<String, String> args;
  var state = ProposalState.waiting;
  String? outcome;

  String get describe {
    final details = args.entries
        .where((e) => e.value.trim().isNotEmpty)
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    return details.isEmpty
        ? action.description
        : '${action.description} ($details)';
  }
}

class OfyMessage {
  OfyMessage.mine(this.text, {this.picture})
    : fromMe = true,
      howTo = null,
      proposal = null,
      params = const {};
  OfyMessage.ofy(this.text, {this.howTo, this.proposal, this.params = const {}})
    : fromMe = false,
      picture = null;

  /// The picture sent with a question, to show beside it.
  final Uint8List? picture;

  final bool fromMe;
  final String text;

  /// A guide Ofy can show for this answer.
  final HowTo? howTo;

  /// What the question named, such as a classroom, for the guide.
  final Map<String, String> params;
  final OfyProposal? proposal;
}

/// A guide running on screen.
class GuideRun {
  GuideRun(this.howTo, [this.params = const {}]);

  final HowTo howTo;

  /// What the person asked about, such as the classroom's name.
  final Map<String, String> params;

  /// The step's own arguments, with `{classroom}` and the like filled in.
  Map<String, String> get args => {
    for (final e in step.args.entries)
      e.key: e.value.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) => params[m.group(1)] ?? '',
      ),
  };
  var index = 0;

  /// Whether the step's preparation was asked for already.
  var prepared = false;

  GuideStep get step => howTo.steps[index];
  bool get last => index >= howTo.steps.length - 1;
}

/// Ofy's state for the whole app.
class Ofy extends ChangeNotifier {
  Ofy({this.ai});

  /// The model; null when the app runs its sample plans only.
  Ai? ai;

  // Screens ------------------------------------------------------------------

  final _screens = <Object, OfyScreen>{};

  /// The screen on top: the last one to say it's showing.
  OfyScreen? get screen => _screens.isEmpty ? null : _screens.values.last;

  void enter(Object owner, OfyScreen screen) {
    _screens.remove(owner);
    _screens[owner] = screen;
  }

  void leave(Object owner) => _screens.remove(owner);

  // Places on screen ---------------------------------------------------------

  final _targets = <String, List<GlobalKey>>{};

  void addTarget(String id, GlobalKey key) => (_targets[id] ??= []).add(key);

  void removeTarget(String id, GlobalKey key) {
    _targets[id]?.remove(key);
    if (_targets[id]?.isEmpty ?? false) _targets.remove(id);
  }

  /// The widget named [id], to scroll it into view.
  BuildContext? contextOf(String id) {
    for (final key in (_targets[id] ?? const <GlobalKey>[]).reversed) {
      if (key.currentContext != null) return key.currentContext;
    }
    return null;
  }

  /// Where [id] is on screen, if it's showing. A page hidden under another
  /// page doesn't count, though one behind a sheet does.
  Rect? rectOf(String id) {
    for (final key in (_targets[id] ?? const <GlobalKey>[]).reversed) {
      final context = key.currentContext;
      if (context == null || !TickerMode.valuesOf(context).enabled) continue;
      final box = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        return box.localToGlobal(Offset.zero) & box.size;
      }
    }
    return null;
  }

  // Conversation -------------------------------------------------------------

  final messages = <OfyMessage>[];
  var busy = false;
  final _alwaysAllowed = <String>{};

  /// Asks Ofy. With [voice], a guide starts on screen straight away and the
  /// answer shows briefly beside the Ofy button.
  ///
  /// With a [picture], Ofy looks at it too; a picture alone asks what it is.
  Future<void> ask(
    String text, {
    bool voice = false,
    Uint8List? picture,
  }) async {
    final question = text.trim().isEmpty && picture != null
        ? 'What does this show, and what should I do about it?'
        : text.trim();
    if (question.isEmpty || busy) return;
    messages.add(OfyMessage.mine(question, picture: picture));
    busy = true;
    notifyListeners();
    final here = screen;
    OfyMessage reply;
    try {
      final model = ai;
      if (model == null) throw const AiFailure('Ofy isn’t available here.');
      final answer = await model.chat(
        OfyQuestion(
          text: question,
          voice: voice,
          picture: picture,
          screen: here?.name ?? 'app',
          context: here?.summary() ?? '',
          actions: [
            for (final a in here?.actions ?? const <OfyAction>[])
              if (!a.id.startsWith('_')) (a.id, a.description, a.params),
          ],
          history: [
            for (final m in messages.reversed.skip(1).take(6).toList().reversed)
              (m.fromMe, m.text),
          ],
        ),
      );
      final howTo = howToById(answer.howTo);
      final action = here?.action(answer.action);
      OfyProposal? proposal;
      if (action != null) {
        proposal = OfyProposal(action, answer.args);
      }
      reply = OfyMessage.ofy(
        answer.answer,
        howTo: howTo,
        proposal: proposal,
        params: answer.args,
      );
      messages.add(reply);
      if (proposal != null &&
          (!proposal.action.needsApproval ||
              _alwaysAllowed.contains(proposal.action.id))) {
        await _carryOut(proposal);
      }
      if (voice && howTo != null && howTo.steps.isNotEmpty) {
        showGuide(howTo, answer.args);
      }
      if (voice) spoken = reply;
    } on AiFailure catch (e) {
      messages.add(OfyMessage.ofy(e.message));
    } on BackendFailure catch (e) {
      messages.add(OfyMessage.ofy(e.message));
    } on Object catch (e) {
      messages.add(OfyMessage.ofy('Ofy couldn’t answer ($e).'));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// The last reply to a spoken question, shown beside the Ofy button.
  OfyMessage? spoken;

  void clearSpoken() {
    spoken = null;
    notifyListeners();
  }

  Future<void> approve(OfyProposal p, {bool always = false}) async {
    if (always) _alwaysAllowed.add(p.action.id);
    await _carryOut(p);
    notifyListeners();
  }

  void decline(OfyProposal p) {
    p.state = ProposalState.declined;
    notifyListeners();
  }

  /// Closes the chat, so what Ofy does next is in plain view. Set by the
  /// chat while it's open.
  VoidCallback? closeChat;

  Future<void> _carryOut(OfyProposal p) async {
    final close = closeChat;
    closeChat = null;
    close?.call();
    try {
      p.outcome = await p.action.run(p.args);
      p.state = ProposalState.done;
      // Said beside the Ofy button, since the chat has closed.
      spoken = OfyMessage.ofy(p.outcome!);
    } on BackendFailure catch (e) {
      p.outcome = e.message;
      p.state = ProposalState.failed;
      spoken = OfyMessage.ofy(e.message);
    } on Object catch (e) {
      p.outcome = 'That didn’t work ($e).';
      p.state = ProposalState.failed;
      spoken = OfyMessage.ofy(p.outcome!);
    }
    notifyListeners();
    // The note beside the button fades after a moment.
    final said = spoken;
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (spoken == said) clearSpoken();
    });
  }

  void clear() {
    messages.clear();
    notifyListeners();
  }

  // Guides -------------------------------------------------------------------

  GuideRun? guide;

  void showGuide(HowTo howTo, [Map<String, String> params = const {}]) {
    if (howTo.steps.isEmpty) return;
    guide = GuideRun(howTo, params);
    notifyListeners();
  }

  /// Carries out the current step for the person, then moves on. A step
  /// with nothing to do just moves on.
  Future<void> doStep() async {
    final g = guide;
    if (g == null) return;
    final action = screen?.action(g.step.doIt);
    final index = g.index;
    if (action != null) {
      try {
        await action.run(g.args);
      } on Object {
        // Pointing the way is still worth it if doing it didn't work.
      }
    }
    if (guide == g && g.index == index) nextStep();
  }

  void nextStep() {
    final g = guide;
    if (g == null) return;
    if (g.last) {
      guide = null;
    } else {
      g.index++;
      g.prepared = false;
    }
    notifyListeners();
  }

  void stopGuide() {
    guide = null;
    notifyListeners();
  }

  /// Runs the current step's preparation, once.
  Future<void> prepareStep() async {
    final g = guide;
    if (g == null || g.prepared) return;
    g.prepared = true;
    final id = g.step.prepare;
    final action = id == null ? null : screen?.action(id);
    if (action != null) {
      try {
        await action.run(const {});
      } on Object {
        // The guide still points the way; the step just isn't open.
      }
    }
  }
}

/// Ofy for everything below it.
class OfyScope extends InheritedNotifier<Ofy> {
  const OfyScope({super.key, required Ofy ofy, required super.child})
    : super(notifier: ofy);

  static Ofy? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OfyScope>()?.notifier;

  static Ofy? watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OfyScope>()?.notifier;
}

/// Names a place on screen so Ofy can point at it.
class OfyTarget extends StatefulWidget {
  const OfyTarget({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<OfyTarget> createState() => _OfyTargetState();
}

class _OfyTargetState extends State<OfyTarget> {
  final _key = GlobalKey();
  Ofy? _ofy;
  String? _id;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  @override
  void didUpdateWidget(OfyTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _register();
  }

  void _register() {
    final ofy = OfyScope.maybeOf(context);
    if (ofy == _ofy && _id == widget.id) return;
    if (_id != null) _ofy?.removeTarget(_id!, _key);
    _ofy = ofy;
    _id = widget.id;
    ofy?.addTarget(widget.id, _key);
  }

  @override
  void dispose() {
    if (_id != null) _ofy?.removeTarget(_id!, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
