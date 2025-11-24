import 'package:flutter/material.dart';

import 'app_logo.dart';

/// Baslayout som sätter stor logga högst upp på varje sida.
class BasePage extends StatelessWidget {
  const BasePage({super.key, required this.child, this.logoSize = 150});

  final Widget child;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite;
        final body = hasBoundedHeight
            ? Expanded(child: child)
            : Flexible(fit: FlexFit.loose, child: child);
        final showLogo = logoSize > 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLogo) AppLogo(size: logoSize),
            body,
          ],
        );
      },
    );
  }
}
