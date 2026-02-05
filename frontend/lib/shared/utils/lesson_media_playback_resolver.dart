import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';

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

  final preferred = item.preferredUrl?.trim();
  if (preferred != null && preferred.isNotEmpty) {
    try {
      return mediaRepository.resolveUrl(preferred);
    } catch (_) {
      return preferred;
    }
  }

  final signed = await mediaRepository.signMedia(item.id);
  try {
    return mediaRepository.resolveUrl(signed.signedUrl);
  } catch (_) {
    return signed.signedUrl;
  }
}
