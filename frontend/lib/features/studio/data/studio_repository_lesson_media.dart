part of 'studio_repository.dart';

class _StudioLessonMediaScope {
  const _StudioLessonMediaScope(this._client);

  final ApiClient _client;

  String _requiredResponseStringField(
    Object? payload,
    String field,
    String label,
  ) {
    final value = StudioRepository._requiredResponseField(
      payload,
      field,
      label,
    );
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw StateError('$label field "$field" must be a non-empty string');
  }

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
    if (lessonMediaIds case []) {
      throw StateError(
        'Lesson media preview batch requires at least one lesson media id.',
      );
    }

    final response = await _client.raw.post<Object?>(
      ApiPaths.mediaPreviews,
      data: {'ids': lessonMediaIds},
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

  Future<String> fetchLessonMediaPlaybackUrl(String lessonMediaId) async {
    if (lessonMediaId.isEmpty) {
      throw StateError('Lesson media playback requires lesson_media_id.');
    }
    final response = await _client.raw.post<Object?>(
      ApiPaths.mediaLessonPlaybackUrl,
      data: {'lesson_media_id': lessonMediaId},
    );
    return _requiredResponseStringField(
      response.data,
      'playback_url',
      'Lesson media playback',
    );
  }

  Future<StudioLessonMediaItem> uploadLessonMedia({
    required String lessonId,
    required Uint8List data,
    required String filename,
    required String contentType,
    required String mediaType,
    void Function(UploadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
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
        if (total <= 0) {
          throw StateError('Upload progress saknar total bytes.');
        }
        onProgress(UploadProgress(sent: sent, total: total));
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

class UploadProgress {
  const UploadProgress({required this.sent, required this.total});

  final int sent;
  final int total;

  double get fraction => total == 0 ? 0 : sent / total;
}
