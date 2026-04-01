import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';

enum CanonicalLessonMediaType { audio, image, video, document }

CanonicalLessonMediaType lessonMediaTypeOf(LessonMediaItem item) {
  switch (item.mediaType) {
    case 'audio':
      return CanonicalLessonMediaType.audio;
    case 'image':
      return CanonicalLessonMediaType.image;
    case 'video':
      return CanonicalLessonMediaType.video;
    case 'document':
      return CanonicalLessonMediaType.document;
    default:
      throw StateError(
        'Ogiltig lesson media_type "${item.mediaType}" för lektionsmedia ${item.id}.',
      );
  }
}

bool isLessonMediaDocument(LessonMediaItem item) {
  return lessonMediaTypeOf(item) == CanonicalLessonMediaType.document;
}

Future<String> resolveLessonMediaSignedPlaybackUrl({
  required String lessonMediaId,
  required MediaPipelineRepository pipelineRepository,
}) async {
  if (lessonMediaId.isEmpty) {
    throw StateError('Lektionsmedia saknar ID.');
  }
  return pipelineRepository.fetchLessonPlaybackUrl(lessonMediaId);
}

Future<String> resolveLessonMediaDocumentUrl({
  required LessonMediaItem item,
  required MediaPipelineRepository pipelineRepository,
}) async {
  if (!isLessonMediaDocument(item)) {
    throw StateError('Lektionsmedia är inte ett dokument: ${item.id}.');
  }
  if (!item.previewReady) {
    throw StateError('Dokumentet är inte klart för visning: ${item.id}.');
  }
  return resolveLessonMediaSignedPlaybackUrl(
    lessonMediaId: item.id,
    pipelineRepository: pipelineRepository,
  );
}

Future<String> resolveLessonMediaPlaybackUrl({
  required LessonMediaItem item,
  required MediaPipelineRepository pipelineRepository,
}) async {
  if (isLessonMediaDocument(item)) {
    throw StateError(
      'Dokument får inte behandlas som uppspelningsmedia: ${item.id}.',
    );
  }
  if (item.id.isEmpty) {
    throw StateError('Lektionsmedia saknar ID.');
  }
  if (!item.previewReady) {
    throw StateError(
      'Lektionsmedia är inte klart för uppspelning: ${item.id}.',
    );
  }
  return resolveLessonMediaSignedPlaybackUrl(
    lessonMediaId: item.id,
    pipelineRepository: pipelineRepository,
  );
}
