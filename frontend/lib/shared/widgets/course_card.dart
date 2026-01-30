import 'package:flutter/material.dart';
import 'package:aveli/core/bootstrap/effects_policy.dart';
import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/shared/utils/image_error_logger.dart';
import 'package:aveli/shared/widgets/card_text.dart';

class CourseCard extends StatefulWidget {
  final String title;
  final String? description;
  final String? heroImageUrl;
  final bool isIntro;
  final VoidCallback? onTap;
  const CourseCard({
    super.key,
    required this.title,
    this.description,
    this.heroImageUrl,
    this.isIntro = false,
    this.onTap,
  });

  @override
  State<CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<CourseCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final enableHoverEffects = EffectsPolicyController.isFull;
    final card = InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(20),
      child: Card(
        elevation: 3,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.heroImageUrl != null && widget.heroImageUrl!.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (SafeMedia.enabled) {
                      SafeMedia.markThumbnails();
                    }
                    final cacheWidth = SafeMedia.cacheDimension(
                      context,
                      constraints.maxWidth,
                      max: 1200,
                    );
                    final cacheHeight = SafeMedia.cacheDimension(
                      context,
                      constraints.maxHeight,
                      max: 900,
                    );

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        _imageFallbackFill(context),
                        Image.network(
                          widget.heroImageUrl!,
                          fit: BoxFit.cover,
                          filterQuality: SafeMedia.filterQuality(
                            full: FilterQuality.high,
                          ),
                          cacheWidth: cacheWidth,
                          cacheHeight: cacheHeight,
                          gaplessPlayback: true,
                          errorBuilder: (_, err, stack) {
                            ImageErrorLogger.log(
                              source: 'CourseCard',
                              url: widget.heroImageUrl,
                              error: err,
                              stackTrace: stack,
                            );
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    );
                  },
                ),
              )
            else
              _imageFallback(context),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CourseTitleText(
                          widget.title,
                          baseStyle: Theme.of(context).textTheme.titleMedium,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.isIntro) const SizedBox(width: 8),
                      if (widget.isIntro)
                        Chip(
                          label: Text(
                            'Introduktion',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                    ],
                  ),
                  if ((widget.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    CourseDescriptionText(
                      widget.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      baseStyle: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!enableHoverEffects) {
      return card;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _scale = 1.01),
      onExit: (_) => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 140),
        child: card,
      ),
    );
  }
}

Widget _imageFallback(BuildContext context) {
  return Container(
    height: 140,
    color: Colors.grey.shade100,
    alignment: Alignment.center,
    child: const Icon(Icons.image, color: Colors.black26, size: 48),
  );
}

Widget _imageFallbackFill(BuildContext context) {
  return ColoredBox(
    color: Colors.grey.shade100,
    child: const Center(
      child: Icon(Icons.image, color: Colors.black26, size: 48),
    ),
  );
}
