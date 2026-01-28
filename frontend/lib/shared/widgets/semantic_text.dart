import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/design_tokens.dart';

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
    final style = (baseStyle ?? theme.textTheme.headlineSmall)?.copyWith(
      color: DesignTokens.headingTextColor,
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
    final style = (baseStyle ?? theme.textTheme.titleMedium)?.copyWith(
      color: DesignTokens.nameTextColor,
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
    final style = (baseStyle ?? theme.textTheme.bodyMedium)?.copyWith(
      color: DesignTokens.mutedTextColor,
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
