import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
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
  bool _loggedUnresolvedPreview = false;

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
    if (oldWidget.lessonMediaId.trim() != widget.lessonMediaId.trim() ||
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
    final normalizedLessonMediaId = widget.lessonMediaId.trim();
    if (normalizedLessonMediaId.isEmpty) {
      _loggedUnresolvedPreview = false;
      final rawSource = widget.src?.trim();
      logMissingLessonMediaIdRender(
        surface: 'studio_editor_preview',
        mediaType: widget.mediaType,
        rawSource: rawSource,
      );
      if (rawSource != null && rawSource.isNotEmpty) {
        logLegacyMediaBlocked(
          surface: 'studio_editor_preview',
          mediaType: widget.mediaType,
          rawSource: rawSource,
          reason: _isLegacyLessonMediaPath(rawSource)
              ? 'legacy_path'
              : 'raw_media_url',
        );
      }
      return Future<LessonMediaPreviewData?>.value(null);
    }
    _loggedUnresolvedPreview = false;
    return ref
        .read(lessonMediaPreviewCacheProvider)
        .getSettledOrFetch(normalizedLessonMediaId);
  }

  int _effectiveHydrationRevision() {
    return widget.hydrationListenable?.value.revision ??
        widget.hydrationRevision;
  }

  bool _effectiveHydrating() {
    final snapshot = widget.hydrationListenable?.value;
    if (snapshot != null) {
      return snapshot.isHydratingId(widget.lessonMediaId);
    }
    return widget.hydrating;
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
    final mediaRepository = ref.watch(mediaRepositoryProvider);
    final normalizedType = widget.mediaType.trim().toLowerCase();
    final supportsVisualPreview =
        normalizedType == 'image' || normalizedType == 'video';
    final placeholderState = _initialPlaceholderState();

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
                final preview = snapshot.data;
                final isHydrating = _effectiveHydrating();
                final previewVisualUrl = _resolveVisualUrl(
                  mediaRepository: mediaRepository,
                  mediaType: normalizedType,
                  preferred: preview?.visualUrl,
                );
                final visualUrl = previewVisualUrl;
                final isHydratingVisible =
                    isHydrating && supportsVisualPreview && visualUrl == null;
                final isAsyncLoading =
                    isHydrating &&
                    snapshot.connectionState == ConnectionState.waiting &&
                    preview == null &&
                    visualUrl == null;
                final isUnresolved =
                    placeholderState == null &&
                    supportsVisualPreview &&
                    !isHydratingVisible &&
                    !isAsyncLoading &&
                    visualUrl == null;
                if (isUnresolved && !_loggedUnresolvedPreview) {
                  _loggedUnresolvedPreview = true;
                  logUnresolvedLessonMediaRender(
                    event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
                    surface: 'studio_editor_preview',
                    mediaType: normalizedType,
                    lessonMediaId: widget.lessonMediaId,
                  );
                } else if (!isUnresolved) {
                  _loggedUnresolvedPreview = false;
                }
                final isLoading = isHydratingVisible || isAsyncLoading;
                return _LessonMediaPreviewFrame(
                  mediaType: normalizedType,
                  visualUrl: visualUrl,
                  fileName: preview?.fileName,
                  durationSeconds: preview?.durationSeconds,
                  isLoading: isLoading,
                  placeholderState:
                      placeholderState ??
                      (isUnresolved
                          ? _LessonMediaPreviewPlaceholderState.unresolved
                          : null),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  _LessonMediaPreviewPlaceholderState? _initialPlaceholderState() {
    final normalizedLessonMediaId = widget.lessonMediaId.trim();
    if (normalizedLessonMediaId.isNotEmpty) {
      return null;
    }
    final rawSource = widget.src?.trim();
    if (rawSource != null && rawSource.isNotEmpty) {
      return _LessonMediaPreviewPlaceholderState.legacyBlocked;
    }
    return _LessonMediaPreviewPlaceholderState.missingId;
  }
}

enum _LessonMediaPreviewPlaceholderState {
  missingId,
  legacyBlocked,
  unresolved,
}

class _LessonMediaPreviewFrame extends StatelessWidget {
  const _LessonMediaPreviewFrame({
    required this.mediaType,
    required this.visualUrl,
    required this.fileName,
    required this.durationSeconds,
    required this.isLoading,
    required this.placeholderState,
  });

  final String mediaType;
  final String? visualUrl;
  final String? fileName;
  final int? durationSeconds;
  final bool isLoading;
  final _LessonMediaPreviewPlaceholderState? placeholderState;

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
                    ? _PreviewSkeleton(mediaType: mediaType, compact: isCompact)
                    : _PreviewLabel(
                        mediaType: mediaType,
                        fileName: fileName,
                        durationSeconds: durationSeconds,
                        placeholderState: placeholderState,
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
        return const SizedBox.shrink();
      },
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({
    required this.mediaType,
    required this.fileName,
    required this.durationSeconds,
    required this.placeholderState,
    required this.compact,
  });

  final String mediaType;
  final String? fileName;
  final int? durationSeconds;
  final _LessonMediaPreviewPlaceholderState? placeholderState;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = fileName ?? _defaultLabel();
    final detail = switch (placeholderState) {
      _LessonMediaPreviewPlaceholderState.missingId => 'Media saknar ID',
      _LessonMediaPreviewPlaceholderState.legacyBlocked =>
        'Äldre media blockerat',
      _LessonMediaPreviewPlaceholderState.unresolved =>
        'Förhandsvisning saknas',
      null => _detailText(),
    };
    final stateKey = placeholderState == null
        ? null
        : const ValueKey<String>('lesson_media_preview_unresolved');
    if (compact) {
      return Align(
        key: stateKey,
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
      key: stateKey,
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
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

  String _defaultLabel() {
    switch (mediaType) {
      case 'image':
        return 'Bild';
      case 'audio':
        return 'Ljud';
      case 'video':
        return 'Video';
      default:
        return 'Media';
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

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton({required this.mediaType, required this.compact});

  final String mediaType;
  final bool compact;

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
        ],
      ),
    );
  }
}

String? _resolveVisualUrl({
  required MediaRepository mediaRepository,
  required String mediaType,
  required String? preferred,
}) {
  final candidate = preferred;
  if (candidate == null) return null;
  final normalized = candidate.trim();
  if (normalized.isEmpty) return null;
  if (_isLegacyLessonMediaPath(normalized)) {
    logLegacyMediaBlocked(
      surface: 'studio_editor_preview',
      mediaType: mediaType,
      rawSource: normalized,
      reason: 'legacy_path',
    );
    return null;
  }

  final uri = Uri.tryParse(normalized);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return normalized;
  }

  try {
    return mediaRepository.resolveDownloadUrl(normalized);
  } catch (_) {
    return null;
  }
}

bool _isLegacyLessonMediaPath(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return false;
  final uri = Uri.tryParse(normalized);
  final path = uri?.path ?? normalized;
  final lowered = path.toLowerCase();
  return lowered.startsWith('/studio/media/') ||
      lowered.startsWith('/media/stream/');
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
