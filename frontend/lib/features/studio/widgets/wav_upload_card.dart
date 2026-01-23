import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/utils/snack.dart';

import 'wav_upload_source.dart';

class WavUploadCard extends ConsumerStatefulWidget {
  const WavUploadCard({
    super.key,
    required this.courseId,
    required this.lessonId,
    this.onMediaUpdated,
    this.existingMediaState,
    this.existingFileName,
    this.pickFileOverride,
    this.uploadFileOverride,
    this.pollInterval = const Duration(seconds: 5),
  });

  final String? courseId;
  final String? lessonId;
  final Future<void> Function()? onMediaUpdated;
  final String? existingMediaState;
  final String? existingFileName;
  final Future<WavUploadFile?> Function()? pickFileOverride;
  final Future<void> Function({
    required Uri uploadUrl,
    required Map<String, String> headers,
    required WavUploadFile file,
    required void Function(int sent, int total) onProgress,
  })? uploadFileOverride;
  final Duration pollInterval;

  @override
  ConsumerState<WavUploadCard> createState() => _WavUploadCardState();
}

class _WavUploadCardState extends ConsumerState<WavUploadCard> {
  static const _lessonRequiredText =
      'Spara lektionen för att kunna ladda upp ljud.';
  static const Color _bodyTextColor = Colors.black;
  static const Color _secondaryTextColor = Color(0xFF4A4A4A);
  WavUploadFile? _selectedFile;
  double _progress = 0.0;
  String? _status;
  String? _error;
  String? _mediaId;
  String? _mediaState;
  Timer? _pollTimer;
  bool _uploading = false;

  String? _missingContextMessage({
    required bool hasLessonId,
    required bool hasCourseId,
  }) {
    if (!hasLessonId) {
      return _lessonRequiredText;
    }
    if (!hasCourseId) {
      return 'Lektionen saknar kurskoppling. Ladda om eller välj lektion igen.';
    }
    return null;
  }

