import 'package:flutter/material.dart';
import 'package:wisdom/shared/utils/image_error_logger.dart';

class ServiceCard extends StatelessWidget {
  final String title;
  final String? description;
  final String? area;
  final int? priceCents;
  final String? imageUrl;
  const ServiceCard({
    super.key,
    required this.title,
    this.description,
    this.area,
    this.priceCents,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final priceText = priceCents == null
        ? ''
        : '${(priceCents! / 100).toStringAsFixed(0)} kr';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl != null && imageUrl!.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, err, stack) {
                  ImageErrorLogger.log(
                    source: 'ServiceCard',
                    url: imageUrl,
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
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if ((area ?? '').isNotEmpty)
                      Chip(
                        label: Text(area!),
                        visualDensity: VisualDensity.compact,
                      ),
                    const Spacer(),
                    if (priceText.isNotEmpty)
                      Text(
                        priceText,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _imageFallback(BuildContext context) {
  return Container(
    height: 120,
    color: Colors.grey.shade100,
    alignment: Alignment.center,
    child: const Icon(Icons.image, color: Colors.black26, size: 40),
  );
}
