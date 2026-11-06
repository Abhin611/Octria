import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import '../theme/tokens.dart';

/// A small line saying what something does: shown when the pointer rests on
/// it, or when a finger holds it, so every icon explains itself.
class HoverHint extends StatefulWidget {
  const HoverHint({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  /// How long the pointer rests before the hint shows.
  static const wait = Duration(milliseconds: 350);

  @override
  State<HoverHint> createState() => _HoverHintState();
}

class _HoverHintState extends State<HoverHint> {
  Timer? _timer;
  OverlayEntry? _entry;

  void _show(Duration after, {Duration? hideAfter}) {
    _timer?.cancel();
    _timer = Timer(after, () {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      // The app's top overlay, so the hint sits above every page and sheet.
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      final origin = overlay.context.findRenderObject();
      final topLeft = origin is RenderBox
          ? box.localToGlobal(Offset.zero, ancestor: origin)
          : box.localToGlobal(Offset.zero);
      final anchor = topLeft & box.size;
      _remove();
      _entry = OverlayEntry(
        builder: (_) => HintBubble.at(anchor: anchor, message: widget.message),
      );
      overlay.insert(_entry!);
      if (hideAfter != null) _timer = Timer(hideAfter, _hide);
    });
  }

  void _remove() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _hide() {
    _timer?.cancel();
    _remove();
  }

  @override
  void deactivate() {
    _hide();
    super.deactivate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) return widget.child;
    return MouseRegion(
      onEnter: (e) {
        if (e.kind == PointerDeviceKind.mouse) _show(HoverHint.wait);
      },
      onExit: (_) => _hide(),
      child: Listener(
        // A click means they know what it does: the hint gets out of the way.
        onPointerDown: (e) {
          if (e.kind == PointerDeviceKind.mouse) _hide();
        },
        child: GestureDetector(
          // Holding a finger on it explains it without pressing it.
          onLongPressStart: (_) => _show(Duration.zero),
          onLongPressEnd: (_) => _show(
            Duration.zero,
            hideAfter: const Duration(milliseconds: 1400),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The hint itself: a small dark pill under what it describes, or above it
/// near the bottom of the screen.
class HintBubble extends StatelessWidget {
  const HintBubble({super.key, required this.message});

  /// Placed by [anchor], the thing it describes, in global coordinates.
  static Widget at({required Rect anchor, required String message}) =>
      IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _HintPlacement(anchor),
          child: HintBubble(message: message),
        ),
      );

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = p.brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 3 * (1 - t)),
          child: child,
        ),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: dark ? const Color(0xF2F4EEE8) : const Color(0xEB211A15),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style:
              TypeRamp.caption(
                dark ? const Color(0xFF1C1612) : const Color(0xFFFFFFFF),
              ).copyWith(
                fontSize: 12,
                height: 1.25,
                decoration: TextDecoration.none,
              ),
        ),
      ),
    );
  }
}

class _HintPlacement extends SingleChildLayoutDelegate {
  _HintPlacement(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    const gap = 6.0;
    const edge = 8.0;
    final below = anchor.bottom + gap;
    final y = below + child.height + edge <= size.height
        ? below
        : anchor.top - gap - child.height;
    final x = (anchor.center.dx - child.width / 2).clamp(
      edge,
      (size.width - child.width - edge).clamp(edge, double.infinity),
    );
    return Offset(x, y.clamp(edge, size.height - child.height - edge));
  }

  @override
  bool shouldRelayout(_HintPlacement old) => old.anchor != anchor;
}
