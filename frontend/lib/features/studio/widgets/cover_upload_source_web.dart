// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html';

class CoverUploadFile {
  CoverUploadFile(this.file);

  final File file;

  String get name => file.name;
  int get size => file.size;
  String? get mimeType => file.type.isEmpty ? null : file.type;
}

Future<CoverUploadFile?> pickCoverFile() async {
  final input = FileUploadInputElement()
    ..accept = '.jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp'
    ..multiple = false;

  final completer = Completer<CoverUploadFile?>();

  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      input.remove();
      return;
    }
    completer.complete(CoverUploadFile(files.first));
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

Future<void> uploadCoverFile({
  required Uri uploadUrl,
  required Map<String, String> headers,
  required CoverUploadFile file,
  required void Function(int sent, int total) onProgress,
}) async {
  final completer = Completer<void>();
  final request = HttpRequest();

  request
    ..open('PUT', uploadUrl.toString())
    ..responseType = 'text';

  headers.forEach(request.setRequestHeader);

  request.upload.onProgress.listen((event) {
    final total = event.total > 0 ? event.total : file.size;
    onProgress(event.loaded.toInt(), total.toInt());
  });

  request.onLoadEnd.listen((_) {
    if (request.status >= 200 && request.status < 300) {
      completer.complete();
    } else {
      completer.completeError(
        StateError('Upload failed with status ${request.status}'),
      );
    }
  });

  request.onError.listen((_) {
    completer.completeError(StateError('Upload failed'));
  });

  request.send(file.file);
  return completer.future;
}
