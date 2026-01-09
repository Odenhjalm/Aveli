import 'package:flutter/material.dart';
import 'package:aveli/shared/utils/image_error_logger.dart';

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
    return MouseRegion(
      onEnter: (_) => setState(() => _scale = 1.01),
      onExit: (_) => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 140),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Card(
            elevation: 3,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.heroImageUrl != null &&
                    widget.heroImageUrl!.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      widget.heroImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, err, stack) {
                        ImageErrorLogger.log(
                          source: 'CourseCard',
                          url: widget.heroImageUrl,
                          error: err,
                          stackTrace: stack,
                        );
                        return _imageFallback(context);
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
                            child: Text(
                              widget.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.isIntro) const SizedBox(width: 8),
                          if (widget.isIntro)
                            const Chip(
                              label: Text('Gratis intro'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      if ((widget.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
