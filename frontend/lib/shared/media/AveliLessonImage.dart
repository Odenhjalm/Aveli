import 'package:flutter/material.dart';

class AveliLessonImage extends StatefulWidget {
  const AveliLessonImage({super.key, required this.src, this.alt});

  final String src;
  final String? alt;

  @override
  State<AveliLessonImage> createState() => _AveliLessonImageState();
}

class _AveliLessonImageState extends State<AveliLessonImage> {
  int _attempt = 0;

  @override
  void didUpdateWidget(covariant AveliLessonImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src.trim() == widget.src.trim()) return;
    _attempt = 0;
  }

  bool _isSupportedHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (!uri.isAbsolute || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  void _retry() {
    setState(() => _attempt += 1);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSrc = widget.src.trim();
    final normalizedAlt = widget.alt?.trim();
    final semanticLabel = normalizedAlt == null || normalizedAlt.isEmpty
        ? null
        : normalizedAlt;

    if (!_isSupportedHttpUrl(normalizedSrc)) {
      return const _LessonImageStateCard(
        message: 'Bilden kunde inte laddas.',
        showRetry: false,
      );
    }

    return Image.network(
      key: ValueKey<String>('$normalizedSrc::$_attempt'),
      normalizedSrc,
      width: double.infinity,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _LessonImageStateCard(
          loading: true,
          message: 'Laddar bild...',
        );
      },
      errorBuilder: (_, _, _) => _LessonImageStateCard(
        message: 'Bilden kunde inte laddas.',
        onRetry: _retry,
      ),
    );
  }
}

class _LessonImageStateCard extends StatelessWidget {
  const _LessonImageStateCard({
    this.loading = false,
    required this.message,
    this.onRetry,
    this.showRetry = true,
  });

  final bool loading;
  final String message;
  final VoidCallback? onRetry;
  final bool showRetry;

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
                Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: loading
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!loading && showRetry && onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Försök igen'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
