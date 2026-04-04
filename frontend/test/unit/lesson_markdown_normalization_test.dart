import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/lesson_content_pipeline.dart';

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> updateAccessToken(String accessToken) async {}
}

MediaRepository _buildMediaRepository() {
  final client = ApiClient(
    baseUrl: 'https://api.example.com',
    tokenStorage: _FakeTokenStorage(),
  );
  return MediaRepository(
    client: client,
    config: const AppConfig(
      apiBaseUrl: 'https://api.example.com',
      stripePublishableKey: 'pk_test_123',
      stripeMerchantDisplayName: 'Aveli',
      subscriptionsEnabled: true,
      supabaseUrl: 'https://project.supabase.co',
    ),
  );
}

void main() {
  group('Lesson markdown normalization', () {
    test('rejects raw /studio/media image URLs on write', () {
      const id = '123e4567-e89b-12d3-a456-426614174000';
      final markdown = '![alt](https://api.example.com/studio/media/$id)';

      expect(
        () => enforceLessonMarkdownStorageContract(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'does not rewrite /api/files URLs in canonical runtime',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        const apiPath = '/api/files/public-media/course/lesson/file.png';
        const absUrl = 'https://api.example.com$apiPath?download=1';
        final markdown = '<audio controls src="$absUrl"></audio>';

        final rewritten = rewriteLessonMarkdownApiFilesUrls(
          markdown: markdown,
          apiFilesPathToStudioMediaUrl: {apiPath: '/studio/media/$id'},
        );

        expect(rewritten, markdown);
      },
    );

    test('document link helper encodes and decodes canonical ids', () {
      const id = '123e4567-e89b-12d3-a456-426614174010';
      final encoded = lessonMediaDocumentLinkUrl(id);

      expect(lessonMediaIdFromDocumentLinkUrl(encoded), id);
    });

    test('rejects HTML media tags even when they target lesson media', () {
      const imageId = '123e4567-e89b-12d3-a456-426614174001';
      const audioId = '123e4567-e89b-12d3-a456-426614174002';
      const videoId = '123e4567-e89b-12d3-a456-426614174003';
      const markdown =
          '''
<img src="/studio/media/$imageId">

<audio src="/studio/media/$audioId"></audio>

<video src="/studio/media/$videoId"></video>
''';

      expect(
        () => enforceLessonMarkdownStorageContract(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects unsupported HTML media tags before storage', () {
      const markdown = '<video src="https://cdn.test/legacy.mp4"></video>';

      expect(
        () => enforceLessonMarkdownStorageContract(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects raw markdown image URLs before storage', () {
      const markdown = '![alt](https://cdn.test/legacy.png)';

      expect(
        () => enforceLessonMarkdownStorageContract(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects raw lesson document links before storage', () {
      const id = '123e4567-e89b-12d3-a456-426614174011';
      const markdown = '[📄 guide.pdf](/studio/media/$id)';

      expect(
        () => enforceLessonMarkdownStorageContract(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'rendering preparation leaves legacy embeds untouched',
      () async {
        final mediaRepository = _buildMediaRepository();

        const legacyMarkdown =
            'Introtext\n\n<video src="ftp://cdn.test/legacy.mp4"></video>\n\nEftertext';
        final preparedLegacy = await prepareLessonMarkdownForRendering(
          mediaRepository,
          legacyMarkdown,
        );

        expect(preparedLegacy, legacyMarkdown);
      },
    );

    test(
      'rendering preparation preserves canonical video tokens for render-only surfaces',
      () async {
        final mediaRepository = _buildMediaRepository();

        const canonicalMarkdown =
            'Introtext\n\n!video(media-replacement)\n\nEftertext';
        final preparedCanonical = await prepareLessonMarkdownForRendering(
          mediaRepository,
          canonicalMarkdown,
        );

        expect(preparedCanonical, canonicalMarkdown);
      },
    );

    test(
      'rendering preparation preserves canonical document tokens for render-only surfaces',
      () async {
        final mediaRepository = _buildMediaRepository();

        const markdown = 'Introtext\n\n!document(media-document)\n';
        final prepared = await prepareLessonMarkdownForRendering(
          mediaRepository,
          markdown,
        );

        expect(prepared, markdown);
      },
    );
  });
}
