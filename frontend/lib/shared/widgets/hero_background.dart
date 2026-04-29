import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/shared/data/app_render_inputs_repository.dart';

class HeroBackground extends ConsumerWidget {
  const HeroBackground({
    super.key,
    this.background = UiBackgroundRenderInputKey.defaultBackground,
    this.opacity = 0.9,
  });

  final UiBackgroundRenderInputKey background;
  final double opacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundInput = ref.watch(
      uiBackgroundRenderInputProvider(background),
    );

    return backgroundInput.when(
      data: (input) => LayoutBuilder(
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
                image: SafeMedia.resizedProvider(
                  NetworkImage(input.resolvedUrl),
                  cacheWidth: cacheWidth,
                  cacheHeight: null,
                ),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: SafeMedia.filterQuality(
                  full: FilterQuality.high,
                ),
                gaplessPlayback: true,
              ),
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
      ),
      loading: () => const ColoredBox(color: Colors.black),
      error: (error, stackTrace) =>
          Error.throwWithStackTrace(error, stackTrace),
    );
  }
}
