import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

int? _shown;

/// Shows [count] on the installed app's icon, or clears it at zero.
Future<void> setAppBadge(int count) async {
  if (count == _shown) return;
  try {
    final navigator = web.window.navigator;
    if (!navigator.has('setAppBadge')) return;
    await (count > 0 ? navigator.setAppBadge(count) : navigator.clearAppBadge())
        .toDart;
    _shown = count;
  } on Object {
    // Not installed, or the browser has no badges: nothing to show.
  }
}
