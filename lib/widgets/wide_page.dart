import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// A page that scrolls wherever the pointer is, across the whole screen,
/// while what's on it keeps to a readable column in the middle. No scroll
/// bar, and nothing is cut off at the column's edge, so a card can grow a
/// little when hovered.
class WidePage extends StatelessWidget {
  const WidePage({
    super.key,
    required this.insets,
    required this.slivers,
    this.maxWidth = 1040,
  });

  /// Room to keep clear on each side, such as for the side rail.
  final EdgeInsets insets;
  final List<Widget> slivers;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final room = math.max(0.0, width - insets.left - insets.right);
        final column = math.min(room, maxWidth);
        final left = insets.left + (room - column) / 2;
        final right = math.max(0.0, width - left - column);
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: CustomScrollView(
            clipBehavior: Clip.none,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(left: left, right: right),
                sliver: SliverMainAxisGroup(slivers: slivers),
              ),
            ],
          ),
        );
      },
    );
  }
}
