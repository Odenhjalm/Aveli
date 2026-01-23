import 'dart:async';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;

import 'wav_upload_types.dart';

class WavUploadFile {
  WavUploadFile(this.file, this.mimeType, this.size);

  final fs.XFile file;
  final String? mimeType;
  final int size;

  String get name => file.name;
}

Future<WavUploadFile?> pickWavFile() async {
  final typeGroup = fs.XTypeGroup(label: 'wav', extensions: const ['wav']);
  final file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  final size = await file.length();
  return WavUploadFile(file, 'audio/wav', size);
}

WavResumableSession? findResumableSession({
  required String courseId,
  required String lessonId,
  required WavUploadFile file,
}) {
  return null;
}

Future<void> uploadWavFile({
  required String mediaId,
  required String courseId,
  required String lessonId,
  required Uri uploadUrl,
  required String objectPath,
  required Map<String, String> headers,
  required WavUploadFile file,
  required String contentType,
  required void Function(int sent, int total) onProgress,
  WavUploadCancelToken? cancelToken,
  void Function(bool resumed)? onResume,
  WavResumableSession? resumableSession,
}) async {
  if (cancelToken?.isCancelled == true) {
    throw const WavUploadFailure(WavUploadFailureKind.cancelled);
  }

  final dio = Dio();
  final dioCancel = CancelToken();
  cancelToken?.onCancel(dioCancel.cancel);

  try {
    final stream = file.file.openRead();
    await dio.putUri<void>(
      uploadUrl,
      data: stream,
      options: Options(
        headers: Map<String, String>.from(headers),
      ),
      cancelToken: dioCancel,
      onSendProgress: (sent, total) {
        final resolvedTotal = total > 0 ? total : file.size;
        onProgress(sent, resolvedTotal);
      },
    );
  } on DioException catch (error) {
    if (error.type == DioExceptionType.cancel) {
      throw const WavUploadFailure(WavUploadFailureKind.cancelled);
    }
    throw WavUploadFailure(WavUploadFailureKind.failed, detail: error.message);
  } catch (error) {
    throw WavUploadFailure(WavUploadFailureKind.failed, detail: error.toString());
  }
}
