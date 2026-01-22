// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html';

class WavUploadFile {
  WavUploadFile(this.file);

  final File file;

  String get name => file.name;
  int get size => file.size;
  String? get mimeType => file.type;
}

Future<WavUploadFile?> pickWavFile() async {
  final input = FileUploadInputElement()
    ..accept = '.wav,audio/wav,audio/x-wav'
    ..multiple = false;

  final completer = Completer<WavUploadFile?>();

  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      input.remove();
      return;
    }
    completer.complete(WavUploadFile(files.first));
    input.remove();
  });

  document.body?.append(input);
  input
    ..style.display = 'none'
    ..value = ''
    ..click();

  return completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () => null,
  );
}

Future<void> uploadWavFile({
  required Uri uploadUrl,
  required Map<String, String> headers,
  required WavUploadFile file,
  required void Function(int sent, int total) onProgress,
}) async {
  final completer = Completer<void>();
  final request = HttpRequest();

  request
    ..open('PUT', uploadUrl.toString())
    ..responseType = 'text';

  headers.forEach(request.setRequestHeader);

  request.upload.onProgress.listen((event) {
    final loaded = (event.loaded ?? 0).toInt();
    final total = (event.total ?? 0).toInt();
    final totalBytes = total > 0 ? total : file.size;
    onProgress(loaded, totalBytes);
  });

  request.onLoadEnd.listen((_) {
    final status = request.status ?? 0;
    if (status >= 200 && status < 300) {
      completer.complete();
    } else {
      completer.completeError(
        StateError('Upload failed with status $status'),
      );
    }
  });

  request.onError.listen((_) {
    completer.completeError(StateError('Upload failed'));
  });

  request.send(file.file);
  return completer.future;
}
