// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

bool kEditorDebug = true;

void logEditor(String message) {
  if (kEditorDebug) {
    print('[EDITOR] $message');
  }
}

String formatEditorSelection(TextSelection? selection) {
  if (selection == null) return 'null';
  return '${selection.baseOffset}:${selection.extentOffset}';
}
