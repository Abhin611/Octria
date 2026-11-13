/// The reminders switch on the profile page: on or off for this device, and
/// what time of day they come.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/reminder_prefs.dart';
import '../platform/reminders.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';

class ReminderSettings extends StatefulWidget {
  const ReminderSettings({super.key, required this.onChanged});

  /// Called once a change is kept, to set the reminders again.
  final VoidCallback onChanged;

  @override
  State<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<ReminderSettings> {
  var _prefs = const ReminderPrefs();
  var _loaded = false;
  String? _problem;

  static const _times = [
    (8, 'Morning, 8 am'),
    (13, 'Midday, 1 pm'),
    (18, 'Evening, 6 pm'),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await ReminderPrefs.load();
    // Switched on, then blocked in the phone's or browser's own settings.
    final blocked = prefs.on && !await remindersAllowed();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loaded = true;
      _problem = blocked ? _blockedText : null;
    });
  }

  String get _blockedText => remindersArriveWhenClosed
      ? 'Notifications are off for Octria. Allow them in your phone’s '
            'settings, under Apps, then Octria.'
      : 'This browser is blocking notifications from Octria. Allow them '
            'from the padlock beside the address, then switch this on again.';

  Future<void> _keep(ReminderPrefs next) async {
    setState(() => _prefs = next);
    await next.save();
    widget.onChanged();
  }

  Future<void> _toggle() async {
    if (_prefs.on) {
      setState(() => _problem = null);
      await _keep(ReminderPrefs(hour: _prefs.hour));
      return;
    }
    final allowed = await remindersAllowed() || await askForReminders();
    if (!mounted) return;
    if (!allowed) {
      setState(() => _problem = _blockedText);
      return;
    }
    setState(() => _problem = null);
    await _keep(ReminderPrefs(on: true, hour: _prefs.hour));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (!remindersSupported) return const SizedBox.shrink();
    final on = _prefs.on;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              on ? CupertinoIcons.bell_fill : CupertinoIcons.bell_slash,
              size: 20,
              color: on ? p.accent : p.inkFaint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminders',
                    style: TypeRamp.label(p.ink).weighted(FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    remindersArriveWhenClosed
                        ? 'The day before a step is due, the day it’s due, '
                              'and the day after if it slips. They arrive on '
                              'this phone even when Octria is closed.'
                        : 'When you open Octria here, it tells you once a '
                              'day what’s due or overdue. A browser can’t '
                              'remind you while Octria is closed; the phone '
                              'app can.',
                    style: TypeRamp.caption(p.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PressButton(
              label: on ? 'Turn off' : 'Turn on',
              prominent: !on,
              height: 44,
              onTap: _loaded ? () => unawaited(_toggle()) : null,
            ),
          ],
        ),
        if (on && remindersArriveWhenClosed) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (hour, label) in _times)
                SelectChip(
                  label: label,
                  selected: _prefs.hour == hour,
                  onTap: () =>
                      unawaited(_keep(ReminderPrefs(on: true, hour: hour))),
                ),
            ],
          ),
        ],
        if (_problem != null) ...[
          const SizedBox(height: 8),
          Text(_problem!, style: TypeRamp.caption(p.blocked)),
        ],
      ],
    );
  }
}
