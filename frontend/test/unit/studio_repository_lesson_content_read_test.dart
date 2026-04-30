import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/data/models/text_bundle.dart';
import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

import '../helpers/lesson_document_fixture_corpus.dart';

const imageMediaId = '11111111-1111-4111-8111-111111111111';
const audioMediaId = '22222222-2222-4222-8222-222222222222';
const videoMediaId = '33333333-3333-4333-8333-333333333333';
const documentMediaId = '44444444-4444-4444-8444-444444444444';

void main() {
  test(
    'LessonStudio rejects content authority fields in structure responses',
    () {
      expect(
        () => LessonStudio.fromResponse({
          'id': 'lesson-1',
          'course_id': 'course-1',
          'lesson_title': 'Lektion',
          'position': 1,
          'content_markdown': '# Persisted',
          'content_document': _lessonDocumentJson('Persisted'),
          'media': const [],
          'etag': '"content-v1"',
        }),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'readLessonContent uses dedicated content endpoint and preserves ETag',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/studio/lessons/lesson-1/content' &&
            options.method.toUpperCase() == 'GET') {
          return _jsonResponse(
            statusCode: 200,
            headers: {
              'etag': ['"content-v1"'],
            },
            body: {
              'lesson_id': 'lesson-1',
              'content_document': _lessonDocumentJson('Persisted'),
              'media': [
                {
                  'lesson_media_id': 'lesson-media-1',
                  'media_asset_id': 'media-1',
                  'position': 1,
                  'media_type': 'image',
                  'state': 'ready',
                },
              ],
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = StudioRepository(client: _clientWith(adapter));

      final result = await repo.readLessonContent('lesson-1');

      expect(result.lessonId, 'lesson-1');
      expect(
        result.contentDocument.toCanonicalJsonString(),
        LessonDocument(
          blocks: const [
            LessonParagraphBlock(children: [LessonTextRun('Persisted')]),
          ],
        ).toCanonicalJsonString(),
      );
      expect(result.etag, '"content-v1"');
      expect(result.media.single.lessonMediaId, 'lesson-media-1');
      expect(result.media.single.mediaAssetId, 'media-1');
      expect(result.media.single.mediaType, 'image');

      final requests = adapter.requestsFor('/studio/lessons/lesson-1/content');
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
    },
  );

  test(
    'readLessonContent hydrates media and CTA document nodes without markdown',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/studio/lessons/lesson-1/content' &&
            options.method.toUpperCase() == 'GET') {
          return _jsonResponse(
            statusCode: 200,
            headers: {
              'etag': ['"content-v1"'],
            },
            body: {
              'lesson_id': 'lesson-1',
              'content_document': _mediaCtaDocumentJson(),
              'media': [
                _contentMediaItem(imageMediaId, 'image'),
                _contentMediaItem(audioMediaId, 'audio'),
                _contentMediaItem(videoMediaId, 'video'),
                _contentMediaItem(documentMediaId, 'document'),
              ],
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = StudioRepository(client: _clientWith(adapter));

      final result = await repo.readLessonContent('lesson-1');

      expect(result.contentDocument.blocks, hasLength(5));
      expect(
        result.contentDocument.blocks.whereType<LessonMediaBlock>().map(
          (block) => '${block.mediaType}:${block.lessonMediaId}',
        ),
        [
          'image:$imageMediaId',
          'audio:$audioMediaId',
          'video:$videoMediaId',
          'document:$documentMediaId',
        ],
      );
      expect(
        (result.contentDocument.blocks.last as LessonCtaBlock).targetUrl,
        '/book',
      );
      expect(result.media, hasLength(4));
    },
  );

  test(
    'readLessonViewSurfacePreview uses canonical lesson view preview endpoint',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/courses/lessons/lesson-1' &&
            options.method.toUpperCase() == 'GET' &&
            options.queryParameters['preview'] == true) {
          return _jsonResponse(
            statusCode: 200,
            body: {
              'lesson': {
                'id': 'lesson-1',
                'course_id': 'course-1',
                'lesson_title': 'Preview lesson',
                'position': 1,
                'content_document': _lessonDocumentJson('Preview'),
              },
              'navigation': {
                'previous_lesson_id': null,
                'next_lesson_id': 'lesson-2',
              },
              'access': {
                'has_access': true,
                'is_enrolled': false,
                'is_in_drip': false,
                'is_premium': true,
                'can_enroll': false,
                'can_purchase': false,
              },
              'cta': {
                'type': 'continue',
                'text_id': 'lesson.cta.continue',
                'enabled': true,
                'reason_code': null,
                'reason_text': null,
                'price': null,
                'action': {'type': 'continue'},
              },
              'text_bundles': [_courseCtaBundle(), _courseLessonChromeBundle()],
              'pricing': {
                'price_amount_cents': 12000,
                'price_currency': 'sek',
                'formatted': '120 SEK',
              },
              'progression': {'unlocked': true, 'reason': 'available'},
              'media': [
                {
                  'lesson_media_id': imageMediaId,
                  'position': 1,
                  'media_type': 'image',
                  'media': {
                    'media_id': 'media-image',
                    'state': 'ready',
                    'resolved_url': 'https://cdn.test/image.webp',
                  },
                },
              ],
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = StudioRepository(client: _clientWith(adapter));

      final result = await repo.readLessonViewSurfacePreview('lesson-1');

      expect(result.lesson.id, 'lesson-1');
      expect(result.lesson.lessonTitle, 'Preview lesson');
      expect(
        result.lesson.contentDocument?.toCanonicalJsonString(),
        LessonDocument(
          blocks: const [
            LessonParagraphBlock(children: [LessonTextRun('Preview')]),
          ],
        ).toCanonicalJsonString(),
      );
      expect(result.navigation.nextLessonId, 'lesson-2');
      expect(result.progression.reason, 'available');
      expect(result.cta?.textId, 'lesson.cta.continue');
      expect(
        resolveText(result.cta!.textId, result.textBundles),
        'Forts\u00e4tt',
      );
      expect(
        result.textBundles.map((bundle) => bundle.bundleId),
        containsAll(['course_cta.v1', 'course_lesson.chrome.v1']),
      );
      expect(result.pricing?.formatted, '120 SEK');
      expect(result.media.single.lessonMediaId, imageMediaId);
      expect(
        result.media.single.media.resolvedUrl,
        'https://cdn.test/image.webp',
      );

      final lessonViewRequests = adapter.requestsFor(
        '/courses/lessons/lesson-1',
      );
      expect(lessonViewRequests, hasLength(1));
      expect(lessonViewRequests.single.method, 'GET');
      expect(lessonViewRequests.single.queryParameters, {'preview': true});
      expect(adapter.requestsFor('/studio/lessons/lesson-1/content'), isEmpty);
      expect(
        adapter.requestsFor('/api/media-placements/$imageMediaId'),
        isEmpty,
      );
    },
  );

  test('updateLessonContent carries If-Match and replacement ETag', () async {
    final corpus = loadLessonDocumentFixtureCorpus();
    final updatedDocument = corpus.document(
      'etag_concurrency',
      field: 'updated_document',
    );
    final adapter = _RecordingAdapter((options) {
      if (options.path == '/studio/lessons/lesson-1/content' &&
          options.method.toUpperCase() == 'PATCH') {
        return _jsonResponse(
          statusCode: 200,
          headers: {
            'etag': ['"content-v2"'],
          },
          body: {
            'lesson_id': 'lesson-1',
            'content_document': updatedDocument.toJson(),
          },
        );
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    final repo = StudioRepository(client: _clientWith(adapter));

    final result = await repo.updateLessonContent(
      'lesson-1',
      contentDocument: updatedDocument,
      ifMatch: ' "content-v1" ',
    );

    expect(result.lessonId, 'lesson-1');
    expect(
      result.contentDocument.toCanonicalJsonString(),
      contains('ETag version two'),
    );
    expect(result.etag, '"content-v2"');

    final requests = adapter.requestsFor('/studio/lessons/lesson-1/content');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'PATCH');
    expect(requests.single.headers['If-Match'], '"content-v1"');
    expect(Map<String, dynamic>.from(requests.single.data as Map), {
      'content_document': updatedDocument.toJson(),
    });
  });

  test(
    'updateLessonContent saves media and CTA nodes as content_document',
    () async {
      final document = LessonDocument.fromJson(_mediaCtaDocumentJson());
      final adapter = _RecordingAdapter((options) {
        if (options.path == '/studio/lessons/lesson-1/content' &&
            options.method.toUpperCase() == 'PATCH') {
          return _jsonResponse(
            statusCode: 200,
            headers: {
              'etag': ['"content-v2"'],
            },
            body: {
              'lesson_id': 'lesson-1',
              'content_document': document.toJson(),
            },
          );
        }
        return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
      });
      final repo = StudioRepository(client: _clientWith(adapter));

      final result = await repo.updateLessonContent(
        'lesson-1',
        contentDocument: document,
        ifMatch: '"content-v1"',
      );

      expect(result.contentDocument.toJson(), document.toJson());
      final request = adapter
          .requestsFor('/studio/lessons/lesson-1/content')
          .single;
      final payload = Map<String, dynamic>.from(request.data as Map);
      expect(payload, isNot(contains('content_markdown')));
      expect(payload, contains('content_document'));
      final savedDocument = Map<String, dynamic>.from(
        payload['content_document'] as Map,
      );
      final blocks = List<Map<String, dynamic>>.from(
        (savedDocument['blocks'] as List).map(
          (block) => Map<String, dynamic>.from(block as Map),
        ),
      );
      expect(
        blocks
            .where((block) => block['type'] == 'media')
            .map(
              (block) => '${block['media_type']}:${block['lesson_media_id']}',
            ),
        [
          'image:$imageMediaId',
          'audio:$audioMediaId',
          'video:$videoMediaId',
          'document:$documentMediaId',
        ],
      );
      expect(blocks.last, {
        'type': 'cta',
        'label': 'Book now',
        'target_url': '/book',
      });
    },
  );

  test(
    'updateLessonContent rejects tokenless writes before transport',
    () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'}),
      );
      final repo = StudioRepository(client: _clientWith(adapter));

      await expectLater(
        repo.updateLessonContent(
          'lesson-1',
          contentDocument: const LessonDocument(
            blocks: [
              LessonParagraphBlock(children: [LessonTextRun('Updated')]),
            ],
          ),
          ifMatch: ' ',
        ),
        throwsA(isA<StateError>()),
      );
      expect(adapter.requestsFor('/studio/lessons/lesson-1/content'), isEmpty);
    },
  );
}

Map<String, Object?> _lessonDocumentJson(String text) {
  return {
    'schema_version': lessonDocumentSchemaVersion,
    'blocks': [
      {
        'type': 'paragraph',
        'children': [
          {'text': text},
        ],
      },
    ],
  };
}

Map<String, Object?> _mediaCtaDocumentJson() {
  return {
    'schema_version': lessonDocumentSchemaVersion,
    'blocks': [
      {'type': 'media', 'media_type': 'image', 'lesson_media_id': imageMediaId},
      {'type': 'media', 'media_type': 'audio', 'lesson_media_id': audioMediaId},
      {'type': 'media', 'media_type': 'video', 'lesson_media_id': videoMediaId},
      {
        'type': 'media',
        'media_type': 'document',
        'lesson_media_id': documentMediaId,
      },
      {'type': 'cta', 'label': 'Book now', 'target_url': '/book'},
    ],
  };
}

Map<String, Object?> _contentMediaItem(String lessonMediaId, String mediaType) {
  return {
    'lesson_media_id': lessonMediaId,
    'media_asset_id': 'asset-$lessonMediaId',
    'position': 1,
    'media_type': mediaType,
    'state': 'ready',
  };
}

Map<String, Object?> _courseCtaBundle() {
  return {
    'bundle_id': 'course_cta.v1',
    'locale': 'sv-SE',
    'version': 'catalog_v1',
    'hash': 'course-cta-test-hash',
    'texts': {
      'course.cta.continue': 'Forts\u00e4tt',
      'course.cta.enroll': 'B\u00f6rja kursen',
      'course.cta.buy': 'K\u00f6p kursen',
      'course.cta.unavailable': 'Inte tillg\u00e4nglig',
      'lesson.cta.continue': 'Forts\u00e4tt',
      'lesson.cta.start': 'B\u00f6rja kursen',
      'lesson.cta.buy': 'K\u00f6p kursen',
      'lesson.cta.unavailable': 'Inte tillg\u00e4nglig',
    },
  };
}

Map<String, Object?> _courseLessonChromeBundle() {
  return {
    'bundle_id': 'course_lesson.chrome.v1',
    'locale': 'sv-SE',
    'version': 'catalog_v1',
    'hash': 'course-lesson-chrome-test-hash',
    'texts': {
      'course_lesson.course.title_fallback': 'Kurs',
      'course_lesson.course.drip_release_notice': 'Kursen sl\u00e4pps stegvis',
      'course_lesson.lesson.title_fallback': 'Lektion',
      'course_lesson.lesson.content_missing': 'Lektionsinneh\u00e5llet saknas.',
      'course_lesson.lesson.previous': 'F\u00f6reg\u00e5ende',
      'course_lesson.lesson.next': 'N\u00e4sta',
    },
  };
}

ApiClient _clientWith(_RecordingAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'http://127.0.0.1:1',
    tokenStorage: _FakeTokenStorage(),
  );
  client.raw.httpClientAdapter = adapter;
  return client;
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, dynamic> body,
  Map<String, List<String>> headers = const <String, List<String>>{},
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;
  final List<_RecordedRequest> _requests = <_RecordedRequest>[];

  List<_RecordedRequest> requestsFor(String path) => _requests
      .where((request) => request.path == path)
      .toList(growable: false);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _requests.add(
      _RecordedRequest(
        path: options.path,
        method: options.method.toUpperCase(),
        queryParameters: Map<String, Object?>.from(options.queryParameters),
        headers: Map<String, Object?>.from(options.headers),
        data: options.data,
      ),
    );
    return _handler(options);
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.path,
    required this.method,
    required this.queryParameters,
    required this.headers,
    required this.data,
  });

  final String path;
  final String method;
  final Map<String, Object?> queryParameters;
  final Map<String, Object?> headers;
  final Object? data;
}

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => _jwtWithExpSeconds(4102444800);

  @override
  Future<String?> readRefreshToken() async => 'rt-1';

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> updateAccessToken(String accessToken) async {}
}

String _jwtWithExpSeconds(int expSeconds) {
  final header = base64Url.encode(utf8.encode(json.encode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(json.encode({'exp': expSeconds})),
  );
  return '$header.$payload.signature';
}
