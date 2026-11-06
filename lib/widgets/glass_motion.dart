import 'package:flutter/cupertino.dart';

/// A page arriving like glass settling into place: it rises the last little
/// way and grows into focus. It turns opaque almost at once, so the page
/// beneath never shows through it; nothing is blurred, so it stays smooth on
/// slower phones. Reduce Motion keeps a quick fade.
class GlassRoute<T> extends PageRouteBuilder<T> {
  GlassRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, _, _) => builder(context),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        opaque: true,
        transitionsBuilder: (context, animation, _, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: const Interval(0, 0.3, curve: Curves.easeOut),
          );
          if (MediaQuery.disableAnimationsOf(context)) {
            return FadeTransition(opacity: fade, child: child);
          }
          final settle = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: Tween(begin: 0.965, end: 1.0).animate(settle),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.025),
                  end: Offset.zero,
                ).animate(settle),
                child: child,
              ),
            ),
          );
        },
      );
}

/// For an [AnimatedSwitcher]: only the new view is drawn, settling into place,
/// so two screens are never seen on top of each other.
///
/// The view keeps the same wrappers from the first frame to the last. Taking
/// them away when the motion ends would make Flutter build the whole view
/// again from nothing, so it would seem to load twice.
Widget glassSwitch(
  Widget child,
  Animation<double> animation, {
  double drift = 0,
}) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final still = MediaQuery.disableAnimationsOf(context);
      final t = still ? 1.0 : Curves.easeOutCubic.transform(animation.value);
      return Opacity(
        opacity: (t * 1.6).clamp(0.0, 1.0),
        child: Transform(
          transform: Matrix4.translationValues(drift * (1 - t), 0, 0)
            ..scaleByDouble(0.985 + 0.015 * t, 0.985 + 0.015 * t, 1, 1),
          alignment: Alignment.center,
          child: child,
        ),
      );
    },
  );
}

/// Shows only the newest child in an [AnimatedSwitcher], never the old one
/// fading out underneath it.
Widget onlyNewest(Widget? current, List<Widget> previous) =>
    current ?? const SizedBox.shrink();

/// Wraps a sheet's contents so it materialises: it rises and grows into
/// place, a pane of glass arriving rather than a card sliding up.
class GlassArrival extends StatelessWidget {
  const GlassArrival({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return ScaleTransition(
      scale: Tween(
        begin: 0.95,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      alignment: Alignment.bottomCenter,
      child: child,
    );
  }
}

/// A pane of glass dropping down from [anchor], such as a menu under a title.
/// Tapping outside closes it.
Future<T?> showGlassPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 320,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final origin = box == null
      ? Offset.zero
      : box.localToGlobal(Offset(0, box.size.height));
  return showGeneralDialog<T>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x14000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) {
      final size = MediaQuery.sizeOf(context);
      final w = width.clamp(0.0, size.width - 16);
      final left = origin.dx.clamp(8.0, size.width - w - 8);
      return Stack(
        children: [
          Positioned(
            left: left,
            top: origin.dy + 8,
            width: w,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: size.height - origin.dy - 24,
              ),
              child: builder(context),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final t = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      if (MediaQuery.disableAnimationsOf(context)) {
        return FadeTransition(opacity: t, child: child);
      }
      return FadeTransition(
        opacity: t,
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(t),
          alignment: Alignment.topLeft,
          child: child,
        ),
      );
    },
  );
}
