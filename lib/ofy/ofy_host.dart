import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../platform/picture.dart';
import '../screens/classroom_forms.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'ofy.dart';

/// Puts Ofy on every screen: a button that opens the chat (or listens, when
/// held), the short answer to a spoken question, and the spotlight of a
/// guide. Sits above the app's navigator, so it stays put as pages change.
class OfyHost extends StatefulWidget {
  const OfyHost({
    super.key,
    required this.ofy,
    required this.navigator,
    required this.child,
  });

  final Ofy ofy;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  State<OfyHost> createState() => _OfyHostState();
}

class _OfyHostState extends State<OfyHost> {
  final _speech = SpeechToText();
  var _listening = false;
  var _heard = '';
  var _chatOpen = false;

  Ofy get _ofy => widget.ofy;

  /// Around the app itself, so the screen can be shown to Ofy.
  final _appKey = GlobalKey();

  /// The app as it looks now, before the chat covers it.
  Future<ui.Image?> _capture() async {
    try {
      final box = _appKey.currentContext?.findRenderObject();
      if (box is! RenderRepaintBoundary || !box.hasSize) return null;
      return await box.toImage(
        pixelRatio: captureScale(box.size.width, box.size.height),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _openChat() async {
    final context = widget.navigator.currentContext;
    if (context == null || _chatOpen) return;
    _chatOpen = true;
    _ofy.clearSpoken();
    // Taken now: once the chat is up, it would be a picture of the chat.
    final screen = _capture();
    await showGlassSheet<void>(
      context,
      (_) => OfyChatSheet(ofy: _ofy, speech: _speech, screen: screen),
    );
    _chatOpen = false;
    unawaited(screen.then((picture) => picture?.dispose()));
  }

  Future<void> _listen() async {
    if (_listening) {
      await _speech.stop();
      return;
    }
    HapticFeedback.mediumImpact();
    final ready = await _speech.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ready) {
      _ofy.messages.add(
        OfyMessage.ofy(
          'I can’t hear on this device. Allow the microphone, or type to me '
          'instead.',
        ),
      );
      await _openChat();
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          setState(() => _listening = false);
          unawaited(_ofy.ask(r.recognizedWords, voice: true));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return OfyScope(
      ofy: _ofy,
      child: Stack(
        children: [
          RepaintBoundary(key: _appKey, child: widget.child),
          Positioned.fill(child: _GuideLayer(ofy: _ofy)),
          _Button(
            ofy: _ofy,
            listening: _listening,
            heard: _heard,
            onTap: _openChat,
            onHold: _listen,
          ),
        ],
      ),
    );
  }
}

/// The round Ofy button, with what it heard or said beside it.
class _Button extends StatelessWidget {
  const _Button({
    required this.ofy,
    required this.listening,
    required this.heard,
    required this.onTap,
    required this.onHold,
  });

  final Ofy ofy;
  final bool listening;
  final String heard;
  final VoidCallback onTap;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final media = MediaQuery.of(context);
    final phone = media.size.width < 700;
    final bottom = media.padding.bottom + (phone ? 96 : 24);
    return ListenableBuilder(
      listenable: ofy,
      builder: (context, _) {
        final spoken = ofy.spoken;
        final bubble = listening
            ? (heard.isEmpty ? 'Listening…' : heard)
            : ofy.busy && spoken == null
            ? null
            : spoken?.text;
        return Positioned(
          right: 14,
          bottom: bottom,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (bubble != null)
                GestureDetector(
                  onTap: () {
                    ofy.clearSpoken();
                    onTap();
                  },
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: math.min(300, media.size.width - 110),
                    ),
                    margin: const EdgeInsets.only(right: 10, bottom: 4),
                    child: GlassPanel(
                      radius: 18,
                      weight: GlassWeight.thick,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Text(
                        bubble,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TypeRamp.label(p.ink),
                      ),
                    ),
                  ),
                ),
              Semantics(
                button: true,
                label: 'Ofy. Tap to chat, hold to speak.',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: listening ? onHold : onTap,
                  onLongPress: onHold,
                  child: _Orb(active: listening || ofy.busy),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.orb, p.accentViolet],
        ),
        boxShadow: [
          BoxShadow(
            color: p.orb.withValues(alpha: active ? 0.7 : 0.38),
            blurRadius: active ? 26 : 16,
            spreadRadius: active ? 3 : 0,
          ),
        ],
      ),
      child: Icon(
        active ? CupertinoIcons.waveform : CupertinoIcons.sparkles,
        color: const Color(0xFFFFFFFF),
        size: 23,
      ),
    );
  }
}

/// The chat with Ofy.
class OfyChatSheet extends StatefulWidget {
  const OfyChatSheet({
    super.key,
    required this.ofy,
    required this.speech,
    this.screen,
  });

  final Ofy ofy;
  final SpeechToText speech;

