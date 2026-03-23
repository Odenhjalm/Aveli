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
    this.authoritativeEditorReady,
    this.durationSeconds,
    this.fileName,
    this.failureReason,
  });

  final String lessonMediaId;
  final String mediaType;
  final String? resolvedPreviewUrl;
  final bool? authoritativeEditorReady;
  final int? durationSeconds;
  final String? fileName;
  final String? failureReason;

  factory LessonMediaPreviewData.unresolved({
    required String lessonMediaId,
    String mediaType = '',
    int? durationSeconds,
    String? fileName,
    String? failureReason,
  }) {
    return LessonMediaPreviewData(
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      authoritativeEditorReady: false,
      durationSeconds: durationSeconds,
      fileName: fileName,
      failureReason: failureReason,
    );
  }

  String? get visualUrl {
    final preview = resolvedPreviewUrl?.trim();
    return preview != null && preview.isNotEmpty ? preview : null;
  }

  LessonMediaPreviewData mergeMetadata(LessonMediaPreviewData metadata) {
    return LessonMediaPreviewData(
      lessonMediaId: lessonMediaId,
      mediaType: mediaType.isEmpty ? metadata.mediaType : mediaType,
      resolvedPreviewUrl: resolvedPreviewUrl,
      authoritativeEditorReady: authoritativeEditorReady,
      durationSeconds: durationSeconds ?? metadata.durationSeconds,
      fileName: fileName ?? metadata.fileName,
      failureReason: failureReason ?? metadata.failureReason,
    );
  }

  LessonMediaPreviewData withoutAuthority() {
    return LessonMediaPreviewData(
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      durationSeconds: durationSeconds,
      fileName: fileName,
    );
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
      authoritativeEditorReady: json['authoritative_editor_ready'] as bool?,
      durationSeconds: duration is num ? duration.toInt() : null,
      fileName: _normalizedString(json['file_name'] ?? json['fileName']),
      failureReason: _normalizedString(
        json['failure_reason'] ?? json['failureReason'],
      ),
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
      resolvedPreviewUrl: resolvedPreviewUrl,
      authoritativeEditorReady: authoritativeEditorReady,
      durationSeconds: durationSeconds,
      fileName: fileName,
      failureReason: failureReason,
    );
  }
}

enum LessonMediaPreviewState { loading, ready, failed }

enum LessonMediaPreviewFailureKind { unresolved, missingId, legacyBlocked }

class LessonMediaPreviewStatus {
  const LessonMediaPreviewStatus({
    required this.state,
    required this.lessonMediaId,
    required this.mediaType,
    this.visualUrl,
    this.fileName,
    this.durationSeconds,
    this.failureReason,
    this.failureKind,
    this.retryAttempt = 0,
    this.isRetrying = false,
    required this.stateVersion,
    this.failedTransitionVersion,
  });

  final LessonMediaPreviewState state;
  final String? lessonMediaId;
  final String mediaType;
  final String? visualUrl;
  final String? fileName;
  final int? durationSeconds;
  final String? failureReason;
  final LessonMediaPreviewFailureKind? failureKind;
  final int retryAttempt;
  final bool isRetrying;
  final int stateVersion;
  final int? failedTransitionVersion;

  bool get isRenderable => state == LessonMediaPreviewState.ready;

