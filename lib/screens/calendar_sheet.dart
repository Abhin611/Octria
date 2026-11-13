/// Puts steps in the person's own calendar: one step through Google Calendar,
/// or any number as a file every calendar opens.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/calendar.dart';
import '../platform/save_file.dart';
import '../theme/tokens.dart';
import 'classroom_forms.dart';
import 'room_lists.dart';

/// A named group of events to offer, such as "My steps".
typedef CalendarChoice = (String label, List<CalEvent> events);

/// A file name made from a classroom's or person's name.
String calendarFileName(String name) {
  final safe = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'octria-${safe.isEmpty ? 'steps' : safe}.ics';
}

class CalendarSheet extends StatefulWidget {
  const CalendarSheet({
    super.key,
    required this.choices,
    required this.fileName,
    this.now,
  });

  /// One choice with one event is a single step, which also gets the Google
  /// Calendar shortcut.
  final List<CalendarChoice> choices;
  final String fileName;
  final DateTime? now;

  @override
  State<CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<CalendarSheet> {
  String? _said;
  var _failed = false;

  Future<void> _file(List<CalEvent> events) async {
    final ok = await saveTextFile(
      widget.fileName,
      'text/calendar',
      icsFor(events, now: widget.now ?? DateTime.now()),
    );
    if (!mounted) return;
    setState(() {
      _failed = !ok;
      _said = !ok
          ? 'The calendar file couldn’t be made. Please try again.'
          : savesToDownloads
          ? 'Saved to Downloads as ${widget.fileName}. Open it and your '
                'calendar offers to add ${events.length == 1 ? 'the step' : 'the steps'}.'
          : 'Choose your calendar app, or save the file and open it later.';
    });
  }

  Future<void> _google(CalEvent e) async {
    var ok = false;
    try {
      ok = await launchUrl(
        googleCalendarLink(e),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _failed = !ok;
      _said = ok
          ? 'Google Calendar opened with the step filled in. Press Save there.'
          : 'Google Calendar couldn’t open. Use the calendar file instead.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final choices = widget.choices.where((c) => c.$2.isNotEmpty).toList();
    final single = choices.length == 1 && choices.first.$2.length == 1
        ? choices.first.$2.first
        : null;
    return SheetFrame(
      title: 'Add to calendar',
      children: [
        if (choices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              single != null
                  ? '“${single.title}” goes on '
                        '${shortDate(single.day)}, the day it’s due.'
                  : 'Each step goes on the day it’s due, as an all-day '
                        'event. Finished steps are left out.',
              style: TypeRamp.label(p.inkSoft),
            ),
          ),
        if (choices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Nothing to add: there are no unfinished steps.',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          ),
        if (single != null)
          ListRow(
            title: 'Open in Google Calendar',
            detail: 'Starts a new event, filled in. You press Save.',
            leading: Icon(CupertinoIcons.calendar, size: 20, color: p.accent),
            trailing: Icon(
              CupertinoIcons.arrow_up_right,
              size: 14,
              color: p.inkFaint,
            ),
            onTap: () => unawaited(_google(single)),
          ),
        for (final (label, events) in choices)
          ListRow(
            title: single != null ? 'Get a calendar file' : label,
            detail: single != null
                ? 'Works with Apple Calendar, Outlook and others.'
                : '${events.length} ${events.length == 1 ? 'step' : 'steps'}, '
                      'from ${shortDate(events.first.day)} to '
                      '${shortDate(events.last.day)}',
            leading: Icon(
              CupertinoIcons.calendar_badge_plus,
              size: 20,
              color: p.accent,
            ),
            trailing: Icon(
              savesToDownloads
                  ? CupertinoIcons.arrow_down_to_line
                  : CupertinoIcons.share,
              size: 14,
              color: p.inkFaint,
            ),
            onTap: () => unawaited(_file(events)),
          ),
        if (_said != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _said!,
              style: TypeRamp.label(_failed ? p.blocked : p.ink),
            ),
          ),
        if (single == null && choices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'If a date changes later, add the steps again: calendars that '
              'recognise them update the old events.',
              style: TypeRamp.caption(p.inkSoft),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}
