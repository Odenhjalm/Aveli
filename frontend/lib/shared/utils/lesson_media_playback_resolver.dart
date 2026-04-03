import 'package:aveli/features/courses/data/courses_repository.dart';

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
