import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';

import 'lesson_media_preview_cache.dart';

class LessonMediaPreview extends ConsumerWidget {
  const LessonMediaPreview({
    super.key,
    required this.lessonMediaId,
    required this.mediaType,
    this.src,
  });

  final String lessonMediaId;
  final String mediaType;
  final String? src;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(lessonMediaPreviewCacheProvider);
    final mediaRepository = ref.watch(mediaRepositoryProvider);
    final normalizedType = mediaType.trim().toLowerCase();
    final previewFuture = lessonMediaId.trim().isEmpty
        ? Future<LessonMediaPreviewData?>.value(null)
        : cache.getPreview(lessonMediaId);

    return RepaintBoundary(
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        descendantsAreFocusable: false,
        child: IgnorePointer(
          ignoring: true,
          child: FutureBuilder<LessonMediaPreviewData?>(
            future: previewFuture,
            builder: (context, snapshot) {
              final preview = snapshot.data;
              final visualUrl = _resolveVisualUrl(
                mediaRepository: mediaRepository,
                preferred: preview?.visualUrl,
                fallback: src,
              );
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting &&
                  preview == null;
              return _LessonMediaPreviewFrame(
                mediaType: normalizedType,
                visualUrl: preview?.previewBlocked == true ? null : visualUrl,
                fileName: preview?.fileName,
                durationSeconds: preview?.durationSeconds,
                isLoading: isLoading,
                isBlocked: preview?.previewBlocked == true,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LessonMediaPreviewFrame extends StatelessWidget {
  const _LessonMediaPreviewFrame({
    required this.mediaType,
    required this.visualUrl,
    required this.fileName,
    required this.durationSeconds,
    required this.isLoading,
    required this.isBlocked,
  });

  final String mediaType;
  final String? visualUrl;
  final String? fileName;
  final int? durationSeconds;
  final bool isLoading;
  final bool isBlocked;

  static const double _imageAspectRatio = 4 / 3;
  static const double _videoAspectRatio = 16 / 9;
  static const double _audioHeight = 92;

  @override
  Widget build(BuildContext context) {
    final isAudio = mediaType == 'audio';
    final content = DecoratedBox(
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
                    Colors.black.withValues(alpha: visualUrl == null ? 0.0 : 0.08),
                    Colors.black.withValues(alpha: 0.34),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: isLoading
                ? _PreviewSkeleton(mediaType: mediaType)
                : _PreviewLabel(
                    mediaType: mediaType,
                    fileName: fileName,
                    durationSeconds: durationSeconds,
                    isBlocked: isBlocked,
                  ),
          ),
        ],
      ),
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
    required this.isBlocked,
  });

  final String mediaType;
  final String? fileName;
  final int? durationSeconds;
  final bool isBlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = fileName ?? _defaultLabel();
    final detail = isBlocked
        ? 'Förhandsvisning otillgänglig i editorn'
        : _detailText();

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
              child: Icon(
                _iconForType(),
                color: Colors.white,
                size: 20,
              ),
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
  const _PreviewSkeleton({required this.mediaType});

  final String mediaType;

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.white.withValues(alpha: 0.18);
    return Align(
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
  required String? preferred,
  required String? fallback,
}) {
  final candidate = preferred?.trim().isNotEmpty == true ? preferred : fallback;
  if (candidate == null) return null;
  final normalized = candidate.trim();
  if (normalized.isEmpty) return null;

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
