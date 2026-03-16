import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

class LessonMediaPreviewData {
  const LessonMediaPreviewData({
    required this.lessonMediaId,
    required this.mediaType,
    this.thumbnailUrl,
    this.posterFrameUrl,
    this.durationSeconds,
    this.fileName,
    this.previewBlocked = false,
  });

  final String lessonMediaId;
  final String mediaType;
  final String? thumbnailUrl;
  final String? posterFrameUrl;
  final int? durationSeconds;
  final String? fileName;
  final bool previewBlocked;

  String? get visualUrl {
    final poster = posterFrameUrl?.trim();
    if (poster != null && poster.isNotEmpty) return poster;
    final thumbnail = thumbnailUrl?.trim();
    if (thumbnail != null && thumbnail.isNotEmpty) return thumbnail;
    return null;
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
      thumbnailUrl: _normalizedString(
        json['thumbnail_url'] ?? json['thumbnailUrl'],
      ),
      posterFrameUrl: _normalizedString(
        json['poster_frame'] ?? json['posterFrame'],
      ),
      durationSeconds: duration is num ? duration.toInt() : null,
      fileName: _normalizedString(json['file_name'] ?? json['fileName']),
      previewBlocked: json['preview_blocked'] == true,
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
        _normalizedString(media['original_name']) ??
        _fileNameFromStoragePath(_normalizedString(media['storage_path']));
    final previewBlocked =
        media['preview_blocked'] == true ||
        media['resolvable_for_editor'] == false;

    final preferredUrl = _firstNonEmpty(<Object?>[
      media['preferredUrl'],
      media['preferred_url'],
      media['thumbnail_url'],
      media['thumbnailUrl'],
      media['download_url'],
      media['downloadUrl'],
      media['playback_url'],
      media['playbackUrl'],
    ]);

    return LessonMediaPreviewData(
      lessonMediaId: lessonMediaId,
      mediaType: mediaType,
      thumbnailUrl: mediaType == 'image' ? preferredUrl : null,
      posterFrameUrl: mediaType == 'video' ? preferredUrl : null,
      durationSeconds: duration is num ? duration.toInt() : null,
      fileName: fileName,
      previewBlocked: previewBlocked,
    );
  }
}

final lessonMediaPreviewCacheProvider = Provider<LessonMediaPreviewCache>((ref) {
  final studioRepository = ref.watch(studioRepositoryProvider);
  return LessonMediaPreviewCache(studioRepository: studioRepository);
});

class LessonMediaPreviewCache {
  LessonMediaPreviewCache({required this.studioRepository});

  final StudioRepository studioRepository;

  final Map<String, LessonMediaPreviewData> _cache =
      <String, LessonMediaPreviewData>{};
  final Map<String, Completer<LessonMediaPreviewData?>> _pending =
      <String, Completer<LessonMediaPreviewData?>>{};
  final Set<String> _queuedIds = <String>{};

  bool _flushScheduled = false;

  Future<LessonMediaPreviewData?> getPreview(String lessonMediaId) {
    final normalized = lessonMediaId.trim();
    if (normalized.isEmpty) {
      return Future<LessonMediaPreviewData?>.value(null);
    }

    final cached = _cache[normalized];
    if (cached != null) {
      return Future<LessonMediaPreviewData?>.value(cached);
    }

    final existing = _pending[normalized];
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<LessonMediaPreviewData?>();
    _pending[normalized] = completer;
    _queuedIds.add(normalized);
    _scheduleFlush();
    return completer.future;
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
      _cache[lessonMediaId] = preview;
      final completer = _pending.remove(lessonMediaId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(preview);
      }
    }
  }

  void primeFromLessonMedia(Iterable<Map<String, dynamic>> mediaItems) {
    final previews = mediaItems
        .map(LessonMediaPreviewData.maybeFromLessonMedia)
        .whereType<LessonMediaPreviewData>();
    prime(previews);
  }

  void _scheduleFlush() {
    if (_flushScheduled || _queuedIds.isEmpty) return;
    _flushScheduled = true;
    scheduleMicrotask(_flushQueued);
  }

  Future<void> _flushQueued() async {
    _flushScheduled = false;
    final ids = _queuedIds.toList(growable: false);
    _queuedIds.clear();
    if (ids.isEmpty) return;

    Map<String, LessonMediaPreviewData> previews =
        <String, LessonMediaPreviewData>{};
    try {
      final payload = await studioRepository.fetchLessonMediaPreviews(ids);
      previews = payload.map(
        (lessonMediaId, value) => MapEntry(
          lessonMediaId,
          LessonMediaPreviewData.fromJson(lessonMediaId, value),
        ),
      );
    } catch (_) {
      previews = <String, LessonMediaPreviewData>{};
    }

    for (final lessonMediaId in ids) {
      final preview = previews[lessonMediaId];
      if (preview != null) {
        _cache[lessonMediaId] = preview;
      }

      final completer = _pending.remove(lessonMediaId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(preview);
      }
    }

    if (_queuedIds.isNotEmpty) {
      _scheduleFlush();
    }
  }
}

String? _firstNonEmpty(Iterable<Object?> values) {
  for (final value in values) {
    final normalized = _normalizedString(value);
    if (normalized != null) return normalized;
  }
  return null;
}

String? _normalizedString(Object? value) {
  if (value == null) return null;
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

String? _fileNameFromStoragePath(String? storagePath) {
  if (storagePath == null || storagePath.isEmpty) return null;
  final parts = storagePath.split('/');
  if (parts.isEmpty) return null;
  final fileName = parts.last.trim();
  return fileName.isEmpty ? null : fileName;
}
