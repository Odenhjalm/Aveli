import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/app_text_colors.dart';

/// Central rule:
/// - If `fontSize <= 12`:
///   - `fontWeight >= w600` -> white
///   - `fontWeight < w600`  -> black
/// - If `fontSize > 12`: unchanged
///
/// Applies based on actual `fontSize`, not token name (`bodySmall`/`bodyMedium`/etc).
class SmallTextColorRule {
  SmallTextColorRule._();

  static const double maxFontSize = 12.0;

  static TextStyle apply(TextStyle style) {
    final fontSize = style.fontSize;
    if (fontSize == null || fontSize > maxFontSize) return style;

    final weight = style.fontWeight ?? FontWeight.w400;
    final enforcedColor = weight.index >= FontWeight.w600.index
        ? Colors.white
        : AppTextColor.body;

    // `foreground` paint overrides `color`, so clear it for <=12px.
    return style.copyWith(color: enforcedColor, foreground: null);
  }

  static TextTheme applyTo(TextTheme theme) {
    TextStyle? enforce(TextStyle? style) {
      if (style == null) return null;
      return apply(style);
    }

    return theme.copyWith(
      displayLarge: enforce(theme.displayLarge),
      displayMedium: enforce(theme.displayMedium),
      displaySmall: enforce(theme.displaySmall),
      headlineLarge: enforce(theme.headlineLarge),
      headlineMedium: enforce(theme.headlineMedium),
      headlineSmall: enforce(theme.headlineSmall),
      titleLarge: enforce(theme.titleLarge),
      titleMedium: enforce(theme.titleMedium),
      titleSmall: enforce(theme.titleSmall),
      bodyLarge: enforce(theme.bodyLarge),
      bodyMedium: enforce(theme.bodyMedium),
      bodySmall: enforce(theme.bodySmall),
      labelLarge: enforce(theme.labelLarge),
      labelMedium: enforce(theme.labelMedium),
      labelSmall: enforce(theme.labelSmall),
    );
  }
}
