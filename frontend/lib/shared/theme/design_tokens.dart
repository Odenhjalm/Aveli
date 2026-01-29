import 'package:flutter/material.dart';

abstract class DesignTokens {
  DesignTokens._();

  // THEME CONTRACT (Landing + Home branded surfaces)
  //
  // - Default body text from ThemeData (`Theme.textTheme.body*`) must be light
  //   (white / gray-white) on branded surfaces. No view should rely on black
  //   defaults there.
  // - Black text is ONLY allowed via `CourseDescriptionText`, which uses
  //   `DesignTokens.bodyTextColor` for course descriptions rendered on light
  //   cards.
  // - Views must never use `Colors.black*` directly in Landing/Home UI.
  // - Use semantic wrappers for typography intent:
  //   `SectionHeading` (headings), `NameText` (names), `MetaText` (meta).

  // Text colors
  static const Color headingTextColor = Colors.white;
  static const Color nameTextColor = Colors.white;
  static const Color bodyTextColor = Colors.black;
  // Muted text on dark branded surfaces (gray-white, not black).
  static const Color mutedTextColor = Color(0xB3FFFFFF);

  /// True when the current [ThemeData] represents a branded/hero surface where
  /// text defaults should be light (landing / glass overlays).
  static bool isBrandedSurface(ThemeData theme) {
    return theme.colorScheme.onSurface == headingTextColor;
  }
}
