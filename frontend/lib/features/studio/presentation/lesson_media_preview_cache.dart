import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/shared/utils/lesson_media_render_telemetry.dart';

class LessonMediaPreviewData {
  const LessonMediaPreviewData({
    required this.lessonMediaId,
    required this.mediaType,
    this.resolvedPreviewUrl,
    this.durationSeconds,
    this.fileName,
  });

  final String lessonMediaId;
  final String mediaType;
  final String? resolvedPreviewUrl;
  final int? durationSeconds;
  final String? fileName;

  factory LessonMediaPreviewData.unresolved({
    required String lessonMediaId,
    String mediaType = '',
    int? durationSeconds,
    String? fileName,
  }) {
    return LessonMediaPreviewData(
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      durationSeconds: durationSeconds,
      fileName: fileName,
    );
  }

  String? get visualUrl {
    final preview = resolvedPreviewUrl?.trim();
    if (preview != null && preview.isNotEmpty) return preview;
    return null;
  }

  bool get requiresVisualResolution {
    switch (mediaType) {
      case 'image':
      case 'video':
        return visualUrl == null;
      default:
        return false;
    }
  }

  factory LessonMediaPreviewData.fromJson(
    String lessonMediaId,
    Map<String, dynamic> json,
  ) {
    final mediaType = (json['media_type'] ?? json['kind'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final duration = json['duration_seconds'];
    return LessonMediaPreviewData(
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      resolvedPreviewUrl: _normalizedString(
        json['resolved_preview_url'] ?? json['resolvedPreviewUrl'],
      ),
      durationSeconds: duration is num ? duration.toInt() : null,
      fileName: _normalizedString(json['file_name'] ?? json['fileName']),
    );
  }

  static LessonMediaPreviewData? maybeFromLessonMedia(
    Map<String, dynamic> media,
  ) {
    final lessonMediaId = _normalizedString(media['id']);
    final mediaType = _normalizedString(media['kind'])?.toLowerCase();
    if (lessonMediaId == null || mediaType == null) return null;

    final duration = media['duration_seconds'];
    final fileName =
        _normalizedString(media['file_name'] ?? media['fileName']) ??
        _normalizedString(media['original_name']);

    return LessonMediaPreviewData(
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      durationSeconds: duration is num ? duration.toInt() : null,
      fileName: fileName,
    );
  }

  LessonMediaPreviewData asNonAuthoritativeCacheEntry() {
    return LessonMediaPreviewData(
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      durationSeconds: durationSeconds,
      fileName: fileName,
    );
  }
}

final lessonMediaPreviewCacheProvider = Provider<LessonMediaPreviewCache>((
  ref,
) {
  final studioRepository = ref.watch(studioRepositoryProvider);
  return LessonMediaPreviewCache(studioRepository: studioRepository);
});

class LessonMediaPreviewHydrationBatch {
  const LessonMediaPreviewHydrationBatch({
    required this.hydratingIds,
    required this.settled,
  });

  final Set<String> hydratingIds;
  final Future<void> settled;
}

class LessonMediaPreviewCache {
  LessonMediaPreviewCache({required this.studioRepository});

  final StudioRepository studioRepository;

  final Map<String, LessonMediaPreviewData> _cache =
      <String, LessonMediaPreviewData>{};
  final Set<String> _stabilizedPlaceholderIds = <String>{};
  final Map<String, Completer<LessonMediaPreviewData?>> _pending =
      <String, Completer<LessonMediaPreviewData?>>{};
  final Map<String, List<Completer<void>>> _batchWaiters =
      <String, List<Completer<void>>>{};
  final Set<String> _queuedIds = <String>{};
  final Set<String> _inFlightIds = <String>{};

  bool _flushScheduled = false;

  Future<LessonMediaPreviewData?> getPreview(String lessonMediaId) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty) {
      return Future<LessonMediaPreviewData?>.value(null);
    }

    if (_stabilizedPlaceholderIds.contains(normalized)) {
      final cached = _cache[normalized];
      if (cached != null) {
        return Future<LessonMediaPreviewData?>.value(cached);
      }
      return Future<LessonMediaPreviewData?>.value(
        LessonMediaPreviewData.unresolved(lessonMediaId: normalized),
      );
    }

    if (_cache.containsKey(normalized)) {
      logLessonMediaPreviewCacheEvent(
        event: 'LESSON_MEDIA_PREVIEW_CACHE_METADATA_USED',
        lessonMediaId: normalized,
        mediaType: _cache[normalized]?.mediaType,
      );
    }

    final existing = _pending[normalized];
    if (existing != null) {
      return existing.future;
    }

    if (_inFlightIds.contains(normalized)) {
      final completer = Completer<LessonMediaPreviewData?>();
      _pending[normalized] = completer;
      return completer.future;
    }

    final completer = Completer<LessonMediaPreviewData?>();
    _pending[normalized] = completer;
    _queuedIds.add(normalized);
    logLessonMediaPreviewCacheEvent(
      event: 'LESSON_MEDIA_PREVIEW_BACKEND_RESOLUTION',
      lessonMediaId: normalized,
    );
    _scheduleFlush();
    return completer.future;
  }

