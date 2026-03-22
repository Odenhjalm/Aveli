import 'package:flutter/foundation.dart';

import 'package:aveli/data/models/course.dart' as app_models;
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';

const bool _courseCoverResolvedUiEnabledDefault = bool.fromEnvironment(
  'COURSE_COVER_RESOLVED_UI_ENABLED',
  defaultValue: false,
);
const bool _courseCoverDebugEnabled = bool.fromEnvironment(
  'COURSE_COVER_FRONTEND_DEBUG',
  defaultValue: false,
);

@immutable
class ResolvedCourseCover {
  const ResolvedCourseCover({
    required this.imageUrl,
    required this.backendSource,
    required this.usedLegacyCompatibility,
    required this.usedPlaceholder,
  });

  final String? imageUrl;
  final String? backendSource;
  final bool usedLegacyCompatibility;
  final bool usedPlaceholder;
}

String? _trimmed(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _resolveUrlSafe(MediaRepository mediaRepository, String? rawUrl) {
  final normalized = _trimmed(rawUrl);
  if (normalized == null) return null;
  try {
    return mediaRepository.resolveDownloadUrl(normalized);
  } catch (_) {
    return null;
  }
}

void _debugLog({
  required String context,
  String? backendSource,
  required bool usedLegacyCompatibility,
  required bool usedPlaceholder,
  String? imageUrl,
}) {
  if (!_courseCoverDebugEnabled) return;
  debugPrint(
    '[COURSE_COVER_FRONTEND] '
    'context=$context '
    'backend_source=${backendSource ?? '<absent>'} '
    'legacy_fallback=$usedLegacyCompatibility '
    'placeholder=$usedPlaceholder '
    'url=${imageUrl ?? '<none>'}',
  );
}

ResolvedCourseCover resolveCourseCover({
  required MediaRepository mediaRepository,
  CourseCoverData? cover,
  String? legacyCoverUrl,
  bool preferResolvedContract = _courseCoverResolvedUiEnabledDefault,
  String debugContext = 'course',
}) {
  final normalizedLegacyUrl = _resolveUrlSafe(mediaRepository, legacyCoverUrl);
  final normalizedCover = cover;

  if (preferResolvedContract && normalizedCover != null) {
    final source = _trimmed(normalizedCover.source);
    final resolvedUrl = _resolveUrlSafe(
      mediaRepository,
      normalizedCover.resolvedUrl,
    );
    final usesBackendResolvedUrl =
        (source == 'control_plane' ||
            source == 'legacy_cover_url' ||
            source == 'legacy_fallback') &&
        resolvedUrl != null;
    if (usesBackendResolvedUrl) {
      final resolved = ResolvedCourseCover(
        imageUrl: resolvedUrl,
        backendSource: source,
        usedLegacyCompatibility: false,
        usedPlaceholder: false,
      );
      _debugLog(
        context: debugContext,
        backendSource: resolved.backendSource,
        usedLegacyCompatibility: resolved.usedLegacyCompatibility,
        usedPlaceholder: resolved.usedPlaceholder,
        imageUrl: resolved.imageUrl,
      );
      return resolved;
    }
    final resolved = ResolvedCourseCover(
      imageUrl: null,
      backendSource: source,
      usedLegacyCompatibility: false,
      usedPlaceholder: true,
    );
    _debugLog(
      context: debugContext,
      backendSource: resolved.backendSource,
      usedLegacyCompatibility: resolved.usedLegacyCompatibility,
      usedPlaceholder: resolved.usedPlaceholder,
      imageUrl: resolved.imageUrl,
    );
    return resolved;
  }

  if (normalizedLegacyUrl != null) {
    final resolved = ResolvedCourseCover(
      imageUrl: normalizedLegacyUrl,
      backendSource: normalizedCover?.source,
      usedLegacyCompatibility: true,
      usedPlaceholder: false,
    );
    _debugLog(
      context: debugContext,
      backendSource: resolved.backendSource,
      usedLegacyCompatibility: resolved.usedLegacyCompatibility,
      usedPlaceholder: resolved.usedPlaceholder,
      imageUrl: resolved.imageUrl,
    );
    return resolved;
  }

  final resolved = ResolvedCourseCover(
    imageUrl: null,
    backendSource: normalizedCover?.source,
    usedLegacyCompatibility: false,
    usedPlaceholder: true,
  );
  _debugLog(
    context: debugContext,
    backendSource: resolved.backendSource,
    usedLegacyCompatibility: resolved.usedLegacyCompatibility,
    usedPlaceholder: resolved.usedPlaceholder,
    imageUrl: resolved.imageUrl,
  );
  return resolved;
}

ResolvedCourseCover resolveCourseSummaryCover(
  CourseSummary course,
  MediaRepository mediaRepository, {
  bool preferResolvedContract = _courseCoverResolvedUiEnabledDefault,
}) {
  return resolveCourseCover(
    mediaRepository: mediaRepository,
    cover: course.cover,
    legacyCoverUrl: course.coverUrl,
    preferResolvedContract: preferResolvedContract,
    debugContext: 'CourseSummary:${course.slug ?? course.id}',
  );
}

ResolvedCourseCover resolveCourseModelCover(
  app_models.Course course,
  MediaRepository mediaRepository, {
  bool preferResolvedContract = _courseCoverResolvedUiEnabledDefault,
}) {
  return resolveCourseCover(
    mediaRepository: mediaRepository,
    cover: course.cover,
    legacyCoverUrl: course.coverUrl,
    preferResolvedContract: preferResolvedContract,
    debugContext: 'Course:${course.slug ?? course.id}',
  );
}

ResolvedCourseCover resolveCourseMapCover(
  Map<String, dynamic> course,
  MediaRepository mediaRepository, {
  bool preferResolvedContract = _courseCoverResolvedUiEnabledDefault,
  String debugContext = 'CourseMap',
}) {
  final coverJson = course['cover'];
  return resolveCourseCover(
    mediaRepository: mediaRepository,
    cover: coverJson is Map<String, dynamic>
        ? CourseCoverData.fromJson(coverJson)
        : coverJson is Map
        ? CourseCoverData.fromJson(Map<String, dynamic>.from(coverJson))
        : null,
    legacyCoverUrl: course['cover_url'] as String?,
    preferResolvedContract: preferResolvedContract,
    debugContext: debugContext,
  );
}
