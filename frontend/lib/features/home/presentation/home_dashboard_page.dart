import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/data/models/activity.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/seminar.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/features/seminars/application/seminar_providers.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/utils/image_error_logger.dart';
import 'package:aveli/shared/widgets/media_player.dart';

class HomeDashboardPage extends ConsumerStatefulWidget {
  const HomeDashboardPage({super.key});

  @override
  ConsumerState<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends ConsumerState<HomeDashboardPage> {
  final Set<String> _loadingServiceIds = <String>{};
  bool _redirecting = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final entitlementsState = ref.watch(entitlementsNotifierProvider);
    final feedAsync = ref.watch(homeFeedProvider);
    final servicesAsync = ref.watch(homeServicesProvider);
    final exploreAsync = ref.watch(landing.popularCoursesProvider);
    final coursesAsync = ref.watch(coursesProvider);
    final seminarsAsync = ref.watch(publicSeminarsProvider);
    final certificatesAsync = ref.watch(myCertificatesProvider);
    final profile = authState.profile;
    final claims = authState.claims;
    final isTeacher =
        profile?.isTeacher == true ||
        profile?.isAdmin == true ||
        claims?.isTeacher == true ||
        claims?.isAdmin == true;
    final mediaRepository = ref.watch(mediaRepositoryProvider);
    final homeAudioAsync = ref.watch(homeAudioProvider);
    final homeAudioSection = _HomeAudioSection(audioAsync: homeAudioAsync);

    if (!entitlementsState.loading && entitlementsState.data == null) {
      // Kick off entitlements load once.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(entitlementsNotifierProvider.notifier).refresh();
      });
    } else if (!_redirecting &&
        entitlementsState.data != null &&
        entitlementsState.data?.membership.isActive != true &&
        !isTeacher) {
      _redirecting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(RoutePath.subscribe);
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: InkWell(
          onTap: () => context.goNamed(AppRoute.landing),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(
              'Aveli',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            onPressed: () => context.goNamed(AppRoute.home),
            icon: const Icon(Icons.home_outlined),
          ),
          if (isTeacher)
            IconButton(
              tooltip: 'Studio',
              onPressed: () => context.goNamed(AppRoute.studio),
              icon: const Icon(Icons.edit),
            ),
          IconButton(
            tooltip: 'Profil',
            onPressed: () => context.goNamed(AppRoute.profile),
            icon: const Icon(Icons.person),
          ),
        ],
      ),
      body: FullBleedBackground(
        // Bundlade bakgrunder laddas lokalt för att slippa 401-svar från API:t.
        image: AppImages.background,
        alignment: Alignment.center,
        topOpacity: 0.22,
        overlayColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.3)
            : const Color(0xFFFFE2B8).withValues(alpha: 0.16),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(homeFeedProvider);
            ref.invalidate(homeServicesProvider);
            ref.invalidate(landing.popularCoursesProvider);
            await ref.read(authControllerProvider.notifier).loadSession();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              if (isWide) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 110, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: homeAudioSection,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ExploreCoursesSection(
                              section: exploreAsync,
                              fallbackCourses: coursesAsync,
                              mediaRepository: mediaRepository,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _FeedSection(
                              feedAsync: feedAsync,
                              seminarsAsync: seminarsAsync,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ServicesSection(
                              servicesAsync: servicesAsync,
                              isLoading: (id) =>
                                  _loadingServiceIds.contains(id),
                              onCheckout: (service) =>
                                  _handleServiceCheckout(context, service),
                              certificatesAsync: certificatesAsync,
                              isAuthenticated: authState.isAuthenticated,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 110, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: homeAudioSection,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ExploreCoursesSection(
                    section: exploreAsync,
                    fallbackCourses: coursesAsync,
                    mediaRepository: mediaRepository,
                  ),
                  const SizedBox(height: 16),
                  _FeedSection(
                    feedAsync: feedAsync,
                    seminarsAsync: seminarsAsync,
                  ),
                  const SizedBox(height: 16),
                  _ServicesSection(
                    servicesAsync: servicesAsync,
                    isLoading: (id) => _loadingServiceIds.contains(id),
                    onCheckout: (service) =>
                        _handleServiceCheckout(context, service),
                    certificatesAsync: certificatesAsync,
                    isAuthenticated: authState.isAuthenticated,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleServiceCheckout(
    BuildContext context,
    Service service,
  ) async {
    if (_loadingServiceIds.contains(service.id)) return;
    void showMessage(String message) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }

    setState(() => _loadingServiceIds.add(service.id));
    try {
      final checkoutApi = ref.read(checkoutApiProvider);
      final url = await checkoutApi.startServiceCheckout(serviceId: service.id);
      if (!context.mounted) return;
      context.push(RoutePath.checkout, extra: url);
    } catch (error, stackTrace) {
      debugPrint('checkout failed: $error\n$stackTrace');
      if (!context.mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      showMessage('Kunde inte skapa beställning: ${failure.message}');
    } finally {
      if (mounted) {
        setState(() => _loadingServiceIds.remove(service.id));
      }
    }
  }
}

class _HomeAudioSection extends StatelessWidget {
  const _HomeAudioSection({required this.audioAsync});

  final AsyncValue<List<HomeAudioItem>> audioAsync;

  @override
  Widget build(BuildContext context) {
    return _GlassSection(
      padding: const EdgeInsets.all(20),
      child: audioAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          'Kunde inte hämta ljud: ${AppFailure.from(error).message}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Text('Inga ljudspår tillgängliga ännu.');
          }
          return _HomeAudioList(items: items);
        },
      ),
    );
  }
}

