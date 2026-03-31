import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;

import 'package:aveli/shared/models/request_headers.dart';

class CoverUploadPreview {
  const CoverUploadPreview({this.resolvedUrl, this.bytes});

  final String? resolvedUrl;
  final Uint8List? bytes;

  void dispose() {}
}

class CoverUploadFile {
  CoverUploadFile(this.file, this.mimeType, this.size);

  final fs.XFile file;
  final String? mimeType;
  final int size;

  String get name => file.name;

  Future<CoverUploadPreview> buildPreview() async {
    final previewUrl = file.path.isEmpty
        ? null
        : Uri.file(file.path).toString();
    return CoverUploadPreview(
      resolvedUrl: previewUrl,
      bytes: await file.readAsBytes(),
    );
  }
}

Future<CoverUploadFile?> pickCoverFile() async {
  final typeGroup = fs.XTypeGroup(
    label: 'image',
    extensions: const ['jpg', 'jpeg', 'png', 'webp'],
  );
  final file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  final size = await file.length();
  final mimeType = _guessMimeType(file.name);
  return CoverUploadFile(file, mimeType, size);
}

String? _guessMimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return null;
}

Future<void> uploadCoverFile({
  required Uri uploadUrl,
  required RequestHeaders headers,
  required CoverUploadFile file,
  required void Function(int sent, int total) onProgress,
}) async {
  final dio = Dio();
  final stream = file.file.openRead();
  await dio.putUri<void>(
    uploadUrl,
    data: stream,
    options: Options(headers: headers.toMap()),
    onSendProgress: (sent, total) {
      final resolvedTotal = total > 0 ? total : file.size;
      onProgress(sent, resolvedTotal);
    },
  );
}
