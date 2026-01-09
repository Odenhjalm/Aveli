import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_access_gate.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/shared/widgets/go_router_back_button.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/widgets/base_page.dart';

class QuizTakePage extends ConsumerStatefulWidget {
  const QuizTakePage({super.key});

  @override
  ConsumerState<QuizTakePage> createState() => _QuizTakePageState();
}

class _QuizTakePageState extends ConsumerState<QuizTakePage> {
  String _quizId = '';
  String _courseId = '';
  bool _initialized = false;
  Map<String, dynamic> _answers = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final state = GoRouterState.of(context);
    final extra = state.extra;
    if (extra is QuizRouteArgs) {
      _quizId = extra.quizId;
      _courseId = extra.courseId ?? '';
    } else {
      final qp = state.uri.queryParameters;
      _quizId = qp['quizId'] ?? qp['id'] ?? '';
      _courseId = qp['courseId'] ?? '';
    }
    _initialized = true;
    ref.listen<AsyncValue<Map<String, dynamic>?>>(
      quizSubmissionProvider(_quizId),
      (previous, next) {
        next.when(
          data: (result) {
            if (result == null) return;
            final passed = result['passed'] == true;
            final message = passed
                ? 'Godkänt! Ditt certifikat är utfärdat.'
                : 'Resultat sparat. Fortsätt öva!';
            if (!mounted || !context.mounted) return;
            showSnack(context, message);
          },
          error: (error, _) {
            if (!mounted || !context.mounted) return;
            showSnack(context, 'Kunde inte lämna in: ${_friendlyError(error)}');
          },
          loading: () {},
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final questions = _quizId.isEmpty
        ? const AsyncValue<List<QuizQuestion>>.data([])
        : ref.watch(quizQuestionsProvider(_quizId));
    final submissionState = _quizId.isEmpty
        ? const AsyncValue<Map<String, dynamic>?>.data(null)
        : ref.watch(quizSubmissionProvider(_quizId));

    Widget content = questions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(_friendlyError(error))),
      data: (items) => _QuizContent(
        quizId: _quizId,
        questions: items,
        answers: _answers,
        onSetSingle: _setSingle,
        onToggleMulti: _toggleMulti,
        onSetBool: _setBool,
        onSubmit: _submit,
        submissionState: submissionState,
      ),
    );

    if (_courseId.isNotEmpty) {
      content = CourseAccessGate(
        courseId: _courseId,
        loading: const Center(child: CircularProgressIndicator()),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const GoRouterBackButton(),
        title: const Text('Quiz'),
      ),
      body: BasePage(child: SafeArea(top: false, child: content)),
    );
  }

  void _setSingle(String qid, int idx) {
    setState(() => _answers = {..._answers, qid: idx});
  }

  void _toggleMulti(String qid, int idx, bool set) {
    final current = (_answers[qid] as List<int>?) ?? <int>[];
    final next = [...current];
    if (set) {
      if (!next.contains(idx)) next.add(idx);
    } else {
      next.remove(idx);
    }
    next.sort();
    setState(() => _answers = {..._answers, qid: next});
  }

  void _setBool(String qid, bool value) {
    setState(() => _answers = {..._answers, qid: value});
  }

  Future<void> _submit() async {
    if (_quizId.isEmpty) {
      showSnack(context, 'Quiz saknas.');
      return;
    }
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      final redirect = GoRouter.of(context).namedLocation(
        AppRoute.courseQuiz,
        queryParameters: {
          'quizId': _quizId,
          if (_courseId.isNotEmpty) 'courseId': _courseId,
        },
      );
      if (!mounted || !context.mounted) return;
      context.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
      return;
    }
    await ref.read(quizSubmissionProvider(_quizId).notifier).submit(_answers);
  }

  String _friendlyError(Object error) => AppFailure.from(error).message;
}

