import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/app_text_colors.dart';
import 'package:aveli/shared/theme/semantic_text_styles.dart';
import 'package:aveli/shared/theme/ui_consts.dart';

const Color kPrimary = Color(0xFF7AA8F7);
const Color kSecondary = Color(0xFF63C7D6);

ThemeData buildLightTheme({bool forLanding = false}) {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: Brightness.light,
    primary: kPrimary,
    secondary: kSecondary,
  );
  final scheme = forLanding
      ? baseScheme
      : baseScheme.copyWith(
          onSurface: AppTextColor.body,
          onBackground: AppTextColor.body,
          onSurfaceVariant: AppTextColor.meta,
        );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );

  final baseTextTheme = ThemeData.light().textTheme.apply(
    fontFamily: 'NotoSans',
    displayColor: scheme.onSurface,
    bodyColor: scheme.onSurface,
  );
  final textTheme = forLanding
      ? baseTextTheme
      : baseTextTheme.copyWith(
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(
            color: AppTextColor.body,
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            color: AppTextColor.body,
          ),
          bodySmall: baseTextTheme.bodySmall?.copyWith(
            color: AppTextColor.body,
          ),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            color: AppTextColor.body,
          ),
          labelMedium: baseTextTheme.labelMedium?.copyWith(
            color: AppTextColor.body,
          ),
          labelSmall: baseTextTheme.labelSmall?.copyWith(
            color: AppTextColor.body,
          ),
        );
  final navLabelStyle = TextStyle(
    fontWeight: FontWeight.w500,
    color: AppTextColor.body,
  );
  final semanticTextStyles = SemanticTextStyles.fromTextTheme(textTheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.light,
    fontFamily: 'NotoSans',
    fontFamilyFallback: const ['NotoSansSymbols2', 'NotoColorEmoji'],
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: forLanding ? Colors.black87 : AppTextColor.body,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 3,
      margin: p12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      surfaceTintColor: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.08),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(64, 48),
        padding: px16,
        shape: buttonShape,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(64, 48),
        padding: px16,
        shape: buttonShape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary),
        minimumSize: const Size(64, 48),
        padding: px16,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: buttonShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade100,
      hintStyle: forLanding ? null : const TextStyle(color: AppTextColor.meta),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      labelTextStyle: forLanding ? null : WidgetStatePropertyAll(navLabelStyle),
    ),
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[semanticTextStyles],
  );
}
