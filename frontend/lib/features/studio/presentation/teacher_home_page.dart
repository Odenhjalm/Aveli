import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/features/teacher/application/bundle_providers.dart';

class TeacherHomeScreen extends ConsumerStatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  ConsumerState<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends ConsumerState<TeacherHomeScreen> {
  final Set<String> _deletingCourseIds = <String>{};
  final Set<String> _hiddenCourseIds = <String>{};

  Future<void> _confirmAndDeleteCourse(
    BuildContext context,
    Map<String, dynamic> course,
  ) async {
    final courseId = course['id']?.toString();
    if (courseId == null || courseId.isEmpty) return;

    final title = course['title']?.toString().trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ta bort kurs'),
        content: Text(
          title == null || title.isEmpty
              ? 'Vill du ta bort kursen? Detta går inte att ångra.'
              : 'Vill du ta bort \"$title\"? Detta går inte att ångra.',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kurs borttagen.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deletingCourseIds.remove(courseId);
        _hiddenCourseIds.remove(courseId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kunde inte ta bort kursen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coursesAsync = ref.watch(myCoursesProvider);
    final bundlesAsync = ref.watch(teacherBundlesProvider);
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
                            'Paketpriser',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        GradientButton.icon(
                          onPressed: () =>
                              context.goNamed(AppRoute.teacherBundles),
                          icon: const Icon(Icons.link_outlined),
                          label: const Text('Skapa paket'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sätt paketpris för flera kurser och dela betalningslänkar direkt i dina lektioner.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    bundlesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                      error: (error, _) => Text(
                        'Kunde inte läsa paket: $error',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      data: (bundles) {
                        if (bundles.isEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Inga paket ännu',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Skapa ett paket för att kombinera flera kurser till rabatterat pris.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: bundles
                              .map(
                                (bundle) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: GlassCard(
                                    opacity: 0.18,
                                    padding: const EdgeInsets.all(16),
                                    borderColor: Colors.white.withValues(
                                      alpha: 0.15,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                bundle['title'] as String? ??
                                                    'Paket',
                                                style: theme
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            if (bundle['is_active'] == true)
                                              _CourseBadge(
                                                icon:
                                                    Icons.check_circle_outline,
                                                label: 'Aktivt',
                                              )
                                            else
                                              _CourseBadge(
                                                icon: Icons.pause_circle,
                                                label: 'Inaktivt',
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          bundle['description'] as String? ??
                                              '',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            TextButton.icon(
                                              onPressed: () async {
                                                final link =
                                                    bundle['payment_link']
                                                        as String? ??
                                                    '';
                                                if (link.isEmpty) return;
                                                await Clipboard.setData(
                                                  ClipboardData(text: link),
                                                );
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Betalningslänk kopierad',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              icon: const Icon(Icons.copy),
                                              label: const Text('Kopiera länk'),
                                            ),
                                            const SizedBox(width: 8),
                                            if (bundle['courses'] is List &&
                                                (bundle['courses'] as List)
                                                    .isNotEmpty)
                                              Wrap(
                                                spacing: 6,
                                                children:
                                                    (bundle['courses']
                                                            as List<dynamic>)
                                                        .take(3)
                                                        .map((course) {
                                                          final c =
                                                              course
                                                                  as Map<
                                                                    String,
                                                                    dynamic
                                                                  >;
                                                          return _CourseBadge(
                                                            icon:
                                                                Icons.menu_book,
                                                            label:
                                                                c['title']
                                                                    as String? ??
                                                                'Kurs',
                                                          );
                                                        })
                                                        .toList(),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
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
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Fel vid hämtning av kurser: $e',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      data: (courses) {
                        final visibleCourses = courses
                            .where((course) {
                              final id = course['id']?.toString();
                              if (id == null || id.isEmpty) return true;
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
                                    final id = course['id'] as String?;
                                    if (id == null) return;
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
                                              (course['title'] ??
                                                      'Namnlös kurs')
                                                  as String,
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
                                                  icon: Icons.sell_outlined,
                                                  label:
                                                      course['branch']
                                                          as String? ??
                                                      'Allmänt',
                                                ),
                                                _CourseBadge(
                                                  icon:
                                                      course['is_free_intro'] ==
                                                          true
                                                      ? Icons
                                                            .workspace_premium_outlined
                                                      : Icons.lock_outline,
                                                  label:
                                                      course['is_free_intro'] ==
                                                          true
                                                      ? 'Introduktion'
                                                      : 'Premium',
                                                ),
                                                _CourseBadge(
                                                  icon:
                                                      course['is_published'] ==
                                                          true
                                                      ? Icons.public_outlined
                                                      : Icons.drafts_outlined,
                                                  label:
                                                      course['is_published'] ==
                                                          true
                                                      ? 'Publicerad'
                                                      : 'Utkast',
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
                                              final courseId = course['id']
                                                  ?.toString();
                                              final isDeleting =
                                                  courseId != null &&
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
                      'Liveseminarier',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Planera och sänd live-seminarier med deltagare från Aveli-communityn. Du kan skapa schemalagda rum, bjuda in deltagare och starta sändningen direkt från studion.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    GradientButton.icon(
                      onPressed: () => context.goNamed(AppRoute.seminarStudio),
                      icon: const Icon(Icons.live_tv_outlined),
                      label: const Text('Öppna liveseminarier'),
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
