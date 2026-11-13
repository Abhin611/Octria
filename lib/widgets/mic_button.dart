/// A microphone that speaks into a text field: what's said is added after
/// what's already typed, on the device, as it's heard.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'controls.dart';

class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.controller,
    this.onUnavailable,
    this.height = 40,
  });

  final TextEditingController controller;

  /// Called when this device or browser can't listen.
  final VoidCallback? onUnavailable;
  final double height;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  final _speech = SpeechToText();
  var _listening = false;

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    var ready = false;
    try {
      ready = await _speech.initialize();
    } on Object {
      ready = false;
    }
    if (!mounted) return;
    if (!ready) {
      widget.onUnavailable?.call();
      return;
    }
    final before = widget.controller.text.trim();
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (r) {
        if (!mounted) return;
        widget.controller.text = [
          if (before.isNotEmpty) before,
          r.recognizedWords,
        ].join(' ');
        if (r.finalResult) setState(() => _listening = false);
      },
    );
  }

  @override
  void dispose() {
    if (_listening) unawaited(_speech.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PressButton(
    label: _listening ? 'Stop listening' : 'Say it instead',
    icon: _listening ? CupertinoIcons.stop_circle : CupertinoIcons.mic,
    iconOnly: true,
    selected: _listening,
    height: widget.height,
    onTap: () => unawaited(_toggle()),
  );
}
