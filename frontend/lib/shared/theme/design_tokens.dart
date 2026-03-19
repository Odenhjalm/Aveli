import 'package:flutter/material.dart';
import 'package:aveli/shared/theme/app_text_colors.dart';
import 'package:aveli/shared/theme/ui_consts.dart';

abstract class DesignTokens {
  DesignTokens._();

  // TEXT CONTRACT
  //
  // - App text defaults to black everywhere.
  // - The only allowed non-black exceptions are:
  //   * text rendered inside buttons
  //   * the landing hero phrase
  //   * informational course-card badges and links
  //   * text rendered explicitly with the Aveli blue-to-purple treatment
  // - Shared widgets should consume these semantic colors rather than
  //   introducing their own light-text defaults.

  // Text colors
  static const Color headingTextColor = AppTextColor.body;
  static const Color nameTextColor = AppTextColor.body;
  static const Color bodyTextColor = AppTextColor.body;
  static const Color mutedTextColor = AppTextColor.body;
  static const Color buttonForegroundColor = Colors.white;
  static const Color filledButtonForegroundColor = buttonForegroundColor;
  static const Color heroTextColor = Colors.white;
  static const Color infoAccentTextColor = kBrandAzure;

  /// No route should switch the app back to a light-text contract.
  static bool isBrandedSurface(ThemeData theme) {
    return false;
  }
}
