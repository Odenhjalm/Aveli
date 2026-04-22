import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _transparentPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

void installTestAssetBundle() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final transparentData = ByteData.view(
    Uint8List.fromList(_transparentPng).buffer,
  );

  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    message,
  ) async {
    final key = const StringCodec().decodeMessage(message) ?? '';
    if (key == 'AssetManifest.json') {
      return ByteData.view(Uint8List.fromList(utf8.encode('{}')).buffer);
    }
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, dynamic>{});
    }
    if (key == 'FontManifest.json') {
      return ByteData.view(Uint8List.fromList(utf8.encode('[]')).buffer);
    }
    if (key == 'NOTICES' || key == 'LICENSES') {
      return ByteData.view(Uint8List.fromList(utf8.encode('')).buffer);
    }
    return transparentData;
  });
}
