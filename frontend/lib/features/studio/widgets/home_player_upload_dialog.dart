import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/studio/application/home_player_library_controller.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/widgets/home_player_upload_routing.dart';

import 'wav_upload_source.dart';
import 'wav_upload_types.dart';

class HomePlayerUploadDialog extends ConsumerStatefulWidget {
  const HomePlayerUploadDialog({
    super.key,
    required this.file,
    required this.title,
    required this.contentType,
    required this.textBundle,
    this.active = true,
  });

  final WavUploadFile file;
  final String title;
  final String contentType;
  final HomePlayerTextBundle textBundle;
  final bool active;

  @override
  ConsumerState<HomePlayerUploadDialog> createState() =>
      _HomePlayerUploadDialogState();
}

class _HomePlayerUploadDialogState
    extends ConsumerState<HomePlayerUploadDialog> {
  static const _pollInterval = Duration(seconds: 5);

  double _progress = 0.0;
  String? _status;
  String? _error;
  bool _uploading = false;
  bool _processing = false;

  Timer? _pollTimer;
  WavUploadCancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cancelToken?.cancel();
    super.dispose();
  }

  void _cancelUpload() {
    _cancelToken?.cancel();
  }

  Future<void> _start() async {
    if (_uploading || _processing) return;
    _pollTimer?.cancel();
    _pollTimer = null;

    setState(() {
      _progress = 0.0;
      _error = null;
      _status = widget.textBundle.requireValue('home.player_upload.prepare_status');
      _uploading = true;
      _processing = false;
    });

    final route = detectHomePlayerUploadRoute(
      mimeType: widget.contentType,
      filename: widget.file.name,
    );
    final errorTextId = homePlayerUploadUnsupportedTextId(route);
    if (errorTextId != null) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        final error = widget.textBundle.requireValue(errorTextId);
        _error = error;
        _status = error;
      });
      return;
    }

    if (route == HomePlayerUploadRoute.wavPipeline) {
      await _uploadViaCanonicalHomePlayerRoute();
      return;
    }

    await _uploadViaCanonicalHomePlayerRoute(
      normalizedMimeType: homePlayerUploadNormalizedMimeType(route),
    );
  }

  Future<void> _uploadViaCanonicalHomePlayerRoute({
    String? normalizedMimeType,
  }) async {
    final normalizedMime = (normalizedMimeType?.trim().isNotEmpty ?? false)
        ? normalizedMimeType!.trim().toLowerCase()
        : _normalizeWavMimeType(widget.contentType, widget.file.name);

    if (!normalizedMime.startsWith('audio/')) {
      final message = widget.textBundle.requireValue(
        'home.player_upload.audio_only_error',
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
      });
      return;
    }

    final studioRepo = ref.read(studioRepositoryProvider);
    final pipelineRepo = ref.read(mediaPipelineRepositoryProvider);
    final uploadCancel = WavUploadCancelToken();
    final dioCancel = CancelToken();
    uploadCancel.onCancel(() => dioCancel.cancel('Upload cancelled'));
    _cancelToken = uploadCancel;

    late final String mediaId;

    try {
      final uploadPayload = await studioRepo.requestHomePlayerUploadUrl(
        filename: widget.file.name,
        mimeType: normalizedMime,
        sizeBytes: widget.file.size,
      );
      final upload = MediaUploadTarget.fromCanonicalMediaAssetResponse(
        uploadPayload,
      );
      if (upload.uploadEndpoint.isEmpty || upload.uploadSessionId.isEmpty) {
        throw StateError('home_player_upload_session_missing');
      }
      mediaId = upload.mediaId;

      if (mounted) {
        setState(
          () => _status = widget.textBundle.requireValue(
            'home.player_upload.uploading_status',
          ),
        );
      }

      await pipelineRepo.uploadBytes(
        target: upload,
        data: await widget.file.readAsBytes(),
        contentType: normalizedMime,
        cancelToken: dioCancel,
        onSendProgress: (sent, total) {
          if (!mounted) return;
          final resolvedTotal = total > 0 ? total : widget.file.size;
          final fraction = resolvedTotal <= 0 ? 0.0 : sent / resolvedTotal;
          setState(() => _progress = fraction.clamp(0.0, 1.0));
        },
      );
    } on DioException catch (error, stackTrace) {
      if (error.type == DioExceptionType.cancel) {
        _showUploadFailure(
          widget.textBundle.requireValue('home.player_upload.cancelled_status'),
        );
        return;
      }
      _showUploadFailure(_messageForUploadStartFailure(error, stackTrace));
      return;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Home upload failed: $error');
      }
      _showUploadFailure(_messageForUploadStartFailure(error, stackTrace));
      return;
    }

    if (!mounted) return;
    setState(() {
      _uploading = false;
      _processing = true;
      _status = widget.textBundle.requireValue(
        'home.player_upload.registering_status',
      );
      _cancelToken = null;
    });

    try {
      await pipelineRepo.completeUpload(mediaId: mediaId);
      await studioRepo.uploadHomePlayerUpload(
        title: widget.title,
        mediaAssetId: mediaId,
        active: widget.active,
      );
      if (!mounted) return;
      ref.invalidate(homePlayerLibraryProvider);
      setState(
        () => _status = widget.textBundle.requireValue(
          'home.player_upload.processing_status',
        ),
      );
      _startPolling(mediaId);
    } catch (error, stackTrace) {
      final message =
          _canonicalBackendMessage(error, stackTrace) ??
          widget.textBundle.requireValue('home.player_upload.save_failed_error');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = message;
        _status = message;
      });
    }
  }

  String _messageForUploadStartFailure(Object error, StackTrace stackTrace) {
    return _canonicalBackendMessage(error, stackTrace) ??
        widget.textBundle.requireValue('home.player_upload.start_failed_error');
  }

  String? _canonicalBackendMessage(Object error, StackTrace stackTrace) {
    final failure = AppFailure.from(error, stackTrace);
    final message = failure.message.trim();
    if (failure.code != null && message.isNotEmpty) {
      return message;
    }
    return null;
  }

  void _showUploadFailure(String message) {
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _error = message;
      _status = message;
      _cancelToken = null;
    });
  }

  void _startPolling(String mediaId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollStatus(mediaId));
    _pollStatus(mediaId);
  }

  Future<void> _pollStatus(String mediaId) async {
    try {
      final repo = ref.read(mediaPipelineRepositoryProvider);
      final status = await repo.fetchStatus(mediaId);
      if (!mounted) return;

      final state = status.state.trim().toLowerCase();
      if (state == 'ready') {
        ref.invalidate(homePlayerLibraryProvider);
        setState(() {
          _processing = false;
          _status = widget.textBundle.requireValue('home.player_upload.ready_status');
        });
        _pollTimer?.cancel();
        _pollTimer = null;
        Navigator.of(context).pop(true);
        return;
      }

      if (state == 'failed') {
        _pollTimer?.cancel();
        _pollTimer = null;
        ref.invalidate(homePlayerLibraryProvider);
        setState(() {
          _processing = false;
          _error = widget.textBundle.requireValue(
            'home.player_upload.processing_failed_error',
          );
          _status = widget.textBundle.requireValue(
            'home.player_upload.processing_failed_error',
          );
        });
        return;
      }

      setState(() {
        _status = widget.textBundle.requireValue(
          'home.player_upload.processing_status',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = widget.textBundle.requireValue(
          'home.player_upload.refresh_failed_error',
        );
      });
    }
  }

  String _normalizeWavMimeType(String mimeType, String filename) {
    final lower = mimeType.trim().toLowerCase();
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
  Widget build(BuildContext context) {
    final canDismiss = !_uploading;
    final theme = Theme.of(context);
    final percent = (_progress * 100).clamp(0, 100).toStringAsFixed(0);

    return PopScope(
      canPop: canDismiss,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.textBundle.requireValue(
                'home.player_upload.wait_until_complete_status',
              ),
            ),
          ),
        );
      },
      child: AlertDialog(
        title: Text(widget.textBundle.requireValue('home.player_upload.title')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _uploading ? _progress : null),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _status ??
                          (_uploading
                              ? widget.textBundle.requireValue(
                                  'home.player_upload.uploading_status',
                                )
                              : widget.textBundle.requireValue(
                                  'home.player_upload.prepare_status',
                                )),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (_uploading)
                    Text('$percent %', style: theme.textTheme.bodySmall),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
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
            onPressed: !_uploading
                ? () => Navigator.of(context).pop(false)
                : null,
            child: Text(
              widget.textBundle.requireValue('home.player_upload.close_action'),
            ),
          ),
          if (_uploading)
            FilledButton.icon(
              onPressed: _cancelUpload,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(
                widget.textBundle.requireValue('home.player_upload.cancel_action'),
              ),
            )
          else if (_error != null && !_processing)
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh),
              label: Text(
                widget.textBundle.requireValue('home.player_upload.retry_action'),
              ),
            ),
        ],
      ),
    );
  }
}
