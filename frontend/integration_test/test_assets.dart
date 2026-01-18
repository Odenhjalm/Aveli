import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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

final Uint8List transparentPngBytes = Uint8List.fromList(_transparentPng);
final MemoryImage transparentImageProvider = MemoryImage(transparentPngBytes);

ByteData _utf8Bytes(String value) {
  return ByteData.view(Uint8List.fromList(utf8.encode(value)).buffer);
}

class TestAssetBundle extends CachingAssetBundle {
  TestAssetBundle._();

  static final TestAssetBundle instance = TestAssetBundle._();

  static String _emptyManifestBase64() {
    final encoded =
        const StandardMessageCodec().encodeMessage(<String, dynamic>{}) ??
        ByteData(0);
    final bytes = encoded.buffer.asUint8List(
      encoded.offsetInBytes,
      encoded.lengthInBytes,
    );
    return json.encode(base64.encode(bytes));
  }

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.json') {
      return _utf8Bytes('{}');
    }
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, dynamic>{}) ??
          ByteData(0);
    }
    if (key == 'AssetManifest.bin.json') {
      return _utf8Bytes(_emptyManifestBase64());
    }
    if (key == 'FontManifest.json') {
      return _utf8Bytes('[]');
    }
    if (key == 'NOTICES' || key == 'LICENSES') {
      return _utf8Bytes('');
    }
    return ByteData.view(transparentPngBytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'AssetManifest.json') return '{}';
    if (key == 'AssetManifest.bin.json') return _emptyManifestBase64();
    if (key == 'FontManifest.json') return '[]';
    if (key == 'NOTICES' || key == 'LICENSES') return '';
    return '';
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async {
    if (key == 'AssetManifest.json') {
      return parser('{}');
    }
    if (key == 'AssetManifest.bin.json') {
      return parser(_emptyManifestBase64());
    }
    if (key == 'FontManifest.json') {
      return parser('[]');
    }
    if (key == 'NOTICES' || key == 'LICENSES') {
      return parser('');
    }
    return super.loadStructuredData(key, parser);
  }
}

void registerTestAssetHandlers() {
  ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
    'flutter/assets',
    (message) async {
      final key = const StringCodec().decodeMessage(message) ?? '';
      return TestAssetBundle.instance.load(key);
    },
  );
}

Widget wrapWithTestAssets(Widget child) {
  return DefaultAssetBundle(
    bundle: TestAssetBundle.instance,
    child: child,
  );
}
