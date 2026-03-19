import 'package:flutter/material.dart';
import 'package:aveli/shared/theme/app_text_colors.dart';

abstract class DesignTokens {
  DesignTokens._();

  // TEXT CONTRACT
  //
  // - App text defaults to black everywhere.
  // - The landing hero phrase is the only allowed non-black exception and
  //   must be styled explicitly where it is rendered.
  // - Shared widgets should consume these semantic colors rather than
  //   introducing their own light-text defaults.

  // Text colors
  static const Color headingTextColor = AppTextColor.body;
  static const Color nameTextColor = AppTextColor.body;
  static const Color bodyTextColor = AppTextColor.body;
  static const Color mutedTextColor = AppTextColor.body;
  static const Color heroTextColor = Colors.white;

  /// No route should switch the app back to a light-text contract.
  static bool isBrandedSurface(ThemeData theme) {
    return false;
  }
}