  LessonMediaPreviewHydrationBatch beginHydrationBatch(
    Iterable<String> lessonMediaIds,
  ) {
    final hydratingIds = <String>{};
    final futures = <Future<void>>[];
    var needsFlush = false;

    for (final lessonMediaId in lessonMediaIds) {
      final normalized = lessonMediaId.trim();
      if (normalized.isEmpty) continue;
      if (_stabilizedPlaceholderIds.contains(normalized)) {
        continue;
      }

      hydratingIds.add(normalized);
      futures.add(_registerBatchWaiter(normalized));
      if (!_inFlightIds.contains(normalized) &&
          !_queuedIds.contains(normalized)) {
        _queuedIds.add(normalized);
        _pending.putIfAbsent(
          normalized,
          () => Completer<LessonMediaPreviewData?>(),
        );
        needsFlush = true;
      }
    }

    if (needsFlush) {
      _scheduleFlush();
    }

    return LessonMediaPreviewHydrationBatch(
      hydratingIds: Set<String>.unmodifiable(hydratingIds),
      settled: futures.isEmpty ? Future<void>.value() : Future.wait(futures),
    );
  }

  Future<void> prefetch(Iterable<String> lessonMediaIds) async {
    final futures = <Future<LessonMediaPreviewData?>>[];
    for (final lessonMediaId in lessonMediaIds) {
      final normalized = lessonMediaId.trim();
      if (normalized.isEmpty) continue;
      futures.add(getPreview(normalized));
    }
    if (futures.isEmpty) return;
    await Future.wait(futures);
  }

  void prime(Iterable<LessonMediaPreviewData> previews) {
    for (final preview in previews) {
      final lessonMediaId = preview.lessonMediaId.trim();
      if (lessonMediaId.isEmpty) continue;
      _stabilizedPlaceholderIds.remove(lessonMediaId);
      _cache[lessonMediaId] = preview.asNonAuthoritativeCacheEntry();
      final completer = _pending.remove(lessonMediaId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(preview);
      }
    }
  }

  void primeFromLessonMedia(Iterable<Map<String, dynamic>> mediaItems) {
    final previews = <LessonMediaPreviewData>[];
    final blockedPreviews = <LessonMediaPreviewData>[];
    for (final media in mediaItems) {
      final preview = LessonMediaPreviewData.maybeFromLessonMedia(media);
      if (preview == null) continue;
      previews.add(preview);
      if (media['resolvable_for_editor'] == false &&
          (preview.mediaType == 'image' || preview.mediaType == 'video')) {
        blockedPreviews.add(preview);
      }
    }
    prime(previews);
    for (final preview in blockedPreviews) {
      _stabilizeFailedPreview(
        lessonMediaId: preview.lessonMediaId,
        preview: preview,
        reason: 'row_marked_unresolvable',
      );
    }
  }

  void _scheduleFlush() {
    if (_flushScheduled || _queuedIds.isEmpty) return;
    _flushScheduled = true;
    scheduleMicrotask(_flushQueued);
  }

  Future<void> _registerBatchWaiter(String lessonMediaId) {
    final completer = Completer<void>();
    final waiters = _batchWaiters.putIfAbsent(
      lessonMediaId,
      () => <Completer<void>>[],
    );
    waiters.add(completer);
    return completer.future;
  }

