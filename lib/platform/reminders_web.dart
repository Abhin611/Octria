import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../model/reminders.dart';

/// True where a reminder arrives at its time even with Octria closed.
bool get remindersArriveWhenClosed => false;

/// True where this browser can show notifications at all.
bool get remindersSupported {
  try {
    return globalContext.has('Notification');
  } on Object {
    return false;
  }
}

/// Whether the person has let this site show notifications.
Future<bool> remindersAllowed() async {
  try {
    return remindersSupported && web.Notification.permission == 'granted';
  } on Object {
    return false;
  }
}

/// Asks to show notifications. Call only from a tap, or browsers refuse.
Future<bool> askForReminders() async {
  try {
    if (!remindersSupported) return false;
    final answer = await web.Notification.requestPermission().toDart;
    return answer.toDart == 'granted';
  } on Object {
    return false;
  }
}

String? _shownOn;

/// A browser can't hold reminders for later, so [upcoming] is unused: it
/// shows today's note once a day, while Octria is open.
Future<void> setReminders(
  List<Reminder> upcoming, {
  String todayTitle = '',
  String todayBody = '',
}) async {
  try {
    if (todayTitle.isEmpty || !await remindersAllowed()) return;
    final now = DateTime.now();
    final day = '${now.year}-${now.month}-${now.day}';
    final storage = web.window.localStorage;
    if (_shownOn == day || storage.getItem('octria.reminded') == day) return;
    _shownOn = day;
    storage.setItem('octria.reminded', day);
    web.Notification(
      todayTitle,
      web.NotificationOptions(body: todayBody, tag: 'octria-due'),
    );
  } on Object {
    // Some phone browsers only notify through an installed app. The
    // dashboard shows the same thing.
  }
}

/// Nothing is held in a browser.
Future<void> clearReminders() async {}
