import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

class EditorSession {
  EditorSession({
    required this.sessionId,
    required this.lessonId,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
  });

  final String sessionId;
  final String? lessonId;
  final quill.QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
}
