import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/errors/app_failure.dart';
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
    this.active = true,
  });

  final WavUploadFile file;
  final String title;
  final String contentType;
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
      _status = 'Förbereder uppladdning...';
      _uploading = true;
      _processing = false;
    });

    final route = detectHomePlayerUploadRoute(
      mimeType: widget.contentType,
      filename: widget.file.name,
    );
    final error = homePlayerUploadUnsupportedMessage(route);
    if (error.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
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
      const message = 'Home-spelaren stöder bara ljudfiler.';
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
        throw StateError('Uppladdningssession saknas.');
      }
      mediaId = upload.mediaId;

      if (mounted) {
        setState(() => _status = 'Laddar upp...');
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
        _showUploadFailure('Uppladdningen avbröts.');
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
      _status = 'Registrerar ljudfil...';
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
      setState(() => _status = 'Bearbetar ljud...');
      _startPolling(mediaId);
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      final message = 'Kunde inte spara uppladdningen: ${failure.message}';
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = message;
        _status = message;
      });
    }
  }

  String _messageForUploadStartFailure(Object error, StackTrace stackTrace) {
    final failure = AppFailure.from(error, stackTrace);
    var message = 'Kunde inte starta uppladdningen. Försök igen.';
    if (failure is ValidationFailure) {
      final detail = failure.message.trim();
      if (detail.isNotEmpty) {
        message = detail.startsWith('File too large')
            ? detail.replaceFirst('File too large', 'Filen är för stor')
            : detail;
      }
    } else if (failure is ServerFailure ||
        failure is NetworkFailure ||
        failure is TimeoutFailure ||
        failure is UnauthorizedFailure ||
        failure is NotFoundFailure ||
        failure is ConfigurationFailure) {
      message = failure.message;
    } else {
      final detail = failure.message.trim();
      if (detail.isNotEmpty) {
        message = 'Kunde inte starta uppladdningen: $detail';
      }
    }
    return message;
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
          _status = 'Ljudfilen är klar för uppspelning.';
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
          _error = 'Bearbetningen misslyckades.';
          _status = 'Bearbetningen misslyckades.';
        });
        return;
      }

      setState(() {
        _status = 'Bearbetar ljud...';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunde inte uppdatera statusen just nu.';
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
          const SnackBar(
            content: Text('Vänta tills uppladdningen är klar eller avbryt.'),
          ),
        );
      },
      child: AlertDialog(
        title: const Text('Laddar upp ljud'),
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
                          (_uploading ? 'Laddar upp...' : 'Förbereder...'),
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
            child: const Text('Stäng'),
          ),
          if (_uploading)
            FilledButton.icon(
              onPressed: _cancelUpload,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Avbryt'),
            )
          else if (_error != null && !_processing)
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh),
              label: const Text('Försök igen'),
            ),
        ],
      ),
    );
  }
}
