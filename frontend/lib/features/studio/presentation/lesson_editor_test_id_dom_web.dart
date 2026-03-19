// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:web/web.dart' as web;

bool syncLessonEditorTestId({required String testId}) {
  final semanticsElement = web.document.querySelector(
    '[flt-semantics-identifier="$testId"]',
  );
  if (semanticsElement != null) {
    semanticsElement.setAttribute('data-testid', testId);
    return true;
  }

  final keyedElement = web.document.querySelector('[key="$testId"]');
  if (keyedElement == null) {
    return false;
  }

  keyedElement.setAttribute('data-testid', testId);
  return true;
}
