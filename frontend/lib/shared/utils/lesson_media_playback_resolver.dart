import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';

bool isLessonMediaPdf(LessonMediaItem item) {
  final kind = item.kind.trim().toLowerCase();
  if (kind == 'document' || kind == 'pdf') {
    return true;
  }
  final fileName = item.originalName?.trim().toLowerCase();
  return fileName != null && fileName.endsWith('.pdf');
}

bool canAttemptLessonMediaPlayback(LessonMediaItem item) {
  if (isLessonMediaPdf(item)) {
    return false;
  }
  if (item.id.trim().isEmpty) {
    return false;
  }
  return item.playbackReady;
}

String? _resolveBrowserPlayableUrl(
  MediaRepository mediaRepository,
  String? value,
) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  try {
    final resolved = mediaRepository.resolvePlaybackUrl(raw);
    final uri = Uri.tryParse(resolved);
    final scheme = uri?.scheme.toLowerCase();
    final isHttpUrl =
        uri != null &&
        uri.hasScheme &&
        (scheme == 'http' || scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!isHttpUrl) {
      return null;
    }
    return resolved;
  } catch (_) {
    return null;
  }
}

Future<String?> resolveLessonMediaSignedPlaybackUrl({
  required String lessonMediaId,
  required MediaRepository mediaRepository,
  required MediaPipelineRepository pipelineRepository,
}) async {
  final mediaId = lessonMediaId.trim();
  if (mediaId.isEmpty) {
    return null;
  }
  final playbackUrl = await pipelineRepository.fetchLessonPlaybackUrl(mediaId);
  return _resolveBrowserPlayableUrl(mediaRepository, playbackUrl);
}

Future<String?> resolveLessonMediaDocumentUrl({
  required LessonMediaItem item,
  required MediaRepository mediaRepository,
  required MediaPipelineRepository pipelineRepository,
}) async {
  if (!isLessonMediaPdf(item)) {
    return null;
  }
  if (!item.playbackReady) {
    return null;
  }
  return resolveLessonMediaSignedPlaybackUrl(
    lessonMediaId: item.id,
    mediaRepository: mediaRepository,
    pipelineRepository: pipelineRepository,
  );
}

Future<String?> resolveLessonMediaPlaybackUrl({
  required LessonMediaItem item,
  required MediaRepository mediaRepository,
  required MediaPipelineRepository pipelineRepository,
}) async {
  if (!canAttemptLessonMediaPlayback(item)) {
    return null;
  }
  return resolveLessonMediaSignedPlaybackUrl(
    lessonMediaId: item.id,
    mediaRepository: mediaRepository,
    pipelineRepository: pipelineRepository,
  );
}
