import 'dart:async';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;

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

Future<void> uploadWavFile({
  required Uri uploadUrl,
  required Map<String, String> headers,
  required WavUploadFile file,
  required void Function(int sent, int total) onProgress,
}) async {
  final dio = Dio();
  final length = file.size;
  final stream = file.file.openRead();
  final uploadHeaders = <String, String>{...headers};
  uploadHeaders['content-length'] = length.toString();
  await dio.putUri<void>(
    uploadUrl,
    data: stream,
    options: Options(
      headers: uploadHeaders,
      contentType: file.mimeType ?? 'audio/wav',
    ),
    onSendProgress: (sent, total) {
      final resolvedTotal = total > 0 ? total : length;
      onProgress(sent, resolvedTotal);
    },
  );
}