  /// The screen behind the chat, taken as it opened, to show Ofy if asked.
  final Future<ui.Image?>? screen;

  @override
  State<OfyChatSheet> createState() => _OfyChatSheetState();
}

class _OfyChatSheetState extends State<OfyChatSheet> {
  final _input = TextEditingController();
  var _listening = false;

  /// A picture to send with the next question, and what it is.
  Uint8List? _picture;
  String _pictureOf = '';
  String? _pictureProblem;

  @override
  void initState() {
    super.initState();
    widget.ofy.closeChat = _close;
  }

  Future<void> _attachScreen() async {
    final picture = await widget.screen;
    final png = picture == null ? null : await pngOf(picture);
    if (!mounted) return;
    setState(() {
      _picture = png;
      _pictureOf = 'The screen behind this chat';
      _pictureProblem = png == null
          ? 'The screen couldn’t be captured here. Choose a picture instead.'
          : null;
    });
  }

  Future<void> _attachFile() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(dialogTitle: 'Choose a picture');
    } on Object {
      setState(
        () => _pictureProblem = 'Files couldn’t be opened on this device.',
      );
      return;
    }
    if (picked == null || !mounted) return;
    final png = await shrinkPicture(await picked.readAsBytes());
    if (!mounted) return;
    setState(() {
      _picture = png;
      _pictureOf = picked!.name;
      _pictureProblem = png == null
          ? 'That isn’t a picture Ofy can read. Try a PNG or JPEG.'
          : null;
    });
  }

  void _attach() {
    unawaited(
      showGlassSheet<void>(
        context,
        (_) => ActionListSheet(
          title: 'Show Ofy a picture',
          items: [
            if (widget.screen != null)
              (
                'The screen behind this chat',
                0,
                () => unawaited(_attachScreen()),
              ),
            ('A picture from this device', 0, () => unawaited(_attachFile())),
          ],
        ),
      ),
    );
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  static const _starters = [
    'What should I do next?',
    'How do I add a file to a step?',
    'How do I invite people?',
    'Draft a plan for me',
  ];

  @override
  void dispose() {
    if (widget.ofy.closeChat == _close) widget.ofy.closeChat = null;
    _input.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    final picture = _picture;
    if (t.isEmpty && picture == null) return;
    _input.clear();
    setState(() {
      _picture = null;
      _pictureProblem = null;
    });
    unawaited(widget.ofy.ask(t, picture: picture));
  }

  Future<void> _mic() async {
    if (_listening) {
      await widget.speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ready = await widget.speech.initialize();
    if (!ready || !mounted) return;
    setState(() => _listening = true);
    await widget.speech.listen(
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (r) {
        if (!mounted) return;
        _input.text = r.recognizedWords;
        if (r.finalResult) {
          setState(() => _listening = false);
          _send();
        }
      },
    );
  }

  void _show(OfyMessage m) {
    final howTo = m.howTo;
    if (howTo == null) return;
    Navigator.of(context).pop();
    widget.ofy.showGuide(howTo, m.params);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ofy = widget.ofy;
    return ListenableBuilder(
      listenable: ofy,
      builder: (context, _) {
        final empty = ofy.messages.isEmpty;
        return SheetFrame(
          title: 'Ofy',
          action: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (empty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in _starters)
                        SelectChip(
                          label: s,
                          selected: false,
                          onTap: () => _send(s),
                        ),
                    ],
                  ),
                ),
              if (_picture != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _picture!,
                          width: 56,
                          height: 40,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pictureOf,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TypeRamp.label(p.ink),
                            ),
                            Text(
                              'Ofy runs on Google’s Gemini, which sees this '
                              'to answer. Octria doesn’t keep it.',
                              style: TypeRamp.caption(p.inkFaint),
                            ),
                          ],
                        ),
                      ),
                      PressButton(
                        label: 'Remove the picture',
                        icon: CupertinoIcons.xmark,
                        iconOnly: true,
                        quiet: true,
                        height: 40,
                        onTap: () => setState(() => _picture = null),
                      ),
                    ],
                  ),
                ),
              if (_pictureProblem != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _pictureProblem!,
                    style: TypeRamp.caption(p.blocked),
                  ),
                ),
              Row(
                children: [
                  PressButton(
                    label: 'Show Ofy a picture',
                    icon: CupertinoIcons.photo,
                    iconOnly: true,
                    quiet: true,
                    selected: _picture != null,
                    height: 44,
                    onTap: _attach,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: CupertinoTextField(
                      controller: _input,
                      placeholder: _listening
                          ? 'Listening…'
                          : 'Ask Ofy anything about Octria',
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      style: TypeRamp.body(p.ink),
                      decoration: BoxDecoration(
                        color: p.control,
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PressButton(
                    label: _listening ? 'Stop listening' : 'Speak to Ofy',
                    icon: _listening
                        ? CupertinoIcons.stop_fill
                        : CupertinoIcons.mic,
                    iconOnly: true,
                    selected: _listening,
                    height: 44,
                    onTap: _mic,
                  ),
                  const SizedBox(width: 4),
                  PressButton(
                    label: 'Send',
                    icon: CupertinoIcons.arrow_up,
                    iconOnly: true,
                    prominent: true,
                    height: 44,
                    onTap: ofy.busy ? null : _send,
                  ),
                ],
              ),
            ],
          ),
          children: [
            if (empty)
              Text(
                'I know how everything in Octria works. Ask me how to do '
                'something and I’ll explain it, or show you on screen; ask me '
                'to do it and I’ll do it once you approve. Hold my button to '
                'talk instead.',
                style: TypeRamp.label(p.inkSoft),
              ),
            for (final m in ofy.messages)
              _Bubble(
                message: m,
                onShow: () => _show(m),
                onApprove: (always) =>
                    unawaited(ofy.approve(m.proposal!, always: always)),
                onDecline: () => ofy.decline(m.proposal!),
              ),
            if (ofy.busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CupertinoActivityIndicator(),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.onShow,
    required this.onApprove,
    required this.onDecline,
  });

  final OfyMessage message;
  final VoidCallback onShow;
  final ValueChanged<bool> onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mine = message.fromMe;
    final proposal = message.proposal;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: mine
            ? BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(18),
              )
            : BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.hairline),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.picture case final picture?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    picture,
                    height: 120,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TypeRamp.body(mine ? const Color(0xFFFFFFFF) : p.ink),
            ),
            if (message.howTo != null) ...[
              const SizedBox(height: 8),
              PressButton(
                label: 'Show me',
                icon: CupertinoIcons.hand_point_right,
                height: 36,
                onTap: onShow,
              ),
            ],
            if (proposal != null) ...[
              const SizedBox(height: 8),
              _ProposalCard(
                proposal: proposal,
                onApprove: onApprove,
                onDecline: onDecline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.onApprove,
    required this.onDecline,
  });

  final OfyProposal proposal;
  final ValueChanged<bool> onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final state = proposal.state;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: glassTint(p, p.accentViolet, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state == ProposalState.waiting
                ? 'Ofy wants to: ${proposal.describe}'
                : proposal.describe,
            style: TypeRamp.label(p.ink),
          ),
          const SizedBox(height: 8),
          switch (state) {
            ProposalState.waiting => Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                PressButton(
                  label: 'Approve',
                  icon: CupertinoIcons.checkmark_alt,
                  prominent: true,
                  height: 36,
                  onTap: () => onApprove(false),
                ),
                PressButton(
                  label: 'Always allow',
                  height: 36,
                  onTap: () => onApprove(true),
                ),
                PressButton(
                  label: 'Deny',
                  quiet: true,
                  height: 36,
                  onTap: onDecline,
                ),
              ],
            ),
            ProposalState.done => Text(
              proposal.outcome ?? 'Done.',
              style: TypeRamp.caption(p.done),
            ),
            ProposalState.declined => Text(
              'You said no, so nothing changed.',
              style: TypeRamp.caption(p.inkSoft),
            ),
            ProposalState.failed => Text(
              proposal.outcome ?? 'That didn’t work.',
              style: TypeRamp.caption(p.blocked),
            ),
          },
        ],
      ),
    );
  }
}

