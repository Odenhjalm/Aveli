import 'package:flutter/material.dart';
import 'package:aveli/shared/theme/design_tokens.dart';

class CourseTitleText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final FontWeight fontWeight;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const CourseTitleText(
    this.text, {
    super.key,
    this.baseStyle,
    this.fontWeight = FontWeight.w800,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBrandedSurface = DesignTokens.isBrandedSurface(theme);
    final style = (baseStyle ?? theme.textTheme.titleMedium)?.copyWith(
      color: isBrandedSurface ? DesignTokens.headingTextColor : null,
      fontWeight: fontWeight,
    );
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );
  }
}

class CourseDescriptionText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final Color? color;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const CourseDescriptionText(
    this.text, {
    super.key,
    this.baseStyle,
    this.color,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (baseStyle ?? theme.textTheme.bodyMedium)?.copyWith(
      color: color ?? DesignTokens.bodyTextColor,
    );
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );
  }
}

class TeacherNameText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final Color? color;
  final FontWeight fontWeight;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const TeacherNameText(
    this.text, {
    super.key,
    this.baseStyle,
    this.color,
    this.fontWeight = FontWeight.w700,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBrandedSurface = DesignTokens.isBrandedSurface(theme);
    final style = (baseStyle ?? theme.textTheme.titleMedium)?.copyWith(
      color: color ?? (isBrandedSurface ? DesignTokens.nameTextColor : null),
      fontWeight: fontWeight,
    );
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );
  }
}
