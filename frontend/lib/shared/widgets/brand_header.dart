import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/app_images.dart';

const LinearGradient kAveliBrandGradient = LinearGradient(
  colors: [kBrandTurquoise, kBrandLilac],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Image(
        image: AppImages.logo,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ShaderMask(
      shaderCallback: (bounds) => kAveliBrandGradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        'Aveli',
        style: (style ?? theme.textTheme.titleMedium)?.copyWith(
          color: DesignTokens.headingTextColor,
          fontWeight: FontWeight.w900,
          letterSpacing: .25,
        ),
      ),
    );
  }
}

class BrandHeaderTitle extends StatelessWidget {
  const BrandHeaderTitle({super.key, this.wordmarkStyle, this.actions});

  final TextStyle? wordmarkStyle;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          BrandWordmark(style: wordmarkStyle),
          const SizedBox(width: 16),
          if (actions != null)
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
        ],
      ),
    );
  }
}
