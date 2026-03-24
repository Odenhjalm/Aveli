import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:aveli/data/models/course.dart' as app_models;
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';

const bool _courseCoverDebugEnabled = bool.fromEnvironment(
  'COURSE_COVER_FRONTEND_DEBUG',
  defaultValue: false,
);

@immutable
class ResolvedCourseCover {
  const ResolvedCourseCover({
    required this.imageUrl,
    required this.backendSource,
    required this.usedPlaceholder,
    required this.hadContractViolation,
  });

  final String? imageUrl;
  final String? backendSource;
  final bool usedPlaceholder;
  final bool hadContractViolation;
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
  required bool usedPlaceholder,
  required bool hadContractViolation,
  String? imageUrl,
  String? coverMediaId,
  String? coverState,
  required bool hasCoverObject,
  required bool hasResolvedUrl,
}) {
  if (!_courseCoverDebugEnabled) return;
  debugPrint(
    '[COURSE_COVER_FRONTEND] '
    'context=$context '
    'cover_media_id=${coverMediaId ?? '<absent>'} '
    'cover_state=${coverState ?? '<absent>'} '
    'has_cover_object=$hasCoverObject '
    'has_resolved_url=$hasResolvedUrl '
    'backend_source=${backendSource ?? '<absent>'} '
    'placeholder=$usedPlaceholder '
    'contract_violation=$hadContractViolation '
    'url=${imageUrl ?? '<none>'}',
  );
}

void _logContractViolation({
  required String context,
  String? coverMediaId,
  String? backendSource,
  String? coverState,
  required bool hasCoverObject,
  required bool hasResolvedUrl,
}) {
  final message =
      '[COURSE_COVER_FRONTEND] '
      'contract_violation=true '
      'context=$context '
      'cover_media_id=${coverMediaId ?? '<absent>'} '
      'cover_state=${coverState ?? '<absent>'} '
      'has_cover_object=$hasCoverObject '
      'has_resolved_url=$hasResolvedUrl '
      'backend_source=${backendSource ?? '<absent>'}';
  developer.log(message, name: 'course_cover_resolver', level: 1000);
  if (_courseCoverDebugEnabled) {
    debugPrint(message);
  }
}

ResolvedCourseCover resolveCourseCover({
  required MediaRepository mediaRepository,
  CourseCoverData? cover,
  String? coverMediaId,
  bool allowEditorOverride = false,
  String debugContext = 'course',
}) {
  final normalizedCover = cover;
  final normalizedMediaId =
      _trimmed(normalizedCover?.mediaId) ?? _trimmed(coverMediaId);
  final backendSource = _trimmed(normalizedCover?.source);
  final coverState = _trimmed(normalizedCover?.state);
  final resolvedUrl = _resolveUrlSafe(
    mediaRepository,
    normalizedCover?.resolvedUrl,
  );
  final hasCoverObject = normalizedCover != null;
  final hasResolvedUrl = _trimmed(normalizedCover?.resolvedUrl) != null;
  final isEditorOverride =
      allowEditorOverride &&
      normalizedMediaId != null &&
      backendSource == 'editor_override' &&
      resolvedUrl != null;
  final isReadyControlPlane =
      normalizedMediaId != null &&
      backendSource == 'control_plane' &&
      coverState == 'ready' &&
      resolvedUrl != null;

  if (isEditorOverride || isReadyControlPlane) {
    final resolved = ResolvedCourseCover(
      imageUrl: resolvedUrl,
      backendSource: backendSource,
      usedPlaceholder: false,
      hadContractViolation: false,
    );
    _debugLog(
      context: debugContext,
      backendSource: resolved.backendSource,
      usedPlaceholder: resolved.usedPlaceholder,
      hadContractViolation: resolved.hadContractViolation,
      imageUrl: resolved.imageUrl,
      coverMediaId: normalizedMediaId,
      coverState: coverState,
      hasCoverObject: hasCoverObject,
      hasResolvedUrl: hasResolvedUrl,
    );
    return resolved;
  }

  final hadContractViolation =
      normalizedMediaId != null &&
      (!allowEditorOverride || backendSource != 'editor_override');
  if (hadContractViolation) {
    _logContractViolation(
      context: debugContext,
      coverMediaId: normalizedMediaId,
      backendSource: backendSource,
      coverState: coverState,
      hasCoverObject: hasCoverObject,
      hasResolvedUrl: hasResolvedUrl,
    );
  }

  final resolved = ResolvedCourseCover(
    imageUrl: null,
    backendSource: backendSource,
    usedPlaceholder: true,
    hadContractViolation: hadContractViolation,
  );
  _debugLog(
    context: debugContext,
    backendSource: resolved.backendSource,
    usedPlaceholder: resolved.usedPlaceholder,
    hadContractViolation: resolved.hadContractViolation,
    imageUrl: resolved.imageUrl,
    coverMediaId: normalizedMediaId,
    coverState: coverState,
    hasCoverObject: hasCoverObject,
    hasResolvedUrl: hasResolvedUrl,
  );
  return resolved;
}

ResolvedCourseCover resolveCourseSummaryCover(
  CourseSummary course,
  MediaRepository mediaRepository,
) {
  return resolveCourseCover(
    mediaRepository: mediaRepository,
    cover: course.cover,
    coverMediaId: course.coverMediaId,
    debugContext: 'CourseSummary:${course.slug ?? course.id}',
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
    debugContext: 'Course:${course.slug ?? course.id}',
  );
}

ResolvedCourseCover resolveCourseMapCover(
  Map<String, dynamic> course,
  MediaRepository mediaRepository, {
  bool allowEditorOverride = false,
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
    coverMediaId: course['cover_media_id'] as String?,
    allowEditorOverride: allowEditorOverride,
    debugContext: debugContext,
  );
}
