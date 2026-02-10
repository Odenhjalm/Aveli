import 'package:flutter/material.dart';

class EditorMediaControls extends StatelessWidget {
  const EditorMediaControls({
    super.key,
    this.onInsertVideo,
    this.onInsertAudio,
  });

  final VoidCallback? onInsertVideo;
  final VoidCallback? onInsertAudio;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const Key('editor_media_controls_insert_video'),
          onPressed: onInsertVideo,
          icon: const Icon(Icons.movie_creation_outlined),
          label: const Text('Infoga video'),
        ),
        FilledButton.icon(
          key: const Key('editor_media_controls_insert_audio'),
          onPressed: onInsertAudio,
          icon: const Icon(Icons.audiotrack_outlined),
          label: const Text('Infoga ljud'),
        ),
      ],
    );
  }
}
