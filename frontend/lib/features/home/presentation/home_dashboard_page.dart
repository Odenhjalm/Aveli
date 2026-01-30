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
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/media/application/media_playback_controller.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/paywall/application/entitlements_notifier.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/features/seminars/application/seminar_providers.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/course_intro_badge.dart';
import 'package:aveli/shared/widgets/courses_showcase_section.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/media_player.dart';
import 'package:aveli/shared/widgets/effects_backdrop_filter.dart';
import 'package:aveli/shared/widgets/semantic_text.dart';
import 'package:aveli/core/bootstrap/effects_policy.dart';
import 'package:aveli/core/bootstrap/safe_media.dart';

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
    final seminarsAsync = ref.watch(publicSeminarsProvider);
    final certificatesAsync = ref.watch(myCertificatesProvider);
    final profile = authState.profile;
    final claims = authState.claims;
    final isTeacher =
        profile?.isTeacher == true ||
        profile?.isAdmin == true ||
        claims?.isTeacher == true ||
        claims?.isAdmin == true;
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

    return AppScaffold(
      title: '',
      disableBack: true,
      showHomeAction: false,
      logoSize: 0,
      maxContentWidth: 1320,
      contentPadding: EdgeInsets.zero,
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
      background: FullBleedBackground(
        // Bundlade bakgrunder laddas lokalt för att slippa 401-svar från API:t.
        image: AppImages.background,
        alignment: Alignment.center,
        topOpacity: 0.22,
        overlayColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF000000).withValues(alpha: 0.3)
            : const Color(0xFFFFE2B8).withValues(alpha: 0.16),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeFeedProvider);
          ref.invalidate(homeServicesProvider);
          ref.invalidate(landing.popularCoursesProvider);
          await ref.read(authControllerProvider.notifier).loadSession();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            const pagePadding = EdgeInsets.fromLTRB(20, 118, 20, 44);
            if (isWide) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final targetWidth = (constraints.maxWidth * 0.46)
                                .clamp(520.0, constraints.maxWidth)
                                .toDouble();
                            return Align(
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: targetWidth,
                                child: homeAudioSection,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 26),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Transform.translate(
                                  offset: const Offset(-12, -10),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 860,
                                    ),
                                    child: const CoursesShowcaseSection(
                                      title: 'Utforska kurser',
                                      layout: CoursesShowcaseLayout.vertical,
                                      desktop: CoursesShowcaseDesktop(
                                        columns: 2,
                                        rows: 3,
                                      ),
                                      includeOuterChrome: false,
                                      showHeroBadge: false,
                                      includeStudioCourses: false,
                                      ctaGradient: kBrandBluePurpleGradient,
                                      tileScale: 0.85,
                                      tileTextColor: DesignTokens.bodyTextColor,
                                      introBadgeVariant:
                                          CourseIntroBadgeVariant.link,
                                      gridCrossAxisSpacing: 2,
                                      gridMainAxisSpacing: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Padding(
                              padding: const EdgeInsets.only(top: 90),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 360,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _FeedSection(
                                      feedAsync: feedAsync,
                                      seminarsAsync: seminarsAsync,
                                    ),
                                    const SizedBox(height: 24),
                                    _ServicesSection(
                                      servicesAsync: servicesAsync,
                                      isLoading: (id) =>
                                          _loadingServiceIds.contains(id),
                                      onCheckout: (service) =>
                                          _handleServiceCheckout(
                                            context,
                                            service,
                                          ),
                                      certificatesAsync: certificatesAsync,
                                      isAuthenticated:
                                          authState.isAuthenticated,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pagePadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      homeAudioSection,
                      const SizedBox(height: 22),
                      const CoursesShowcaseSection(
                        title: 'Utforska kurser',
                        layout: CoursesShowcaseLayout.vertical,
                        desktop: CoursesShowcaseDesktop(columns: 2, rows: 3),
                        includeOuterChrome: false,
                        showHeroBadge: false,
                        includeStudioCourses: false,
                        ctaGradient: kBrandBluePurpleGradient,
                        tileScale: 0.85,
                        tileTextColor: DesignTokens.bodyTextColor,
                        introBadgeVariant: CourseIntroBadgeVariant.link,
                        gridCrossAxisSpacing: 2,
                        gridMainAxisSpacing: 2,
                      ),
                      const SizedBox(height: 22),
                      _FeedSection(
                        feedAsync: feedAsync,
                        seminarsAsync: seminarsAsync,
                      ),
                      const SizedBox(height: 22),
                      _ServicesSection(
                        servicesAsync: servicesAsync,
                        isLoading: (id) => _loadingServiceIds.contains(id),
                        onCheckout: (service) =>
                            _handleServiceCheckout(context, service),
                        certificatesAsync: certificatesAsync,
                        isAuthenticated: authState.isAuthenticated,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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
    return audioAsync.when(
      loading: () => const _NowPlayingShell(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _NowPlayingShell(
        child: Text(
          'Kunde inte hämta ljud: ${AppFailure.from(error).message}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _NowPlayingShell(
            child: MetaText('Inga ljudspår tillgängliga ännu.'),
          );
        }
        return _HomeAudioList(items: items);
      },
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
    final playback = ref.watch(mediaPlaybackControllerProvider);
    final activeId = playback.currentMediaId;
    final selected =
        (activeId != null &&
            items.any((item) => item.id == activeId) &&
            playback.isPlaying)
        ? items.firstWhere((item) => item.id == activeId)
        : _resolveSelected(items);

    final durationHint = (selected.durationSeconds ?? 0) > 0
        ? Duration(seconds: selected.durationSeconds!)
        : null;

    final mediaType = selected.kind == 'video'
        ? MediaPlaybackType.video
        : MediaPlaybackType.audio;
    final isActive =
        playback.currentMediaId == selected.id &&
        playback.isPlaying &&
        playback.mediaType == mediaType;
    final hasUrl = (playback.url ?? '').trim().isNotEmpty;
    final showLoading = isActive && playback.isLoading;

    final (onPlay, statusMessage, canPlay, statusIsError) =
        _resolvePlaybackAction(selected, durationHint: durationHint);

    return _NowPlayingShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _NowPlayingArtwork(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (selected.courseTitle.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          selected.courseTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (statusMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          statusMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: DesignTokens.bodyTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Bibliotek',
                onPressed: () => _openLibrary(context, items),
                icon: const Icon(Icons.library_music_outlined),
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              if (isActive)
                IconButton.filled(
                  tooltip: 'Stoppa',
                  onPressed: ref
                      .read(mediaPlaybackControllerProvider.notifier)
                      .stop,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: const Icon(Icons.stop_rounded),
                )
              else
                IconButton.filled(
                  tooltip: 'Spela',
                  onPressed: canPlay ? () async => await onPlay() : null,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
            ],
          ),
          if (showLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (isActive && hasUrl) ...[
            const SizedBox(height: 12),
            if (mediaType == MediaPlaybackType.audio)
              InlineAudioPlayer(
                url: playback.url!,
                title: null,
                durationHint: durationHint,
                autoPlay: true,
                compact: true,
              )
            else
              InlineVideoPlayer(
                url: playback.url!,
                title: selected.displayTitle,
                autoPlay: true,
              ),
          ],
        ],
      ),
    );
  }

  (
    Future<void> Function() onPlay,
    String? statusMessage,
    bool canPlay,
    bool statusIsError,
  )
  _resolvePlaybackAction(HomeAudioItem item, {Duration? durationHint}) {
    final mediaAssetId = item.mediaAssetId;
    if (mediaAssetId != null) {
      final state = item.mediaState ?? 'uploaded';
      if (state != 'ready') {
        final message = state == 'failed'
            ? 'Ljudet kunde inte bearbetas.'
            : 'Ljudet bearbetas…';
        return (_noOp, message, false, state == 'failed');
      }
      return (
        () => _playPipelineInline(item, durationHint: durationHint),
        null,
        true,
        false,
      );
    }
    final url = item.preferredUrl;
    if (url == null || url.trim().isEmpty) {
      return (_noOp, 'Ljudlänken saknas för detta spår.', false, true);
    }
    return (
      () => _playLegacyInline(item, durationHint: durationHint),
      null,
      true,
      false,
    );
  }

  Future<void> _noOp() async {}

  Future<void> _playPipelineInline(
    HomeAudioItem item, {
    Duration? durationHint,
  }) async {
    final mediaAssetId = item.mediaAssetId;
    if (mediaAssetId == null || mediaAssetId.trim().isEmpty) return;
    final mediaType = item.kind == 'video'
        ? MediaPlaybackType.video
        : MediaPlaybackType.audio;
    final controller = ref.read(mediaPlaybackControllerProvider.notifier);
    try {
      await controller.play(
        mediaId: item.id,
        mediaType: mediaType,
        title: item.displayTitle,
        durationHint: durationHint,
        urlLoader: () async {
          final repo = ref.read(mediaPipelineRepositoryProvider);
          final playback = await repo.fetchPlaybackUrl(mediaAssetId);
          return playback.playbackUrl.toString();
        },
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunde inte spela upp media: ${failure.message}'),
        ),
      );
    }
  }

  Future<void> _playLegacyInline(
    HomeAudioItem item, {
    Duration? durationHint,
  }) async {
    final preferred = item.preferredUrl;
    if (preferred == null || preferred.trim().isEmpty) return;
    String url = preferred.trim();
    final repo = ref.read(mediaRepositoryProvider);
    try {
      url = repo.resolveUrl(url);
    } catch (_) {
      // Keep original URL when it's already absolute (e.g. signed storage URL).
    }
    final mediaType = item.kind == 'video'
        ? MediaPlaybackType.video
        : MediaPlaybackType.audio;
    await ref
        .read(mediaPlaybackControllerProvider.notifier)
        .play(
          mediaId: item.id,
          mediaType: mediaType,
          url: url,
          title: item.displayTitle,
          durationHint: durationHint,
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
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 8),
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
    final scheme = theme.colorScheme;
    final duration = (item.durationSeconds ?? 0) > 0
        ? _formatDuration(Duration(seconds: item.durationSeconds!))
        : null;
    final border = BorderSide(
      color: isSelected
          ? scheme.primary.withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.12),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.fromBorderSide(border),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
              size: 18,
              color: isSelected ? scheme.primary : null,
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

class _NowPlayingShell extends StatelessWidget {
  const _NowPlayingShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.32);
    final border = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.18);
    final wingOpacity = theme.brightness == Brightness.dark ? 0.22 : 0.16;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              surface,
              surface.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.04 : 0.26,
              ),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: _NowPlayingWingsBackdrop(opacity: wingOpacity),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.2),
                      radius: 1.2,
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(18), child: child),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingWingsBackdrop extends StatelessWidget {
  const _NowPlayingWingsBackdrop({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: -60,
          top: -26,
          bottom: -28,
          width: 240,
          child: _LogoWing(side: _WingSide.left, opacity: opacity),
        ),
        Positioned(
          right: -60,
          top: -26,
          bottom: -28,
          width: 240,
          child: _LogoWing(side: _WingSide.right, opacity: opacity),
        ),
      ],
    );
  }
}

