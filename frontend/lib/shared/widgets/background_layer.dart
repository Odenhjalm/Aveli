import 'package:flutter/material.dart';
import 'package:aveli/shared/utils/app_images.dart';

/// Full-viewport background image with a soft, readable overlay.
/// - Always covers the entire available space (desktop/web/mobile)
/// - Subtle neutral scrim for readability (warm lift in light mode)
/// - Does not capture gestures (content above remains interactive)
class BackgroundLayer extends StatelessWidget {
  const BackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness != Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        IgnorePointer(
          child: Image(
            // Bundlad bakgrund hålls lokalt för att undvika 401 från backend.
            image: AppImages.background,
            alignment: Alignment.center,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
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
