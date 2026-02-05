import 'package:flutter/material.dart';

import 'package:aveli/features/studio/widgets/wav_upload_card.dart';

class WavReplaceDialog extends StatefulWidget {
  const WavReplaceDialog({
    super.key,
    required this.courseId,
    required this.lessonId,
    required this.existingFileName,
    this.onMediaUpdated,
  });

  final String courseId;
  final String lessonId;
  final String existingFileName;
  final Future<void> Function()? onMediaUpdated;

  @override
  State<WavReplaceDialog> createState() => _WavReplaceDialogState();
}

class _WavReplaceDialogState extends State<WavReplaceDialog> {
  String? _lastFinalState;

  void _handleFinalState(String mediaAssetId, String finalState) {
    setState(() => _lastFinalState = finalState);
    if (finalState == 'ready' && mounted) {
      Navigator.of(context).pop(mediaAssetId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodySmall;

    return AlertDialog(
      title: const Text('Byt WAV'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ersätt "${widget.existingFileName}" genom att ladda upp en ny WAV. '
              'Den gamla filen tas bort när den nya MP3:an är klar.',
              style: bodyStyle,
            ),
            const SizedBox(height: 12),
            WavUploadCard(
              courseId: widget.courseId,
              lessonId: widget.lessonId,
              onMediaUpdated: widget.onMediaUpdated,
              actionLabel: 'Byt WAV',
              onPipelineFinalState: _handleFinalState,
            ),
            if (_lastFinalState == 'failed') ...[
              const SizedBox(height: 12),
              Text(
                'Bearbetningen misslyckades. Du kan försöka igen genom att ladda upp en ny WAV.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
      ],
    );
  }
}
