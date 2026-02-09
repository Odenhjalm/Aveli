enum MediaResolutionMode {
  editorInsert,
  editorPreview,
  studentRender,
}

extension MediaResolutionModeApi on MediaResolutionMode {
  String get apiValue {
    switch (this) {
      case MediaResolutionMode.editorInsert:
        return 'editor_insert';
      case MediaResolutionMode.editorPreview:
        return 'editor_preview';
      case MediaResolutionMode.studentRender:
        return 'student_render';
    }
  }
}

