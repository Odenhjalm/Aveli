import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/card_text.dart';

class CourseCatalogPage extends ConsumerWidget {
  const CourseCatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final popularAsync = ref.watch(landing.popularCoursesProvider);
    final myAsync = ref.watch(landing.myStudioCoursesProvider);
    final mediaRepository = ref.watch(mediaRepositoryProvider);

    final combined = _combineCourses(
      popularAsync.valueOrNull,
      myAsync.valueOrNull,
      mediaRepository,
    );
    final isLoading =
        popularAsync.isLoading || myAsync.isLoading || combined == null;
    final Object? error = popularAsync.error ?? myAsync.error;
    final courses = combined ?? const <Map<String, dynamic>>[];

    return AppScaffold(
      title: 'Alla kurser',
      showHomeAction: false,
      actions: const [TopNavActionButtons()],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? _ErrorState(error: error)
              : _CourseList(courses: courses, theme: theme),
        ),
      ),
    );
  }

  List<Map<String, dynamic>>? _combineCourses(
    landing.LandingSectionState? popular,
    landing.LandingSectionState? myCourses,
    MediaRepository mediaRepository,
  ) {
    if (popular == null && myCourses == null) return null;
    final items = <Map<String, dynamic>>[];
    final seen = <String>{};

    void add(Map<String, dynamic> raw) {
      final map = Map<String, dynamic>.from(raw);
      final slug = (map['slug'] as String?)?.trim();
      final id = (map['id'] as String?)?.trim();
      final key = slug?.isNotEmpty == true
          ? slug!
          : (id ?? map.hashCode.toString());
      if (seen.contains(key)) return;
      seen.add(key);
      items.add(map);
    }

    final ownPublished = <Map<String, dynamic>>[];
    if (myCourses != null) {
      for (final course in myCourses.items) {
        if (course['is_published'] == true) {
          add(course);
          ownPublished.add(Map<String, dynamic>.from(course));
        }
      }
    }

    if (ownPublished.isNotEmpty) {
      items
        ..clear()
        ..addAll(ownPublished);
    } else if (popular != null) {
      for (final course in popular.items) {
        add(course);
      }
    }

    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    int priorityFor(Map<String, dynamic> item) {
      final raw = item['teacher_priority'];
      if (raw is num) return raw.toInt();
      if (raw is String) {
        final parsed = int.tryParse(raw);
        if (parsed != null) return parsed;
      }
      return 1000;
    }

    items.sort((a, b) {
      final priorityCompare = priorityFor(a).compareTo(priorityFor(b));
      if (priorityCompare != 0) return priorityCompare;
      final aUpdated = parseDate(a['updated_at'] ?? a['created_at']);
      final bUpdated = parseDate(b['updated_at'] ?? b['created_at']);
      return bUpdated.compareTo(aUpdated);
    });

    for (final item in items) {
      final cover = item['cover_url'] as String?;
      if (cover != null && cover.isNotEmpty) {
        final resolved = _resolveMediaUrl(mediaRepository, cover) ?? cover;
        item['cover_url'] = resolved;
      }
    }
    return items;
  }

  String? _resolveMediaUrl(MediaRepository repository, String? path) {
    if (path == null || path.isEmpty) return path;
    try {
      return repository.resolveUrl(path);
    } catch (_) {
      return path;
    }
  }
}

class _CourseList extends StatelessWidget {
  const _CourseList({required this.courses, required this.theme});

  final List<Map<String, dynamic>> courses;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 56,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(height: 12),
            Text(
              'Inga publicerade kurser ännu.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Publicera en kurs i studion för att visa den här.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final crossAxisCount = isWide ? 2 : 1;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: isWide ? 2.6 : 1.9,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: courses.length,
          itemBuilder: (context, index) {
            final course = courses[index];
            return _CourseTile(course: course);
          },
        );
      },
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course});

  final Map<String, dynamic> course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (course['title'] as String?) ?? 'Kurs';
    final description = (course['description'] as String?) ?? '';
    final slug = (course['slug'] as String?) ?? '';
    final isIntro = course['is_free_intro'] == true;
    final branch = (course['branch'] as String?) ?? '';

    final radius = BorderRadius.circular(20);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: slug.isEmpty
            ? null
            : () => context.pushNamed(
                AppRoute.course,
                pathParameters: {'slug': slug},
              ),
        borderRadius: radius,
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          opacity: 0.18,
          borderRadius: radius,
          borderColor: Colors.white.withValues(alpha: 0.18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CourseTitleText(
                    title,
                    baseStyle: theme.textTheme.titleLarge,
                    fontWeight: FontWeight.w700,
                    maxLines: null,
                    overflow: null,
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    CourseDescriptionText(
                      description,
                      baseStyle: theme.textTheme.bodyMedium,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (branch.isNotEmpty)
                    _Chip(icon: Icons.sell_outlined, label: branch),
                  if (isIntro)
                    const _Chip(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Introduktion',
                    ),
                  _Chip(
                    icon: course['is_published'] == true
                        ? Icons.public_outlined
                        : Icons.drafts_outlined,
                    label: course['is_published'] == true
                        ? 'Publicerad'
                        : 'Utkast',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

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
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            'Kunde inte hämta kurser just nu.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (error != null)
            Text(
              error.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
