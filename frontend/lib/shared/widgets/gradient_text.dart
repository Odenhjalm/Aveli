import 'package:flutter/material.dart';

/// Simple helper for preserving call sites while keeping auth/link text legible
/// on light surfaces.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    required this.style,
    this.gradient,
    super.key,
  });

  final String text;
  final TextStyle style;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style.copyWith(color: Colors.black));
  }
}
