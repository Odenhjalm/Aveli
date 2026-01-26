import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/ui_consts.dart';

/// Simple helper for rendering text with the Aveli gradient palette.
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

  static const Gradient _defaultGradient = LinearGradient(
    colors: [kBrandTurquoise, kBrandLilac],
  );

  @override
  Widget build(BuildContext context) {
    final resolvedGradient = gradient ?? _defaultGradient;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => resolvedGradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(text, style: style),
    );
  }
}
