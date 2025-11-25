import 'dart:typed_data';

class WebPickedFile {
  WebPickedFile({required this.name, required this.bytes, this.mimeType});

  final String name;
  final Uint8List bytes;
  final String? mimeType;
}

Future<List<WebPickedFile>?> pickFilesFromHtml({
  required List<String> allowedExtensions,
  required bool allowMultiple,
  String? accept,
}) async {
  return null;
}
