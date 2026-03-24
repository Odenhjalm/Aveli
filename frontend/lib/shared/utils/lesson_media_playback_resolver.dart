import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';

bool isLessonMediaPdf(LessonMediaItem item) {
  final kind = item.kind.trim().toLowerCase();
  if (kind == 'pdf' || kind == 'document') return true;
  final contentType = item.contentType?.trim().toLowerCase();
  if (contentType == 'application/pdf') return true;
  return item.fileName.toLowerCase().endsWith('.pdf');
}

bool canAttemptLessonMediaPlayback(LessonMediaItem item) {
  if (isLessonMediaPdf(item)) return false;
  if (item.id.trim().isEmpty) return false;
  return item.resolvableForStudent != false;
}

bool _isAuthProtectedPlaybackPath(String path) {
  final normalized = path.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.startsWith('/studio/media/') ||
      normalized.startsWith('/api/media/') ||
      normalized.startsWith('/media/sign') ||
      normalized.startsWith('/media/stream/');
}

bool _isBrowserSafeDocumentPath(String path) {
  final normalized = path.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (normalized.startsWith('/studio/media/')) return false;
  if (normalized.startsWith('/api/media/')) return false;
  if (normalized.startsWith('/media/sign')) return false;
  return normalized.startsWith('/media/stream/') ||
      normalized.startsWith('/api/files/');
}

String? _resolveBrowserPlayableUrl(
  MediaRepository mediaRepository,
  String? value,
) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  try {
    final rawUri = Uri.tryParse(raw);
    final rawScheme = rawUri?.scheme.toLowerCase();
    final hasUnsupportedScheme =
        rawUri != null &&
        rawUri.hasScheme &&
        rawScheme != 'http' &&
        rawScheme != 'https';
    if (hasUnsupportedScheme) {
      return null;
    }

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
    final path = uri.path ?? resolved;
    if (_isAuthProtectedPlaybackPath(path)) {
      return null;
    }
    return resolved;
  } catch (_) {
    return null;
  }
}

String? _resolveBrowserDocumentUrl(
  MediaRepository mediaRepository,
  String? value,
) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  try {
    final rawUri = Uri.tryParse(raw);
    final rawScheme = rawUri?.scheme.toLowerCase();
    final hasUnsupportedScheme =
        rawUri != null &&
        rawUri.hasScheme &&
        rawScheme != 'http' &&
        rawScheme != 'https';
    if (hasUnsupportedScheme) {
      return null;
    }

    if (rawUri != null &&
        rawUri.hasScheme &&
        (rawScheme == 'http' || rawScheme == 'https') &&
        rawUri.host.isNotEmpty) {
      return mediaRepository.resolveDownloadUrl(raw);
    }

    final path = rawUri?.path ?? raw;
    if (!_isBrowserSafeDocumentPath(path)) {
      return null;
    }
    return mediaRepository.resolveDownloadUrl(raw);
  } catch (_) {
    return null;
  }
}

String? resolveLessonMediaDocumentUrl({
  required LessonMediaItem item,
  required MediaRepository mediaRepository,
}) {
  if (!isLessonMediaPdf(item)) return null;
  for (final candidate in <String?>[
    item.signedUrl,
    item.downloadUrl,
    item.playbackUrl,
    item.preferredUrlValue,
  ]) {
    final resolved = _resolveBrowserDocumentUrl(mediaRepository, candidate);
    if (resolved != null) return resolved;
  }
  return null;
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
/// - Legacy lesson-media fallback is blocked; unresolved media stays blocked
///   until the backend can resolve it canonically.
Future<String?> resolveLessonMediaPlaybackUrl({
  required LessonMediaItem item,
  required MediaRepository mediaRepository,
  required MediaPipelineRepository pipelineRepository,
}) async {
  if (!canAttemptLessonMediaPlayback(item)) return null;
  final lessonMediaId = item.id.trim();
  final playbackUrl = await pipelineRepository.fetchLessonPlaybackUrl(
    lessonMediaId,
  );
  return _resolveBrowserPlayableUrl(mediaRepository, playbackUrl);
}
