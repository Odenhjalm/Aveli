part of 'studio_repository.dart';

class _StudioLessonMediaScope {
  const _StudioLessonMediaScope(this._client);

  final ApiClient _client;

  Future<List<StudioLessonMediaItem>> listLessonMedia(String lessonId) async {
    final response = await _client.raw.get<Object?>(
      '/api/lesson-media/$lessonId',
    );
    final list = StudioRepository._requiredResponseListField(
      response.data,
      'items',
      'Lesson media list',
    );
    return list
        .map((e) => StudioLessonMediaItem.fromResponse(e))
        .toList(growable: false);
  }

  Future<StudioLessonMediaPreviewBatch> fetchLessonMediaPreviews(
    List<String> lessonMediaIds,
  ) async {
    final requestedIds = <String>[];
    final seenIds = <String>{};
    for (final lessonMediaId in lessonMediaIds) {
      if (lessonMediaId.isEmpty) {
        continue;
      }
      if (seenIds.add(lessonMediaId)) {
        requestedIds.add(lessonMediaId);
      }
    }
    if (requestedIds.isEmpty) {
      return StudioLessonMediaPreviewBatch(
        items: const <StudioLessonMediaPreviewItem>[],
      );
    }

    final response = await _client.raw.post<Object?>(
      ApiPaths.mediaPreviews,
      data: {'ids': requestedIds},
    );
    final rawItems = StudioRepository._requiredResponseField(
      response.data,
      'items',
      'Lesson media previews',
    );
    if (rawItems is! Map) {
      throw StateError(
        'Lesson media previews field "items" must be an object.',
      );
    }
    final items = <StudioLessonMediaPreviewItem>[];
    for (final entry in rawItems.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw StateError('Lesson media previews returned an empty id key.');
      }
      items.add(
        StudioLessonMediaPreviewItem.fromResponse(
          entry.key as String,
          entry.value,
        ),
      );
    }
    return StudioLessonMediaPreviewBatch(items: items);
  }

  Future<StudioLessonMediaItem> uploadLessonMedia({
    required String lessonId,
    required Uint8List data,
    required String filename,
    required String contentType,
    void Function(UploadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final mediaType = _detectUploadMediaType(contentType);
    if (mediaType == null) {
      throw StateError(
        'Unsupported lesson media content type for canonical edge contract.',
      );
    }

    final upload = await _requestLessonMediaUploadTarget(
      filename: filename,
      mimeType: contentType,
      sizeBytes: data.length,
      mediaType: mediaType,
      lessonId: lessonId,
    );
    if (upload.uploadUrl.isEmpty) {
      throw StateError('Ofullständigt svar från studio media upload-url.');
    }

    final dio = Dio();
    await dio.putUri<void>(
      Uri.parse(upload.uploadUrl),
      data: data,
      options: Options(headers: upload.headers.toMap()),
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (onProgress == null) return;
        final resolvedTotal = total > 0 ? total : data.length;
        onProgress(UploadProgress(sent: sent, total: resolvedTotal));
      },
    );

    final response = await _client.raw.post<Object?>(
      '/api/lesson-media/$lessonId/${upload.lessonMediaId}/complete',
      data: const {},
    );
    return StudioLessonMediaItem.fromResponse(response.data);
  }

  Future<void> deleteLessonMedia(String lessonId, String lessonMediaId) async {
    await _client.delete('/api/lesson-media/$lessonId/$lessonMediaId');
  }

  Future<void> reorderLessonMedia(
    String lessonId,
    List<String> orderedMediaIds,
  ) async {
    await _client.patch(
      '/api/lesson-media/$lessonId/reorder',
      body: {'lesson_media_ids': orderedMediaIds},
    );
  }

  Future<StudioLessonMediaUploadTarget> _requestLessonMediaUploadTarget({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    required String lessonId,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/api/lesson-media/$lessonId/upload-url',
      data: {
        'filename': filename,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'media_type': mediaType,
      },
    );
    return StudioLessonMediaUploadTarget.fromResponse(response.data);
  }
}

String? _detectUploadMediaType(String contentType) {
  if (contentType.isEmpty) return null;
  final lower = contentType.toLowerCase();
  if (lower.startsWith('image/')) return 'image';
  if (lower.startsWith('video/')) return 'video';
  if (lower.startsWith('audio/')) return 'audio';
  if (lower == 'application/pdf') return 'document';
  return null;
}

class UploadProgress {
  const UploadProgress({required this.sent, required this.total});

  final int sent;
  final int total;

  double get fraction => total == 0 ? 0 : sent / total;
}
