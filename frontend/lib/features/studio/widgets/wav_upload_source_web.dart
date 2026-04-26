// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html';
import 'dart:typed_data';

import 'wav_upload_types.dart';

class WavUploadFile {
  WavUploadFile(this.file);

  final File file;

  String get name => file.name;
  int get size => file.size;
  String? get mimeType => file.type.isEmpty ? null : file.type;
  int? get lastModified => file.lastModified;

  Future<Uint8List> _readBlobBytes(Blob blob) async {
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
      completer.completeError(StateError('Unsupported upload buffer'));
    });
    reader.onError.listen((_) {
      completer.completeError(StateError('Failed to read upload bytes'));
    });
    reader.readAsArrayBuffer(blob);

    return completer.future;
  }

  Future<Uint8List> readAsBytes() async => _readBlobBytes(file);

  Future<Uint8List> readRangeBytes(int start, int endExclusive) async {
    if (start < 0 || endExclusive < start) {
      throw RangeError.range(start, 0, endExclusive, 'start');
    }
    return _readBlobBytes(file.slice(start, endExclusive));
  }
}

Future<WavUploadFile?> pickWavFile() async {
  final input = FileUploadInputElement()
    ..accept =
        '.mp3,.wav,.m4a,audio/mpeg,audio/mp3,audio/wav,audio/x-wav,audio/m4a,audio/mp4'
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

Future<WavUploadFile?> pickMediaFile() async {
  final input = FileUploadInputElement()
    ..accept =
        '.mp3,.wav,.m4a,.aac,.ogg,audio/mpeg,audio/mp3,audio/wav,audio/x-wav,audio/mp4,audio/aac,audio/ogg'
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

Future<WavResumableSession?> findResumableSession({
  required String courseId,
  required String lessonId,
  required WavUploadFile file,
}) async {
  return null;
}

void clearResumableSession(WavResumableSession session) {}

Future<void> uploadWavFile({
  required Uri uploadEndpoint,
  required WavUploadFile file,
  required String contentType,
  Map<String, String> headers = const <String, String>{},
  required void Function(int sent, int total) onProgress,
  WavUploadCancelToken? cancelToken,
  int? byteStart,
  int? byteEndExclusive,
  int? totalBytes,
  Uint8List? bodyBytes,
}) async {
  if (cancelToken?.isCancelled == true) {
    throw const WavUploadFailure(WavUploadFailureKind.cancelled);
  }

  final request = HttpRequest();
  final completer = Completer<void>();

  request
    ..open('PUT', uploadEndpoint.toString())
    ..responseType = 'text';
  request.setRequestHeader('Content-Type', contentType);
  headers.forEach((key, value) {
    if (key.toLowerCase() == 'content-type') return;
    request.setRequestHeader(key, value);
  });

  cancelToken?.onCancel(request.abort);

  final start = byteStart;
  final end = byteEndExclusive;
  final payloadSize =
      bodyBytes?.length ??
      ((start != null && end != null) ? end - start : file.size);

  request.upload.onProgress.listen((event) {
    final loaded = (event.loaded ?? 0).toInt();
    final total = (event.total ?? 0).toInt();
    final resolvedTotal = total > 0 ? total : payloadSize;
    onProgress(loaded, resolvedTotal);
  });

  request.onAbort.listen((_) {
    if (completer.isCompleted) return;
    completer.completeError(
      const WavUploadFailure(WavUploadFailureKind.cancelled),
    );
  });

  request.onError.listen((_) {
    if (completer.isCompleted) return;
    completer.completeError(
      const WavUploadFailure(WavUploadFailureKind.failed),
    );
  });

  request.onLoadEnd.listen((_) {
    if (completer.isCompleted) return;
    final status = request.status ?? 0;
    if (status >= 200 && status < 300) {
      completer.complete();
      return;
    }
    completer.completeError(
      WavUploadFailure(WavUploadFailureKind.failed, detail: 'put:$status'),
    );
  });

  request.send(
    bodyBytes ??
        ((start != null && end != null)
            ? file.file.slice(start, end)
            : file.file),
  );
  return completer.future;
}
