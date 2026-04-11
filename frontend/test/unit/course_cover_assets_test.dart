import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/utils/course_cover_assets.dart';

void main() {
  test('prefers cover url over slug asset', () {
    final assets = BackendAssetResolver('http://localhost');
    final provider = CourseCoverAssets.resolve(
      assets: assets,
      slug: 'foundations-of-soulwisdom',
      coverUrl: 'https://cdn.test/cover.jpg',
    );

    expect(provider, isA<NetworkImage>());
    final image = provider as NetworkImage;
    expect(image.url, 'https://cdn.test/cover.jpg');
  });

  test('returns null when backend cover url is missing', () {
    final assets = BackendAssetResolver('http://localhost');
    final provider = CourseCoverAssets.resolve(
      assets: assets,
      slug: 'foundations-of-soulwisdom',
      coverUrl: '',
    );

    expect(provider, isNull);
  });
}
