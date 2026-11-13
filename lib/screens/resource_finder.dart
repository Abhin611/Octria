/// Ofy searches the web for things worth reading or watching for one step.
/// The person picks which to keep; kept ones join the step's study materials.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../model/plan.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'classroom_forms.dart';
import 'room_lists.dart';
import 'step_collab.dart';

/// The searches Google suggests beside an answer it helped with. Each opens
/// that search on Google.
class GoogleSuggestions extends StatelessWidget {
  const GoogleSuggestions({super.key, required this.searches});

  final List<String> searches;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (searches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Search on Google', style: TypeRamp.caption(p.inkSoft)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final q in searches)
              PressButton(
                label: q,
                icon: CupertinoIcons.search,
                quiet: true,
                height: 36,
                onTap: () => unawaited(
                  launchUrl(
                    googleSearchLink(q),
                    mode: LaunchMode.externalApplication,
                    webOnlyWindowName: '_blank',
                  ).catchError((Object _) => false),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class ResourceFinderSheet extends StatefulWidget {
  const ResourceFinderSheet({
    super.key,
    required this.backend,
    required this.classroomId,
    required this.subject,
    required this.step,
    required this.have,
  });

  final Backend backend;
  final String classroomId;

  /// The classroom's task.
  final String subject;
  final PlanStep step;

  /// Links the step has already.
  final List<String> have;

  @override
  State<ResourceFinderSheet> createState() => _ResourceFinderSheetState();
}

class _ResourceFinderSheetState extends State<ResourceFinderSheet> {
  ResourceFind? _found;
  String? _problem;

  /// Links kept so far in this sheet.
  final _kept = <String>{};
  final _keeping = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    setState(() {
      _found = null;
      _problem = null;
    });
    try {
      final found = await widget.backend.ai.findResources(
        ResourceBrief(
          subject: widget.subject,
          step: widget.step.title,
          description: widget.step.description,
          have: [...widget.have, ..._kept],
        ),
      );
      if (mounted) setState(() => _found = found);
    } on AiFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _keep(FoundResource r) async {
    setState(() {
      _keeping.add(r.url);
      _problem = null;
    });
    try {
      await widget.backend.saveMaterial(
        widget.classroomId,
        StudyMaterial(
          id: widget.backend.newId(),
          kind: r.video ? MaterialKind.video : MaterialKind.link,
          title: r.title,
          url: r.url,
          note: r.why,
          stepId: widget.step.id,
          ownerUid: widget.backend.currentUser?.uid ?? '',
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) setState(() => _kept.add(r.url));
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _keeping.remove(r.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final found = _found;
    if (found == null) {
      return SheetFrame(
        title: 'Find with Ofy',
        action: _problem == null
            ? null
            : PressButton(
                label: 'Try again',
                prominent: true,
                height: 46,
                expand: true,
                onTap: () => unawaited(_search()),
              ),
        children: [
          const SizedBox(height: 24),
          if (_problem == null) ...[
            const Center(child: CupertinoActivityIndicator(radius: 13)),
            const SizedBox(height: 12),
            Text(
              'Ofy is searching the web for “${widget.step.title}”…',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          ] else
            Text(_problem!, style: TypeRamp.body(p.ink)),
          const SizedBox(height: 24),
        ],
      );
    }
    return SheetFrame(
      title: 'Find with Ofy',
      message: _problem,
      action: PressButton(
        label: _kept.isEmpty ? 'Close' : 'Done: ${_kept.length} kept',
        prominent: _kept.isNotEmpty,
        height: 46,
        expand: true,
        onTap: () => Navigator.of(context).pop(_kept.length),
      ),
      children: [
        Text(
          found.resources.isEmpty
              ? 'Ofy found nothing good enough for “${widget.step.title}”.'
              : 'For “${widget.step.title}”. Open one to look, and keep '
                    'what’s useful: it joins this step’s study materials.',
          style: TypeRamp.label(p.inkSoft),
        ),
        const SizedBox(height: 12),
        for (final r in found.resources)
          ListRow(
            lines: 3,
            title: r.title,
            detail: sentences([
              Uri.tryParse(r.url)?.host.replaceFirst('www.', '') ?? '',
              if (r.why.isNotEmpty) r.why,
              if (!r.confirmed)
                'Ofy couldn’t confirm this link: check it opens.',
            ]),
            leading: Icon(
              r.video ? CupertinoIcons.play_rectangle : CupertinoIcons.link,
              size: 20,
              color: r.confirmed ? p.accent : p.inkFaint,
            ),
            trailing: _kept.contains(r.url)
                ? Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    size: 22,
                    color: p.done,
                  )
                : PressButton(
                    label: 'Keep',
                    height: 36,
                    onTap: _keeping.contains(r.url)
                        ? null
                        : () => unawaited(_keep(r)),
                  ),
            onTap: () => unawaited(openLink(r.url)),
          ),
        if (found.searches.isNotEmpty) ...[
          const SizedBox(height: 8),
          GoogleSuggestions(searches: found.searches),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: PressButton(
            label: 'Search again',
            icon: CupertinoIcons.arrow_clockwise,
            quiet: true,
            onTap: () => unawaited(_search()),
          ),
        ),
        Text(
          'These come from a web search, so open one before you rely on it. '
          'Each search uses one of your Ofy requests for today.',
          style: TypeRamp.caption(p.inkFaint),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
