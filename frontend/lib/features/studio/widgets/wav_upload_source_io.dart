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
  final stream = file.file.openRead();
  await dio.putUri<void>(
    uploadUrl,
    data: stream,
    options: Options(
      headers: Map<String, String>.from(headers),
    ),
    onSendProgress: (sent, total) {
      final resolvedTotal = total > 0 ? total : file.size;
      onProgress(sent, resolvedTotal);
    },
  );
}
