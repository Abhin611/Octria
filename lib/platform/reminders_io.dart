import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../model/reminders.dart';

/// True where a reminder arrives at its time even with Octria closed.
bool get remindersArriveWhenClosed =>
    defaultTargetPlatform == TargetPlatform.android;

/// True where this device can show reminders at all.
bool get remindersSupported => defaultTargetPlatform == TargetPlatform.android;

final _plugin = FlutterLocalNotificationsPlugin();
var _ready = false;

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'due_steps',
    'Due steps',
    channelDescription: 'When a step of yours is due or overdue.',
    importance: Importance.high,
    priority: Priority.high,
  ),
);

Future<AndroidFlutterLocalNotificationsPlugin?> _android() async {
  if (!remindersSupported) return null;
  if (!_ready) {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notify'),
      ),
    );
    _ready = true;
  }
  return _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
}

/// Whether the person has let Octria show notifications.
Future<bool> remindersAllowed() async {
  try {
    return await (await _android())?.areNotificationsEnabled() ?? false;
  } on Object {
    return false;
  }
}

/// Asks to show notifications. Call only from a tap.
Future<bool> askForReminders() async {
  try {
    final android = await _android();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ??
        await android.areNotificationsEnabled() ??
        false;
  } on Object {
    return false;
  }
}

/// Replaces every reminder the phone holds with [upcoming]. [todayNote] is
/// for browsers and unused here.
Future<void> setReminders(
  List<Reminder> upcoming, {
  String todayTitle = '',
  String todayBody = '',
}) async {
  try {
    if (await _android() == null) return;
    await _plugin.cancelAll();
    for (final r in upcoming) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        // The moment itself, so the phone's own time zone needn't be known.
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: _details,
        // Within a few minutes is fine, and needs no special permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  } on Object {
    // Reminders are a nicety: the plan itself is unaffected.
  }
}

/// Drops every reminder the phone holds.
Future<void> clearReminders() async {
  try {
    if (await _android() == null) return;
    await _plugin.cancelAll();
  } on Object {
    // Nothing held, nothing to drop.
  }
}
