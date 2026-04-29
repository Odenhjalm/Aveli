import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/shared/data/app_render_inputs_repository.dart';

/// Full-viewport background image with a soft, readable overlay.
class BackgroundLayer extends ConsumerWidget {
  const BackgroundLayer({
    super.key,
    this.background = UiBackgroundRenderInputKey.defaultBackground,
  });

  const BackgroundLayer.lesson({super.key})
    : background = UiBackgroundRenderInputKey.lesson;

  final UiBackgroundRenderInputKey background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness != Brightness.dark;
    final backgroundInput = ref.watch(
      uiBackgroundRenderInputProvider(background),
    );

    return backgroundInput.when(
      data: (input) => _ResolvedBackgroundLayer(
        provider: NetworkImage(input.resolvedUrl),
        isLightMode: isLightMode,
      ),
      loading: () => const ColoredBox(color: Colors.black),
      error: (error, stackTrace) =>
          Error.throwWithStackTrace(error, stackTrace),
    );
  }
}

class _ResolvedBackgroundLayer extends StatelessWidget {
  const _ResolvedBackgroundLayer({
    required this.provider,
    required this.isLightMode,
  });

  final ImageProvider<Object> provider;
  final bool isLightMode;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        IgnorePointer(
          child: LayoutBuilder(
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

              return Image(
                image: SafeMedia.resizedProvider(
                  provider,
                  cacheWidth: cacheWidth,
                  cacheHeight: null,
                ),
                alignment: Alignment.center,
                fit: BoxFit.cover,
                filterQuality: SafeMedia.filterQuality(
                  full: FilterQuality.high,
                ),
                gaplessPlayback: true,
              );
            },
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x42000000), Colors.transparent],
                  stops: [0.0, 0.25],
                ),
              ),
            ),
          ),
        ),
        if (isLightMode)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0xFFFFE2B8).withValues(alpha: 0.10),
              ),
            ),
          ),
      ],
    );
  }
}

/// Utility wrapper that paints the shared background behind `child`.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [const BackgroundLayer(), child],
    );
  }
}
