import 'package:flutter/material.dart';

import 'package:wisdom/shared/theme/ui_consts.dart';

// Central helpers for Material 3 controls using the WidgetStateProperty APIs (the
// newer namespace keeps us clear of the legacy MaterialStateProperty warnings).
ButtonStyle elevatedPrimaryStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;

  Color? overlayResolver(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return scheme.onPrimary.withValues(alpha: 0.12);
    }
    if (states.contains(WidgetState.hovered)) {
      return scheme.onPrimary.withValues(alpha: 0.08);
    }
    if (states.contains(WidgetState.focused)) {
      return scheme.onPrimary.withValues(alpha: 0.08);
    }
    return null;
  }

  Color foregroundResolver(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return scheme.onSurface.withValues(alpha: 0.38);
    }
    return scheme.onPrimary;
  }

  Color backgroundResolver(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return scheme.onSurface.withValues(alpha: 0.12);
    }
    return scheme.primary;
  }

  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
    padding: const WidgetStatePropertyAll(px16),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: br12),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(foregroundResolver),
    backgroundColor: WidgetStateProperty.resolveWith(backgroundResolver),
    overlayColor: WidgetStateProperty.resolveWith(overlayResolver),
    elevation: const WidgetStatePropertyAll(0),
  );
}

RadioThemeData cleanRadioTheme(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;

  Color fillResolver(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return scheme.onSurfaceVariant.withValues(alpha: 0.38);
    }
    return scheme.primary;
  }

  Color? overlayResolver(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return scheme.primary.withValues(alpha: 0.16);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return scheme.primary.withValues(alpha: 0.08);
    }
    return null;
  }

  return RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith(fillResolver),
    overlayColor: WidgetStateProperty.resolveWith(overlayResolver),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
