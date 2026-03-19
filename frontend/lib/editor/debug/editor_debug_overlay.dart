import 'package:flutter/material.dart';

import 'package:aveli/editor/debug/editor_debug.dart';

class EditorDebugOverlay extends StatelessWidget {
  const EditorDebugOverlay({
    super.key,
    required this.sessionId,
    required this.controllerIdentity,
    required this.hasFocus,
    required this.selection,
  });

  final String sessionId;
  final int controllerIdentity;
  final bool hasFocus;
  final TextSelection? selection;

  @override
  Widget build(BuildContext context) {
    if (!kEditorDebug) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final textStyle =
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.2,
        ) ??
        const TextStyle(fontSize: 11, height: 1.2);

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: DefaultTextStyle(
              style: textStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Editor Debug',
                    style: textStyle.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  _EditorDebugRow(label: 'session', value: sessionId),
                  _EditorDebugRow(
                    label: 'controller',
                    value: '$controllerIdentity',
                  ),
                  _EditorDebugRow(
                    label: 'focus',
                    value: hasFocus ? 'true' : 'false',
                  ),
                  _EditorDebugRow(
                    label: 'selection',
                    value: formatEditorSelection(selection),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorDebugRow extends StatelessWidget {
  const _EditorDebugRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text('$label: $value'),
    );
  }
}
