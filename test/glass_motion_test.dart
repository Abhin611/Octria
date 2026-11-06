import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:octria/widgets/glass_motion.dart';

var _builtTimes = 0;

class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    _builtTimes++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

Widget _switcher(String tab) => Directionality(
  textDirection: TextDirection.ltr,
  child: AnimatedSwitcher(
    duration: const Duration(milliseconds: 260),
    layoutBuilder: onlyNewest,
    transitionBuilder: (child, animation) =>
        glassSwitch(child, animation, drift: 18),
    child: KeyedSubtree(
      key: ValueKey(tab),
      child: tab == 'a' ? const SizedBox() : const _Page(),
    ),
  ),
);

void main() {
  testWidgets('a tab is built once, not again when its motion ends', (
    tester,
  ) async {
    await tester.pumpWidget(_switcher('a'));
    _builtTimes = 0;
    await tester.pumpWidget(_switcher('b'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(_builtTimes, 1);
  });
}