class _HomeAudioList extends ConsumerStatefulWidget {
  const _HomeAudioList({required this.items});

  final List<HomeAudioItem> items;

  @override
  ConsumerState<_HomeAudioList> createState() => _HomeAudioListState();
}

class _HomeAudioListState extends ConsumerState<_HomeAudioList> {
  String? _selectedId;
  Future<MediaPlaybackUrl>? _playbackFuture;
  String? _playbackMediaId;

  @override
  void didUpdateWidget(covariant _HomeAudioList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedId == null) return;
    final stillExists = widget.items.any((item) => item.id == _selectedId);
    if (!stillExists) {
      _selectedId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final selected = _resolveSelected(items);
    final mediaRepo = ref.watch(mediaRepositoryProvider);
    final pipelineRepo = ref.watch(mediaPipelineRepositoryProvider);
    String? resolvedUrl = selected.preferredUrl;
    if (resolvedUrl != null) {
      try {
        resolvedUrl = mediaRepo.resolveUrl(resolvedUrl);
      } catch (_) {}
    }
    final durationHint = (selected.durationSeconds ?? 0) > 0
        ? Duration(seconds: selected.durationSeconds!)
        : null;

    if (selected.mediaAssetId != null && selected.mediaState == 'ready') {
      if (_playbackMediaId != selected.mediaAssetId) {
        _playbackMediaId = selected.mediaAssetId;
        _playbackFuture = pipelineRepo.fetchPlaybackUrl(selected.mediaAssetId!);
      }
    } else {
      _playbackMediaId = null;
      _playbackFuture = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selected.displayTitle,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (selected.courseTitle.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            selected.courseTitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 10),
        if (selected.mediaAssetId != null)
          _buildPipelineAudio(selected, durationHint: durationHint)
        else if (resolvedUrl == null)
          const Text('Ljudlänken saknas för detta spår.')
        else
          InlineAudioPlayer(
            url: resolvedUrl,
            durationHint: durationHint,
            compact: true,
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _openLibrary(context, items),
            icon: const Icon(Icons.library_music_outlined),
            label: Text('Bibliotek (${items.length})'),
          ),
        ),
      ],
    );
  }

  Widget _buildPipelineAudio(HomeAudioItem item, {Duration? durationHint}) {
    final state = item.mediaState ?? 'uploaded';
    if (state != 'ready') {
      final message = state == 'failed'
          ? 'Ljudet kunde inte bearbetas.'
          : 'Ljudet bearbetas…';
      return Text(message);
    }
    final future = _playbackFuture;
    if (future == null) {
      return const Text('Ljudlänken saknas för detta spår.');
    }
    return FutureBuilder<MediaPlaybackUrl>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        if (!snapshot.hasData) {
          return const Text('Kunde inte hämta uppspelningslänk.');
        }
        final url = snapshot.data!.playbackUrl.toString();
        return InlineAudioPlayer(
          url: url,
          durationHint: durationHint,
          compact: true,
        );
      },
    );
  }

  void _openLibrary(BuildContext context, List<HomeAudioItem> items) {
    final selectedId = _resolveSelected(items).id;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final height = MediaQuery.of(sheetContext).size.height * 0.7;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _GlassSection(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: height,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Bibliotek',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${items.length} spår',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = item.id == selectedId;
                          return _AudioRow(
                            item: item,
                            isSelected: isSelected,
                            onTap: () {
                              if (!mounted) return;
                              setState(() => _selectedId = item.id);
                              Navigator.of(sheetContext).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  HomeAudioItem _resolveSelected(List<HomeAudioItem> items) {
    if (_selectedId == null) {
      return items.first;
    }
    return items.firstWhere(
      (item) => item.id == _selectedId,
      orElse: () => items.first,
    );
  }
}

class _AudioRow extends StatelessWidget {
  const _AudioRow({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final HomeAudioItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = (item.durationSeconds ?? 0) > 0
        ? _formatDuration(Duration(seconds: item.durationSeconds!))
        : null;
    final border = BorderSide(
      color: Colors.white.withValues(alpha: isSelected ? 0.28 : 0.12),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: isSelected ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.fromBorderSide(border),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.courseTitle.trim().isNotEmpty)
                    Text(
                      item.courseTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (duration != null)
              Text(
                duration,
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

String _formatDuration(Duration duration) {
  String two(int n) => n.toString().padLeft(2, '0');
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = two(minutes);
  final ss = two(seconds);
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

class _ExploreCoursesSection extends StatelessWidget {
  const _ExploreCoursesSection({
    required this.section,
    required this.fallbackCourses,
    required this.mediaRepository,
  });

  final AsyncValue<landing.LandingSectionState> section;
  final AsyncValue<List<CourseSummary>> fallbackCourses;
  final MediaRepository mediaRepository;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Utforska kurser',
      trailing: TextButton(
        onPressed: () => context.goNamed(AppRoute.courseCatalog),
        child: const Text('Visa alla'),
      ),
      child: section.when(
        loading: () => _buildFallback(context),
        error: (error, _) => _buildFallback(context, fallbackError: error),
        data: (state) {
          final items = state.items;
          if (items.isNotEmpty) {
            return _buildCourseList(context, items, mediaRepository);
          }
          return _buildFallback(context);
        },
      ),
    );
  }

  Widget _buildFallback(BuildContext context, {Object? fallbackError}) {
    return fallbackCourses.when(
      data: (courses) {
        if (courses.isEmpty) {
          return const Text('Inga kurser publicerade ännu.');
        }
        return _buildCourseList(
          context,
          _mapCourseSummaries(courses),
          mediaRepository,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        final cause = fallbackError ?? error;
        return Text('Kunde inte hämta kurser: ${cause.toString()}');
      },
    );
  }

  List<Map<String, dynamic>> _mapCourseSummaries(List<CourseSummary> courses) {
    return courses
        .where((course) => (course.slug ?? '').isNotEmpty)
        .map((course) {
          return {
            'title': course.title,
            'description': course.description ?? '',
            'slug': course.slug ?? '',
            'is_free_intro': course.isFreeIntro,
            'cover_url': course.coverUrl,
          };
        })
        .toList(growable: false);
  }

  Widget _buildCourseList(
    BuildContext context,
    List<Map<String, dynamic>> items,
    MediaRepository mediaRepository,
  ) {
    if (items.isEmpty) {
      return const Text('Inga kurser publicerade ännu.');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: items
          .take(6)
          .map((course) {
            final title = (course['title'] as String?) ?? 'Kurs';
            final description = (course['description'] as String?) ?? '';
            final slug = (course['slug'] as String?) ?? '';
            final isIntro = course['is_free_intro'] == true;
            final rawCoverUrl = (course['cover_url'] as String?) ?? '';
            final resolvedCoverUrl = _resolveCoverUrl(
              mediaRepository,
              rawCoverUrl,
            );
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: InkWell(
                onTap: slug.isEmpty
                    ? null
                    : () => context.goNamed(
                        AppRoute.course,
                        pathParameters: {'slug': slug},
                      ),
                borderRadius: BorderRadius.circular(16),
                child: _GlassTile(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (resolvedCoverUrl != null &&
                          resolvedCoverUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            resolvedCoverUrl,
                            fit: BoxFit.cover,
                            height: 72,
                            width: 96,
                            errorBuilder: (_, err, stack) {
                              ImageErrorLogger.log(
                                source: 'Home/Explore/CoverURL',
                                url: resolvedCoverUrl,
                                error: err,
                                stackTrace: stack,
                              );
                              return const _CourseIconFallback();
                            },
                          ),
                        )
                      else
                        const _CourseIconFallback(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                description,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                            if (isIntro) ...[
                              const SizedBox(height: 6),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Chip(
                                  label: Text('Gratis intro'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  String? _resolveCoverUrl(MediaRepository repository, String? coverUrl) {
    if (coverUrl == null || coverUrl.isEmpty) return null;
    try {
      return repository.resolveUrl(coverUrl);
    } catch (_) {
      return coverUrl;
    }
  }
}

class _CourseIconFallback extends StatelessWidget {
  const _CourseIconFallback();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image(
        image: AppImages.background,
        height: 72,
        width: 96,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _FeedSection extends StatelessWidget {
  const _FeedSection({required this.feedAsync, required this.seminarsAsync});

  final AsyncValue<List<Activity>> feedAsync;
  final AsyncValue<List<Seminar>> seminarsAsync;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Gemensam vägg',
      trailing: TextButton(
        onPressed: () => context.goNamed(AppRoute.community),
        child: const Text('Visa allt'),
      ),
      child: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text('Kunde inte hämta feed: ${error.toString()}'),
        data: (activities) {
          final seminarHighlights = _buildSeminarHighlights(context);
          if (activities.isEmpty && seminarHighlights == null) {
            return const Text('Inga aktiviteter ännu.');
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seminarHighlights != null) ...[
                seminarHighlights,
                if (activities.isNotEmpty) const SizedBox(height: 12),
              ],
              if (activities.isEmpty)
                const Text('Inga aktiviteter ännu.')
              else
                for (final activity in activities.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _GlassTile(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.bolt_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  activity.summary.isEmpty
                                      ? activity.type
                                      : activity.summary,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatFullDate(
                                    activity.occurredAt.toLocal(),
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget? _buildSeminarHighlights(BuildContext context) {
    return seminarsAsync.maybeWhen(
      data: (seminars) {
        final upcoming = _upcomingSeminars(seminars);
        if (upcoming.isEmpty) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Livesändningar',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final seminar in upcoming.take(2))
              Builder(
                builder: (tileContext) {
                  void join() {
                    tileContext.pushNamed(
                      AppRoute.seminarJoin,
                      pathParameters: {'id': seminar.id},
                    );
                  }

                  return _SeminarHighlightTile(
                    seminar: seminar,
                    onTap: join,
                    action: GradientButton.tonal(
                      onPressed: join,
                      child: const Text('Gå med'),
                    ),
                  );
                },
              ),
          ],
        );
      },
      orElse: () => null,
    );
  }
}

List<Seminar> _upcomingSeminars(List<Seminar> seminars) {
  final filtered = seminars
      .where(
        (seminar) =>
            seminar.status == SeminarStatus.live ||
            seminar.status == SeminarStatus.scheduled,
      )
      .toList(growable: false);
  filtered.sort((a, b) {
    if (a.status == SeminarStatus.live && b.status != SeminarStatus.live) {
      return -1;
    }
    if (b.status == SeminarStatus.live && a.status != SeminarStatus.live) {
      return 1;
    }
    final aTime = a.scheduledAt ?? DateTime.utc(9999, 12, 31);
    final bTime = b.scheduledAt ?? DateTime.utc(9999, 12, 31);
    return aTime.compareTo(bTime);
  });
  return filtered;
}

String _formatSeminarDate(DateTime date) {
  final localizedDate = DateFormat('EEEE d MMM', 'sv_SE').format(date);
  final String dateLabel = toBeginningOfSentenceCase(localizedDate);
  final timeLabel = DateFormat('HH:mm', 'sv_SE').format(date);
  return '$dateLabel · $timeLabel';
}

class _SeminarHighlightTile extends StatelessWidget {
  const _SeminarHighlightTile({
    required this.seminar,
    required this.onTap,
    this.action,
  });

  final Seminar seminar;
  final VoidCallback onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheduled = seminar.scheduledAt?.toLocal();
    final hostNameCandidate = seminar.hostDisplayName?.trim();
    final metadataHostValue = seminar.livekitMetadata['host_name']?.toString();
    final metadataHost = metadataHostValue?.trim();
    final hostName = (hostNameCandidate != null && hostNameCandidate.isNotEmpty)
        ? hostNameCandidate
        : (metadataHost != null && metadataHost.isNotEmpty
              ? metadataHost
              : 'Okänd lärare');
    final scheduleLabel = scheduled != null
        ? _formatSeminarDate(scheduled)
        : null;
    final statusLabel = switch (seminar.status) {
      SeminarStatus.live => 'Live nu',
      SeminarStatus.scheduled => 'Planerat',
      SeminarStatus.ended => 'Avslutat',
      SeminarStatus.canceled => 'Inställt',
      SeminarStatus.draft => null,
    };
    final infoLine = [
      if (statusLabel != null) statusLabel,
      if (scheduleLabel != null) scheduleLabel,
      if (seminar.durationMinutes != null && seminar.durationMinutes! > 0)
        '${seminar.durationMinutes} min',
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: _GlassTile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                seminar.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Lärare: $hostName',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (infoLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  infoLine,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
              if (seminar.description != null &&
                  seminar.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  seminar.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: action!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({
    required this.servicesAsync,
    required this.onCheckout,
    required this.isLoading,
    required this.certificatesAsync,
    required this.isAuthenticated,
  });

  final AsyncValue<List<Service>> servicesAsync;
  final Future<void> Function(Service service) onCheckout;
  final bool Function(String id) isLoading;
  final AsyncValue<List<Certificate>> certificatesAsync;
  final bool isAuthenticated;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Tjänster',
      trailing: TextButton(
        onPressed: () => context.goNamed(
          AppRoute.community,
          queryParameters: const {'tab': 'services'},
          extra: const CommunityRouteArgs(initialTab: 'services'),
        ),
        child: const Text('Visa alla'),
      ),
      child: servicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          'Kunde inte hämta tjänster: ${AppFailure.from(error).message}',
        ),
        data: (services) {
          if (services.isEmpty) {
            return const Text('Inga tjänster publicerade just nu.');
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: services
                .take(5)
                .map((service) {
                  final loading = isLoading(service.id);
                  final gate = _resolveGate(service);
                  VoidCallback? action;
                  switch (gate.action) {
                    case _GateAction.checkout:
                      action = () => onCheckout(service);
                      break;
                    case _GateAction.login:
                      action = () => _goToLogin(context, service);
                      break;
                    case null:
                      action = null;
                  }
                  final effectiveAction = (loading || action == null)
                      ? null
                      : action;
                  final buttonChild = loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(gate.label);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _GlassTile(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            service.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (service.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              service.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          if (service.requiresCertification) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.verified_user_rounded,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  service.certifiedArea?.isNotEmpty == true
                                      ? 'Kräver certifiering: ${service.certifiedArea}'
                                      : 'Kräver certifiering',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${service.price.toStringAsFixed(2)} ${service.currency.toUpperCase()}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              GradientButton(
                                onPressed: effectiveAction,
                                child: buttonChild,
                              ),
                            ],
                          ),
                          if (gate.helper != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              gate.helper!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          );
        },
      ),
    );
  }

  ({_GateAction? action, String label, String? helper}) _resolveGate(
    Service service,
  ) {
    if (!service.requiresCertification) {
      return (action: _GateAction.checkout, label: 'Boka', helper: null);
    }
    if (!isAuthenticated) {
      return (
        action: _GateAction.login,
        label: 'Logga in för att boka',
        helper: 'Logga in för att visa dina certifieringar.',
      );
    }
    return certificatesAsync.when(
      loading: () =>
          (action: null, label: 'Kontrollerar behörighet...', helper: null),
      error: (error, _) => (
        action: null,
        label: 'Inte tillgängligt',
        helper: 'Certifieringsstatus kunde inte hämtas just nu.',
      ),
      data: (certs) {
        final requiredArea = (service.certifiedArea ?? '').trim();
        final hasMatch = certs.any((cert) {
          if (!cert.isVerified) return false;
          if (requiredArea.isEmpty) return true;
          return cert.title.trim().toLowerCase() == requiredArea.toLowerCase();
        });
        if (hasMatch) {
          return (action: _GateAction.checkout, label: 'Boka', helper: null);
        }
        final helper = requiredArea.isEmpty
            ? 'Verifierad certifiering krävs innan bokning.'
            : 'Du behöver certifieringen "$requiredArea" för att boka.';
        return (action: null, label: 'Certifiering krävs', helper: helper);
      },
    );
  }

  void _goToLogin(BuildContext context, Service service) {
    final router = GoRouter.of(context);
    var redirect = '/';
    try {
      redirect = router.namedLocation(
        AppRoute.serviceDetail,
        pathParameters: {'id': service.id},
      );
    } catch (_) {}
    router.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
  }
}

enum _GateAction { checkout, login }

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _GlassSection(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.38);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, baseColor.withValues(alpha: 0.68)],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _GlassTile extends StatelessWidget {
  const _GlassTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            color: Colors.white.withValues(alpha: 0.22),
          ),
          child: child,
        ),
      ),
    );
  }
}