/// A guide's spotlight: everything else dims, the place to tap glows, and a
/// card says what to do. Tapping the place does it and moves the guide on.
class _GuideLayer extends StatefulWidget {
  const _GuideLayer({required this.ofy});

  final Ofy ofy;

  @override
  State<_GuideLayer> createState() => _GuideLayerState();
}

class _GuideLayerState extends State<_GuideLayer>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  Rect? _rect;
  GuideRun? _run;
  int _index = -1;
  var _waited = 0;
  var _missing = false;
  var _scrolled = false;
  Timer? _poll;

  /// Shows a step for a moment, then does it, so the guide plays like a
  /// demonstration. The last step waits for the person's own tap.
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    widget.ofy.addListener(_changed);
  }

  @override
  void dispose() {
    widget.ofy.removeListener(_changed);
    _poll?.cancel();
    _auto?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _changed() {
    final run = widget.ofy.guide;
    if (run == null) {
      _poll?.cancel();
      _auto?.cancel();
      _pulse.stop();
      if (_run != null) setState(() => _run = null);
      return;
    }
    if (run != _run || run.index != _index) {
      _run = run;
      _index = run.index;
      _waited = 0;
      _missing = false;
      _scrolled = false;
      _auto?.cancel();
      _auto = null;
      _rect = null;
      if (!MediaQuery.disableAnimationsOf(context)) {
        unawaited(_pulse.repeat(reverse: true));
      }
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(milliseconds: 120), (_) => _find());
      _find();
    }
  }

  /// Looks for the step's place on screen, opening the way if it can.
  void _find() {
    final run = _run;
    if (run == null || !mounted) return;
    final ofy = widget.ofy;
    var rect = ofy.rectOf(run.step.target);
    if (rect == null && run.step.prepare != null && !run.prepared) {
      unawaited(ofy.prepareStep());
    }
    _waited++;
    final origin = context.findRenderObject();
    if (rect != null && origin is RenderBox && origin.attached) {
      rect = Rect.fromPoints(
        origin.globalToLocal(rect.topLeft),
        origin.globalToLocal(rect.bottomRight),
      );
    }
    // Something being opened first gets longer to appear.
    final patience = run.step.prepare == null ? 7 : 22;
    if (rect == null && _waited > patience) {
      if (run.step.optional) {
        ofy.nextStep();
        return;
      }
      if (!_missing) setState(() => _missing = true);
      return;
    }
    // The first time it's found, bring it into view if it's scrolled away.
    if (rect != null && _rect == null && !_scrolled) {
      _scrolled = true;
      final target = ofy.contextOf(run.step.target);
      if (target != null && target.mounted) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: 0.4,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    if (rect != _rect) setState(() => _rect = rect);
    if (rect != null && !run.last && _auto == null) {
      final index = run.index;
      _auto = Timer(const Duration(milliseconds: 1700), () {
        if (mounted && widget.ofy.guide == run && run.index == index) {
          unawaited(widget.ofy.doStep());
        }
      });
    }
  }

  void _tapped(PointerUpEvent e) {
    final rect = _rect;
    final run = _run;
    if (run == null || rect == null) return;
    if (!rect.inflate(6).contains(e.localPosition)) return;
    // Let the tap do its work, then move on, unless the card's own Next or
    // Stop moved the guide already.
    final at = run.index;
    Timer(const Duration(milliseconds: 350), () {
      if (mounted && widget.ofy.guide == run && run.index == at) {
        widget.ofy.nextStep();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    if (run == null) return const SizedBox.shrink();
    final p = Palette.of(context);
    final rect = _rect;
    final pad = MediaQuery.paddingOf(context);
    final say = _missing
        ? 'I can’t see that here. ${run.step.say}'
        : run.step.say;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: _tapped,
      child: Stack(
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _SpotlightPainter(
                  rect: rect,
                  glow: p.orb,
                  pulse: _pulse.value,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _CardPlacement(rect: rect, padding: pad),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassPanel(
                  radius: 20,
                  weight: GlassWeight.thick,
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${run.howTo.title} · Step ${run.index + 1} of '
                        '${run.howTo.steps.length}',
                        style: TypeRamp.caption(p.inkSoft),
                      ),
                      const SizedBox(height: 4),
                      Text(say, style: TypeRamp.body(p.ink)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          PressButton(
                            label: 'Stop',
                            quiet: true,
                            height: 36,
                            onTap: widget.ofy.stopGuide,
                          ),
                          const SizedBox(width: 6),
                          PressButton(
                            label: run.last ? 'Done' : 'Next',
                            prominent: true,
                            height: 36,
                            onTap: run.last
                                ? widget.ofy.nextStep
                                : () => unawaited(widget.ofy.doStep()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts the guide's card just below the spotlight, or just above it when
/// there's no room below, so it never covers what it points at.
class _CardPlacement extends SingleChildLayoutDelegate {
  _CardPlacement({required this.rect, required this.padding});

  final Rect? rect;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.min(420, constraints.maxWidth - 32));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (size.width - child.width) / 2;
    final r = rect;
    if (r == null) return Offset(x, (size.height - child.height) / 2);
    const gap = 18.0;
    final below = r.bottom + gap;
    final fitsBelow = below + child.height <= size.height - padding.bottom - 8;
    final y = fitsBelow
        ? below
        : math.max(padding.top + 8, r.top - gap - child.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_CardPlacement old) =>
      old.rect != rect || old.padding != padding;
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({
    required this.rect,
    required this.glow,
    required this.pulse,
  });

  final Rect? rect;
  final Color glow;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Offset.zero & size;
    final dim = Paint()..color = const Color(0x8C000000);
    final r = rect;
    if (r == null) {
      canvas.drawRect(whole, dim);
      return;
    }
    final hole = RRect.fromRectAndRadius(
      r.inflate(8),
      const Radius.circular(16),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(whole),
        Path()..addRRect(hole),
      ),
      dim,
    );
    final spread = 3 + 6 * pulse;
    canvas.drawRRect(
      hole.inflate(spread),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = glow.withValues(alpha: 0.95 - 0.5 * pulse),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = glow,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.rect != rect || old.pulse != pulse || old.glow != glow;
}
