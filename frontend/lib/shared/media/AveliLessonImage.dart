import 'package:flutter/material.dart';

class AveliLessonImage extends StatelessWidget {
  const AveliLessonImage({super.key, required this.src, this.alt});

  final String src;
  final String? alt;

  bool _isSupportedHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (!uri.isAbsolute || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSrc = src.trim();
    if (!_isSupportedHttpUrl(normalizedSrc)) {
      return const SizedBox.shrink();
    }

    final normalizedAlt = alt?.trim();
    final semanticLabel = normalizedAlt == null || normalizedAlt.isEmpty
        ? null
        : normalizedAlt;

    return Image.network(
      normalizedSrc,
      width: double.infinity,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
