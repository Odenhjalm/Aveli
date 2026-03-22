// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html';
import 'dart:typed_data';

class CoverUploadPreview {
  CoverUploadPreview({this.resolvedUrl, this.bytes});

  final String? resolvedUrl;
  final Uint8List? bytes;

  void dispose() {
    final url = resolvedUrl;
    if (url == null || url.isEmpty || !url.startsWith('blob:')) return;
    Url.revokeObjectUrl(url);
  }
}

class CoverUploadFile {
  CoverUploadFile(this.file);

  final File file;

  String get name => file.name;
  int get size => file.size;
  String? get mimeType => file.type.isEmpty ? null : file.type;

  Future<CoverUploadPreview> buildPreview() async {
    final reader = FileReader();
    final completer = Completer<Uint8List>();

    reader.onLoad.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(Uint8List.view(result));
        return;
      }
      if (result is Uint8List) {
        completer.complete(result);
        return;
      }
      completer.completeError(StateError('Unsupported preview buffer'));
    });
    reader.onError.listen((_) {
      completer.completeError(StateError('Failed to build cover preview'));
    });
    reader.readAsArrayBuffer(file);

    return CoverUploadPreview(
      resolvedUrl: Url.createObjectUrl(file),
      bytes: await completer.future,
    );
  }
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
      completer.completeError(StateError('Upload failed with status $status'));
    }
  });

  request.onError.listen((_) {
    completer.completeError(StateError('Upload failed'));
  });

  request.send(file.file);
  return completer.future;
}
