import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  static TextTheme textTheme({Brightness brightness = Brightness.light}) {
    final base = brightness == Brightness.light
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;
    final tt = GoogleFonts.interTextTheme(base);
    return tt.copyWith(
      displayLarge: tt.displayLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
      ),
      displayMedium: tt.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.25,
      ),
      displaySmall: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800),
      headlineLarge: tt.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
      headlineMedium: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      headlineSmall: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: tt.bodyLarge?.copyWith(height: 1.4),
      bodyMedium: tt.bodyMedium?.copyWith(height: 1.4),
      bodySmall: tt.bodySmall?.copyWith(height: 1.4),
      labelLarge: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      labelSmall: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
