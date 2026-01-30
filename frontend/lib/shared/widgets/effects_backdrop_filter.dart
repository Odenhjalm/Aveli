import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'package:aveli/core/bootstrap/effects_policy.dart';

class EffectsBackdropFilter extends StatelessWidget {
  const EffectsBackdropFilter({
    super.key,
    required this.child,
    required this.sigmaX,
    required this.sigmaY,
  });

  final Widget child;
  final double sigmaX;
  final double sigmaY;

  @override
  Widget build(BuildContext context) {
    if (EffectsPolicyController.isSafe) {
      return child;
    }
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
      child: child,
    );
  }
}

