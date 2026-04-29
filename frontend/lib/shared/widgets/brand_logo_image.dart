import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/shared/data/app_render_inputs_repository.dart';

class BrandLogoImage extends ConsumerWidget {
  const BrandLogoImage({
    super.key,
    required this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.opacity = 1.0,
    this.semanticLabel,
  });

  final double height;
  final double? width;
  final BoxFit fit;
  final double opacity;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = ref.watch(brandLogoRenderInputProvider);
    final reservedWidth = width ?? height;
    return logo.when(
      data: (input) {
        final image = Image.network(
          input.resolvedUrl,
          width: width,
          height: height,
          fit: fit,
          alignment: Alignment.center,
          filterQuality: SafeMedia.filterQuality(full: FilterQuality.high),
          cacheWidth: SafeMedia.cacheDimension(
            context,
            reservedWidth,
            max: 900,
          ),
          cacheHeight: SafeMedia.cacheDimension(context, height, max: 500),
          gaplessPlayback: true,
          semanticLabel: semanticLabel,
          excludeFromSemantics: semanticLabel == null,
        );
        if (opacity >= 1.0) {
          return image;
        }
        return Opacity(opacity: opacity.clamp(0.0, 1.0), child: image);
      },
      loading: () => SizedBox(width: reservedWidth, height: height),
      error: (error, stackTrace) =>
          Error.throwWithStackTrace(error, stackTrace),
    );
  }
}
