import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;

import 'wav_upload_types.dart';

class WavUploadFile {
  WavUploadFile(this.file, this.mimeType, this.size);

  final fs.XFile file;
  final String? mimeType;
  final int size;

  String get name => file.name;

  Future<Uint8List> readAsBytes() => file.readAsBytes();

  Future<Uint8List> readRangeBytes(int start, int endExclusive) async {
    if (start < 0 || endExclusive < start) {
      throw RangeError.range(start, 0, endExclusive, 'start');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(start, endExclusive)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

String _mimeTypeForAudioSource(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.mp3')) {
    return 'audio/mpeg';
  }
  if (lower.endsWith('.m4a')) {
    return 'audio/m4a';
  }
  return 'audio/wav';
}

Future<WavUploadFile?> pickWavFile() async {
  final typeGroup = fs.XTypeGroup(
    label: 'mp3/wav/m4a',
    extensions: const ['mp3', 'wav', 'm4a'],
  );
  final file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  final size = await file.length();
  return WavUploadFile(file, _mimeTypeForAudioSource(file.name), size);
}

Future<WavUploadFile?> pickMediaFile() async {
  const extensions = <String>['mp3', 'm4a', 'aac', 'ogg', 'wav'];

  final typeGroup = fs.XTypeGroup(label: 'audio', extensions: extensions);
  final file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  final size = await file.length();
  return WavUploadFile(file, null, size);
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

  final dio = Dio();
  final dioCancel = CancelToken();
  cancelToken?.onCancel(dioCancel.cancel);

  try {
    final start = byteStart;
    final end = byteEndExclusive;
    final data = bodyBytes ?? file.file.openRead(start, end);
    final payloadSize =
        bodyBytes?.length ??
        ((start != null && end != null) ? end - start : file.size);
    final requestHeaders = Map<String, String>.from(headers);
    if (bodyBytes != null) {
      requestHeaders[Headers.contentLengthHeader] = '${bodyBytes.length}';
    }
    await dio.putUri<void>(
      uploadEndpoint,
      data: data,
      options: Options(contentType: contentType, headers: requestHeaders),
      cancelToken: dioCancel,
      onSendProgress: (sent, total) {
        final resolvedTotal = total > 0 ? total : payloadSize;
        onProgress(sent, resolvedTotal);
      },
    );
  } on DioException catch (error) {
    if (error.type == DioExceptionType.cancel) {
      throw const WavUploadFailure(WavUploadFailureKind.cancelled);
    }
    throw WavUploadFailure(WavUploadFailureKind.failed, detail: error.message);
  } catch (error) {
    throw WavUploadFailure(
      WavUploadFailureKind.failed,
      detail: error.toString(),
    );
  }
}
