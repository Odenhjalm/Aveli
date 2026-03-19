import 'package:flutter/foundation.dart';

void logMissingLessonMediaIdRender({
  required String surface,
  required String mediaType,
  String? rawSource,
}) {
  _logLessonMediaTelemetry(
    'MISSING_LESSON_MEDIA_ID_RENDER',
    fields: {
      'surface': surface,
      'media_type': mediaType,
      'raw_source_present': _nonEmpty(rawSource),
      if (_nonEmpty(rawSource)) 'raw_source': rawSource!.trim(),
    },
  );
}

void logLessonMediaPreviewCacheEvent({
  required String event,
  required String lessonMediaId,
  String? mediaType,
}) {
  _logLessonMediaTelemetry(
    event,
    fields: {
      'lesson_media_id': lessonMediaId.trim(),
      if (_nonEmpty(mediaType)) 'media_type': mediaType!.trim(),
    },
  );
}

void logLegacyLessonMediaPathUsage({
  required String event,
  required String surface,
  required String url,
}) {
  _logLessonMediaTelemetry(
    event,
    fields: {'surface': surface, 'url': url.trim()},
  );
}

void logLegacyMediaBlocked({
  required String surface,
  required String mediaType,
  String? rawSource,
  String? reason,
  String? lessonMediaId,
}) {
  _logLessonMediaTelemetry(
    'LEGACY_MEDIA_BLOCKED',
    fields: {
      'surface': surface,
      'media_type': mediaType,
      if (_nonEmpty(reason)) 'reason': reason!.trim(),
      if (_nonEmpty(lessonMediaId)) 'lesson_media_id': lessonMediaId!.trim(),
      if (_nonEmpty(rawSource)) 'raw_source': rawSource!.trim(),
    },
  );
}

void logUnresolvedLessonMediaRender({
  required String event,
  required String surface,
  required String mediaType,
  String? lessonMediaId,
  Object? error,
}) {
  _logLessonMediaTelemetry(
    event,
    fields: {
      'surface': surface,
      'media_type': mediaType,
      if (_nonEmpty(lessonMediaId)) 'lesson_media_id': lessonMediaId!.trim(),
      if (error != null) 'error': error.toString(),
    },
  );
}

void logLessonMediaPreviewResolutionFailure({
  required String surface,
  required String lessonMediaId,
  String? mediaType,
  Object? error,
}) {
  _logLessonMediaTelemetry(
    'LESSON_MEDIA_PREVIEW_RESOLUTION_FAILURE',
    fields: {
      'surface': surface,
      'lesson_media_id': lessonMediaId.trim(),
      if (_nonEmpty(mediaType)) 'media_type': mediaType!.trim(),
      if (error != null) 'error': error.toString(),
    },
  );
}

void logLessonMediaPreviewEndpointContractFailure({
  required String surface,
  Iterable<String> lessonMediaIds = const <String>[],
  Object? error,
}) {
  final normalizedIds = lessonMediaIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
  _logLessonMediaTelemetry(
    'LESSON_MEDIA_PREVIEW_ENDPOINT_CONTRACT_FAILURE',
    fields: {
      'surface': surface,
      if (normalizedIds.isNotEmpty) 'lesson_media_ids': normalizedIds.join(','),
      if (error != null) 'error': error.toString(),
    },
  );
}

void logLessonMediaPlaceholderStabilized({
  required String surface,
  required String lessonMediaId,
  String? mediaType,
  String? reason,
}) {
  _logLessonMediaTelemetry(
    'LESSON_MEDIA_PLACEHOLDER_STABILIZED',
    fields: {
      'surface': surface,
      'lesson_media_id': lessonMediaId.trim(),
      if (_nonEmpty(mediaType)) 'media_type': mediaType!.trim(),
      if (_nonEmpty(reason)) 'reason': reason!.trim(),
    },
  );
}

void _logLessonMediaTelemetry(
  String event, {
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  final buffer = StringBuffer(event);
  fields.forEach((key, value) {
    if (value == null) return;
    buffer.write(' $key=$value');
  });
  debugPrint(buffer.toString());
}

bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;