  void _completeBatchWaiters(String lessonMediaId) {
    final waiters = _batchWaiters.remove(lessonMediaId);
    if (waiters == null) return;
    for (final completer in waiters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  void _recordBatchFailureTelemetry({
    required List<String> ids,
    required Object error,
  }) {
    if (_looksLikePreviewEndpointContractFailure(error)) {
      logLessonMediaPreviewEndpointContractFailure(
        surface: 'studio_editor_preview',
        lessonMediaIds: ids,
        error: error,
      );
      return;
    }
    for (final lessonMediaId in ids) {
      logLessonMediaPreviewResolutionFailure(
        surface: 'studio_editor_preview',
        lessonMediaId: lessonMediaId,
        mediaType: _cache[lessonMediaId]?.mediaType,
        error: error,
      );
    }
  }

  void _stabilizeFailedPreview({
    required String lessonMediaId,
    LessonMediaPreviewData? preview,
    LessonMediaPreviewData? fallback,
    Object? error,
    required String reason,
  }) {
    final source =
        preview ??
        fallback ??
        LessonMediaPreviewData.unresolved(lessonMediaId: lessonMediaId);
    final unresolved = LessonMediaPreviewData.unresolved(
      lessonMediaId: lessonMediaId,
      mediaType: source.mediaType,
      durationSeconds: source.durationSeconds,
      fileName: source.fileName,
    );
    _cache[lessonMediaId] = unresolved.asNonAuthoritativeCacheEntry();
    _stabilizedPlaceholderIds.add(lessonMediaId);
    logLessonMediaPreviewResolutionFailure(
      surface: 'studio_editor_preview',
      lessonMediaId: lessonMediaId,
      mediaType: source.mediaType,
      error: error,
    );
    logLessonMediaPlaceholderStabilized(
      surface: 'studio_editor_preview',
      lessonMediaId: lessonMediaId,
      mediaType: source.mediaType,
      reason: reason,
    );
  }

  Future<void> _flushQueued() async {
    _flushScheduled = false;
    final ids = _queuedIds.toList(growable: false);
    _queuedIds.clear();
    if (ids.isEmpty) return;
    _inFlightIds.addAll(ids);

    Map<String, LessonMediaPreviewData> previews =
        <String, LessonMediaPreviewData>{};
    Object? batchError;
    try {
      final payload = await studioRepository.fetchLessonMediaPreviews(ids);
      previews = payload.map(
        (lessonMediaId, value) => MapEntry(
          lessonMediaId,
          LessonMediaPreviewData.fromJson(lessonMediaId, value),
        ),
      );
    } catch (error) {
      batchError = error;
      _recordBatchFailureTelemetry(ids: ids, error: error);
      previews = <String, LessonMediaPreviewData>{};
    }

    for (final lessonMediaId in ids) {
      final preview = previews[lessonMediaId];
      final needsPlaceholderStabilization =
          preview == null || preview.requiresVisualResolution;
      LessonMediaPreviewData? result = preview;
      if (preview != null && !preview.requiresVisualResolution) {
        _stabilizedPlaceholderIds.remove(lessonMediaId);
        _cache[lessonMediaId] = preview.asNonAuthoritativeCacheEntry();
      } else if (needsPlaceholderStabilization) {
        _stabilizeFailedPreview(
          lessonMediaId: lessonMediaId,
          preview: preview,
          fallback: _cache[lessonMediaId],
          error: batchError,
          reason: batchError == null
              ? 'backend_returned_unresolved_preview'
              : 'preview_resolution_request_failed',
        );
        result = _cache[lessonMediaId];
      } else {
        _stabilizedPlaceholderIds.remove(lessonMediaId);
        _cache.remove(lessonMediaId);
      }

      final completer = _pending.remove(lessonMediaId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(result);
      }
      _completeBatchWaiters(lessonMediaId);
    }

    _inFlightIds.removeAll(ids);

    if (_queuedIds.isNotEmpty) {
      _scheduleFlush();
    }
  }
}

bool _looksLikePreviewEndpointContractFailure(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;
    final detail = responseData == null ? '' : responseData.toString();
    if (statusCode == 405) {
      return true;
    }
    return detail.toLowerCase().contains('method not allowed');
  }
  return error.toString().toLowerCase().contains('method not allowed');
}

String? _normalizedString(Object? value) {
  if (value == null) return null;
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}
