import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/features/media/data/media_resolution_mode.dart';

const Duration _signedUrlLeeway = Duration(seconds: 30);

bool _hasValidSignedWindow(DateTime? expiresAt) {
  if (expiresAt == null) return true;
  final now = DateTime.now().toUtc();
  return now.isBefore(expiresAt.subtract(_signedUrlLeeway));
}

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
  MediaResolutionMode mode = MediaResolutionMode.studentRender,
}) async {
  final mediaId = lessonMediaId.trim();
  if (mediaId.isEmpty) return null;
  final signed = await mediaRepository.signMedia(mediaId, mode: mode);
  return _resolveBrowserPlayableUrl(mediaRepository, signed.signedUrl);
}

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
      return _resolveBrowserPlayableUrl(
        mediaRepository,
        playback.playbackUrl.toString(),
      );
    }
  }

  final playbackUrl = item.playbackUrl?.trim();
  if (playbackUrl != null && playbackUrl.isNotEmpty) {
    final signedUrl = item.signedUrl?.trim();
    final sameAsSigned =
        signedUrl != null && signedUrl.isNotEmpty && playbackUrl == signedUrl;
    if (sameAsSigned) {
      if (_hasValidSignedWindow(item.signedUrlExpiresAt)) {
        final playable = _resolveBrowserPlayableUrl(
          mediaRepository,
          playbackUrl,
        );
        if (playable != null) return playable;
      }
    } else {
      final playable = _resolveBrowserPlayableUrl(mediaRepository, playbackUrl);
      if (playable != null) return playable;
    }
  }

  final download = item.downloadUrl?.trim();
  if (download != null &&
      download.isNotEmpty &&
      download.toLowerCase().startsWith('/api/files/')) {
    final playable = _resolveBrowserPlayableUrl(mediaRepository, download);
    if (playable != null) return playable;
  }

  final signedUrl = item.signedUrl?.trim();
  final hasValidSigned =
      signedUrl != null &&
      signedUrl.isNotEmpty &&
      _hasValidSignedWindow(item.signedUrlExpiresAt);

  if (hasValidSigned) {
    final playable = _resolveBrowserPlayableUrl(mediaRepository, signedUrl);
    if (playable != null) return playable;
  }

  try {
    final signed = await resolveLessonMediaSignedPlaybackUrl(
      lessonMediaId: item.id,
      mediaRepository: mediaRepository,
      mode: mode,
    );
    if (signed != null && signed.isNotEmpty) return signed;
  } catch (_) {
    // Fall back to any download URLs below.
  }

  if (download != null && download.isNotEmpty) {
    final playable = _resolveBrowserPlayableUrl(mediaRepository, download);
    if (playable != null) return playable;
  }

  if (signedUrl != null && signedUrl.isNotEmpty) {
    final playable = _resolveBrowserPlayableUrl(mediaRepository, signedUrl);
    if (playable != null) return playable;
  }

  return null;
}
