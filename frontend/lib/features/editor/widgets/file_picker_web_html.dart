// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class WebPickedFile {
  WebPickedFile({required this.name, required this.bytes, this.mimeType});

  final String name;
  final Uint8List bytes;
  final String? mimeType;
}

Future<List<WebPickedFile>?> pickFilesFromHtml({
  required List<String> allowedExtensions,
  required bool allowMultiple,
  String? accept,
}) async {
  final input = FileUploadInputElement()
    ..accept = _buildAcceptString(allowedExtensions, accept)
    ..multiple = allowMultiple;

  final completer = Completer<List<WebPickedFile>?>();
  StreamSubscription<Event>? focusSub;

  void completeWith(List<WebPickedFile>? files) {
    if (completer.isCompleted) return;
    focusSub?.cancel();
    focusSub = null;
    input.remove();
    completer.complete(files);
  }

  // Detect cancel by watching window focus return after the file dialog closes.
  // Give the input change-handler enough time to fire first to avoid a race
  // where Chrome focuses the window before dispatching `change`.
  var changeTriggered = false;

  focusSub = window.onFocus.listen((event) {
    if (completer.isCompleted) return;
    Future<void>(() async {
      const checks = 25;
      for (var i = 0; i < checks; i++) {
        if (completer.isCompleted || changeTriggered) return;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (completer.isCompleted || changeTriggered) return;
      final files = input.files;
      if (files == null || files.isEmpty) {
        completeWith(null);
      }
    });
  });

  input.onChange.first.then((event) async {
    changeTriggered = true;
    final files = input.files;
    if (kDebugMode) {
      debugPrint('File input change -> files=${files?.length ?? 0}');
    }
    if (files == null || files.isEmpty) {
      completeWith(<WebPickedFile>[]);
      return;
    }
    final results = <WebPickedFile>[];
    for (final file in files) {
      if (kDebugMode) {
        debugPrint(
          'Reading file name=${file.name} size=${file.size} type=${file.type}',
        );
      }
      final reader = FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoadEnd.first;
      if (reader.error != null && kDebugMode) {
        debugPrint('FileReader error for ${file.name}: ${reader.error}');
      }
      final buffer = reader.result;
      Uint8List? bytes;
      if (buffer is ByteBuffer) {
        bytes = Uint8List.view(buffer);
      } else if (buffer is Uint8List) {
        bytes = buffer;
      }

      if (bytes != null) {
        if (kDebugMode) {
          debugPrint('Read ${bytes.length} bytes for ${file.name}');
        }
        results.add(
          WebPickedFile(name: file.name, bytes: bytes, mimeType: file.type),
        );
      } else if (kDebugMode) {
        debugPrint(
          'Unexpected reader result for ${file.name}: ${buffer.runtimeType}',
        );
      }
    }
    completeWith(results);
  });

  // The input must be attached to the document to work consistently.
  document.body?.append(input);
  input
    ..style.display = 'none'
    ..value = ''
    ..click();

  return completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () {
      completeWith(null);
      return null;
    },
  );
}

String _buildAcceptString(List<String> allowedExtensions, String? accept) {
  if (accept != null && accept.isNotEmpty) {
    return accept;
  }
  if (allowedExtensions.isEmpty) {
    return '';
  }
  final prefixed = allowedExtensions
      .where((ext) => ext.trim().isNotEmpty)
      .map((ext) => ext.startsWith('.') ? ext : '.$ext')
      .join(',');
  return prefixed;
}
