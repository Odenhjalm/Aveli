import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/studio/application/home_player_library_controller.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';

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
  static const _contextCourseKey = 'home-player';

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

  String get _contextLessonKey {
    final profile = ref.read(authControllerProvider).profile;
    return profile?.id ?? 'library';
  }

  bool get _isWavUpload {
    final lower = widget.contentType.trim().toLowerCase();
    if (lower == 'audio/wav' ||
        lower == 'audio/x-wav' ||
        lower == 'audio/wave' ||
        lower == 'audio/vnd.wave') {
      return true;
    }
    return widget.file.name.toLowerCase().endsWith('.wav');
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

  Future<void> _start() async {
    if (_uploading || _processing) return;
    _pollTimer?.cancel();
    _pollTimer = null;

    setState(() {
      _progress = 0.0;
      _error = null;
      _status = 'Förbereder uppladdning…';
      _uploading = true;
      _processing = false;
    });

    final lower = widget.contentType.trim().toLowerCase();
    final filenameLower = widget.file.name.toLowerCase();
    final isMp4 = lower == 'video/mp4' || filenameLower.endsWith('.mp4');
    final isVideo = lower.startsWith('video/') || isMp4;
    final isAudio = lower.startsWith('audio/') || _isWavUpload;

    if (isAudio && !_isWavUpload) {
      const message = 'Endast WAV stöds för ljud i Home Player.';
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
      });
      return;
    }

    if (isVideo && !isMp4) {
      const message = 'Endast MP4 stöds för video i Home Player.';
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
      });
      return;
    }

    if (_isWavUpload) {
      await _uploadViaMediaPipeline();
    } else {
      await _uploadViaHomeStorage();
    }
  }

  Future<void> _uploadViaMediaPipeline() async {
    final normalizedMime = _normalizeWavMimeType(
      widget.contentType,
      widget.file.name,
    );

    WavResumableSession? resumableSession;
    try {
      resumableSession = await findResumableSession(
        courseId: _contextCourseKey,
        lessonId: _contextLessonKey,
        file: widget.file,
      );
    } catch (_) {
      resumableSession = null;
    }

    if (resumableSession != null) {
      try {
        final repo = ref.read(mediaPipelineRepositoryProvider);
        final db = await repo.fetchStatus(resumableSession.mediaId);
        final dbState = db.state.trim().toLowerCase();
        final dbAllowsResume = dbState == 'uploaded' || dbState == 'processing';
        if (!dbAllowsResume) {
          clearResumableSession(resumableSession);
          resumableSession = null;
        }
      } catch (_) {
        // If status fails we still try resuming; signing refresh will catch auth issues.
      }
    }

    Uri uploadUrl;
    String objectPath;
    Map<String, String> uploadHeaders;
    String mediaId;

    if (resumableSession != null) {
      mediaId = resumableSession.mediaId;
      uploadUrl = resumableSession.sessionUrl;
      objectPath = resumableSession.objectPath;
      uploadHeaders = resumableSession.resumableHeaders();
      if (mounted) {
        setState(() => _status = 'Återupptar uppladdning…');
      }
    } else {
      try {
        final repo = ref.read(mediaPipelineRepositoryProvider);
        final upload = await repo.requestUploadUrl(
          filename: widget.file.name,
          mimeType: normalizedMime,
          sizeBytes: widget.file.size,
          mediaType: 'audio',
          purpose: 'home_player_audio',
        );
        mediaId = upload.mediaId;
        uploadUrl = upload.uploadUrl;
        objectPath = upload.objectPath;
        uploadHeaders = upload.headers;
        if (mounted) {
          setState(() => _status = 'Laddar upp…');
        }
      } catch (error, stackTrace) {
        final failure = AppFailure.from(error, stackTrace);
        var message = 'Kunde inte starta uppladdningen. Försök igen.';
        if (failure is ValidationFailure) {
          final detail = failure.message.trim();
          if (detail.isNotEmpty) {
            message = detail.startsWith('File too large')
                ? detail.replaceFirst('File too large', 'Filen är för stor')
                : detail;
          }
        } else if (failure is ServerFailure) {
          message = failure.message;
        } else if (failure is NetworkFailure ||
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
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _error = message;
          _status = message;
        });
        return;
      }
    }

    _cancelToken = WavUploadCancelToken();

    try {
      await uploadWavFile(
        mediaId: mediaId,
        courseId: _contextCourseKey,
        lessonId: _contextLessonKey,
        uploadUrl: uploadUrl,
        objectPath: objectPath,
        headers: uploadHeaders,
        file: widget.file,
        contentType: normalizedMime,
        onProgress: (sent, total) {
          if (!mounted) return;
          final fraction = total <= 0 ? 0.0 : sent / total;
          setState(() => _progress = fraction.clamp(0.0, 1.0));
        },
        cancelToken: _cancelToken,
        onResume: (resumed) {
          if (!mounted || !resumed) return;
          setState(() => _status = 'Återupptar uppladdning…');
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
    } on WavUploadFailure catch (failure) {
      final message = _friendlyUploadFailure(failure.kind);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
        _cancelToken = null;
      });
      return;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Home WAV upload failed: $error');
      }
      final message = 'Uppladdningen misslyckades. Försök igen.';
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
        _cancelToken = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _uploading = false;
      _processing = true;
      _status = 'Registrerar media…';
      _cancelToken = null;
    });

    try {
      final repo = ref.read(studioRepositoryProvider);
      await repo.uploadHomePlayerUpload(
        title: widget.title,
        mediaAssetId: mediaId,
        active: widget.active,
      );
      if (!mounted) return;
      ref.invalidate(homePlayerLibraryProvider);
      setState(() => _status = 'Bearbetar ljud…');
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

  Future<void> _uploadViaHomeStorage() async {
    final mimeType = widget.contentType.trim().toLowerCase();
    WavResumableSession? resumableSession;
    try {
      resumableSession = await findResumableSession(
        courseId: _contextCourseKey,
        lessonId: _contextLessonKey,
        file: widget.file,
      );
    } catch (_) {
      resumableSession = null;
    }

    Uri uploadUrl;
    String objectPath;
    Map<String, String> uploadHeaders;
    String sessionId;

    if (resumableSession != null) {
      sessionId = resumableSession.mediaId;
      uploadUrl = resumableSession.sessionUrl;
      objectPath = resumableSession.objectPath;
      uploadHeaders = resumableSession.resumableHeaders();
      if (mounted) {
        setState(() => _status = 'Återupptar uppladdning…');
      }
    } else {
      try {
        final repo = ref.read(studioRepositoryProvider);
        final signing = await repo.requestHomePlayerUploadUrl(
          filename: widget.file.name,
          mimeType: mimeType,
          sizeBytes: widget.file.size,
        );
        final uploadUrlRaw = signing['upload_url']?.toString() ?? '';
        final objectPathRaw = signing['object_path']?.toString() ?? '';
        final headersRaw = signing['headers'] as Map? ?? const {};
        if (uploadUrlRaw.isEmpty || objectPathRaw.isEmpty) {
          throw StateError('Uppladdningslänk saknas.');
        }
        uploadUrl = Uri.parse(uploadUrlRaw);
        objectPath = objectPathRaw;
        uploadHeaders = <String, String>{
          for (final entry in headersRaw.entries)
            entry.key.toString(): entry.value.toString(),
        };
        sessionId = objectPathRaw;
        if (mounted) {
          setState(() => _status = 'Laddar upp…');
        }
      } catch (error, stackTrace) {
        final failure = AppFailure.from(error, stackTrace);
        final message = 'Kunde inte starta uppladdningen: ${failure.message}';
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _error = message;
          _status = message;
        });
        return;
      }
    }

    _cancelToken = WavUploadCancelToken();

    try {
      await uploadWavFile(
        mediaId: sessionId,
        courseId: _contextCourseKey,
        lessonId: _contextLessonKey,
        uploadUrl: uploadUrl,
        objectPath: objectPath,
        headers: uploadHeaders,
        file: widget.file,
        contentType: mimeType,
        onProgress: (sent, total) {
          if (!mounted) return;
          final fraction = total <= 0 ? 0.0 : sent / total;
          setState(() => _progress = fraction.clamp(0.0, 1.0));
        },
        cancelToken: _cancelToken,
        onResume: (resumed) {
          if (!mounted || !resumed) return;
          setState(() => _status = 'Återupptar uppladdning…');
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
          final repo = ref.read(studioRepositoryProvider);
          final refreshed = await repo.refreshHomePlayerUploadUrl(
            objectPath: session.objectPath,
            mimeType: session.contentType,
          );
          final uploadUrlRaw = refreshed['upload_url']?.toString() ?? '';
          final objectPathRaw = refreshed['object_path']?.toString() ?? '';
          final headersRaw = refreshed['headers'] as Map? ?? const {};
          if (uploadUrlRaw.isEmpty || objectPathRaw.isEmpty) {
            throw const WavUploadFailure(WavUploadFailureKind.failed);
          }
          return WavUploadSigningRefresh(
            uploadUrl: Uri.parse(uploadUrlRaw),
            objectPath: objectPathRaw,
            headers: <String, String>{
              for (final entry in headersRaw.entries)
                entry.key.toString(): entry.value.toString(),
            },
            expiresAt:
                DateTime.tryParse(
                  refreshed['expires_at']?.toString() ?? '',
                )?.toUtc() ??
                DateTime.now().toUtc().add(const Duration(hours: 2)),
          );
        },
        onSigningRefresh: () {
          if (!mounted) return;
          setState(() => _status = 'Återautentiserar uppladdning…');
        },
        resumableSession: resumableSession,
      );
    } on WavUploadFailure catch (failure) {
      final message = _friendlyUploadFailure(failure.kind);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
        _cancelToken = null;
      });
      return;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Home upload failed: $error');
      }
      final message = 'Uppladdningen misslyckades. Försök igen.';
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = message;
        _status = message;
        _cancelToken = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _uploading = false;
      _status = 'Registrerar media…';
      _cancelToken = null;
    });

    try {
      final repo = ref.read(studioRepositoryProvider);
      await repo.createHomePlayerUploadFromStorage(
        title: widget.title,
        storagePath: objectPath,
        contentType: mimeType,
        byteSize: widget.file.size,
        originalName: widget.file.name,
        active: widget.active,
      );
      if (!mounted) return;
      ref.invalidate(homePlayerLibraryProvider);
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      final message = 'Kunde inte spara uppladdningen: ${failure.message}';
      if (!mounted) return;
      setState(() {
        _error = message;
        _status = message;
      });
    }
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
          _status = 'MP3 klar – ljudet kan spelas upp';
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
        _status = 'Bearbetar ljud…';
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
        title: const Text('Laddar upp media'),
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
                      _status ?? (_uploading ? 'Laddar upp…' : 'Förbereder…'),
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
