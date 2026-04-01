import 'package:flutter/material.dart';

class AveliLessonImage extends StatelessWidget {
  const AveliLessonImage({super.key, required this.src, this.alt});

  final String src;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      src,
      width: double.infinity,
      fit: BoxFit.contain,
      semanticLabel: alt,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _LessonImageStateCard(
          message: 'Laddar bild...',
          loading: true,
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return const _LessonImageStateCard(message: 'Bilden kunde inte visas.');
      },
    );
  }
}

class _LessonImageStateCard extends StatelessWidget {
  const _LessonImageStateCard({required this.message, this.loading = false});

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                )
              else
                Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: loading
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
