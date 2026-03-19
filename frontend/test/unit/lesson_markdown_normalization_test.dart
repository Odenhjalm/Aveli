import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/utils/lesson_content_pipeline.dart';

String _jwtForSub(String sub) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': sub})))
      .replaceAll('=', '');
  return '$header.$payload.signature';
}

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

class _FakeMediaPipelineRepository extends MediaPipelineRepository {
  _FakeMediaPipelineRepository(this._playbackUrl)
    : super(
        client: ApiClient(
          baseUrl: 'https://api.example.com',
          tokenStorage: _FakeTokenStorage(),
        ),
      );

  final String _playbackUrl;

  @override
  Future<String> fetchLessonPlaybackUrl(String lessonMediaId) async =>
      _playbackUrl;
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
        () => normalizeLessonMarkdownForStorage(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'rewrites /api/files URLs to /studio/media URLs when mapping exists',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        const apiPath = '/api/files/public-media/course/lesson/file.png';
        const absUrl = 'https://api.example.com$apiPath?download=1';
        final markdown = '<audio controls src="$absUrl"></audio>';

        final rewritten = rewriteLessonMarkdownApiFilesUrls(
          markdown: markdown,
          apiFilesPathToStudioMediaUrl: {apiPath: '/studio/media/$id'},
        );

        expect(rewritten, contains('/studio/media/$id'));
        expect(rewritten, isNot(contains(absUrl)));
      },
    );

    test('rejects raw /media/stream token URLs on write', () {
      const id = '123e4567-e89b-12d3-a456-426614174000';
      final token = _jwtForSub(id);
      final markdown = '![alt](/media/stream/$token)';

      expect(
        () => normalizeLessonMarkdownForStorage(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test('normalizes internal document links into canonical tokens', () {
      const id = '123e4567-e89b-12d3-a456-426614174010';
      final markdown = '[📄 guide.pdf](${lessonMediaDocumentLinkUrl(id)})';

      final normalized = normalizeLessonMarkdownForStorage(markdown);

      expect(normalized, '!document($id)');
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
        () => normalizeLessonMarkdownForStorage(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects unsupported HTML media tags before storage', () {
      const markdown = '<video src="https://cdn.test/legacy.mp4"></video>';

      expect(
        () => normalizeLessonMarkdownForStorage(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects raw markdown image URLs before storage', () {
      const markdown = '![alt](https://cdn.test/legacy.png)';

      expect(
        () => normalizeLessonMarkdownForStorage(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects raw lesson document links before storage', () {
      const id = '123e4567-e89b-12d3-a456-426614174011';
      const markdown = '[📄 guide.pdf](/studio/media/$id)';

      expect(
        () => normalizeLessonMarkdownForStorage(markdown),
        throwsA(isA<StateError>()),
      );
    });

    test('legacy video detection: empty and invalid URLs are legacy', () {
      expect(isLegacyVideoEmbed(''), isTrue);
      expect(isLegacyVideoEmbed('ftp://cdn.test/legacy.mp4'), isTrue);
      expect(isLegacyVideoEmbed('/studio/media/legacy-path'), isTrue);
    });

    test('legacy video detection: valid HTTPS embed is not legacy', () {
      expect(isLegacyVideoEmbed('https://cdn.test/video.mp4'), isFalse);
    });

    test(
      'legacy video detection: lesson media marker without playback URL is legacy',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        final payload = jsonEncode({'lesson_media_id': id, 'kind': 'video'});
        expect(isLegacyVideoEmbed(payload), isTrue);
      },
    );

    test(
      'legacy video detection: structured payload with valid playback URL is not legacy',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        final payload = jsonEncode({
          'lesson_media_id': id,
          'kind': 'video',
          'src': 'https://cdn.test/video.mp4',
        });
        expect(isLegacyVideoEmbed(payload), isFalse);
      },
    );

    test(
      'rendering preparation resolves canonical video tokens without rewriting legacy embeds',
      () async {
        final mediaRepository = _buildMediaRepository();
        final pipelineRepository = _FakeMediaPipelineRepository(
          'https://cdn.example.com/video.mp4',
        );

        const legacyMarkdown =
            'Introtext\n\n<video src="ftp://cdn.test/legacy.mp4"></video>\n\nEftertext';
        final preparedLegacy = await prepareLessonMarkdownForRendering(
          mediaRepository,
          legacyMarkdown,
          pipelineRepository: pipelineRepository,
        );

        expect(preparedLegacy, contains('ftp://cdn.test/legacy.mp4'));
        expect(preparedLegacy, isNot(contains('https://cdn.example.com')));

        const canonicalMarkdown =
            'Introtext\n\n!video(media-replacement)\n\nEftertext';
        final preparedCanonical = await prepareLessonMarkdownForRendering(
          mediaRepository,
          canonicalMarkdown,
          lessonMedia: const [
            LessonMediaItem(
              id: 'media-replacement',
              kind: 'video',
              storagePath: 'lesson-1/replacement.mp4',
              originalName: 'replacement.mp4',
              position: 1,
            ),
          ],
          pipelineRepository: pipelineRepository,
        );

        expect(
          preparedCanonical,
          contains('https://cdn.example.com/video.mp4'),
        );
        expect(
          preparedCanonical,
          isNot(contains('/studio/media/media-replacement')),
        );
      },
    );

    test(
      'rendering preparation resolves canonical document tokens via lesson playback authority',
      () async {
        final mediaRepository = _buildMediaRepository();
        final pipelineRepository = _FakeMediaPipelineRepository(
          'https://cdn.example.com/guide.pdf',
        );

        const markdown = 'Introtext\n\n!document(media-document)\n';
        final prepared = await prepareLessonMarkdownForRendering(
          mediaRepository,
          markdown,
          lessonMedia: const [
            LessonMediaItem(
              id: 'media-document',
              kind: 'document',
              storagePath: 'lesson-1/docs/guide.pdf',
              originalName: 'guide.pdf',
              position: 1,
            ),
          ],
          pipelineRepository: pipelineRepository,
        );

        expect(
          prepared,
          contains('[📄 guide.pdf](https://cdn.example.com/guide.pdf)'),
        );
        expect(prepared, isNot(contains('/studio/media/media-document')));
      },
    );
  });
}
