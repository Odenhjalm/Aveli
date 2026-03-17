import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

class EditorSession {
  EditorSession({
    required this.sessionId,
    required this.lessonId,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.canonicalMarkdown,
  }) : revision = 0;

  final String sessionId;
  final String lessonId;
  int revision;
  final QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  String canonicalMarkdown;

  void incrementRevision() {
    revision += 1;
  }

  bool matches(String sessionId, String lessonId) {
    return this.sessionId == sessionId && this.lessonId == lessonId;
  }
}
