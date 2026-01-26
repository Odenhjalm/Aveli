import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/app_text_colors.dart';

@immutable
class SemanticTextStyles extends ThemeExtension<SemanticTextStyles> {
  const SemanticTextStyles({
    required this.courseCardDescription,
    required this.courseDetailDescription,
    required this.readerBody,
  });

  factory SemanticTextStyles.fromTextTheme(TextTheme textTheme) {
    return SemanticTextStyles(
      courseCardDescription:
          (textTheme.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
            color: AppTextColor.body,
          ),
      courseDetailDescription:
          (textTheme.bodyLarge ??
                  textTheme.bodyMedium ??
                  const TextStyle(fontSize: 16))
              .copyWith(color: AppTextColor.body),
      readerBody: (textTheme.bodyMedium ?? const TextStyle(fontSize: 16))
          .copyWith(color: AppTextColor.body),
    );
  }

  final TextStyle courseCardDescription;
  final TextStyle courseDetailDescription;
  final TextStyle readerBody;

  @override
  SemanticTextStyles copyWith({
    TextStyle? courseCardDescription,
    TextStyle? courseDetailDescription,
    TextStyle? readerBody,
  }) {
    return SemanticTextStyles(
      courseCardDescription:
          courseCardDescription ?? this.courseCardDescription,
      courseDetailDescription:
          courseDetailDescription ?? this.courseDetailDescription,
      readerBody: readerBody ?? this.readerBody,
    );
  }

  @override
  SemanticTextStyles lerp(ThemeExtension<SemanticTextStyles>? other, double t) {
    if (other is! SemanticTextStyles) return this;
    return SemanticTextStyles(
      courseCardDescription:
          TextStyle.lerp(
            courseCardDescription,
            other.courseCardDescription,
            t,
          ) ??
          courseCardDescription,
      courseDetailDescription:
          TextStyle.lerp(
            courseDetailDescription,
            other.courseDetailDescription,
            t,
          ) ??
          courseDetailDescription,
      readerBody: TextStyle.lerp(readerBody, other.readerBody, t) ?? readerBody,
    );
  }
}

extension SemanticTextStylesContextX on BuildContext {
  SemanticTextStyles get semanticTextStyles {
    final theme = Theme.of(this);
    return theme.extension<SemanticTextStyles>() ??
        SemanticTextStyles.fromTextTheme(theme.textTheme);
  }
}
