import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;

class CoverUploadFile {
  CoverUploadFile(this.file, this.mimeType, this.size);

  final fs.XFile file;
  final String? mimeType;
  final int size;

  String get name => file.name;
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
  required Map<String, String> headers,
  required CoverUploadFile file,
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
