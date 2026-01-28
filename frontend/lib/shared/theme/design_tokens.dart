import 'package:flutter/material.dart';

abstract class DesignTokens {
  DesignTokens._();

  // Text colors
  static const Color headingTextColor = Colors.white;
  static const Color nameTextColor = Colors.white;
  static const Color bodyTextColor = Colors.black;
  // Muted text on dark branded surfaces (gray-white, not black).
  static const Color mutedTextColor = Color(0xB3FFFFFF);
}
