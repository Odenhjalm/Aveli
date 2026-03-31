import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
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
    final preview = resolvedPreviewUrl;
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

  factory LessonMediaPreviewData.fromPreviewItem(
    StudioLessonMediaPreviewItem preview,
  ) {
    return LessonMediaPreviewData(
      lessonMediaId: preview.lessonMediaId,
      mediaType: preview.mediaType,
      resolvedPreviewUrl: preview.previewUrl,
      authoritativeEditorReady: preview.authoritativeEditorReady,
      durationSeconds: preview.durationSeconds,
      fileName: preview.fileName,
      failureReason: preview.failureReason,
    );
  }

  static LessonMediaPreviewData fromLessonMediaItem(
    StudioLessonMediaItem media,
  ) {
    return LessonMediaPreviewData(
      lessonMediaId: media.lessonMediaId,
      mediaType: media.mediaType,
      fileName: media.originalName,
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

  final _PreviewStore<LessonMediaPreviewData> _cache =
      _PreviewStore<LessonMediaPreviewData>();
  final _PreviewStore<Completer<LessonMediaPreviewData?>> _pending =
      _PreviewStore<Completer<LessonMediaPreviewData?>>();
  final _PreviewStore<List<Completer<void>>> _batchWaiters =
      _PreviewStore<List<Completer<void>>>();
  final _PreviewStore<LessonMediaPreviewStatus> _trackedStatuses =
      _PreviewStore<LessonMediaPreviewStatus>();
  final _PreviewStore<int> _consumedFailedTransitionVersions =
      _PreviewStore<int>();
  final _PreviewStore<_TransientResolverRetryState> _transientResolverRetries =
      _PreviewStore<_TransientResolverRetryState>();
  final Set<String> _queuedIds = <String>{};
  final Set<String> _inFlightIds = <String>{};

  bool _flushScheduled = false;

  LessonMediaPreviewData? peek(String lessonMediaId) {
    if (lessonMediaId.isEmpty) {
      return null;
    }
    return _cache.valueFor(lessonMediaId);
  }

  LessonMediaPreviewStatus? peekStatus(String lessonMediaId) {
    if (lessonMediaId.isEmpty) {
      return null;
    }
    return _trackedStatusFor(
      lessonMediaId: lessonMediaId,
      preview: _cache.valueFor(lessonMediaId),
    );
  }

  LessonMediaPreviewStatus statusForPreview(
    String lessonMediaId,
    LessonMediaPreviewData? preview,
  ) {
    if (lessonMediaId.isEmpty) {
      return invalidStatus(
        mediaType: preview?.mediaType ?? '',
        failureKind: LessonMediaPreviewFailureKind.missingId,
      );
    }
    return _trackedStatusFor(lessonMediaId: lessonMediaId, preview: preview);
  }

  LessonMediaPreviewStatus invalidStatus({
    required String mediaType,
    required LessonMediaPreviewFailureKind failureKind,
  }) {
    return LessonMediaPreviewStatus(
      state: LessonMediaPreviewState.failed,
      lessonMediaId: null,
      mediaType: mediaType,
      failureKind: failureKind,
      stateVersion: 0,
    );
  }

  bool consumeFailedTransitionLog(
    String lessonMediaId,
    int failedTransitionVersion,
  ) {
    if (lessonMediaId.isEmpty || failedTransitionVersion <= 0) {
      return false;
    }
    final consumed =
        _consumedFailedTransitionVersions.valueFor(lessonMediaId) ?? 0;
    if (consumed >= failedTransitionVersion) {
      return false;
    }
    _consumedFailedTransitionVersions.set(
      lessonMediaId,
      failedTransitionVersion,
    );
    return true;
  }

  bool isSettled(String lessonMediaId) {
    if (lessonMediaId.isEmpty) {
      return false;
    }
    return _rawStatusFor(lessonMediaId: lessonMediaId).state ==
        LessonMediaPreviewState.ready;
  }

  Future<LessonMediaPreviewData?> getSettledOrFetch(String lessonMediaId) {
    if (lessonMediaId.isEmpty) {
      return Future<LessonMediaPreviewData?>.value(null);
    }
    if (isSettled(lessonMediaId)) {
      return Future<LessonMediaPreviewData?>.value(
        _cache.valueFor(lessonMediaId) ??
            LessonMediaPreviewData.unresolved(lessonMediaId: lessonMediaId),
      );
    }
    return getPreview(lessonMediaId);
  }

  Future<LessonMediaPreviewData?> getPreview(String lessonMediaId) {
    if (lessonMediaId.isEmpty) {
      return Future<LessonMediaPreviewData?>.value(null);
    }

    if (_cache.contains(lessonMediaId)) {
      logLessonMediaPreviewCacheEvent(
        event: 'LESSON_MEDIA_PREVIEW_CACHE_METADATA_USED',
        lessonMediaId: lessonMediaId,
        mediaType: _cache.valueFor(lessonMediaId)?.mediaType,
      );
    }

    final existing = _pending.valueFor(lessonMediaId);
    if (existing != null) {
      return existing.future;
    }

    if (_inFlightIds.contains(lessonMediaId)) {
      final completer = Completer<LessonMediaPreviewData?>();
      _pending.set(lessonMediaId, completer);
      return completer.future;
    }

    final completer = Completer<LessonMediaPreviewData?>();
    _clearTransientResolverRetry(lessonMediaId);
    _pending.set(lessonMediaId, completer);
    _queuedIds.add(lessonMediaId);
    logLessonMediaPreviewCacheEvent(
      event: 'LESSON_MEDIA_PREVIEW_BACKEND_RESOLUTION',
      lessonMediaId: lessonMediaId,
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
      if (lessonMediaId.isEmpty) {
        continue;
      }
      if (isSettled(lessonMediaId)) {
        continue;
      }

      hydratingIds.add(lessonMediaId);
      futures.add(_registerBatchWaiter(lessonMediaId));
      if (!_inFlightIds.contains(lessonMediaId) &&
          !_queuedIds.contains(lessonMediaId)) {
        _queuedIds.add(lessonMediaId);
        _pending.putIfAbsent(
          lessonMediaId,
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
      if (lessonMediaId.isEmpty) {
        continue;
      }
      futures.add(getSettledOrFetch(lessonMediaId));
    }
    if (futures.isEmpty) {
      return;
    }
    await Future.wait(futures);
  }

  void invalidate(Iterable<String> lessonMediaIds) {
    for (final lessonMediaId in lessonMediaIds) {
      if (lessonMediaId.isEmpty) {
        continue;
      }
      _clearTransientResolverRetry(lessonMediaId);
      final cached = _cache.valueFor(lessonMediaId);
      if (cached == null) {
        continue;
      }
      _cache.set(lessonMediaId, cached.withoutAuthority());
    }
  }

  void prime(Iterable<LessonMediaPreviewData> previews) {
    for (final preview in previews) {
      final lessonMediaId = preview.lessonMediaId;
      if (lessonMediaId.isEmpty) {
        continue;
      }
      final existing = _cache.valueFor(lessonMediaId);
      final metadataOnly = preview.withoutAuthority();
      if (existing == null) {
        _cache.set(lessonMediaId, metadataOnly);
        continue;
      }
      _cache.set(lessonMediaId, existing.mergeMetadata(metadataOnly));
    }
  }

  void primeFromLessonMedia(Iterable<StudioLessonMediaItem> mediaItems) {
    final previews = <LessonMediaPreviewData>[];
    for (final media in mediaItems) {
      previews.add(LessonMediaPreviewData.fromLessonMediaItem(media));
    }
    prime(previews);
  }

  void _scheduleFlush() {
    if (_flushScheduled || _queuedIds.isEmpty) {
      return;
    }
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
    final effectivePreview = preview ?? _cache.valueFor(lessonMediaId);
    final mediaType = effectivePreview?.mediaType ?? '';
    final visualUrl = effectivePreview?.visualUrl;
    final retryState = _transientResolverRetries.valueFor(lessonMediaId);
    final retryAttempt = retryState?.attempt ?? 0;
    final isFetching =
        _pending.contains(lessonMediaId) ||
        _queuedIds.contains(lessonMediaId) ||
        _inFlightIds.contains(lessonMediaId);
    final isRetrying =
        retryAttempt > 0 && (isFetching || retryState?.timer != null);

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
        (effectivePreview?.failureReason?.isNotEmpty ?? false)) {
      return LessonMediaPreviewStatus(
        state: LessonMediaPreviewState.failed,
        lessonMediaId: lessonMediaId,
        mediaType: mediaType,
        fileName: effectivePreview?.fileName,
        durationSeconds: effectivePreview?.durationSeconds,
        failureReason: effectivePreview?.failureReason,
        failureKind: LessonMediaPreviewFailureKind.unresolved,
        retryAttempt: retryAttempt,
        isRetrying: isRetrying,
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
    final previous = _trackedStatuses.valueFor(lessonMediaId);
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
    _trackedStatuses.set(lessonMediaId, tracked);
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
    if (waiters == null) {
      return;
    }
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
        mediaType: _cache.valueFor(lessonMediaId)?.mediaType,
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
    _cache.set(lessonMediaId, failed.asNonAuthoritativeCacheEntry());
    logLessonMediaPreviewResolutionFailure(
      surface: 'studio_editor_preview',
      lessonMediaId: lessonMediaId,
      mediaType: source.mediaType,
      error: error,
    );
    return failed;
  }

  void _clearTransientResolverRetry(String lessonMediaId) {
    _transientResolverRetries.remove(lessonMediaId)?.timer?.cancel();
  }

  bool _scheduleTransientResolverRetry({
    required String lessonMediaId,
    LessonMediaPreviewData? preview,
  }) {
    final source =
        preview ??
        _cache.valueFor(lessonMediaId) ??
        LessonMediaPreviewData.unresolved(lessonMediaId: lessonMediaId);
    if (!_isTransientResolverRetryEligible(source)) {
      return false;
    }

    final nextAttempt =
        (_transientResolverRetries.valueFor(lessonMediaId)?.attempt ?? 0) + 1;
    if (nextAttempt > _transientResolverMaxRetries) {
      return false;
    }

    _transientResolverRetries.remove(lessonMediaId)?.timer?.cancel();
    _cache.set(lessonMediaId, source.withoutAuthority());
    late final Timer retryTimer;
    retryTimer = Timer(_transientResolverRetryDelay, () {
      final retryState = _transientResolverRetries.valueFor(lessonMediaId);
      if (retryState != null && identical(retryState.timer, retryTimer)) {
        _transientResolverRetries.set(
          lessonMediaId,
          retryState.copyWith(clearTimer: true),
        );
      }
      if (!_pending.contains(lessonMediaId) ||
          _queuedIds.contains(lessonMediaId) ||
          _inFlightIds.contains(lessonMediaId)) {
        return;
      }
      _queuedIds.add(lessonMediaId);
      _scheduleFlush();
    });
    _transientResolverRetries.set(
      lessonMediaId,
      _TransientResolverRetryState(attempt: nextAttempt, timer: retryTimer),
    );
    return true;
  }

  Future<void> _flushQueued() async {
    _flushScheduled = false;
    final ids = _queuedIds.toList(growable: false);
    _queuedIds.clear();
    if (ids.isEmpty) {
      return;
    }
    _inFlightIds.addAll(ids);

    final previews = _PreviewStore<LessonMediaPreviewData>();
    Object? batchError;
    try {
      final payload = await studioRepository.fetchLessonMediaPreviews(ids);
      for (final item in payload.items) {
        previews.set(
          item.lessonMediaId,
          LessonMediaPreviewData.fromPreviewItem(item).mergeMetadata(
            _cache.valueFor(item.lessonMediaId) ??
                LessonMediaPreviewData.unresolved(
                  lessonMediaId: item.lessonMediaId,
                ),
          ),
        );
      }
    } catch (error) {
      batchError = error;
      _recordBatchFailureTelemetry(ids: ids, error: error);
    }

    for (final lessonMediaId in ids) {
      final preview = previews.valueFor(lessonMediaId);
      final cachedPreview = _cache.valueFor(lessonMediaId);
      LessonMediaPreviewData? result;

      if (preview != null) {
        if (_isReadyPreviewData(preview)) {
          _clearTransientResolverRetry(lessonMediaId);
          _cache.set(lessonMediaId, preview.asNonAuthoritativeCacheEntry());
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
    return detail.contains('method not allowed') ||
        detail.contains('Method Not Allowed');
  }
  final detail = error.toString();
  return detail.contains('method not allowed') ||
      detail.contains('Method Not Allowed');
}

bool _isReadyPreviewData(LessonMediaPreviewData preview) {
  return preview.authoritativeEditorReady == true;
}

bool _isTransientResolverRetryEligible(LessonMediaPreviewData preview) {
  return preview.mediaType == 'image';
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

class _PreviewStoreEntry<T> {
  _PreviewStoreEntry({required this.lessonMediaId, required this.value});

  final String lessonMediaId;
  T value;
}

class _PreviewStore<T> {
  final List<_PreviewStoreEntry<T>> _entries = <_PreviewStoreEntry<T>>[];

  bool contains(String lessonMediaId) => _indexOf(lessonMediaId) != -1;

  T? valueFor(String lessonMediaId) {
    final index = _indexOf(lessonMediaId);
    if (index == -1) {
      return null;
    }
    return _entries[index].value;
  }

  void set(String lessonMediaId, T value) {
    final index = _indexOf(lessonMediaId);
    if (index == -1) {
      _entries.add(
        _PreviewStoreEntry<T>(lessonMediaId: lessonMediaId, value: value),
      );
      return;
    }
    _entries[index].value = value;
  }

  T putIfAbsent(String lessonMediaId, T Function() create) {
    final existing = valueFor(lessonMediaId);
    if (existing != null) {
      return existing;
    }
    final created = create();
    set(lessonMediaId, created);
    return created;
  }

  T? remove(String lessonMediaId) {
    final index = _indexOf(lessonMediaId);
    if (index == -1) {
      return null;
    }
    return _entries.removeAt(index).value;
  }

  int _indexOf(String lessonMediaId) {
    for (var index = 0; index < _entries.length; index += 1) {
      if (_entries[index].lessonMediaId == lessonMediaId) {
        return index;
      }
    }
    return -1;
  }
}

class _TransientResolverRetryState {
  const _TransientResolverRetryState({
    required this.attempt,
    required this.timer,
  });

  final int attempt;
  final Timer? timer;

  _TransientResolverRetryState copyWith({
    int? attempt,
    Timer? timer,
    bool clearTimer = false,
  }) {
    return _TransientResolverRetryState(
      attempt: attempt ?? this.attempt,
      timer: clearTimer ? null : (timer ?? this.timer),
    );
  }
}
