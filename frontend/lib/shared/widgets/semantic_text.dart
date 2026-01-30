import 'package:flutter/material.dart';

import 'package:aveli/core/bootstrap/effects_policy.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/ui_consts.dart';

class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.text, {
    super.key,
    this.baseStyle,
    this.fontWeight = FontWeight.w800,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final String text;
  final TextStyle? baseStyle;
  final FontWeight fontWeight;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBrandedSurface = DesignTokens.isBrandedSurface(theme);
    final style = (baseStyle ?? theme.textTheme.headlineSmall)?.copyWith(
      color: isBrandedSurface ? DesignTokens.headingTextColor : null,
      fontWeight: fontWeight,
    );
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

class NameText extends StatelessWidget {
  const NameText(
    this.text, {
    super.key,
    this.baseStyle,
    this.fontWeight = FontWeight.w700,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final String text;
  final TextStyle? baseStyle;
  final FontWeight fontWeight;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBrandedSurface = DesignTokens.isBrandedSurface(theme);
    final style = (baseStyle ?? theme.textTheme.titleMedium)?.copyWith(
      color: isBrandedSurface ? DesignTokens.nameTextColor : null,
      fontWeight: fontWeight,
    );
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

class MetaText extends StatelessWidget {
  const MetaText(
    this.text, {
    super.key,
    this.baseStyle,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final TextStyle? baseStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBrandedSurface = DesignTokens.isBrandedSurface(theme);
    final style = (baseStyle ?? theme.textTheme.bodyMedium)?.copyWith(
      color: isBrandedSurface ? DesignTokens.mutedTextColor : null,
    );
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

class HeroHeading extends StatefulWidget {
  const HeroHeading({
    super.key,
    required this.leading,
    required this.gradientWord,
  });

  final String leading;
  final String gradientWord;

  @override
  State<HeroHeading> createState() => _HeroHeadingState();
}

class _HeroHeadingState extends State<HeroHeading>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (EffectsPolicyController.isFull) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 5),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBrandedSurface = DesignTokens.isBrandedSurface(theme);
    final base = theme.textTheme.displayLarge?.copyWith(
      fontWeight: FontWeight.w900,
      color: isBrandedSurface ? DesignTokens.headingTextColor : null,
      height: 1.04,
      letterSpacing: -.5,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        Text(widget.leading, textAlign: TextAlign.center, style: base),
        if (EffectsPolicyController.isSafe)
          Text(
            widget.gradientWord,
            textAlign: TextAlign.center,
            style: base?.copyWith(
              color: isBrandedSurface ? DesignTokens.headingTextColor : null,
            ),
          )
        else
          AnimatedBuilder(
            animation: _controller!,
            builder: (context, child) {
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  final sweep = bounds.width * 1.5;
                  final start = -bounds.width + sweep * _controller!.value;
                  return const LinearGradient(
                    colors: [kBrandTurquoise, kBrandLilac, kBrandTurquoise],
                    stops: [0.0, 0.5, 1.0],
                  ).createShader(Rect.fromLTWH(start, 0, sweep, bounds.height));
                },
                child: child,
              );
            },
            child: Text(
              widget.gradientWord,
              textAlign: TextAlign.center,
              style: base?.copyWith(
                color: isBrandedSurface ? DesignTokens.headingTextColor : null,
              ),
            ),
          ),
      ],
    );
  }
}
