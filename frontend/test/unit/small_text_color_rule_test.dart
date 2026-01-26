import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/theme/app_text_colors.dart';
import 'package:aveli/shared/theme/light_theme.dart';
import 'package:aveli/shared/theme/small_text_color_rule.dart';

void main() {
  test('Default typography sizes', () {
    final theme = buildLightTheme();
    expect(theme.textTheme.bodySmall?.fontSize, lessThanOrEqualTo(12));
    expect(theme.textTheme.bodyMedium?.fontSize, greaterThan(12));
    expect(theme.textTheme.bodyLarge?.fontSize, greaterThan(12));
  });

  test('SmallTextColorRule.apply enforces black for <=12 regular', () {
    final style = SmallTextColorRule.apply(
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    );
    expect(style.color, AppTextColor.body);
  });

  test('SmallTextColorRule.apply enforces white for <=12 semi-bold', () {
    final style = SmallTextColorRule.apply(
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
    expect(style.color, const Color(0xFFFFFFFF));
  });

  test('SmallTextColorRule.apply leaves >12 unchanged', () {
    final style = SmallTextColorRule.apply(
      const TextStyle(fontSize: 13, color: Color(0xFF123456)),
    );
    expect(style.color, const Color(0xFF123456));
  });

  test(
    'SmallTextColorRule.applyTo triggers by actual fontSize (not token)',
    () {
      final themed = SmallTextColorRule.applyTo(
        const TextTheme(
          bodyMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
      expect(themed.bodyMedium?.color, AppTextColor.body);
      expect(themed.labelSmall?.color, const Color(0xFFFFFFFF));
    },
  );
}