  void _showMissingContextMessage(String message) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _error = message;
      _uploading = false;
    });
    showSnack(context, message);
  }

  String _normalizeWavMimeType(String? mimeType, String filename) {
    final lower = (mimeType ?? '').trim().toLowerCase();
    if (lower == 'audio/wav' || lower == 'audio/x-wav') {
      return lower;
    }
    if (lower == 'audio/wave' || lower == 'audio/vnd.wave') {
      return 'audio/wav';
    }
    if (filename.toLowerCase().endsWith('.wav')) {
      return 'audio/wav';
    }
    return lower.isEmpty ? 'audio/wav' : lower;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final courseId = widget.courseId;
    final lessonId = widget.lessonId;
    final hasLessonId = lessonId != null && lessonId.isNotEmpty;
    final hasCourseId = courseId != null && courseId.isNotEmpty;
    if (!hasLessonId || !hasCourseId) {
      final message = _missingContextMessage(
        hasLessonId: hasLessonId,
        hasCourseId: hasCourseId,
      );
      if (message != null) {
        _showMissingContextMessage(message);
      }
      return;
    }

    final picker = widget.pickFileOverride ?? pickWavFile;
    final picked = await picker();
    if (!mounted) return;
    if (picked == null) {
      setState(() => _status = 'Ingen fil vald.');
      return;
    }

    setState(() {
      _selectedFile = picked;
      _progress = 0.0;
      _status = 'WAV vald – förbereder uppladdning…';
      _error = null;
      _mediaId = null;
      _mediaState = null;
      _uploading = true;
    });

    try {
      final repo = ref.read(mediaPipelineRepositoryProvider);
      setState(() => _status = 'Begär uppladdningslänk…');
      final upload = await repo.requestUploadUrl(
        filename: picked.name,
        mimeType: _normalizeWavMimeType(picked.mimeType, picked.name),
        sizeBytes: picked.size,
        mediaType: 'audio',
        courseId: courseId,
        lessonId: lessonId,
      );

      _mediaId = upload.mediaId;
      setState(() => _status = 'Laddar upp WAV…');

      final uploader = widget.uploadFileOverride ?? uploadWavFile;
      await uploader(
        uploadUrl: upload.uploadUrl,
        headers: upload.headers,
        file: picked,
        onProgress: (sent, total) {
          if (!mounted) return;
          final fraction = total <= 0 ? 0.0 : sent / total;
          setState(() => _progress = fraction.clamp(0.0, 1.0));
        },
      );

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _status = 'WAV vald – bearbetas till MP3…';
        _mediaState = 'uploaded';
      });
      await widget.onMediaUpdated?.call();
      _startPolling();
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = failure.message;
        _status = 'Uppladdning misslyckades.';
      });
      showSnack(context, failure.message);
    }
  }

  void _startPolling() {
    final mediaId = _mediaId;
    if (mediaId == null) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) {
      _pollStatus(mediaId);
    });
    _pollStatus(mediaId);
  }

  Future<void> _pollStatus(String mediaId) async {
    try {
      final repo = ref.read(mediaPipelineRepositoryProvider);
      final status = await repo.fetchStatus(mediaId);
      if (!mounted) return;
      setState(() {
        _mediaState = status.state;
        _error = status.errorMessage;
        _status = _statusLabel(status.state);
      });
      if (status.state == 'ready' || status.state == 'failed') {
        _pollTimer?.cancel();
        _pollTimer = null;
        await widget.onMediaUpdated?.call();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  String _statusLabel(String state) {
    switch (state) {
      case 'uploaded':
        return 'WAV vald – bearbetas till MP3…';
      case 'processing':
        return 'WAV vald – bearbetas till MP3…';
      case 'ready':
        return 'MP3 klar – ljudet kan spelas upp';
      case 'failed':
        return 'Bearbetningen misslyckades.';
      default:
        return 'Status okänd.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLessonId =
        widget.lessonId != null && widget.lessonId!.trim().isNotEmpty;
    final hasCourseId =
        widget.courseId != null && widget.courseId!.trim().isNotEmpty;
    final canUpload = hasLessonId && hasCourseId;
    final theme = Theme.of(context);
    final titleStyle =
        theme.textTheme.titleMedium?.copyWith(color: Colors.white);
    final bodyStyle =
        theme.textTheme.bodySmall?.copyWith(color: _bodyTextColor);
    final secondaryStyle =
        theme.textTheme.bodySmall?.copyWith(color: _secondaryTextColor);
    final progressVisible = _uploading && _progress > 0;
    final effectiveState = _mediaState ?? widget.existingMediaState;
    final isProcessingState =
        effectiveState == 'uploaded' || effectiveState == 'processing';
    final isReadyState = effectiveState == 'ready';
    final isFailedState = effectiveState == 'failed';
    final showProcessingState = _uploading || isProcessingState;
    final showReadyState = !showProcessingState && (isReadyState || isFailedState);
    final showUploadAction = !showProcessingState && !showReadyState;
    final showReplaceAction = showReadyState;
    final displayFileName = _selectedFile?.name ?? widget.existingFileName;
    final missingMessage = _missingContextMessage(
      hasLessonId: hasLessonId,
      hasCourseId: hasCourseId,
    );

    String? statusText;
    if (_uploading) {
      statusText = _status ?? (effectiveState != null
          ? _statusLabel(effectiveState)
          : null);
    } else if (effectiveState != null) {
      statusText = _statusLabel(effectiveState);
    } else {
      statusText = _status;
    }
    if (statusText == null && showProcessingState) {
      statusText = 'WAV vald – bearbetas till MP3…';
    }

    Widget? actionButton;
    if (showUploadAction) {
      actionButton = ElevatedButton.icon(
        onPressed: canUpload && !_uploading ? _pickAndUpload : null,
        icon: const Icon(Icons.upload_file),
        label: const Text('Ladda upp WAV'),
      );
    } else if (showReplaceAction) {
      actionButton = OutlinedButton.icon(
        onPressed: canUpload && !_uploading ? _pickAndUpload : null,
        icon: const Icon(Icons.sync),
        label: const Text('Byt WAV'),
      );
    }

    final actionRowChildren = <Widget>[
      if (actionButton != null) actionButton,
      if (displayFileName != null) ...[
        if (actionButton != null) const SizedBox(width: 12),
        Expanded(
          child: Text(
            displayFileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondaryStyle,
          ),
        ),
      ],
    ];

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      opacity: 0.16,
      borderColor: Colors.white.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(
              'WAV-uppladdning',
              style: titleStyle,
            ),
            const SizedBox(height: 8),
            Text(
              'WAV laddas upp och bearbetas till MP3 innan uppspelning.',
              style: bodyStyle,
            ),
            if (actionRowChildren.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: actionRowChildren),
            ],
            if (progressVisible) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
            ],
            if (!canUpload) ...[
              const SizedBox(height: 12),
              Text(
                missingMessage ?? _lessonRequiredText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (canUpload && statusText != null) ...[
              const SizedBox(height: 12),
              Text(
                statusText,
                style: bodyStyle,
              ),
            ],
            if (canUpload && showProcessingState) ...[
              const SizedBox(height: 4),
              Text(
                'Du kan ladda upp en ny WAV när bearbetningen är klar.',
                style: secondaryStyle,
              ),
            ],
            if (canUpload && _error != null && _error!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
        ],
      ),
    );
  }
}
