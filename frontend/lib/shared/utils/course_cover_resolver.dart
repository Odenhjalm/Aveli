import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/features/media/data/media_resolution_mode.dart';
import 'package:aveli/features/studio/data/studio_models.dart';

Future<String?> resolveCourseCoverUrl({
  required MediaRepository mediaRepository,
  String? coverMediaId,
  MediaResolutionMode mode = MediaResolutionMode.studentRender,
}) {
  final mediaId = coverMediaId?.trim();
  if (mediaId == null || mediaId.isEmpty) {
    return Future<String?>.value(null);
  }

  return mediaRepository.signMedia(mediaId, mode: mode).then((signed) {
    final signedUrl = signed.signedUrl.trim();
    if (signedUrl.isEmpty) {
      return null;
    }
    return mediaRepository.resolveDownloadUrl(signedUrl);
  });
}

Future<String?> resolveCourseSummaryCoverUrl(
  CourseSummary course,
  MediaRepository mediaRepository,
) {
  return resolveCourseCoverUrl(
    mediaRepository: mediaRepository,
    coverMediaId: course.coverMediaId,
  );
}

Future<String?> resolveStudioCourseCoverUrl(
  CourseStudio course,
  MediaRepository mediaRepository,
) {
  return resolveCourseCoverUrl(
    mediaRepository: mediaRepository,
    coverMediaId: course.coverMediaId,
    mode: MediaResolutionMode.editorPreview,
  );
}
