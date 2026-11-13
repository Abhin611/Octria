/// A mock interview: Ofy asks a few open questions, the person answers each
/// in their own words, typed or spoken, and Ofy marks them all at the end
/// with what would have made each stronger.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../ai/ai.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/mic_button.dart';
import 'classroom_forms.dart';
import 'step_panel.dart';

class InterviewSheet extends StatefulWidget {
  const InterviewSheet({
    super.key,
    required this.backend,
    required this.brief,
    required this.title,
    this.classroomId = '',
    this.targetId = '',
  });

  final Backend backend;
  final QuizBrief brief;
  final String title;

  /// Where the result is kept. With no classroom it isn't kept.
  final String classroomId;
  final String targetId;

  @override
  State<InterviewSheet> createState() => _InterviewSheetState();
}

class _InterviewSheetState extends State<InterviewSheet> {
  Interview? _interview;
  InterviewReview? _review;
  String? _problem;
  var _index = 0;
  var _marking = false;
  final _answer = TextEditingController();
  final _answers = <String>[];

  /// Whether the result reached this person's results: null while saving.
  bool? _kept;

  @override
  void initState() {
    super.initState();
    _answer.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _problem = null;
      _interview = null;
    });
    try {
      final interview = await widget.backend.ai.makeInterview(widget.brief);
      if (mounted) setState(() => _interview = interview);
    } on AiFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _next() async {
    final interview = _interview!;
    _answers.add(_answer.text.trim());
    _answer.clear();
    if (_answers.length < interview.questions.length) {
      setState(() => _index++);
      return;
    }
    await _mark();
  }

  Future<void> _mark() async {
    final interview = _interview!;
    setState(() {
      _marking = true;
      _problem = null;
    });
    try {
      final review = await widget.backend.ai.reviewInterview(widget.brief, [
        for (final (i, q) in interview.questions.indexed) (q, _answers[i]),
      ]);
      if (!mounted) return;
      setState(() {
        _review = review;
        _marking = false;
      });
      unawaited(_keep(interview, review));
    } on AiFailure catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.message;
          _marking = false;
        });
      }
    } on BackendFailure catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.message;
          _marking = false;
        });
      }
    }
  }

  Future<void> _keep(Interview interview, InterviewReview review) async {
    if (widget.classroomId.isEmpty || review.outOf == 0) return;
    try {
      await widget.backend.saveResult(
        TestResult(
          id: '',
          classroomId: widget.classroomId,
          label: widget.title,
          targetId: widget.targetId,
          right: review.score,
          total: review.outOf,
          mock: true,
          interview: true,
          level: widget.brief.level.stored,
          // What scored under six is worth coming back to.
          missed: [
            for (final (i, q) in interview.questions.indexed)
              if (review.answers[i].score < 6) q.question,
          ],
          at: DateTime.now(),
        ),
      );
      if (mounted) setState(() => _kept = true);
    } on BackendFailure {
      if (mounted) setState(() => _kept = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final interview = _interview;
    if (interview == null || _marking) {
      // Writing the questions, marking the answers, or either went wrong.
      final failed = _problem != null;
      return SheetFrame(
        title: interview?.title ?? widget.title,
        action: !failed
            ? null
            : PressButton(
                label: 'Try again',
                prominent: true,
                height: 46,
                expand: true,
                onTap: () => unawaited(interview == null ? _load() : _mark()),
              ),
        children: [
          const SizedBox(height: 24),
          if (!failed) ...[
            const Center(child: CupertinoActivityIndicator(radius: 13)),
            const SizedBox(height: 12),
            Text(
              _marking
                  ? 'Ofy is reading your answers…'
                  : 'Ofy is writing your interview…',
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.inkSoft),
            ),
          ] else
            Text(_problem!, style: TypeRamp.body(p.ink)),
          const SizedBox(height: 24),
        ],
      );
    }
    final review = _review;
    if (review == null &&
        _problem != null &&
        _answers.length == interview.questions.length) {
      // Marking failed after the last answer: offer it again.
      return SheetFrame(
        title: interview.title,
        action: PressButton(
          label: 'Try again',
          prominent: true,
          height: 46,
          expand: true,
          onTap: () => unawaited(_mark()),
        ),
        children: [
          const SizedBox(height: 18),
          Text(_problem!, style: TypeRamp.body(p.ink)),
          const SizedBox(height: 6),
          Text(
            'Your answers are kept: nothing needs typing again.',
            style: TypeRamp.label(p.inkSoft),
          ),
          const SizedBox(height: 18),
        ],
      );
    }
    if (review != null) {
      final percent = review.outOf == 0
          ? 0
          : (review.score / review.outOf * 100).round();
      return SheetFrame(
        title: interview.title,
        action: PressButton(
          label: 'Finish',
          prominent: true,
          height: 46,
          expand: true,
          onTap: () =>
              Navigator.of(context)
                  .pop(review.outOf == 0 ? 0.0 : review.score / review.outOf),
        ),
        children: [
          const SizedBox(height: 10),
          Text(
            '${review.score} of ${review.outOf}',
            textAlign: TextAlign.center,
            style: TypeRamp.title(p.ink).copyWith(fontSize: 30),
          ),
          const SizedBox(height: 2),
          Text(
            '$percent%',
            textAlign: TextAlign.center,
            style: TypeRamp.label(p.inkSoft),
          ),
          if (review.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.summary,
              textAlign: TextAlign.center,
              style: TypeRamp.body(p.ink),
            ),
          ],
          if (widget.classroomId.isNotEmpty && _kept != null) ...[
            const SizedBox(height: 6),
            Text(
              _kept!
                  ? 'Saved to your results.'
                  : 'This result couldn’t be saved.',
              textAlign: TextAlign.center,
              style: TypeRamp.caption(_kept! ? p.inkSoft : p.blocked),
            ),
          ],
          for (final (i, q) in interview.questions.indexed) ...[
            StepSectionTitle(
              'Question ${i + 1} · ${review.answers[i].score} of 10',
            ),
            Text(
              q.question,
              style: TypeRamp.label(p.ink).weighted(FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _answers[i].isEmpty ? 'You skipped this one.' : _answers[i],
              style: TypeRamp.label(p.inkSoft),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: glassTint(
                p,
                review.answers[i].score >= 6 ? p.done : p.accentWarm,
                radius: 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (review.answers[i].feedback.isNotEmpty)
                    Text(
                      review.answers[i].feedback,
                      style: TypeRamp.label(p.ink),
                    ),
                  if (q.lookFor.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'A strong answer covers: ${q.lookFor}',
                      style: TypeRamp.caption(p.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
        ],
      );
    }
    final q = interview.questions[_index];
    final total = interview.questions.length;
    final last = _index + 1 == total;
    final empty = _answer.text.trim().isEmpty;
    return SheetFrame(
      title: interview.title,
      message: _problem,
      action: PressButton(
        label: empty
            ? (last ? 'Skip and see how I did' : 'Skip this one')
            : (last ? 'See how I did' : 'Next question'),
        prominent: !empty,
        height: 46,
        expand: true,
        onTap: () => unawaited(_next()),
      ),
      children: [
        Text(
          'Question ${_index + 1} of $total',
          style: TypeRamp.caption(p.inkSoft),
        ),
        const SizedBox(height: 8),
        Text(q.question, style: TypeRamp.body(p.ink)),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: GlassField(
                // A new field for each question, so nothing carries over.
                key: ValueKey('answer-$_index'),
                label: 'Your answer, in your own words',
                controller: _answer,
                maxLines: 8,
                minLines: 4,
              ),
            ),
            const SizedBox(width: 8),
            MicButton(
              controller: _answer,
              onUnavailable: () => setState(
                () => _problem = 'Voice isn’t available here. Type it instead.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'A few sentences is enough. Ofy marks every answer at the end.',
          style: TypeRamp.caption(p.inkSoft),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
