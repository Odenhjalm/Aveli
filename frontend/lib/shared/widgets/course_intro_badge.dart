import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/ui_consts.dart';

enum CourseIntroBadgeVariant { badge, link }

const LinearGradient _courseIntroBadgeGradient = kBrandVibrantGradient;

class CourseIntroBadge extends StatelessWidget {
  const CourseIntroBadge({
    super.key,
    this.label = 'Introduktion',
    this.textColor,
    this.variant = CourseIntroBadgeVariant.badge,
    this.gradient = _courseIntroBadgeGradient,
  });

  final String label;
  final Color? textColor;
  final CourseIntroBadgeVariant variant;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTextColor =
        textColor ??
        (variant == CourseIntroBadgeVariant.badge
            ? Colors.white
            : DesignTokens.infoAccentTextColor);
    switch (variant) {
      case CourseIntroBadgeVariant.badge:
        final style = theme.textTheme.labelSmall?.copyWith(
          color: resolvedTextColor,
          fontWeight: FontWeight.w800,
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: gradient),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(label, style: style),
            ),
          ),
        );
      case CourseIntroBadgeVariant.link:
        final baseStyle =
            theme.textTheme.labelLarge ??
            theme.textTheme.labelMedium ??
            theme.textTheme.labelSmall ??
            const TextStyle();
        final buttonStyle =
            theme.textButtonTheme.style?.textStyle?.resolve({}) ??
            const TextStyle(fontWeight: FontWeight.w600);
        final style = baseStyle.merge(buttonStyle);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(label, style: style.copyWith(color: resolvedTextColor)),
        );
    }
  }
}
