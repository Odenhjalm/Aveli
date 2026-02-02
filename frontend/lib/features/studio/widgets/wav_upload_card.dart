import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/utils/snack.dart';

import 'wav_upload_source.dart';
import 'wav_upload_types.dart';

class WavUploadCard extends ConsumerStatefulWidget {
  const WavUploadCard({
    super.key,
    required this.courseId,
    required this.lessonId,
    this.onMediaUpdated,
    this.existingLessonMediaId,
    this.existingMediaState,
    this.existingFileName,
    this.pickFileOverride,
    this.uploadFileOverride,
    this.pollInterval = const Duration(seconds: 5),
  });

  final String? courseId;
  final String? lessonId;
  final Future<void> Function()? onMediaUpdated;
  final String? existingLessonMediaId;
  final String? existingMediaState;
  final String? existingFileName;
  final Future<WavUploadFile?> Function()? pickFileOverride;
  final Future<void> Function({
    required String mediaId,
    required String courseId,
    required String lessonId,
    required Uri uploadUrl,
    required String objectPath,
    required Map<String, String> headers,
    required WavUploadFile file,
    required String contentType,
    required void Function(int sent, int total) onProgress,
    WavUploadCancelToken? cancelToken,
    void Function(bool resumed)? onResume,
    Future<bool> Function()? ensureAuth,
    Future<WavUploadSigningRefresh> Function(WavResumableSession session)?
    refreshSigning,
    void Function()? onSigningRefresh,
    WavResumableSession? resumableSession,
  })?
  uploadFileOverride;
  final Duration pollInterval;

  @override
  ConsumerState<WavUploadCard> createState() => _WavUploadCardState();
}

class _WavUploadCardState extends ConsumerState<WavUploadCard> {
  static const _lessonRequiredText =
      'Spara lektionen för att kunna ladda upp ljud.';

  WavUploadFile? _selectedFile;
  double _progress = 0.0;
  String? _status;
  String? _error;
  String? _mediaId;
  String? _mediaState;
  Timer? _pollTimer;
  bool _uploading = false;
  bool _deleting = false;
  bool _deleted = false;
  WavUploadCancelToken? _cancelToken;

  @override
  void didUpdateWidget(covariant WavUploadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextId = widget.existingLessonMediaId;
    if (nextId != null && nextId.trim().isNotEmpty) {
      _deleted = false;
    }
  }

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