  LessonMediaPreviewStatus copyWith({
    LessonMediaPreviewState? state,
    String? lessonMediaId,
    String? mediaType,
    String? visualUrl,
    bool clearVisualUrl = false,
    String? fileName,
    bool clearFileName = false,
    int? durationSeconds,
    bool clearDurationSeconds = false,
    String? failureReason,
    bool clearFailureReason = false,
    LessonMediaPreviewFailureKind? failureKind,
    bool clearFailureKind = false,
    int? retryAttempt,
    bool? isRetrying,
    int? stateVersion,
    int? failedTransitionVersion,
    bool clearFailedTransitionVersion = false,
  }) {
    return LessonMediaPreviewStatus(
      state: state ?? this.state,
      lessonMediaId: lessonMediaId ?? this.lessonMediaId,
      mediaType: mediaType ?? this.mediaType,
      visualUrl: clearVisualUrl ? null : (visualUrl ?? this.visualUrl),
      fileName: clearFileName ? null : (fileName ?? this.fileName),
      durationSeconds: clearDurationSeconds
          ? null
          : (durationSeconds ?? this.durationSeconds),
      failureReason: clearFailureReason
          ? null
          : (failureReason ?? this.failureReason),
      failureKind: clearFailureKind ? null : (failureKind ?? this.failureKind),
      retryAttempt: retryAttempt ?? this.retryAttempt,
      isRetrying: isRetrying ?? this.isRetrying,
      stateVersion: stateVersion ?? this.stateVersion,
      failedTransitionVersion: clearFailedTransitionVersion
          ? null
          : (failedTransitionVersion ?? this.failedTransitionVersion),
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
  LessonMediaPreviewCache({
    required this.studioRepository,
    Duration transientResolverRetryDelay = const Duration(milliseconds: 400),
    int transientResolverMaxRetries = 12,
  }) : assert(!transientResolverRetryDelay.isNegative),
       assert(transientResolverMaxRetries >= 0),
       _transientResolverRetryDelay = transientResolverRetryDelay,
       _transientResolverMaxRetries = transientResolverMaxRetries;

  final StudioRepository studioRepository;
  final Duration _transientResolverRetryDelay;
  final int _transientResolverMaxRetries;

  final Map<String, LessonMediaPreviewData> _cache =
      <String, LessonMediaPreviewData>{};
  final Map<String, Completer<LessonMediaPreviewData?>> _pending =
      <String, Completer<LessonMediaPreviewData?>>{};
  final Map<String, List<Completer<void>>> _batchWaiters =
      <String, List<Completer<void>>>{};
  final Map<String, LessonMediaPreviewStatus> _trackedStatuses =
      <String, LessonMediaPreviewStatus>{};
  final Map<String, int> _consumedFailedTransitionVersions = <String, int>{};
  final Map<String, int> _transientResolverRetryCounts = <String, int>{};
  final Map<String, Timer> _transientResolverRetryTimers = <String, Timer>{};
  final Set<String> _queuedIds = <String>{};
  final Set<String> _inFlightIds = <String>{};

  bool _flushScheduled = false;

  LessonMediaPreviewData? peek(String lessonMediaId) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty) return null;
    return _cache[normalized];
  }

