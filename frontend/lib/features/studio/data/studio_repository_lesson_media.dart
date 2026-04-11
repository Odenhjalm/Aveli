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

    final items = <StudioLessonMediaPreviewItem>[];
    for (final lessonMediaId in lessonMediaIds) {
      if (lessonMediaId.isEmpty) {
        throw StateError('Lesson media previews returned an empty id key.');
      }
      final response = await _client.raw.get<Object?>(
        '/api/media-placements/$lessonMediaId',
      );
      items.add(
        StudioLessonMediaPreviewItem.fromPlacementResponse(
          lessonMediaId,
          response.data,
        ),
      );
    }
    return StudioLessonMediaPreviewBatch(items: items);
  }

  Future<List<StudioLessonMediaItem>> fetchLessonMediaPlacements(
    List<String> lessonMediaIds,
  ) async {
    if (lessonMediaIds case []) {
      return const <StudioLessonMediaItem>[];
    }

    final items = <StudioLessonMediaItem>[];
    for (final lessonMediaId in lessonMediaIds) {
      if (lessonMediaId.isEmpty) {
        throw StateError(
          'Lesson media placement read requires a non-empty id.',
        );
      }
      final response = await _client.raw.get<Object?>(
        '/api/media-placements/$lessonMediaId',
      );
      items.add(StudioLessonMediaItem.fromPlacementResponse(response.data));
    }
    items.sort((a, b) => a.position.compareTo(b.position));
    return items;
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
    if (upload.assetState != 'pending_upload') {
      throw StateError(
        'Studio media upload-url returnerade ogiltigt asset_state.',
      );
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

    await _completeLessonMediaUpload(mediaAssetId: upload.mediaAssetId);
    return _createLessonMediaPlacement(
      lessonId: lessonId,
      mediaAssetId: upload.mediaAssetId,
      filename: filename,
    );
  }

  Future<void> _completeLessonMediaUpload({
    required String mediaAssetId,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/api/media-assets/$mediaAssetId/upload-completion',
      data: const {},
    );
    final completedMediaAssetId = _requiredResponseStringField(
      response.data,
      'media_asset_id',
      'Studio lesson media upload-completion',
    );
    if (completedMediaAssetId != mediaAssetId) {
      throw StateError(
        'Studio media upload-completion returnerade fel media_asset_id.',
      );
    }
    final assetState = _requiredResponseStringField(
      response.data,
      'asset_state',
      'Studio lesson media upload-completion',
    );
    if (assetState != 'uploaded') {
      throw StateError(
        'Studio media upload-completion returnerade ogiltigt asset_state.',
      );
    }
  }

  Future<StudioLessonMediaItem> _createLessonMediaPlacement({
    required String lessonId,
    required String mediaAssetId,
    required String filename,
  }) async {
    final response = await _client.raw.post<Object?>(
      '/api/lessons/$lessonId/media-placements',
      data: {'media_asset_id': mediaAssetId},
    );
    return StudioLessonMediaItem.fromPlacementResponse(response.data);
  }

  Future<void> deleteLessonMedia(String lessonId, String lessonMediaId) async {
    await _client.delete('/api/media-placements/$lessonMediaId');
  }

  Future<void> reorderLessonMedia(
    String lessonId,
    List<String> orderedMediaIds,
  ) async {
    await _client.patch(
      '/api/lessons/$lessonId/media-placements/reorder',
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
      '/api/lessons/$lessonId/media-assets/upload-url',
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
