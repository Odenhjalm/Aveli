import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class TeacherHomeScreen extends ConsumerStatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  ConsumerState<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends ConsumerState<TeacherHomeScreen> {
  final Set<String> _deletingCourseIds = <String>{};
  final Set<String> _hiddenCourseIds = <String>{};
  final TextEditingController _referralEmailCtrl = TextEditingController();
  final TextEditingController _referralDurationCtrl = TextEditingController(
    text: '14',
  );
  String _referralDurationUnit = 'days';
  bool _sendingReferral = false;
  String? _specialOfferAction;

  @override
  void dispose() {
    _referralEmailCtrl.dispose();
    _referralDurationCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDeleteCourse(
    BuildContext context,
    CourseStudio course,
  ) async {
    final courseId = course.id.trim();
    if (courseId.isEmpty) return;

    final title = course.title.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ta bort kurs'),
        content: Text(
          title.isEmpty
              ? 'Vill du ta bort kursen? Detta går inte att ångra.'
              : 'Vill du ta bort "$title"? Detta går inte att ångra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _deletingCourseIds.add(courseId);
      _hiddenCourseIds.add(courseId);
    });

    try {
      final repo = ref.read(studioRepositoryProvider);
      await repo.deleteCourse(courseId);
      if (!mounted) return;
      setState(() => _deletingCourseIds.remove(courseId));
      ref.invalidate(myCoursesProvider);
      ref.invalidate(studioCoursesProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kurs borttagen.')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deletingCourseIds.remove(courseId);
        _hiddenCourseIds.remove(courseId);
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunde inte ta bort kursen.')),
      );
    }
  }

  Future<void> _sendReferralInvitation(BuildContext context) async {
    final email = _referralEmailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ange en giltig e-postadress.')),
      );
      return;
    }

    final durationValue = int.tryParse(_referralDurationCtrl.text.trim());
    if (durationValue == null || durationValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ange en giltig längd för inbjudan.')),
      );
      return;
    }

    setState(() => _sendingReferral = true);
    try {
      final repo = ref.read(studioRepositoryProvider);
      await repo.createReferralInvitation(
        email: email,
        freeDays: _referralDurationUnit == 'days' ? durationValue : null,
        freeMonths: _referralDurationUnit == 'months' ? durationValue : null,
      );
      if (!mounted || !context.mounted) return;
      _referralEmailCtrl.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Inbjudan skickad till $email')));
    } catch (_) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunde inte skicka inbjudan.')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingReferral = false);
      }
    }
  }

  Future<_SpecialOfferDraft?> _showSpecialOfferDialog(
    BuildContext context, {
    required List<CourseStudio> courses,
    SpecialOfferExecutionState? initialOffer,
  }) {
    final priceController = TextEditingController(
      text: initialOffer == null
          ? ''
          : (initialOffer.priceAmountCents ~/ 100).toString(),
    );
    final selectedCourseIds = <String>{...?initialOffer?.courseIds};
    String? validationMessage;

    return showDialog<_SpecialOfferDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                initialOffer == null
                    ? 'Skapa erbjudande'
                    : 'Redigera erbjudande',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pris (kr)',
                          prefixText: 'kr ',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Välj kurser',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final course in courses)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selectedCourseIds.contains(course.id),
                          onChanged: (selected) {
                            setDialogState(() {
                              if (selected == true) {
                                if (selectedCourseIds.length < 5) {
                                  selectedCourseIds.add(course.id);
                                }
                              } else {
                                selectedCourseIds.remove(course.id);
                              }
                              validationMessage = null;
                            });
                          },
                          title: Text(course.title),
                          subtitle: Text(_coursePositionLabel(course)),
                        ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationMessage!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Avbryt'),
                ),
                FilledButton(
                  onPressed: () {
                    final priceKronor = int.tryParse(
                      priceController.text.replaceAll(' ', '').trim(),
                    );
                    if (priceKronor == null || priceKronor <= 0) {
                      setDialogState(() {
                        validationMessage = 'Ange ett giltigt pris.';
                      });
                      return;
                    }
                    if (selectedCourseIds.isEmpty ||
                        selectedCourseIds.length > 5) {
                      setDialogState(() {
                        validationMessage = 'Välj mellan 1 och 5 kurser.';
                      });
                      return;
                    }
                    final orderedCourseIds = courses
                        .where(
                          (course) => selectedCourseIds.contains(course.id),
                        )
                        .map((course) => course.id)
                        .toList(growable: false);
                    Navigator.of(dialogContext).pop(
                      _SpecialOfferDraft(
                        priceAmountCents: priceKronor * 100,
                        courseIds: orderedCourseIds,
                      ),
                    );
                  },
                  child: Text(
                    initialOffer == null
                        ? 'Skapa erbjudande'
                        : 'Spara erbjudande',
                  ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(priceController.dispose);
  }

  Future<void> _editSpecialOffer(
    BuildContext context, {
    required List<CourseStudio> courses,
    SpecialOfferExecutionState? currentOffer,
  }) async {
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Du behöver minst en kurs för att skapa ett erbjudande.',
          ),
        ),
      );
      return;
    }

    final draft = await _showSpecialOfferDialog(
      context,
      courses: courses,
      initialOffer: currentOffer,
    );
    if (draft == null) return;

    setState(() => _specialOfferAction = 'save');
    try {
      final repo = ref.read(studioRepositoryProvider);
      if (currentOffer == null) {
        await repo.createSpecialOfferExecution(
          courseIds: draft.courseIds,
          priceAmountCents: draft.priceAmountCents,
        );
      } else {
        await repo.updateSpecialOfferExecution(
          currentOffer.specialOfferId,
          courseIds: draft.courseIds,
          priceAmountCents: draft.priceAmountCents,
        );
      }
    } catch (_) {
      // Execution state is rendered from backend after invalidation below.
    } finally {
      if (mounted) {
        ref.invalidate(teacherSpecialOfferExecutionProvider);
        setState(() => _specialOfferAction = null);
      }
    }
  }

  Future<void> _generateSpecialOfferImage(
    BuildContext context,
    SpecialOfferExecutionState offer,
  ) async {
    setState(() => _specialOfferAction = 'generate');
    try {
      final repo = ref.read(studioRepositoryProvider);
      await repo.generateSpecialOfferImage(offer.specialOfferId);
    } catch (_) {
      // Execution state is rendered from backend after invalidation below.
    } finally {
      if (mounted) {
        ref.invalidate(teacherSpecialOfferExecutionProvider);
        setState(() => _specialOfferAction = null);
      }
    }
  }

  Future<void> _confirmAndRegenerateSpecialOffer(
    BuildContext context,
    SpecialOfferExecutionState offer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uppdatera erbjudande'),
        content: const Text(
          'Detta kommer ersätta den nuvarande bilden. Vill du fortsätta?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fortsätt'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _specialOfferAction = 'regenerate');
    try {
      final repo = ref.read(studioRepositoryProvider);
      await repo.regenerateSpecialOfferImage(
        offer.specialOfferId,
        confirmOverwrite: true,
      );
    } catch (_) {
      // Execution state is rendered from backend after invalidation below.
    } finally {
      if (mounted) {
        ref.invalidate(teacherSpecialOfferExecutionProvider);
        setState(() => _specialOfferAction = null);
      }
    }
  }

  bool _isValidEmail(String value) {
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return regex.hasMatch(value);
  }

  static String _coursePositionLabel(CourseStudio course) {
    if (course.groupPosition <= 0) return 'Position 0';
    return 'Position ${course.groupPosition}';
  }

  String _courseReleaseLabel(CourseStudio course) {
    if (!course.dripEnabled) return 'Direktstart';
    final interval = course.dripIntervalDays;
    if (interval == null) return 'Dropp aktivt';
    return 'Dropp $interval dagar';
  }

  String _formatPrice(int amountCents) {
    final kronor = amountCents ~/ 100;
    final ore = amountCents % 100;
    final digits = kronor.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index += 1) {
      final reverseIndex = digits.length - index;
      buffer.write(digits[index]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(' ');
      }
    }
    final formattedWhole = buffer.toString();
    if (ore == 0) {
      return '$formattedWhole kr';
    }
    return '$formattedWhole,${ore.toString().padLeft(2, '0')} kr';
  }

  Widget _buildSpecialOfferSection(
    BuildContext context, {
    required ThemeData theme,
    required AsyncValue<List<CourseStudio>> coursesAsync,
  }) {
    final specialOfferAsync = ref.watch(teacherSpecialOfferExecutionProvider);
    final courses = coursesAsync.valueOrNull ?? const <CourseStudio>[];
    final canOpenOfferEditor =
        _specialOfferAction == null &&
        coursesAsync.hasValue &&
        courses.isNotEmpty;
    final formActionLabel = specialOfferAsync.valueOrNull == null
        ? 'Skapa erbjudande'
        : 'Redigera erbjudande';

    return GlassCard(
      padding: const EdgeInsets.all(24),
      opacity: 0.16,
      borderColor: Colors.white.withValues(alpha: 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Erbjudanden',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hantera ett backendstyrt erbjudande med bild, pris och aktuell status.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GradientButton.icon(
                onPressed: canOpenOfferEditor
                    ? () => _editSpecialOffer(
                        context,
                        courses: courses,
                        currentOffer: specialOfferAsync.valueOrNull,
                      )
                    : null,
                icon: _specialOfferAction == 'save'
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.local_offer_outlined),
                label: Text(formActionLabel),
              ),
            ],
          ),
          const SizedBox(height: 20),
          specialOfferAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (error, stackTrace) => Text(
              'Erbjudandet kunde inte laddas.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            data: (offer) {
              if (offer == null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inget erbjudande skapat ännu.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Skapa ett erbjudande för att välja kurser, sätta pris och generera en bild.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                );
              }

              final statusLabel = offer.imageCurrent
                  ? 'aktuell'
                  : 'behöver uppdateras';
              final statusIcon = offer.imageCurrent
                  ? Icons.check_circle_outline
                  : Icons.update_outlined;
              final generatingImage = _specialOfferAction == 'generate';
              final regeneratingImage = _specialOfferAction == 'regenerate';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (offer.hasRenderableImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.network(
                          offer.image!.resolvedUrl!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 42,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Ingen erbjudandebild ännu.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _CourseBadge(
                        icon: Icons.sell_outlined,
                        label: _formatPrice(offer.priceAmountCents),
                      ),
                      _CourseBadge(icon: statusIcon, label: statusLabel),
                      _CourseBadge(
                        icon: Icons.collections_outlined,
                        label: '${offer.sourceCount} kurser',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      TextButton.icon(
                        onPressed: _specialOfferAction != null
                            ? null
                            : () => _editSpecialOffer(
                                context,
                                courses: courses,
                                currentOffer: offer,
                              ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Redigera erbjudande'),
                      ),
                      if (offer.activeOutputId == null)
                        GradientButton.icon(
                          onPressed: generatingImage
                              ? null
                              : () =>
                                    _generateSpecialOfferImage(context, offer),
                          icon: generatingImage
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_outlined),
                          label: Text(
                            generatingImage
                                ? 'Genererar bild...'
                                : 'Generera bild',
                          ),
                        ),
                      if (offer.activeOutputId != null && offer.imageRequired)
                        GradientButton.icon(
                          onPressed: regeneratingImage
                              ? null
                              : () => _confirmAndRegenerateSpecialOffer(
                                  context,
                                  offer,
                                ),
                          icon: regeneratingImage
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_outlined),
                          label: Text(
                            regeneratingImage
                                ? 'Uppdaterar erbjudande...'
                                : 'Uppdatera erbjudande',
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coursesAsync = ref.watch(studioCoursesProvider);
    return AppScaffold(
      title: 'Kurstudio',
      maxContentWidth: 980,
      logoSize: 0,
      showHomeAction: false,
      onBack: () => context.goNamed(AppRoute.home),
      actions: const [TopNavActionButtons()],
      contentPadding: EdgeInsets.zero,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Studio för lärare',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Administrera dina kurser, publicera nytt innehåll och följ din katalog.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              _buildSpecialOfferSection(
                context,
                theme: theme,
                coursesAsync: coursesAsync,
              ),
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(24),
                opacity: 0.16,
                borderColor: Colors.white.withValues(alpha: 0.15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Media-spelaren',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Välj vilka meditationer och livesändningar som ska presenteras på din offentliga sida. Ladda upp omslag, redigera titlar och styr ordningen.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    GradientButton.icon(
                      onPressed: () => context.goNamed(AppRoute.studioProfile),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Öppna spelarens kontrollpanel'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(24),
                opacity: 0.16,
                borderColor: Colors.white.withValues(alpha: 0.15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Mina kurser',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        GradientButton.icon(
                          onPressed: () =>
                              context.goNamed(AppRoute.teacherEditor),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Skapa kurs'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    coursesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, stackTrace) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Kurserna kunde inte laddas.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      data: (courses) {
                        final visibleCourses = courses
                            .where((course) {
                              final id = course.id.trim();
                              if (id.isEmpty) return true;
                              return !_hiddenCourseIds.contains(id);
                            })
                            .toList(growable: false);
                        if (visibleCourses.isEmpty) {
                          return Column(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 52,
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Du har inga kurser ännu.',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Skapa din första kurs för att komma igång.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 16),
                              GradientButton(
                                onPressed: () =>
                                    context.goNamed(AppRoute.teacherEditor),
                                child: const Text('Skapa första kursen'),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            for (final course in visibleCourses)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: GlassCard(
                                  opacity: 0.18,
                                  borderColor: Colors.white.withValues(
                                    alpha: 0.18,
                                  ),
                                  padding: const EdgeInsets.all(18),
                                  onTap: () {
                                    final id = course.id;
                                    context.goNamed(
                                      AppRoute.teacherEditor,
                                      extra: CourseEditorRouteArgs(
                                        courseId: id,
                                      ),
                                    );
                                  },
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              course.title,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 6,
                                              children: [
                                                _CourseBadge(
                                                  icon: Icons.route_outlined,
                                                  label: _coursePositionLabel(
                                                    course,
                                                  ),
                                                ),
                                                _CourseBadge(
                                                  icon: Icons.schedule_outlined,
                                                  label: _courseReleaseLabel(
                                                    course,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Builder(
                                            builder: (context) {
                                              final courseId = course.id;
                                              final isDeleting =
                                                  _deletingCourseIds.contains(
                                                    courseId,
                                                  );
                                              return IconButton(
                                                tooltip: 'Ta bort kurs',
                                                onPressed: isDeleting
                                                    ? null
                                                    : () =>
                                                          _confirmAndDeleteCourse(
                                                            context,
                                                            course,
                                                          ),
                                                icon: isDeleting
                                                    ? const SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      )
                                                    : Icon(
                                                        Icons.delete_outline,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                              );
                                            },
                                          ),
                                          Icon(
                                            Icons.chevron_right,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(24),
                opacity: 0.16,
                borderColor: Colors.white.withValues(alpha: 0.15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Skapa inbjudningskod',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Skicka en personlig medlemsinbjudan som ger tillfällig tillgång utan Stripe-provperiod.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _referralEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-post',
                        hintText: 'namn@example.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _referralDurationCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Längd',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _referralDurationUnit,
                            decoration: const InputDecoration(
                              labelText: 'Enhet',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'days',
                                child: Text('Dagar'),
                              ),
                              DropdownMenuItem(
                                value: 'months',
                                child: Text('Månader'),
                              ),
                            ],
                            onChanged: _sendingReferral
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(
                                      () => _referralDurationUnit = value,
                                    );
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GradientButton(
                      onPressed: _sendingReferral
                          ? null
                          : () => _sendReferralInvitation(context),
                      child: _sendingReferral
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Skicka inbjudan'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseBadge extends StatelessWidget {
  const _CourseBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurface),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecialOfferDraft {
  const _SpecialOfferDraft({
    required this.priceAmountCents,
    required this.courseIds,
  });

  final int priceAmountCents;
  final List<String> courseIds;
}
