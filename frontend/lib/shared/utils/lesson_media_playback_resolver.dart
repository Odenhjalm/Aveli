import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';

bool _isAuthProtectedPlaybackPath(String path) {
  final normalized = path.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.startsWith('/studio/media/') ||
      normalized.startsWith('/api/media/') ||
      normalized.startsWith('/media/sign');
}

String? _resolveBrowserPlayableUrl(
  MediaRepository mediaRepository,
  String? value,
) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  var resolved = raw;
  try {
    resolved = mediaRepository.resolveUrl(raw);
  } catch (_) {
    // Keep the original URL when it is already absolute/signed.
  }

  final uri = Uri.tryParse(resolved);
  final path = uri?.path ?? resolved;
  if (_isAuthProtectedPlaybackPath(path)) {
    return null;
  }
  return resolved;
}

Future<String?> resolveLessonMediaSignedPlaybackUrl({
  required String lessonMediaId,
  required MediaRepository mediaRepository,
  required MediaPipelineRepository pipelineRepository,
}) async {
  final mediaId = lessonMediaId.trim();
  if (mediaId.isEmpty) return null;
  final playbackUrl = await pipelineRepository.fetchLessonPlaybackUrl(mediaId);
  return _resolveBrowserPlayableUrl(mediaRepository, playbackUrl);
}

/// Single source of truth for resolving lesson media playback URLs.
///
/// - Always resolves lesson media via `POST /api/media/lesson-playback`.
/// - Backend handles both pipeline (`media_asset_id`) and legacy (`storage_path`)
///   rows for backward compatibility.
Future<String?> resolveLessonMediaPlaybackUrl({
  required LessonMediaItem item,
  required MediaRepository mediaRepository,
  required MediaPipelineRepository pipelineRepository,
}) async {
  final lessonMediaId = item.id.trim();
  if (lessonMediaId.isEmpty) return null;
  final playbackUrl = await pipelineRepository.fetchLessonPlaybackUrl(
    lessonMediaId,
  );
  return _resolveBrowserPlayableUrl(mediaRepository, playbackUrl);
}
