import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/courses_grid.dart';
import 'package:aveli/shared/widgets/home_hero_panel.dart';
import 'package:aveli/data/models/community_post.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(myCoursesProvider);
    final authState = ref.watch(authControllerProvider);
    final postsAsync = ref.watch(postsProvider);
    final feedPublisher = ref.watch(postPublisherProvider);
    final assets = ref.watch(backendAssetResolverProvider);

    final progressAsync = coursesAsync.when<AsyncValue<Map<String, double>>>(
      data: (courses) {
        if (courses.isEmpty) {
          return const AsyncValue.data({});
        }
        final ids = courses.map((c) => c.id).toList();
        return ref.watch(courseProgressProvider(CourseProgressRequest(ids)));
      },
      loading: () => const AsyncValue.loading(),
      error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
    );

    return AppScaffold(
      title: 'Andlig Väg',
      disableBack: true,
      extendBodyBehindAppBar: true,
      transparentAppBar: true,
      background: FullBleedBackground(
        // Den gemensamma bakgrunden ligger lokalt i appen för stabil rendering.
        image: AppImages.background,
        alignment: Alignment.center,
        topOpacity: 0.28,
        overlayColor: Theme.of(context).brightness != Brightness.dark
            ? const Color(0xFFFFE2B8).withValues(alpha: 0.10)
            : null,
        child: const SizedBox.shrink(),
      ),
      actions: [
        IconButton(
          onPressed: () => context.pushNamed(AppRoute.settings),
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'Inställningar',
        ),
        IconButton(
          onPressed: () => context.pushNamed(AppRoute.profile),
          icon: const Icon(Icons.person_rounded),
          tooltip: 'Profil',
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(postsProvider);
          ref.invalidate(myCoursesProvider);
          ref.invalidate(myCertificatesProvider);
          await ref.read(authControllerProvider.notifier).loadSession();
        },
        child: ListView(
          children: [
            HomeHeroPanel(
              displayName:
                  authState.profile?.displayName ?? authState.profile?.email,
            ),
            _ComposerCard(
              controller: _composer,
              onPublish: _publishPost,
              isPublishing: feedPublisher.isLoading,
              error: feedPublisher.whenOrNull(error: (error, _) => error),
            ),
            const SizedBox(height: 12),
            postsAsync.when(
              loading: () => const _FeedCard.loading(),
              error: (error, _) => _FeedCard.error(message: _errorText(error)),
              data: (posts) => _FeedCard(posts: posts),
            ),
            const SizedBox(height: 18),
            _ShortcutCards(),
            const SizedBox(height: 18),
            _CoursesCard(
              coursesAsync: coursesAsync,
              progressAsync: progressAsync,
              assets: assets,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publishPost(String content) async {
    final text = content.trim();
    if (text.isEmpty) return;
    await ref.read(postPublisherProvider.notifier).publish(content: text);
    final state = ref.read(postPublisherProvider);
    state.when(
      data: (post) {
        _composer.clear();
        ref.invalidate(postsProvider);
        if (post != null) {
          if (!mounted || !context.mounted) return;
          showSnack(context, 'Inlägget publicerades.');
        }
      },
      error: (error, _) {
        if (!mounted || !context.mounted) return;
        showSnack(context, 'Kunde inte publicera: ${_errorText(error)}');
      },
      loading: () {},
    );
  }

  String _errorText(Object error) => AppFailure.from(error).message;
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.controller,
    required this.onPublish,
    required this.isPublishing,
    required this.error,
  });

  final TextEditingController controller;
  final Future<void> Function(String text) onPublish;
  final bool isPublishing;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _GlassSection(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Dela något i communityt',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Skriv ett inlägg...'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: isPublishing ? null : () => onPublish(controller.text),
              child: isPublishing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Publicera'),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage(error),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _errorMessage(Object? error) {
    if (error is AppFailure) return error.message;
    return error?.toString() ?? 'Ett okänt fel inträffade.';
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard._({
    required this.posts,
    required this.loading,
    required this.errorMessage,
  });

  const _FeedCard({required List<CommunityPost> posts})
    : this._(posts: posts, loading: false, errorMessage: null);

  const _FeedCard.loading()
    : this._(posts: const [], loading: true, errorMessage: null);

  const _FeedCard.error({required String message})
    : this._(posts: const [], loading: false, errorMessage: message);

  final List<CommunityPost> posts;
  final bool loading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget content;
    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (errorMessage != null) {
      content = Text(errorMessage!, style: t.bodyMedium);
    } else if (posts.isEmpty) {
      content = Text('Inga inlägg ännu.', style: t.bodyMedium);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nyligen i communityt',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...posts.map(
            (post) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    post.profile?.displayName ?? 'Användare',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(post.content, style: t.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return _GlassSection(padding: const EdgeInsets.all(18), child: content);
  }
}

class _ShortcutCards extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _GlassSection(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Välkommen hem.',
            style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Utforska introduktionskurser (gratis förhandsvisningar).',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton(
                onPressed: () => context.pushNamed(AppRoute.courseIntro),
                child: const Text('Öppna introduktionskurs'),
              ),
              OutlinedButton(
                onPressed: () => context.pushNamed(AppRoute.studio),
                child: const Text('Gå till Studio (lärare)'),
              ),
              OutlinedButton(
                onPressed: () => context.pushNamed(AppRoute.community),
                child: const Text('Community'),
              ),
              OutlinedButton(
                onPressed: () => context.pushNamed(AppRoute.tarot),
                child: const Text('Tarotförfrågan'),
              ),
              OutlinedButton(
                onPressed: () => context.pushNamed(AppRoute.booking),
                child: const Text('Bokningar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoursesCard extends StatelessWidget {
  const _CoursesCard({
    required this.coursesAsync,
    required this.progressAsync,
    required this.assets,
  });

  final AsyncValue<List<CourseSummary>> coursesAsync;
  final AsyncValue<Map<String, double>> progressAsync;
  final BackendAssetResolver assets;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _GlassSection(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Mina kurser',
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          coursesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Text(
              error is AppFailure ? error.message : error.toString(),
              style: t.bodyMedium,
            ),
            data: (courses) {
              if (courses.isEmpty) {
                return Text(
                  'Du är ännu inte anmäld till någon kurs.',
                  style: t.bodyMedium,
                );
              }
              return progressAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Text(
                  error is AppFailure ? error.message : error.toString(),
                  style: t.bodyMedium,
                ),
                data: (progress) => CoursesGrid(
                  courses: courses,
                  progress: progress,
                  assets: assets,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({
    required this.child,
    this.padding = const EdgeInsets.all(12),
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
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, baseColor.withValues(alpha: 0.7)],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
