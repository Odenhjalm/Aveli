import 'package:flutter/material.dart';

import 'package:aveli/shared/theme/ui_consts.dart';

/// Brand-styled button with the Aveli turquoise→royal gradient background.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.gradient,
    this.padding,
    this.borderRadius,
  });

  GradientButton.icon({
    super.key,
    required this.onPressed,
    required Widget icon,
    required Widget label,
    this.onLongPress,
    this.gradient,
    this.padding,
    this.borderRadius,
    double spacing = 10,
  }) : child = _IconLabel(icon: icon, label: label, spacing: spacing);

  const GradientButton.tonal({
    super.key,
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.padding,
    this.borderRadius,
    Gradient? gradient,
  }) : gradient = gradient ?? _tonalGradient;

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget child;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  static const LinearGradient _tonalGradient = LinearGradient(
    colors: [Color(0xCC63C7D6), Color(0xCC7AA8F7), Color(0xCCB58CFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const EdgeInsetsGeometry _defaultPadding = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 14,
  );

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = borderRadius ?? br16;
    final Gradient resolvedGradient = _resolveGradient(
      enabled: onPressed != null,
    );
    final FilledButton button = FilledButton(
      onPressed: onPressed,
      onLongPress: onLongPress,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        padding: padding ?? _defaultPadding,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      child: child,
    );

    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: resolvedGradient,
          borderRadius: radius,
        ),
        child: button,
      ),
    );
  }

  Gradient _resolveGradient({required bool enabled}) {
    final Gradient base = gradient ?? kBrandVibrantGradient;
    if (enabled) return base;
    if (base is LinearGradient) {
      return LinearGradient(
        colors: base.colors
            .map((c) => c.withValues(alpha: 0.35))
            .toList(growable: false),
        begin: base.begin,
        end: base.end,
      );
    }
    return LinearGradient(
      colors: const [
        kBrandTurquoise,
        kBrandLilac,
      ].map((c) => c.withValues(alpha: 0.35)).toList(growable: false),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}

class _IconLabel extends StatelessWidget {
  const _IconLabel({
    required this.icon,
    required this.label,
    required this.spacing,
  });

  final Widget icon;
  final Widget label;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        SizedBox(width: spacing),
        Flexible(child: label),
      ],
    );
  }
}
