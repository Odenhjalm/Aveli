import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'editor_test_bridge_stub.dart'
    if (dart.library.html) 'editor_test_bridge_web.dart'
    as bridge;

void registerAveliEditorTestBridge(
  quill.QuillController? Function() controllerAccessor,
) {
  bridge.registerAveliEditorTestBridge(controllerAccessor);
}

void unregisterAveliEditorTestBridge() {
  bridge.unregisterAveliEditorTestBridge();
}
