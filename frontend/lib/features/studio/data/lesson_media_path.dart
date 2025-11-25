class LessonMediaPathBuilder {
  LessonMediaPathBuilder({int Function()? timestampBuilder})
    : _timestampBuilder =
          timestampBuilder ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _timestampBuilder;

  String bucketFor({required bool isIntro}) {
    return isIntro ? 'public-media' : 'course-media';
  }

  String buildPath({
    required String courseId,
    required String lessonId,
    required String filename,
  }) {
    final sanitized = _sanitizeFilename(filename);
    final ts = _timestampBuilder();
    return '$courseId/$lessonId/${ts}_$sanitized';
  }

  String kindFromContentType(String contentType) {
    final normalized = contentType.toLowerCase();
    if (normalized.startsWith('image/')) return 'image';
    if (normalized.startsWith('video/')) return 'video';
    if (normalized.startsWith('audio/')) return 'audio';
    if (normalized.contains('pdf')) return 'pdf';
    return 'other';
  }

  String _sanitizeFilename(String input) {
    final trimmed = input.trim().toLowerCase();
    if (trimmed.isEmpty) return 'media';
    final sanitized = trimmed.replaceAll(RegExp(r'[^a-z0-9._-]+'), '_');
    final collapsed = sanitized.replaceAll(RegExp(r'_+'), '_');
    final cleaned = collapsed.replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'media' : cleaned;
  }
}
