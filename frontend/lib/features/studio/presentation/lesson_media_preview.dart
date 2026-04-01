import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/shared/utils/lesson_media_render_telemetry.dart';

import 'lesson_media_preview_cache.dart';
import 'lesson_media_preview_hydration.dart';

class LessonMediaPreview extends ConsumerStatefulWidget {
  const LessonMediaPreview({
    super.key,
    required this.lessonMediaId,
    required this.mediaType,
    this.src,
    this.hydrating = false,
    this.hydrationRevision = 0,
    this.hydrationListenable,
  });

  final String lessonMediaId;
  final String mediaType;
  final String? src;
  final bool hydrating;
  final int hydrationRevision;
  final ValueListenable<LessonMediaPreviewHydrationSnapshot>?
  hydrationListenable;

  @override
  ConsumerState<LessonMediaPreview> createState() => _LessonMediaPreviewState();
}

class _LessonMediaPreviewState extends ConsumerState<LessonMediaPreview> {
  late Future<LessonMediaPreviewData?> _previewFuture;
  late int _hydrationRevision;

  @override
  void initState() {
    super.initState();
    _hydrationRevision = _effectiveHydrationRevision();
    _attachHydrationListenable();
    _previewFuture = _createPreviewFuture();
  }

  @override
  void didUpdateWidget(covariant LessonMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hydrationListenable != widget.hydrationListenable) {
      _detachHydrationListenable(oldWidget.hydrationListenable);
      _attachHydrationListenable();
    }
    if (oldWidget.lessonMediaId != widget.lessonMediaId ||
        _hydrationRevision != _effectiveHydrationRevision()) {
      _hydrationRevision = _effectiveHydrationRevision();
      _previewFuture = _createPreviewFuture();
    }
  }

  @override
  void dispose() {
    _detachHydrationListenable(widget.hydrationListenable);
    super.dispose();
  }

  Future<LessonMediaPreviewData?> _createPreviewFuture() {
    if (widget.lessonMediaId.isEmpty) {
      final rawSource = widget.src;
      logMissingLessonMediaIdRender(
        surface: 'studio_editor_preview',
        mediaType: widget.mediaType,
        rawSource: rawSource,
      );
      return Future<LessonMediaPreviewData?>.error(
        StateError('Lesson media preview saknar lessonMediaId.'),
      );
    }
    return ref
        .read(lessonMediaPreviewCacheProvider)
        .getSettledOrFetch(widget.lessonMediaId);
  }

  int _effectiveHydrationRevision() {
    final listenable = widget.hydrationListenable;
    if (listenable != null) {
      return listenable.value.revision;
    }
    return widget.hydrationRevision;
  }

  void _attachHydrationListenable() {
    widget.hydrationListenable?.addListener(_handleHydrationStateChanged);
  }

  void _detachHydrationListenable(
    ValueListenable<LessonMediaPreviewHydrationSnapshot>? listenable,
  ) {
    listenable?.removeListener(_handleHydrationStateChanged);
  }

  void _handleHydrationStateChanged() {
    final nextRevision = _effectiveHydrationRevision();
    if (_hydrationRevision != nextRevision) {
      _hydrationRevision = nextRevision;
      _previewFuture = _createPreviewFuture();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewCache = ref.read(lessonMediaPreviewCacheProvider);
    final mediaType = widget.mediaType;

    return Semantics(
      identifier: 'media-preview',
      child: RepaintBoundary(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          descendantsAreFocusable: false,
          child: IgnorePointer(
            ignoring: true,
            child: FutureBuilder<LessonMediaPreviewData?>(
              future: _previewFuture,
              builder: (context, snapshot) {
                final status = previewCache.statusForPreview(
                  widget.lessonMediaId,
                  snapshot.data,
                );
                _maybeLogUnresolved(mediaType: mediaType, status: status);
                return _buildPreviewFrame(mediaType: mediaType, status: status);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _maybeLogUnresolved({
    required String mediaType,
    required LessonMediaPreviewStatus status,
  }) {
    if (status.state != LessonMediaPreviewState.failed ||
        status.failureKind != LessonMediaPreviewFailureKind.unresolved) {
      return;
    }
    final lessonMediaId = status.lessonMediaId;
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      return;
    }
    logUnresolvedLessonMediaRender(
      event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
      surface: 'studio_editor_preview',
      mediaType: mediaType,
      lessonMediaId: lessonMediaId,
    );
  }

  Widget _buildPreviewFrame({
    required String mediaType,
    required LessonMediaPreviewStatus status,
  }) {
    return _LessonMediaPreviewFrame(
      mediaType: mediaType,
      visualUrl: status.isRenderable ? status.visualUrl : null,
      fileName: status.fileName,
      durationSeconds: status.durationSeconds,
      isLoading: status.state == LessonMediaPreviewState.loading,
      loadingLabel: null,
      errorMessage: status.state == LessonMediaPreviewState.failed
          ? _failureMessage(status)
          : null,
    );
  }

  String _failureMessage(LessonMediaPreviewStatus status) {
    switch (status.failureKind) {
      case LessonMediaPreviewFailureKind.missingId:
        return 'Media saknar ID.';
      case LessonMediaPreviewFailureKind.unresolved:
      case null:
        return 'Förhandsvisningen kunde inte laddas.';
    }
  }
}

class _LessonMediaPreviewFrame extends StatelessWidget {
  const _LessonMediaPreviewFrame({
    required this.mediaType,
    required this.visualUrl,
    required this.fileName,
    required this.durationSeconds,
    required this.isLoading,
    required this.loadingLabel,
    required this.errorMessage,
  });

  final String mediaType;
  final String? visualUrl;
  final String? fileName;
  final int? durationSeconds;
  final bool isLoading;
  final String? loadingLabel;
  final String? errorMessage;

  static const double _imageAspectRatio = 4 / 3;
  static const double _videoAspectRatio = 16 / 9;
  static const double _audioHeight = 92;

  @override
  Widget build(BuildContext context) {
    final isAudio = mediaType == 'audio';
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final minDetailedWidth = isAudio ? 84.0 : 128.0;
        final minDetailedHeight = isAudio ? 72.0 : 84.0;
        final isCompact =
            constraints.maxWidth < minDetailedWidth ||
            constraints.maxHeight < minDetailedHeight;
        return DecoratedBox(
          decoration: _frameDecoration(context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (visualUrl != null) _PreviewImage(url: visualUrl!),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(
                          alpha: visualUrl == null ? 0.0 : 0.08,
                        ),
                        Colors.black.withValues(alpha: 0.34),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(isCompact ? 8 : 14),
                child: isLoading
                    ? _PreviewSkeleton(
                        mediaType: mediaType,
                        compact: isCompact,
                        label: loadingLabel,
                      )
                    : errorMessage != null
                    ? _PreviewError(message: errorMessage!, compact: isCompact)
                    : _PreviewLabel(
                        mediaType: mediaType,
                        fileName: fileName,
                        durationSeconds: durationSeconds,
                        compact: isCompact,
                      ),
              ),
            ],
          ),
        );
      },
    );

    if (isAudio) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(height: _audioHeight, child: content),
      );
    }

    final aspectRatio = mediaType == 'image'
        ? _imageAspectRatio
        : _videoAspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(aspectRatio: aspectRatio, child: content),
    );
  }

  BoxDecoration _frameDecoration(BuildContext context) {
    final theme = Theme.of(context);
    return BoxDecoration(
      border: Border.all(color: theme.colorScheme.outlineVariant),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.surfaceContainer,
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        return const _PreviewError(
          message: 'Förhandsvisningen kunde inte visas.',
          compact: false,
        );
      },
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({
    required this.mediaType,
    required this.fileName,
    required this.durationSeconds,
    required this.compact,
  });

  final String mediaType;
  final String? fileName;
  final int? durationSeconds;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(_iconForType(), color: Colors.white, size: 16),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.bottomLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(_iconForType(), color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_detailText() != null)
                  Text(
                    _detailText()!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType() {
    switch (mediaType) {
      case 'image':
        return Icons.image_outlined;
      case 'audio':
        return Icons.audiotrack_outlined;
      case 'video':
        return Icons.movie_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String? _detailText() {
    if (durationSeconds != null && durationSeconds! > 0) {
      return _formatDuration(durationSeconds!);
    }
    switch (mediaType) {
      case 'image':
        return 'Stillbild';
      case 'audio':
        return 'Passiv ljudpreview';
      case 'video':
        return 'Passiv videopreview';
      default:
        return null;
    }
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message, required this.compact});

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.error_outline,
              color: theme.colorScheme.error,
              size: 16,
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton({
    required this.mediaType,
    required this.compact,
    this.label,
  });

  final String mediaType;
  final bool compact;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.white.withValues(alpha: 0.18);
    if (compact) {
      return Align(
        key: const ValueKey<String>('lesson_media_preview_loading'),
        alignment: Alignment.bottomLeft,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
    final hasLabel = label != null && label!.isNotEmpty;
    return Align(
      key: const ValueKey<String>('lesson_media_preview_loading'),
      alignment: Alignment.bottomLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: mediaType == 'audio' ? 180 : 140,
            height: 12,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 96,
            height: 10,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          if (hasLabel) ...[
            const SizedBox(height: 10),
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final hours = minutes ~/ 60;
  if (hours > 0) {
    final remainingMinutes = minutes % 60;
    return '${hours.toString()}:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
}