enum _WingSide { left, right }

class _LogoWing extends StatelessWidget {
  const _LogoWing({required this.side, required this.opacity});

  final _WingSide side;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final rotation = side == _WingSide.left ? -0.08 : 0.08;
    final alignment = side == _WingSide.left
        ? Alignment.topLeft
        : Alignment.topRight;
    final scaleAlignment = side == _WingSide.left
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return Opacity(
      opacity: opacity,
      child: _maybeBlur(
        sigma: 12,
        child: Transform.rotate(
          angle: rotation,
          child: ClipRect(
            child: Align(
              alignment: alignment,
              widthFactor: 0.60,
              heightFactor: 0.48,
              child: Transform.scale(
                scale: 2.25,
                alignment: scaleAlignment,
                child: Image(image: AppImages.logo, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _maybeBlur({required double sigma, required Widget child}) {
  if (EffectsPolicyController.isSafe) {
    return child;
  }
  return ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: child,
  );
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 68,
        width: 68,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Image(
              image: SafeMedia.resizedProvider(
                AppImages.logo,
                cacheWidth: SafeMedia.cacheDimension(context, 68, max: 240),
                cacheHeight: SafeMedia.cacheDimension(context, 68, max: 240),
              ),
              fit: BoxFit.contain,
              filterQuality: SafeMedia.filterQuality(full: FilterQuality.high),
              gaplessPlayback: true,
            ),
          ),
        ),
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
            return const MetaText('Inga aktiviteter ännu.');
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seminarHighlights != null) ...[
                seminarHighlights,
                if (activities.isNotEmpty) const SizedBox(height: 12),
              ],
              if (activities.isEmpty)
                const MetaText('Inga aktiviteter ännu.')
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
                                NameText(
                                  activity.summary.isEmpty
                                      ? activity.type
                                      : activity.summary,
                                  baseStyle: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                  fontWeight: FontWeight.w600,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                MetaText(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatFullDate(
                                    activity.occurredAt.toLocal(),
                                  ),
                                  baseStyle: Theme.of(
                                    context,
                                  ).textTheme.bodySmall,
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
            SectionHeading(
              'Livesändningar',
              baseStyle: Theme.of(context).textTheme.titleMedium,
              fontWeight: FontWeight.w600,
              maxLines: 2,
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
            return const MetaText('Inga tjänster publicerade just nu.');
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
                          NameText(
                            service.title,
                            baseStyle: Theme.of(context).textTheme.titleMedium,
                            fontWeight: FontWeight.w600,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (service.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            MetaText(
                              service.description,
                              baseStyle: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionHeading(
                title,
                baseStyle: Theme.of(context).textTheme.titleLarge,
                fontWeight: FontWeight.bold,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
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
      child: EffectsBackdropFilter(
        sigmaX: 20,
        sigmaY: 20,
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
      child: EffectsBackdropFilter(
        sigmaX: 16,
        sigmaY: 16,
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
