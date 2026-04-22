import 'package:flutter/widgets.dart';
import 'package:aveli/core/bootstrap/effects_policy.dart';

/// Centraliserade referenser till bundlade bilder som används återkommande
/// i UI:et. Håller paths konsekventa och undviker duplicerad hårdkodning.
class AppImages {
  static const String backgroundPath = 'assets/images/bakgrund.png';
  static const String lessonBackgroundPath =
      'assets/images/bakgrundlektion.png';
  static const String logoPath = 'assets/images/loggo_clea.png';
  static const String observatoriumBackgroundPath =
      'assets/images/observatorium_bg.png';

  static const AssetImage _background = AssetImage(backgroundPath);
  static const AssetImage _lessonBackground = AssetImage(lessonBackgroundPath);
  static const AssetImage _logo = AssetImage(logoPath);
  static const AssetImage _observatoriumBackground = AssetImage(
    observatoriumBackgroundPath,
  );

  /// Background is heavily used and must remain stable in CPU-only SAFE mode.
  /// In SAFE we decode at a smaller size to avoid stalls/timeouts.
  static ImageProvider<Object> get background {
    if (EffectsPolicyController.isSafe) {
      return ResizeImage.resizeIfNeeded(640, null, _background);
    }
    return _background;
  }

  static ImageProvider<Object> get lessonBackground {
    if (EffectsPolicyController.isSafe) {
      return ResizeImage.resizeIfNeeded(640, null, _lessonBackground);
    }
    return _lessonBackground;
  }

  /// In SAFE we decode the logo to a smaller size to reduce CPU overhead during
  /// warm-up.
  static ImageProvider<Object> get logo {
    if (EffectsPolicyController.isSafe) {
      return ResizeImage.resizeIfNeeded(512, null, _logo);
    }
    return _logo;
  }

  static ImageProvider<Object> get observatoriumBackground {
    if (EffectsPolicyController.isSafe) {
      return ResizeImage.resizeIfNeeded(960, null, _observatoriumBackground);
    }
    return _observatoriumBackground;
  }
}