  LessonMediaPreviewStatus? peekStatus(String lessonMediaId) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty) return null;
    return _trackedStatusFor(
      lessonMediaId: normalized,
      preview: _cache[normalized],
    );
  }

  LessonMediaPreviewStatus statusForPreview(
    String lessonMediaId,
    LessonMediaPreviewData? preview,
  ) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty) {
      return invalidStatus(
        mediaType: preview?.mediaType ?? '',
        failureKind: LessonMediaPreviewFailureKind.missingId,
      );
    }
    return _trackedStatusFor(lessonMediaId: normalized, preview: preview);
  }

  LessonMediaPreviewStatus invalidStatus({
    required String mediaType,
    required LessonMediaPreviewFailureKind failureKind,
  }) {
    return LessonMediaPreviewStatus(
      state: LessonMediaPreviewState.failed,
      lessonMediaId: null,
      mediaType: mediaType.trim().toLowerCase(),
      failureKind: failureKind,
      stateVersion: 0,
    );
  }

  bool consumeFailedTransitionLog(
    String lessonMediaId,
    int failedTransitionVersion,
  ) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty || failedTransitionVersion <= 0) {
      return false;
    }
    final consumed = _consumedFailedTransitionVersions[normalized] ?? 0;
    if (consumed >= failedTransitionVersion) {
      return false;
    }
    _consumedFailedTransitionVersions[normalized] = failedTransitionVersion;
    return true;
  }

  bool isSettled(String lessonMediaId) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty) return false;
    return _rawStatusFor(lessonMediaId: normalized).state ==
        LessonMediaPreviewState.ready;
  }

  Future<LessonMediaPreviewData?> getSettledOrFetch(String lessonMediaId) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty) {
      return Future<LessonMediaPreviewData?>.value(null);
    }
    if (isSettled(normalized)) {
      return Future<LessonMediaPreviewData?>.value(
        _cache[normalized] ??
            LessonMediaPreviewData.unresolved(lessonMediaId: normalized),
      );
    }
    return getPreview(normalized);
  }

  Future<LessonMediaPreviewData?> getPreview(String lessonMediaId) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty) {
      return Future<LessonMediaPreviewData?>.value(null);
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
    _clearTransientResolverRetry(normalized);
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
      if (isSettled(normalized)) {
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
      futures.add(getSettledOrFetch(normalized));
    }
    if (futures.isEmpty) return;
    await Future.wait(futures);
  }

  void invalidate(Iterable<String> lessonMediaIds) {
    for (final lessonMediaId in lessonMediaIds) {
      final normalized = lessonMediaId.trim();
      if (normalized.isEmpty) continue;
      _clearTransientResolverRetry(normalized);
      final cached = _cache[normalized];
      if (cached == null) continue;
      _cache[normalized] = cached.withoutAuthority();
    }
  }

  void prime(Iterable<LessonMediaPreviewData> previews) {
    for (final preview in previews) {
      final lessonMediaId = preview.lessonMediaId.trim();
      if (lessonMediaId.isEmpty) continue;
      final existing = _cache[lessonMediaId];
      final metadataOnly = preview.withoutAuthority();
      if (existing == null) {
        _cache[lessonMediaId] = metadataOnly;
        continue;
      }
      _cache[lessonMediaId] = existing.mergeMetadata(metadataOnly);
    }
  }

  void primeFromLessonMedia(Iterable<Map<String, dynamic>> mediaItems) {
    final previews = <LessonMediaPreviewData>[];
    for (final media in mediaItems) {
      final preview = LessonMediaPreviewData.maybeFromLessonMedia(media);
      if (preview == null) continue;
      previews.add(preview);
    }
    prime(previews);
  }

  void _scheduleFlush() {
    if (_flushScheduled || _queuedIds.isEmpty) return;
    _flushScheduled = true;
    scheduleMicrotask(_flushQueued);
  }

  LessonMediaPreviewStatus _trackedStatusFor({
    required String lessonMediaId,
    LessonMediaPreviewData? preview,
  }) {
    final candidate = _rawStatusFor(
      lessonMediaId: lessonMediaId,
      preview: preview,
    );
    return _trackStatus(lessonMediaId, candidate);
  }

  LessonMediaPreviewStatus _rawStatusFor({
    required String lessonMediaId,
    LessonMediaPreviewData? preview,
  }) {
    final effectivePreview = preview ?? _cache[lessonMediaId];
    final mediaType = (effectivePreview?.mediaType ?? '').trim().toLowerCase();
    final visualUrl = effectivePreview?.visualUrl;
    final retryAttempt = _transientResolverRetryCounts[lessonMediaId] ?? 0;
    final isFetching =
        _pending.containsKey(lessonMediaId) ||
        _queuedIds.contains(lessonMediaId) ||
        _inFlightIds.contains(lessonMediaId);
    final isRetrying =
        retryAttempt > 0 &&
        (isFetching ||
            _transientResolverRetryTimers.containsKey(lessonMediaId));

    if (isFetching) {
      return LessonMediaPreviewStatus(
        state: LessonMediaPreviewState.loading,
        lessonMediaId: lessonMediaId,
        mediaType: mediaType,
        fileName: effectivePreview?.fileName,
        durationSeconds: effectivePreview?.durationSeconds,
        failureReason: effectivePreview?.failureReason,
        retryAttempt: retryAttempt,
        isRetrying: isRetrying,
        stateVersion: 0,
      );
    }

    if (effectivePreview?.authoritativeEditorReady == true) {
      return LessonMediaPreviewStatus(
        state: LessonMediaPreviewState.ready,
        lessonMediaId: lessonMediaId,
        mediaType: mediaType,
        visualUrl: visualUrl,
        fileName: effectivePreview?.fileName,
        durationSeconds: effectivePreview?.durationSeconds,
        failureReason: effectivePreview?.failureReason,
        retryAttempt: retryAttempt,
        stateVersion: 0,
      );
    }

    if (effectivePreview?.authoritativeEditorReady == false ||
        ((effectivePreview?.failureReason?.trim().isNotEmpty ?? false))) {
      return LessonMediaPreviewStatus(
        state: LessonMediaPreviewState.failed,
        lessonMediaId: lessonMediaId,
        mediaType: mediaType,
        fileName: effectivePreview?.fileName,
        durationSeconds: effectivePreview?.durationSeconds,
        failureReason: effectivePreview?.failureReason,
        failureKind: LessonMediaPreviewFailureKind.unresolved,
        retryAttempt: retryAttempt,
        stateVersion: 0,
      );
    }

    return LessonMediaPreviewStatus(
      state: LessonMediaPreviewState.loading,
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      fileName: effectivePreview?.fileName,
      durationSeconds: effectivePreview?.durationSeconds,
      failureReason: effectivePreview?.failureReason,
      retryAttempt: retryAttempt,
      isRetrying: isRetrying,
      stateVersion: 0,
    );
  }

  LessonMediaPreviewStatus _trackStatus(
    String lessonMediaId,
    LessonMediaPreviewStatus next,
  ) {
    final previous = _trackedStatuses[lessonMediaId];
    if (previous != null && _sameTrackedStatus(previous, next)) {
      return previous;
    }
    final nextStateVersion = (previous?.stateVersion ?? 0) + 1;
    final nextFailedTransitionVersion =
        previous?.state != LessonMediaPreviewState.failed &&
            next.state == LessonMediaPreviewState.failed
        ? (previous?.failedTransitionVersion ?? 0) + 1
        : previous?.failedTransitionVersion;
    final tracked = next.copyWith(
      stateVersion: nextStateVersion,
      failedTransitionVersion: nextFailedTransitionVersion,
      clearFailedTransitionVersion:
          next.state != LessonMediaPreviewState.failed &&
          nextFailedTransitionVersion == null,
    );
    _trackedStatuses[lessonMediaId] = tracked;
    return tracked;
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

  LessonMediaPreviewData _storeFailedPreview({
    required String lessonMediaId,
    LessonMediaPreviewData? preview,
    Object? error,
    required String reason,
  }) {
    _clearTransientResolverRetry(lessonMediaId);
    final source =
        preview ??
        LessonMediaPreviewData.unresolved(lessonMediaId: lessonMediaId);
    final failed = LessonMediaPreviewData.unresolved(
      lessonMediaId: lessonMediaId,
      mediaType: source.mediaType,
      durationSeconds: source.durationSeconds,
      fileName: source.fileName,
      failureReason: source.failureReason ?? reason,
    );
    _cache[lessonMediaId] = failed.asNonAuthoritativeCacheEntry();
    logLessonMediaPreviewResolutionFailure(
      surface: 'studio_editor_preview',
      lessonMediaId: lessonMediaId,
      mediaType: source.mediaType,
      error: error,
    );
    return failed;
  }

  void _clearTransientResolverRetry(String lessonMediaId) {
    _transientResolverRetryCounts.remove(lessonMediaId);
    _transientResolverRetryTimers.remove(lessonMediaId)?.cancel();
  }

  bool _scheduleTransientResolverRetry({
    required String lessonMediaId,
    LessonMediaPreviewData? preview,
  }) {
    final source =
        preview ??
        _cache[lessonMediaId] ??
        LessonMediaPreviewData.unresolved(lessonMediaId: lessonMediaId);
    if (!_isTransientResolverRetryEligible(source)) {
      return false;
    }
    final nextAttempt = (_transientResolverRetryCounts[lessonMediaId] ?? 0) + 1;
    if (nextAttempt > _transientResolverMaxRetries) {
      return false;
    }

    _transientResolverRetryCounts[lessonMediaId] = nextAttempt;
    _cache[lessonMediaId] = source.withoutAuthority();
    _transientResolverRetryTimers.remove(lessonMediaId)?.cancel();
    _transientResolverRetryTimers[lessonMediaId] = Timer(
      _transientResolverRetryDelay,
      () {
        _transientResolverRetryTimers.remove(lessonMediaId);
        if (!_pending.containsKey(lessonMediaId) ||
            _queuedIds.contains(lessonMediaId) ||
            _inFlightIds.contains(lessonMediaId)) {
          return;
        }
        _queuedIds.add(lessonMediaId);
        _scheduleFlush();
      },
    );
    return true;
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
          LessonMediaPreviewData.fromJson(lessonMediaId, value).mergeMetadata(
            _cache[lessonMediaId] ??
                LessonMediaPreviewData.unresolved(lessonMediaId: lessonMediaId),
          ),
        ),
      );
    } catch (error) {
      batchError = error;
      _recordBatchFailureTelemetry(ids: ids, error: error);
      previews = <String, LessonMediaPreviewData>{};
    }

    for (final lessonMediaId in ids) {
      final preview = previews[lessonMediaId];
      final cachedPreview = _cache[lessonMediaId];
      LessonMediaPreviewData? result;

      if (preview != null) {
        if (_isReadyPreviewData(preview)) {
          _clearTransientResolverRetry(lessonMediaId);
          _cache[lessonMediaId] = preview.asNonAuthoritativeCacheEntry();
          result = preview;
        } else if (_scheduleTransientResolverRetry(
          lessonMediaId: lessonMediaId,
          preview: preview,
        )) {
          continue;
        } else {
          result = _storeFailedPreview(
            lessonMediaId: lessonMediaId,
            preview: preview,
            error: batchError,
            reason:
                preview.failureReason ?? 'backend_returned_unresolved_preview',
          );
        }
      } else if (batchError != null) {
        if (cachedPreview != null && _isReadyPreviewData(cachedPreview)) {
          _clearTransientResolverRetry(lessonMediaId);
          result = cachedPreview;
        } else {
          result = _storeFailedPreview(
            lessonMediaId: lessonMediaId,
            preview: cachedPreview,
            error: batchError,
            reason: 'preview_resolution_request_failed',
          );
        }
      } else {
        if (_scheduleTransientResolverRetry(
          lessonMediaId: lessonMediaId,
          preview: cachedPreview,
        )) {
          continue;
        }
        result = _storeFailedPreview(
          lessonMediaId: lessonMediaId,
          preview: cachedPreview,
          reason: 'backend_returned_unresolved_preview',
        );
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

bool _isReadyPreviewData(LessonMediaPreviewData preview) {
  return preview.authoritativeEditorReady == true;
}

bool _isTransientResolverRetryEligible(LessonMediaPreviewData preview) {
  return preview.mediaType.trim().toLowerCase() == 'image';
}

bool _sameTrackedStatus(
  LessonMediaPreviewStatus previous,
  LessonMediaPreviewStatus next,
) {
  return previous.state == next.state &&
      previous.lessonMediaId == next.lessonMediaId &&
      previous.mediaType == next.mediaType &&
      previous.visualUrl == next.visualUrl &&
      previous.fileName == next.fileName &&
      previous.durationSeconds == next.durationSeconds &&
      previous.failureReason == next.failureReason &&
      previous.failureKind == next.failureKind &&
      previous.retryAttempt == next.retryAttempt &&
      previous.isRetrying == next.isRetrying;
}
