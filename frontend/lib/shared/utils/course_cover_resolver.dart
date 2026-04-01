import 'package:flutter/foundation.dart';

import 'package:aveli/data/models/course.dart' as app_models;
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';

@immutable
class ResolvedCourseCover {
  const ResolvedCourseCover({required this.imageUrl});

  final String? imageUrl;
}

ResolvedCourseCover resolveCourseCover({
  required MediaRepository mediaRepository,
  CourseCoverData? cover,
  String? coverMediaId,
}) {
  if (cover == null) {
    return const ResolvedCourseCover(imageUrl: null);
  }

  if (coverMediaId == null || cover.mediaId == null) {
    return const ResolvedCourseCover(imageUrl: null);
  }

  if (cover.mediaId != coverMediaId) {
    return const ResolvedCourseCover(imageUrl: null);
  }

  if (cover.state != 'ready' || cover.source != 'control_plane') {
    return const ResolvedCourseCover(imageUrl: null);
  }

  final resolvedUrl = cover.resolvedUrl;
  if (resolvedUrl == null) {
    return const ResolvedCourseCover(imageUrl: null);
  }

  return ResolvedCourseCover(
    imageUrl: mediaRepository.resolveDownloadUrl(resolvedUrl),
  );
}

ResolvedCourseCover resolveCourseSummaryCover(
  CourseSummary course,
  MediaRepository mediaRepository,
) {
  return resolveCourseCover(
    mediaRepository: mediaRepository,
    cover: course.cover,
    coverMediaId: course.coverMediaId,
  );
}

ResolvedCourseCover resolveCourseModelCover(
  app_models.Course course,
  MediaRepository mediaRepository,
) {
  return resolveCourseCover(
    mediaRepository: mediaRepository,
    cover: course.cover,
    coverMediaId: course.coverMediaId,
  );
}

CourseCoverData? _courseCoverFromPayload(Object? payload) {
  switch (payload) {
    case {'state': final String state, 'source': final String source}:
      return CourseCoverData(
        mediaId: payload['media_id'] as String?,
        state: state,
        resolvedUrl: payload['resolved_url'] as String?,
        source: source,
      );
    default:
      return null;
  }
}

ResolvedCourseCover resolveCourseMapCover(
  Object? course,
  MediaRepository mediaRepository,
) {
  final coverJson = switch (course) {
    final Map<Object?, Object?> data => data['cover'],
    _ => null,
  };
  final coverMediaId = switch (course) {
    final Map<Object?, Object?> data => data['cover_media_id'] as String?,
    _ => null,
  };
  return resolveCourseCover(
    mediaRepository: mediaRepository,
    cover: _courseCoverFromPayload(coverJson),
    coverMediaId: coverMediaId,
  );
}
