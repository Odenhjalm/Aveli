import 'package:flutter/material.dart';

import 'package:aveli/core/bootstrap/safe_media.dart';

/// Background helper that paints an [ImageProvider] safely without forcing
/// cache dimensions. Useful when the layout constraints may still be zero
/// during the first frame (web) which otherwise risks triggering asserts
/// when passing cacheWidth/cacheHeight manually.
class SafeBackground extends StatelessWidget {
  const SafeBackground({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.child,
    this.ignorePointer = true,
    this.placeholder,
  });

  final ImageProvider<Object> image;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? child;
  final bool ignorePointer;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        if (SafeMedia.enabled) {
          SafeMedia.markBackground();
        }
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final cacheWidth = SafeMedia.cacheDimension(
          context,
          maxWidth,
          max: 640,
        );

        final resolvedPlaceholder =
            placeholder ?? const ColoredBox(color: Colors.black);

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: resolvedPlaceholder),
            Positioned.fill(
              child: Image(
                image: SafeMedia.resizedProvider(
                  image,
                  cacheWidth: cacheWidth,
                  cacheHeight: null,
                ),
                fit: fit,
                alignment: alignment,
                filterQuality: SafeMedia.filterQuality(
                  full: FilterQuality.high,
                ),
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
            if (child != null) Positioned.fill(child: child!),
          ],
        );
      },
    );
    if (!ignorePointer) {
      return content;
    }
    return IgnorePointer(child: content);
  }
}
