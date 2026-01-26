import 'package:flutter/material.dart';

class HeroTitleText extends StatelessWidget {
  const HeroTitleText(
    this.text, {
    super.key,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        theme.textTheme.displaySmall ??
        theme.textTheme.headlineLarge ??
        const TextStyle(fontSize: 34, fontWeight: FontWeight.w800);
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: baseStyle.copyWith(
        color: Colors.white,
        fontWeight: baseStyle.fontWeight ?? FontWeight.w800,
      ),
    );
  }
}

class AppHeaderText extends StatelessWidget {
  const AppHeaderText(
    this.text, {
    super.key,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        theme.textTheme.headlineSmall ??
        theme.textTheme.titleLarge ??
        const TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: baseStyle.copyWith(
        color: Colors.white,
        fontWeight: baseStyle.fontWeight ?? FontWeight.w700,
      ),
    );
  }
}
