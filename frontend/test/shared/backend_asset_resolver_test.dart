import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wisdom/shared/utils/backend_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prefixes relative paths with /assets/', () {
    final resolver = BackendAssetResolver('https://api.example.com');
    expect(
      resolver.url('images/example.png'),
      'https://api.example.com/assets/images/example.png',
    );
    expect(
      resolver.url('/assets/icons/icon.svg'),
      'https://api.example.com/assets/icons/icon.svg',
    );
  });

  test('returns relative URL when base is empty', () {
    final resolver = BackendAssetResolver('');
    expect(resolver.url('images/foo.png'), '/assets/images/foo.png');
  });

  test('passes through absolute URLs unchanged', () {
    final resolver = BackendAssetResolver('https://api.example.com');
    const absolute = 'https://cdn.example.com/foo.png';
    expect(resolver.url(absolute), absolute);
  });

  test('creates NetworkImage providers', () {
    final resolver = BackendAssetResolver('https://api.example.com');
    final provider = resolver.imageProvider('images/foo.png');
    expect(provider, isA<NetworkImage>());
    final image = provider as NetworkImage;
    expect(image.url, 'https://api.example.com/assets/images/foo.png');
  });
}
