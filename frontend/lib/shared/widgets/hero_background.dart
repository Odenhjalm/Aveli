import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/shared/utils/backend_assets.dart';

/// Fullscreen bakgrundsbild med mjuk gradient för bättre läsbarhet.
class HeroBackground extends ConsumerWidget {
  final String assetPath;
  final double opacity;
  const HeroBackground({
    super.key,
    required this.assetPath,
    this.opacity = 0.9,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(backendAssetResolverProvider);
    final normalized = assetPath.replaceFirst(RegExp(r'^/+'), '');
    final ImageProvider<Object> provider = normalized.startsWith('assets/')
        ? AssetImage(normalized)
        : normalized.startsWith('images/')
        ? AssetImage('assets/$normalized')
        : assets.imageProvider(assetPath);

    return LayoutBuilder(
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

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Image(
              // Bundlade bakgrunder används lokalt; övriga hämtas via backend-resolvern.
              image: SafeMedia.resizedProvider(
                provider,
                cacheWidth: cacheWidth,
                cacheHeight: null,
              ),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: SafeMedia.filterQuality(full: FilterQuality.high),
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
            // Subtil mörk gradient för att text/widgets ligger tydligt ovanpå
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.20 * opacity),
                    Colors.black.withValues(alpha: 0.45 * opacity),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
