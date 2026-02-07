import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/features/media/data/media_resolution_mode.dart';

/// Single source of truth for resolving lesson media playback URLs.
///
/// - Legacy lesson media: `lesson_media.id` resolves via `/media/sign` →
///   `/media/stream/{jwt}`.
/// - Pipeline audio: `lesson_media.mediaAssetId` resolves via
///   `POST /api/media/playback-url`.
Future<String?> resolveLessonMediaPlaybackUrl({
  required LessonMediaItem item,
  required MediaRepository mediaRepository,
  required MediaPipelineRepository pipelineRepository,
  MediaResolutionMode mode = MediaResolutionMode.studentRender,
}) async {
  if (item.kind == 'audio') {
    final mediaAssetId = item.mediaAssetId?.trim();
    if (mediaAssetId != null && mediaAssetId.isNotEmpty) {
      final state = (item.mediaState ?? 'uploaded').trim().toLowerCase();
      if (state != 'ready') return null;
      final playback = await pipelineRepository.fetchPlaybackUrl(mediaAssetId);
      return playback.playbackUrl.toString();
    }
  }

  final playbackUrl = item.playbackUrl?.trim();
  if (playbackUrl != null && playbackUrl.isNotEmpty) {
    final signedUrl = item.signedUrl?.trim();
    if (signedUrl != null && signedUrl.isNotEmpty && playbackUrl == signedUrl) {
      final expiresAt = item.signedUrlExpiresAt;
      final now = DateTime.now().toUtc();
      final hasValidSigned =
          expiresAt == null ||
          now.isBefore(expiresAt.subtract(const Duration(seconds: 30)));
      if (hasValidSigned) {
        try {
          return mediaRepository.resolveUrl(playbackUrl);
        } catch (_) {
          return playbackUrl;
        }
      }
    } else {
      try {
        return mediaRepository.resolveUrl(playbackUrl);
      } catch (_) {
        return playbackUrl;
      }
    }
  }

  final download = item.downloadUrl?.trim();
  if (download != null &&
      download.isNotEmpty &&
      download.toLowerCase().startsWith('/api/files/')) {
    try {
      return mediaRepository.resolveUrl(download);
    } catch (_) {
      return download;
    }
  }

  final signedUrl = item.signedUrl?.trim();
  final expiresAt = item.signedUrlExpiresAt;
  final now = DateTime.now().toUtc();
  final hasValidSigned =
      signedUrl != null &&
      signedUrl.isNotEmpty &&
      (expiresAt == null ||
          now.isBefore(expiresAt.subtract(const Duration(seconds: 30))));

  if (hasValidSigned) {
    try {
      return mediaRepository.resolveUrl(signedUrl!);
    } catch (_) {
      return signedUrl;
    }
  }

  try {
    final signed = await mediaRepository.signMedia(item.id, mode: mode);
    final resolved = signed.signedUrl.trim();
    if (resolved.isNotEmpty) {
      try {
        return mediaRepository.resolveUrl(resolved);
      } catch (_) {
        return resolved;
      }
    }
  } catch (_) {
    // Fall back to any download URLs below.
  }

  if (download != null && download.isNotEmpty) {
    try {
      return mediaRepository.resolveUrl(download);
    } catch (_) {
      return download;
    }
  }

  if (signedUrl != null && signedUrl.isNotEmpty) {
    try {
      return mediaRepository.resolveUrl(signedUrl);
    } catch (_) {
      return signedUrl;
    }
  }

  return null;
}
