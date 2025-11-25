import 'package:flutter/material.dart';

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
  });

  final ImageProvider image;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? child;
  final bool ignorePointer;

  @override
  Widget build(BuildContext context) {
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(image: image, fit: fit, alignment: alignment),
      ),
      child: child,
    );
    if (!ignorePointer) {
      return decorated;
    }
    return IgnorePointer(child: decorated);
  }
}
