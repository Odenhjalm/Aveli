import 'dart:async';

import 'package:flutter/foundation.dart';

class LessonMediaPreviewHydrationSnapshot {
  const LessonMediaPreviewHydrationSnapshot({
    required this.lessonId,
    required this.requestId,
    required this.runId,
    required this.initialHydrationIds,
    required this.hydratingEmbedIds,
    required this.revision,
  });

  factory LessonMediaPreviewHydrationSnapshot.empty() =>
      const LessonMediaPreviewHydrationSnapshot(
        lessonId: null,
        requestId: null,
        runId: 0,
        initialHydrationIds: <String>{},
        hydratingEmbedIds: <String>{},
        revision: 0,
      );

  final String? lessonId;
  final int? requestId;
  final int runId;
  final Set<String> initialHydrationIds;
  final Set<String> hydratingEmbedIds;
  final int revision;

  bool get isActive =>
      lessonId != null && requestId != null && hydratingEmbedIds.isNotEmpty;

  bool matchesRequest({required String lessonId, required int requestId}) {
    return this.lessonId == lessonId && this.requestId == requestId;
  }

  bool isHydratingId(String lessonMediaId) {
    if (lessonMediaId.isEmpty) return false;
    return hydratingEmbedIds.contains(lessonMediaId);
  }
}

class LessonMediaPreviewHydrationController
    extends ValueNotifier<LessonMediaPreviewHydrationSnapshot> {
  LessonMediaPreviewHydrationController({
    this.timeout = const Duration(seconds: 5),
  }) : super(LessonMediaPreviewHydrationSnapshot.empty());

  final Duration timeout;

  Timer? _timeoutTimer;
  bool _disposed = false;

  void reset({bool bumpRevision = false}) {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final current = value;
    _publish(
      LessonMediaPreviewHydrationSnapshot(
        lessonId: null,
        requestId: null,
        runId: current.runId + 1,
        initialHydrationIds: const <String>{},
        hydratingEmbedIds: const <String>{},
        revision: bumpRevision ? current.revision + 1 : current.revision,
      ),
    );
  }

  void start({
    required String lessonId,
    required int requestId,
    required Set<String> initialHydrationIds,
    required Set<String> hydratingEmbedIds,
    required Future<void> settled,
  }) {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    final initialIds = _collectHydrationIds(initialHydrationIds);
    final hydratingIds = _collectHydrationIds(hydratingEmbedIds);
    final nextRunId = value.runId + 1;

    if (hydratingIds.isEmpty) {
      _publish(
        LessonMediaPreviewHydrationSnapshot(
          lessonId: null,
          requestId: null,
          runId: nextRunId,
          initialHydrationIds: initialIds,
          hydratingEmbedIds: const <String>{},
          revision: value.revision,
        ),
      );
      return;
    }

    _publish(
      LessonMediaPreviewHydrationSnapshot(
        lessonId: lessonId,
        requestId: requestId,
        runId: nextRunId,
        initialHydrationIds: initialIds,
        hydratingEmbedIds: hydratingIds,
        revision: value.revision,
      ),
    );

    _timeoutTimer = Timer(timeout, () {
      _finishRun(lessonId: lessonId, requestId: requestId, runId: nextRunId);
    });

    unawaited(
      settled.then(
        (_) => _finishRun(
          lessonId: lessonId,
          requestId: requestId,
          runId: nextRunId,
        ),
        onError: (_, _) => _finishRun(
          lessonId: lessonId,
          requestId: requestId,
          runId: nextRunId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    super.dispose();
  }

  void _finishRun({
    required String lessonId,
    required int requestId,
    required int runId,
  }) {
    if (_disposed) return;
    final current = value;
    if (current.runId != runId ||
        !current.matchesRequest(lessonId: lessonId, requestId: requestId)) {
      return;
    }

    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _publish(
      LessonMediaPreviewHydrationSnapshot(
        lessonId: null,
        requestId: null,
        runId: runId,
        initialHydrationIds: const <String>{},
        hydratingEmbedIds: const <String>{},
        revision: current.revision + 1,
      ),
    );
  }

  void _publish(LessonMediaPreviewHydrationSnapshot nextValue) {
    if (_disposed) return;
    value = nextValue;
  }

  static Set<String> _collectHydrationIds(Iterable<String> ids) {
    final collected = <String>{};
    for (final id in ids) {
      if (id.isEmpty) continue;
      collected.add(id);
    }
    return Set<String>.unmodifiable(collected);
  }
}
