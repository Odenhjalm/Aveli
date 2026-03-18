enum EditorOperationType {
  replaceText,
  formatSelection,
  insertEmbed,
  replaceEmbed,
}

class EditorOperation {
  const EditorOperation({
    required this.type,
    required this.sessionId,
    required this.lessonId,
    required this.baseRevision,
    this.payload,
  });

  final EditorOperationType type;
  final String sessionId;
  final String? lessonId;
  final int baseRevision;
  final Object? payload;
}
