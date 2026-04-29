import 'package:flutter/widgets.dart';
import 'package:aveli/core/bootstrap/effects_policy.dart';

class AppImages {
  static const String backgroundPath = 'assets/images/bakgrund.png';
  static const String lessonBackgroundPath =
      'assets/images/bakgrundlektion.png';
  static const String observatoriumBackgroundPath =
      'assets/images/observatorium_bg.png';

  static const AssetImage _background = AssetImage(backgroundPath);
  static const AssetImage _lessonBackground = AssetImage(lessonBackgroundPath);
  static const AssetImage _observatoriumBackground = AssetImage(
    observatoriumBackgroundPath,
  );

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

  static ImageProvider<Object> get observatoriumBackground {
    if (EffectsPolicyController.isSafe) {
      return ResizeImage.resizeIfNeeded(960, null, _observatoriumBackground);
    }
    return _observatoriumBackground;
  }
}