  String _suggestMediaDisplayName(String filename) {
    final trimmed = filename.trim();
    if (trimmed.isEmpty) return '';
    final withoutQuery = trimmed.split('?').first;
    final segments = withoutQuery.split('/');
    final last = segments.isNotEmpty ? segments.last : withoutQuery;
    final parts = last.split('.');
    final stem = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join('.')
        : last;
    return stem.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  Future<String?> _promptRequiredMediaDisplayName(String suggested) async {
    final controller = TextEditingController(text: suggested);
    String current = controller.text.trim();

    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Ge ljudet/videon ett namn'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Namn',
              hintText: 'Till exempel: Introduktion',
            ),
            onChanged: (_) => setDialogState(() {
              current = controller.text.trim();
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Avbryt'),
            ),
            ElevatedButton(
              onPressed: current.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(current),
              child: const Text('Fortsätt'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result?.trim();
  }

  String _friendlyUploadFailure(WavUploadFailureKind kind) {
    switch (kind) {
      case WavUploadFailureKind.cancelled:
        return 'Uppladdningen avbröts.';
      case WavUploadFailureKind.expired:
        return 'Kunde inte återautentisera uppladdningen. Försök igen.';
      case WavUploadFailureKind.failed:
        return 'Uppladdningen misslyckades. Försök igen.';
    }
  }

  void _cancelUpload() {
    _cancelToken?.cancel();
  }

  Future<void> _deleteExisting() async {
    final mediaId = widget.existingLessonMediaId;
    if (mediaId == null || mediaId.trim().isEmpty) return;
    if (_deleting) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    _cancelToken?.cancel();
    setState(() {
      _deleting = true;
      _error = null;
      _status = 'Tar bort…';
    });
    try {
      final repo = ref.read(studioRepositoryProvider);
      await repo.deleteLessonMedia(mediaId);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _deleted = true;
        _selectedFile = null;
        _progress = 0.0;
        _status = null;
        _error = null;
        _mediaId = null;
        _mediaState = null;
        _uploading = false;
        _cancelToken = null;
      });
      await widget.onMediaUpdated?.call();
      if (!mounted) return;
      showSnack(context, 'Ljud borttaget.');
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      final message = 'Kunde inte ta bort ljud: ${failure.message}';
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = message;
        _status = message;
      });
      showSnack(context, message);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cancelToken?.cancel();
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

    final displayName = await _promptRequiredMediaDisplayName(
      _suggestMediaDisplayName(picked.name),
    );
    if (!mounted) return;
    if (displayName == null) {
      setState(() => _status = 'Uppladdning avbröts.');
      return;
    }
    if (displayName.trim().isEmpty) {
      setState(() => _status = 'Namn krävs för ljud och video.');
      showSnack(context, 'Namn krävs för ljud och video.');
      return;
    }

    final normalizedMime = _normalizeWavMimeType(picked.mimeType, picked.name);

    final resumeSession = await findResumableSession(
      courseId: courseId,
      lessonId: lessonId,
      file: picked,
    );
    if (!mounted) return;

    WavResumableSession? resumableSession = resumeSession;
    if (resumableSession != null) {
      String? dbState;
      try {
        final repo = ref.read(mediaPipelineRepositoryProvider);
        final status = await repo.fetchStatus(resumableSession.mediaId);
        dbState = status.state;
      } catch (_) {
        dbState = null;
      }

      final dbAllowsResume = dbState == 'uploaded' || dbState == 'processing';
      if (!dbAllowsResume) {
        if (dbState == 'failed') {
          clearResumableSession(resumableSession);
          if (!mounted) return;
          setState(() {
            _selectedFile = null;
            _progress = 0.0;
            _status = _statusLabel('failed');
            _error = null;
            _mediaId = null;
            _mediaState = 'failed';
            _uploading = false;
            _cancelToken = null;
          });
          return;
        }
        resumableSession = null;
      }
    }

    if (!mounted) return;

    setState(() {
      _selectedFile = picked;
      _progress = 0.0;
      _status = resumableSession != null
          ? 'Återupptar uppladdning…'
          : 'Förbereder uppladdning…';
      _error = null;
      _mediaId = null;
      _mediaState = null;
      _uploading = true;
    });

    Uri uploadUrl;
    String objectPath;
    Map<String, String> uploadHeaders;
    String mediaId;

    if (resumableSession != null) {
      mediaId = resumableSession.mediaId;
      uploadUrl = resumableSession.sessionUrl;
      objectPath = resumableSession.objectPath;
      uploadHeaders = resumableSession.resumableHeaders();
    } else {
      try {
        final repo = ref.read(mediaPipelineRepositoryProvider);
        final upload = await repo.requestUploadUrl(
          filename: picked.name,
          mimeType: normalizedMime,
          sizeBytes: picked.size,
          mediaType: 'audio',
          courseId: courseId,
          lessonId: lessonId,
        );
        mediaId = upload.mediaId;
        uploadUrl = upload.uploadUrl;
        objectPath = upload.objectPath;
        uploadHeaders = upload.headers;
        if (mounted) {
          setState(() => _status = 'Laddar upp studiomaster…');
        }
      } catch (error, stackTrace) {
        final failure = AppFailure.from(error, stackTrace);
        var message = 'Kunde inte starta uppladdningen. Försök igen.';
        if (failure is ValidationFailure) {
          final detail = failure.message.trim();
          if (detail.isNotEmpty) {
            final localized = detail.startsWith('File too large')
                ? detail.replaceFirst('File too large', 'Filen är för stor')
                : detail;
            message = localized;
          }
        }
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _error = message;
          _status = message;
        });
        showSnack(context, message);
        return;
      }
    }

    _cancelToken = WavUploadCancelToken();
    _mediaId = mediaId;

    try {
      final uploader = widget.uploadFileOverride ?? uploadWavFile;
      await uploader(
        mediaId: mediaId,
        courseId: courseId,
        lessonId: lessonId,
        uploadUrl: uploadUrl,
        objectPath: objectPath,
        headers: uploadHeaders,
        file: picked,
        contentType: normalizedMime,
        onProgress: (sent, total) {
          if (!mounted) return;
          final fraction = total <= 0 ? 0.0 : sent / total;
          setState(() => _progress = fraction.clamp(0.0, 1.0));
        },
        cancelToken: _cancelToken,
        onResume: (resumed) {
          if (!mounted) return;
          if (resumed) {
            setState(() => _status = 'Återupptar uppladdning…');
          }
        },
        ensureAuth: () async {
          final client = ref.read(apiClientProvider);
          return client.ensureAuth(
            onRefresh: () {
              if (!mounted) return;
              setState(() => _status = 'Återautentiserar session…');
            },
          );
        },
        refreshSigning: (session) async {
          final repo = ref.read(mediaPipelineRepositoryProvider);
          final refreshed = await repo.refreshUploadUrl(
            mediaId: session.mediaId,
          );
          return WavUploadSigningRefresh(
            uploadUrl: refreshed.uploadUrl,
            objectPath: refreshed.objectPath,
            headers: refreshed.headers,
            expiresAt: refreshed.expiresAt,
          );
        },
        onSigningRefresh: () {
          if (!mounted) return;
          setState(() => _status = 'Återautentiserar uppladdning…');
        },
        resumableSession: resumableSession,
      );

      try {
        final studioRepo = ref.read(studioRepositoryProvider);
        final mediaItems = await studioRepo.listLessonMedia(lessonId);
        String? lessonMediaId;
        for (final item in mediaItems) {
          final assetId = item['media_asset_id']?.toString();
          if (assetId != null && assetId == mediaId) {
            lessonMediaId = item['id']?.toString();
            break;
          }
        }
        if (lessonMediaId != null && lessonMediaId.trim().isNotEmpty) {
          await studioRepo.createProfileMedia(
            mediaKind: TeacherProfileMediaKind.lessonMedia,
            mediaId: lessonMediaId,
            title: displayName.trim(),
            isPublished: false,
          );
        }
      } catch (_) {
        // Best-effort: WAV should still work even if Home-media registration fails.
      }

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _status = 'Uppladdning klar – bearbetas till MP3';
        _mediaState = 'uploaded';
        _cancelToken = null;
      });
      await widget.onMediaUpdated?.call();
      _startPolling();
    } on WavUploadFailure catch (failure) {
      final message = _friendlyUploadFailure(failure.kind);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
        _cancelToken = null;
      });
      showSnack(context, message);
    } catch (error) {
      final message = 'Uppladdningen misslyckades. Försök igen.';
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
        _error = status.errorMessage?.isNotEmpty == true
            ? 'Bearbetningen misslyckades.'
            : null;
        _status = _statusLabel(status.state);
      });
      if (status.state == 'ready' || status.state == 'failed') {
        _pollTimer?.cancel();
        _pollTimer = null;
        await widget.onMediaUpdated?.call();
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
      case 'uploaded':
        return 'Uppladdning klar – bearbetas till MP3';
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
    final hasLessonId =
        widget.lessonId != null && widget.lessonId!.trim().isNotEmpty;
    final hasCourseId =
        widget.courseId != null && widget.courseId!.trim().isNotEmpty;
    final canUpload = hasLessonId && hasCourseId;
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium;
    final bodyStyle = theme.textTheme.bodySmall;
    final secondaryStyle = theme.textTheme.bodySmall;
    final progressVisible = _uploading && _progress > 0;
    final effectiveState = _deleted
        ? null
        : (_mediaState ?? widget.existingMediaState);
    final isProcessingState =
        effectiveState == 'uploaded' || effectiveState == 'processing';
    final isReadyState = effectiveState == 'ready';
    final isFailedState = effectiveState == 'failed';
    final showProcessingState = _uploading || isProcessingState;
    final showProcessingDetails = !_uploading && isProcessingState;
    final showReadyState =
        !showProcessingState && (isReadyState || isFailedState);
    final showUploadAction = !showProcessingState && !showReadyState;
    final showReplaceAction = showReadyState;
    final displayFileName = _deleted
        ? null
        : (_selectedFile?.name ?? widget.existingFileName);
    final missingMessage = _missingContextMessage(
      hasLessonId: hasLessonId,
      hasCourseId: hasCourseId,
    );

    String? statusText;
    if (_uploading || _deleting) {
      statusText = _status;
    } else if (effectiveState != null) {
      statusText = _statusLabel(effectiveState);
    } else {
      statusText = _status;
    }
    if (statusText == null && showProcessingDetails) {
      statusText = 'Uppladdning klar – bearbetas till MP3';
    }

    Widget? actionButton;
    if (showUploadAction) {
      actionButton = ElevatedButton.icon(
        onPressed: canUpload && !_uploading && !_deleting
            ? _pickAndUpload
            : null,
        icon: const Icon(Icons.upload_file),
        label: const Text('Ladda upp WAV'),
      );
    } else if (showReplaceAction) {
      actionButton = OutlinedButton.icon(
        onPressed: canUpload && !_uploading && !_deleting
            ? _pickAndUpload
            : null,
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

    final canDelete = canUpload && !_uploading && !_deleting;
    final showDeleteButton =
        widget.existingLessonMediaId != null &&
        widget.existingLessonMediaId!.trim().isNotEmpty &&
        !_deleted;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      opacity: 0.16,
      borderColor: Colors.white.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Studiomaster (WAV)', style: titleStyle),
          const SizedBox(height: 8),
          Text(
            'Studiomaster laddas upp och bearbetas till MP3 innan uppspelning.',
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
          if (showDeleteButton) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: canDelete ? _deleteExisting : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Ta bort'),
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
          if (canUpload && showProcessingDetails) ...[
            const SizedBox(height: 4),
            Text(
              'Du kan ladda upp en ny master när bearbetningen är klar.',
              style: secondaryStyle,
            ),
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
