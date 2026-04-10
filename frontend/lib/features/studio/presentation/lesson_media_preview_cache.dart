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

  String? get visualUrl {
    final preview = resolvedPreviewUrl;
    return preview != null && preview.isNotEmpty ? preview : null;
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
}

enum LessonMediaPreviewState { loading, ready, failed }

enum LessonMediaPreviewFailureKind { unresolved, missingId }

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
  });

  final LessonMediaPreviewState state;
  final String? lessonMediaId;
  final String mediaType;
  final String? visualUrl;
  final String? fileName;
  final int? durationSeconds;
  final String? failureReason;
  final LessonMediaPreviewFailureKind? failureKind;

  bool get isRenderable => state == LessonMediaPreviewState.ready;
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

class _PreviewFailure {
  const _PreviewFailure({required this.reason});

  final String reason;
}

class LessonMediaPreviewCache {
  LessonMediaPreviewCache({required this.studioRepository});

  final StudioRepository studioRepository;

  final _PreviewStore<LessonMediaPreviewData> _cache =
      _PreviewStore<LessonMediaPreviewData>();
  final _PreviewStore<Completer<LessonMediaPreviewData?>> _pending =
      _PreviewStore<Completer<LessonMediaPreviewData?>>();
  final _PreviewStore<List<Completer<void>>> _batchWaiters =
      _PreviewStore<List<Completer<void>>>();
  final _PreviewStore<_PreviewFailure> _failures =
      _PreviewStore<_PreviewFailure>();
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
    return _statusFor(
      lessonMediaId: lessonMediaId,
      preview: _cache.valueFor(lessonMediaId),
    );
  }

  LessonMediaPreviewStatus statusForPreview(
    String lessonMediaId,
    LessonMediaPreviewData? preview,
  ) {
    if (lessonMediaId.isEmpty) {
      final mediaType = preview == null ? '' : preview.mediaType;
      return invalidStatus(
        mediaType: mediaType,
        failureKind: LessonMediaPreviewFailureKind.missingId,
      );
    }
    return _statusFor(lessonMediaId: lessonMediaId, preview: preview);
  }

  LessonMediaPreviewStatus invalidStatus({
    required String mediaType,
    required LessonMediaPreviewFailureKind failureKind,
    String? failureReason,
  }) {
    return LessonMediaPreviewStatus(
      state: LessonMediaPreviewState.failed,
      lessonMediaId: null,
      mediaType: mediaType,
      failureKind: failureKind,
      failureReason: failureReason,
    );
  }

  bool isSettled(String lessonMediaId) {
    if (lessonMediaId.isEmpty) {
      return false;
    }
    final preview = _cache.valueFor(lessonMediaId);
    return preview != null && preview.authoritativeEditorReady == true;
  }

  Future<LessonMediaPreviewData?> getSettledOrFetch(String lessonMediaId) {
    if (lessonMediaId.isEmpty) {
      return Future<LessonMediaPreviewData?>.error(
        StateError('Lesson media preview kräver lessonMediaId.'),
      );
    }
    if (isSettled(lessonMediaId)) {
      return Future<LessonMediaPreviewData?>.value(
        _cache.valueFor(lessonMediaId),
      );
    }
    return getPreview(lessonMediaId);
  }

  Future<LessonMediaPreviewData?> getPreview(String lessonMediaId) {
    if (lessonMediaId.isEmpty) {
      return Future<LessonMediaPreviewData?>.error(
        StateError('Lesson media preview kräver lessonMediaId.'),
      );
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
    _failures.remove(lessonMediaId);
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
      _failures.remove(lessonMediaId);
      _cache.remove(lessonMediaId);
    }
  }

  void prime(Iterable<LessonMediaPreviewData> previews) {
    if (previews.isEmpty) {
      return;
    }
    for (final preview in previews) {
      if (preview.lessonMediaId.isEmpty) {
        continue;
      }
      _failures.remove(preview.lessonMediaId);
      _cache.set(preview.lessonMediaId, preview);
    }
  }

  void primeFromLessonMedia(Iterable<StudioLessonMediaItem> mediaItems) {
    if (mediaItems.isEmpty) {
      return;
    }
    final previews = <LessonMediaPreviewData>[];
    for (final item in mediaItems) {
      if (item.lessonMediaId.isEmpty) {
        continue;
      }
      final resolvedUrl = item.media?.resolvedUrl?.trim();
      final ready =
          item.state == 'ready' &&
          resolvedUrl != null &&
          resolvedUrl.isNotEmpty;
      previews.add(
        LessonMediaPreviewData(
          lessonMediaId: item.lessonMediaId,
          mediaType: item.mediaType,
          resolvedPreviewUrl: ready ? resolvedUrl : null,
          authoritativeEditorReady: ready,
          failureReason: item.state == 'failed' ? 'failed' : null,
        ),
      );
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

  LessonMediaPreviewStatus _statusFor({
    required String lessonMediaId,
    LessonMediaPreviewData? preview,
  }) {
    return _rawStatusFor(lessonMediaId: lessonMediaId, preview: preview);
  }

  LessonMediaPreviewStatus _rawStatusFor({
    required String lessonMediaId,
    LessonMediaPreviewData? preview,
  }) {
    final failure = _failures.valueFor(lessonMediaId);
    final mediaType = preview == null ? '' : preview.mediaType;
    final visualUrl = preview?.visualUrl;
    final isFetching =
        _pending.contains(lessonMediaId) ||
        _queuedIds.contains(lessonMediaId) ||
        _inFlightIds.contains(lessonMediaId);

    if (isFetching) {
      return LessonMediaPreviewStatus(
        state: LessonMediaPreviewState.loading,
        lessonMediaId: lessonMediaId,
        mediaType: mediaType,
        fileName: preview?.fileName,
        durationSeconds: preview?.durationSeconds,
        failureReason: preview?.failureReason,
      );
    }

    if (preview?.authoritativeEditorReady == true) {
      return LessonMediaPreviewStatus(
        state: LessonMediaPreviewState.ready,
        lessonMediaId: lessonMediaId,
        mediaType: mediaType,
        visualUrl: visualUrl,
        fileName: preview?.fileName,
        durationSeconds: preview?.durationSeconds,
        failureReason: preview?.failureReason,
      );
    }

    if (failure != null) {
      return LessonMediaPreviewStatus(
        state: LessonMediaPreviewState.failed,
        lessonMediaId: lessonMediaId,
        mediaType: mediaType,
        failureReason: failure.reason,
        failureKind: LessonMediaPreviewFailureKind.unresolved,
      );
    }

    if (preview?.authoritativeEditorReady == false ||
        preview?.failureReason?.isNotEmpty == true) {
      return LessonMediaPreviewStatus(
        state: LessonMediaPreviewState.failed,
        lessonMediaId: lessonMediaId,
        mediaType: mediaType,
        fileName: preview?.fileName,
        durationSeconds: preview?.durationSeconds,
        failureReason: preview?.failureReason,
        failureKind: LessonMediaPreviewFailureKind.unresolved,
      );
    }

    return LessonMediaPreviewStatus(
      state: LessonMediaPreviewState.loading,
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      fileName: preview?.fileName,
      durationSeconds: preview?.durationSeconds,
      failureReason: preview?.failureReason,
    );
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

  void _markRequestFailure({
    required String lessonMediaId,
    Object? error,
    required String reason,
  }) {
    final mediaType = _cache.valueFor(lessonMediaId)?.mediaType;
    _cache.remove(lessonMediaId);
    _failures.set(lessonMediaId, _PreviewFailure(reason: reason));
    logLessonMediaPreviewResolutionFailure(
      surface: 'studio_editor_preview',
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      error: error,
    );
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
    StackTrace? batchStackTrace;
    try {
      final payload = await studioRepository.fetchLessonMediaPreviews(ids);
      for (final item in payload.items) {
        previews.set(
          item.lessonMediaId,
          LessonMediaPreviewData.fromPreviewItem(item),
        );
      }
    } catch (error, stackTrace) {
      batchError = error;
      batchStackTrace = stackTrace;
      _recordBatchFailureTelemetry(ids: ids, error: error);
    }

    for (final lessonMediaId in ids) {
      final preview = previews.valueFor(lessonMediaId);
      LessonMediaPreviewData? result;

      if (preview != null) {
        _failures.remove(lessonMediaId);
        _cache.set(lessonMediaId, preview);
        result = preview;
      } else if (batchError != null) {
        _markRequestFailure(
          lessonMediaId: lessonMediaId,
          error: batchError,
          reason: 'preview_resolution_request_failed',
        );
        final completer = _pending.remove(lessonMediaId);
        if (completer != null && !completer.isCompleted) {
          final effectiveStackTrace = batchStackTrace ?? StackTrace.current;
          completer.completeError(batchError, effectiveStackTrace);
        }
        _completeBatchWaiters(lessonMediaId);
        continue;
      } else {
        final error = StateError(
          'Lesson media preview missing for lesson media $lessonMediaId.',
        );
        _markRequestFailure(
          lessonMediaId: lessonMediaId,
          error: error,
          reason: 'backend_returned_unresolved_preview',
        );
        final completer = _pending.remove(lessonMediaId);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(error, StackTrace.current);
        }
        _completeBatchWaiters(lessonMediaId);
        continue;
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
