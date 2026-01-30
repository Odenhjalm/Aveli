import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/course_cover_assets.dart';
import 'package:aveli/shared/utils/image_error_logger.dart';

class CoursesGrid extends StatelessWidget {
  final List<CourseSummary> courses;
  final Map<String, double>? progress; // course_id -> 0..1
  final BackendAssetResolver assets;
  const CoursesGrid({
    super.key,
    required this.courses,
    required this.assets,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cross = w >= 900 ? 3 : (w >= 600 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: courses.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          itemBuilder: (_, i) {
            final c = courses[i];
            final cover = c.resolvedCoverUrl ?? '';
            final title = c.title;
            final id = c.id;
            final pct = (progress?[id] ?? 0.0).clamp(0.0, 1.0);
            final slug = c.slug ?? '';
            final coverProvider = CourseCoverAssets.resolve(
              assets: assets,
              slug: slug,
              coverUrl: cover,
            );
            return LayoutBuilder(
              builder: (context, tileConstraints) {
                if (SafeMedia.enabled) {
                  SafeMedia.markThumbnails();
                }
                final cacheWidth = SafeMedia.cacheDimension(
                  context,
                  tileConstraints.maxWidth,
                  max: 1200,
                );
                final cacheHeight = SafeMedia.cacheDimension(
                  context,
                  tileConstraints.maxHeight,
                  max: 900,
                );

                Widget gradientFallback() => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: .24),
                        Colors.white.withValues(alpha: .08),
                      ],
                    ),
                  ),
                );

                Widget buildCover() {
                  final placeholder = gradientFallback();
                  if (coverProvider != null) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        placeholder,
                        Image(
                          image: SafeMedia.resizedProvider(
                            coverProvider,
                            cacheWidth: cacheWidth,
                            cacheHeight: cacheHeight,
                          ),
                          fit: BoxFit.cover,
                          filterQuality: SafeMedia.filterQuality(
                            full: FilterQuality.high,
                          ),
                          gaplessPlayback: true,
                          errorBuilder: (_, err, stack) {
                            ImageErrorLogger.log(
                              source: 'CoursesGrid/CoverProvider',
                              url: cover.isNotEmpty ? cover : slug,
                              error: err,
                              stackTrace: stack,
                            );
                            if (cover.isNotEmpty) {
                              return Image.network(
                                cover,
                                fit: BoxFit.cover,
                                filterQuality: SafeMedia.filterQuality(
                                  full: FilterQuality.high,
                                ),
                                cacheWidth: cacheWidth,
                                cacheHeight: cacheHeight,
                                gaplessPlayback: true,
                                errorBuilder: (_, err2, stack2) {
                                  ImageErrorLogger.log(
                                    source: 'CoursesGrid/CoverURL',
                                    url: cover,
                                    error: err2,
                                    stackTrace: stack2,
                                  );
                                  return const SizedBox.shrink();
                                },
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    );
                  }
                  if (cover.isNotEmpty) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        placeholder,
                        Image.network(
                          cover,
                          fit: BoxFit.cover,
                          filterQuality: SafeMedia.filterQuality(
                            full: FilterQuality.high,
                          ),
                          cacheWidth: cacheWidth,
                          cacheHeight: cacheHeight,
                          gaplessPlayback: true,
                          errorBuilder: (_, err, stack) {
                            ImageErrorLogger.log(
                              source: 'CoursesGrid/CoverURL',
                              url: cover,
                              error: err,
                              stackTrace: stack,
                            );
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    );
                  }
                  return placeholder;
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      buildCover(),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (pct > 0)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.12,
                                  ),
                                  color: Colors.black,
                                  minHeight: 6,
                                ),
                              ),
                            const Spacer(),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: ElevatedButton(
                                onPressed: slug.isEmpty
                                    ? null
                                    : () => context.pushNamed(
                                        AppRoute.course,
                                        pathParameters: {'slug': slug},
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Öppna',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
