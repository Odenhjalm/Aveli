import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/glass_card.dart';

import 'wav_upload_source.dart';

class WavUploadCard extends ConsumerStatefulWidget {
  const WavUploadCard({
    super.key,
    required this.courseId,
    required this.lessonId,
    this.replacementLessonMediaId,
    this.onMediaUpdated,
    this.pickFileOverride,
    this.pollInterval = const Duration(seconds: 5),
    this.actionLabel = 'Ladda upp ljud',
    this.onPipelineFinalState,
  });

  final String? courseId;
  final String? lessonId;
  final String? replacementLessonMediaId;
  final Future<void> Function()? onMediaUpdated;
  final void Function(String lessonMediaId, String finalState)?
  onPipelineFinalState;
  final Future<WavUploadFile?> Function()? pickFileOverride;
  final Duration pollInterval;
  final String actionLabel;

  @override
  ConsumerState<WavUploadCard> createState() => _WavUploadCardState();
}

class _WavUploadCardState extends ConsumerState<WavUploadCard> {
  static const _lessonRequiredText =
      'Spara lektionen för att kunna ladda upp ljud.';
  static const Set<String> _allowedMimeTypes = <String>{
    'audio/m4a',
    'audio/mp3',
    'audio/mp4',
    'audio/mpeg',
    'audio/wav',
    'audio/x-wav',
  };

  WavUploadFile? _selectedFile;
  double _progress = 0.0;
  String? _status;
  String? _error;
  String? _mediaState;
  Timer? _pollTimer;
  bool _uploading = false;
  CancelToken? _cancelToken;

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

  String? _validationMessageForSelectedFile(WavUploadFile file) {
    final mimeType = file.mimeType;
    if (mimeType == null || !_allowedMimeTypes.contains(mimeType)) {
      return 'Endast MP3, WAV eller M4A med kanonisk MIME-typ stöds.';
    }
    return null;
  }

  void _cancelUpload() {
    _cancelToken?.cancel('cancelled-by-user');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cancelToken?.cancel('disposed');
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final lessonId = widget.lessonId;
    final hasLessonId = lessonId != null && lessonId.isNotEmpty;
    final hasCourseId = widget.courseId != null && widget.courseId!.isNotEmpty;
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

    final validationMessage = _validationMessageForSelectedFile(picked);
    if (validationMessage != null) {
      setState(() {
        _selectedFile = null;
        _status = validationMessage;
        _error = validationMessage;
        _uploading = false;
      });
      showSnack(context, validationMessage);
      return;
    }

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    setState(() {
      _selectedFile = picked;
      _progress = 0.0;
      _status = 'Laddar upp studiomaster…';
      _error = null;
      _mediaState = null;
      _uploading = true;
    });

    try {
      final repo = ref.read(studioRepositoryProvider);
      final uploaded = await repo.uploadLessonMedia(
        lessonId: lessonId,
        data: bytes,
        filename: picked.name,
        contentType: picked.mimeType!,
        mediaType: 'audio',
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress.fraction.clamp(0.0, 1.0));
        },
      );

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _mediaState = uploaded.state;
        _status = _statusLabel(uploaded.state);
        _cancelToken = null;
      });

      await widget.onMediaUpdated?.call();
      if (!mounted) return;

      if (uploaded.state == 'ready' || uploaded.state == 'failed') {
        widget.onPipelineFinalState?.call(
          uploaded.lessonMediaId,
          uploaded.state,
        );
        return;
      }

      _startPolling(uploaded.lessonMediaId);
    } on DioException catch (error, stackTrace) {
      final cancelled = CancelToken.isCancel(error) || cancelToken.isCancelled;
      final message = cancelled
          ? 'Uppladdningen avbröts.'
          : AppFailure.from(error, stackTrace).message;
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
        _cancelToken = null;
      });
      showSnack(context, message);
    } catch (error, stackTrace) {
      final message = AppFailure.from(error, stackTrace).message;
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
        _cancelToken = null;
      });
      showSnack(context, message);
    }
  }

  void _startPolling(String lessonMediaId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) {
      _pollStatus(lessonMediaId);
    });
    _pollStatus(lessonMediaId);
  }

  Future<void> _pollStatus(String lessonMediaId) async {
    final lessonId = widget.lessonId;
    if (lessonId == null || lessonId.isEmpty) {
      return;
    }

    try {
      final repo = ref.read(studioRepositoryProvider);
      final items = await repo.listLessonMedia(lessonId);

      StudioLessonMediaItem? current;
      for (final item in items) {
        if (item.lessonMediaId == lessonMediaId) {
          current = item;
          break;
        }
      }
      if (current == null) {
        return;
      }
      final resolvedCurrent = current;

      if (!mounted) return;
      setState(() {
        _mediaState = resolvedCurrent.state;
        _error = resolvedCurrent.state == 'failed'
            ? 'Bearbetningen misslyckades.'
            : null;
        _status = _statusLabel(resolvedCurrent.state);
      });

      if (resolvedCurrent.state == 'ready' ||
          resolvedCurrent.state == 'failed') {
        _pollTimer?.cancel();
        _pollTimer = null;
        await widget.onMediaUpdated?.call();
        widget.onPipelineFinalState?.call(lessonMediaId, resolvedCurrent.state);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunde inte uppdatera statusen just nu.';
      });
    }
  }

  String _statusLabel(String state) {
    switch (state) {
      case 'pending_upload':
      case 'uploaded':
      case 'processing':
        return 'Uppladdning klar – bearbetas till MP3';
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
    final hasLessonId = widget.lessonId != null && widget.lessonId!.isNotEmpty;
    final hasCourseId = widget.courseId != null && widget.courseId!.isNotEmpty;
    final canUpload = hasLessonId && hasCourseId;
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium;
    final bodyStyle = theme.textTheme.bodySmall;
    final secondaryStyle = theme.textTheme.bodySmall;
    final progressVisible = _uploading && _progress > 0;
    final displayFileName = _selectedFile?.name;
    final missingMessage = _missingContextMessage(
      hasLessonId: hasLessonId,
      hasCourseId: hasCourseId,
    );

    String? statusText;
    if (_uploading) {
      statusText = _status;
    } else if (_mediaState != null) {
      statusText = _statusLabel(_mediaState!);
    } else {
      statusText = _status;
    }

    final actionButton = ElevatedButton.icon(
      onPressed: canUpload && !_uploading ? _pickAndUpload : null,
      icon: const Icon(Icons.upload_file),
      label: Text(widget.actionLabel),
    );

    final actionRowChildren = <Widget>[
      actionButton,
      if (displayFileName != null) ...[
        const SizedBox(width: 12),
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
          Text('Ljud (MP3/WAV/M4A)', style: titleStyle),
          const SizedBox(height: 8),
          Text(
            'Varje MP3-, WAV- eller M4A-fil laddas upp och bearbetas till MP3 innan uppspelning.',
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
          if (_uploading) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _cancelToken == null ? null : _cancelUpload,
              icon: const Icon(Icons.close),
              label: const Text('Avbryt'),
            ),
          ],
          if (!canUpload) ...[
            const SizedBox(height: 12),
            Text(
              missingMessage ?? _lessonRequiredText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (canUpload && statusText != null) ...[
            const SizedBox(height: 12),
            Text(statusText, style: bodyStyle),
          ],
          if (canUpload && _error != null && _error!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
