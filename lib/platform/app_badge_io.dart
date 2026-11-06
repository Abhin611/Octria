import 'package:app_badge_plus/app_badge_plus.dart';

int? _shown;

/// Shows [count] on the app icon, or clears it at zero.
Future<void> setAppBadge(int count) async {
  if (count == _shown) return;
  try {
    if (!await AppBadgePlus.isSupported()) return;
    await AppBadgePlus.updateBadge(count < 0 ? 0 : count);
    _shown = count;
  } on Object {
    // A launcher without badges simply shows none.
  }
}