class _QuizContent extends StatelessWidget {
  const _QuizContent({
    required this.quizId,
    required this.questions,
    required this.answers,
    required this.onSetSingle,
    required this.onToggleMulti,
    required this.onSetBool,
    required this.onSubmit,
    required this.submissionState,
  });

  final String quizId;
  final List<QuizQuestion> questions;
  final Map<String, dynamic> answers;
  final void Function(String qid, int idx) onSetSingle;
  final void Function(String qid, int idx, bool set) onToggleMulti;
  final void Function(String qid, bool value) onSetBool;
  final Future<void> Function() onSubmit;
  final AsyncValue<Map<String, dynamic>?> submissionState;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final result = submissionState.whenOrNull(data: (value) => value);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result != null) ...[
                    _ResultBanner(result: result),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: ListView.separated(
                      itemCount: questions.length,
                      separatorBuilder: (context, _) =>
                          const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final question = questions[index];
                        final qid = question.id;
                        final kind = question.kind;
                        final prompt = question.prompt;
                        final options = question.options;
                        return _QuestionWidget(
                          index: index + 1,
                          qid: qid,
                          prompt: prompt,
                          kind: kind,
                          options: options,
                          value: answers[qid],
                          onChangeSingle: (idx) => onSetSingle(qid, idx),
                          onChangeMulti: (idx, value) =>
                              onToggleMulti(qid, idx, value),
                          onChangeBool: (value) => onSetBool(qid, value),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 220,
                      child: GradientButton.icon(
                        onPressed: submissionState.isLoading ? null : onSubmit,
                        icon: submissionState.isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Lämna in'),
                      ),
                    ),
                  ),
                  if (submissionState.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _friendlyError(submissionState.error!),
                        style: t.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(Object error) => AppFailure.from(error).message;
}

class _QuestionWidget extends StatelessWidget {
  const _QuestionWidget({
    required this.index,
    required this.qid,
    required this.prompt,
    required this.kind,
    required this.options,
    required this.value,
    required this.onChangeSingle,
    required this.onChangeMulti,
    required this.onChangeBool,
  });

  final int index;
  final String qid;
  final String prompt;
  final String kind;
  final List<String> options;
  final dynamic value;
  final void Function(int index) onChangeSingle;
  final void Function(int index, bool value) onChangeMulti;
  final void Function(bool value) onChangeBool;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    switch (kind) {
      case 'multi':
        final selected = (value as List<int>?) ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$index. $prompt', style: t.titleMedium),
            gap8,
            ...List.generate(options.length, (i) {
              return CheckboxListTile(
                value: selected.contains(i),
                onChanged: (v) => onChangeMulti(i, v ?? false),
                title: Text(options[i]),
                controlAffinity: ListTileControlAffinity.leading,
              );
            }),
          ],
        );
      case 'bool':
        final boolValue = value == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$index. $prompt', style: t.titleMedium),
            gap8,
            SwitchListTile(
              value: boolValue,
              onChanged: onChangeBool,
              title: const Text('Sant'),
            ),
          ],
        );
      case 'single':
      default:
        final int? selectedValue = value is int ? value as int : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$index. $prompt', style: t.titleMedium),
            gap8,
            RadioGroup<int>(
              groupValue: selectedValue,
              onChanged: (selected) {
                if (selected != null) onChangeSingle(selected);
              },
              child: Column(
                children: [
                  for (var i = 0; i < options.length; i++)
                    RadioListTile<int>(value: i, title: Text(options[i])),
                ],
              ),
            ),
          ],
        );
    }
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final passed = result['passed'] == true;
    final score = result['score'] ?? '';
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: passed ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                passed ? Icons.verified_rounded : Icons.info_outline,
                color: passed
                    ? const Color(0xFF059669)
                    : const Color(0xFFB91C1C),
              ),
              const SizedBox(width: 8),
              Text(
                passed ? 'Grattis!' : 'Resultat',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (score != '') ...[
            const SizedBox(height: 6),
            Text('Poäng: $score'),
          ],
        ],
      ),
    );
  }
}
