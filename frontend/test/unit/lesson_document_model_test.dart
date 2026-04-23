import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/editor/document/lesson_document.dart';

import '../helpers/lesson_document_fixture_corpus.dart';

const mediaId = '11111111-1111-4111-8111-111111111111';

void main() {
  test('serializes an empty lesson_document_v1 document canonically', () {
    final document = LessonDocument.empty();

    expect(document.toJson(), {
      'schema_version': 'lesson_document_v1',
      'blocks': <Object?>[],
    });
    expect(jsonDecode(document.toCanonicalJsonString()), {
      'blocks': <Object?>[],
      'schema_version': 'lesson_document_v1',
    });
  });

  test('parses and serializes every supported block shape', () {
    final document = LessonDocument.empty()
        .insertParagraph(0, const [LessonTextRun('Paragraph')])
        .insertHeading(1, level: 2, children: const [LessonTextRun('Heading')])
        .insertBulletList(2, const [
          LessonListItem(children: [LessonTextRun('Bullet')]),
        ])
        .insertOrderedList(3, const [
          LessonListItem(children: [LessonTextRun('Ordered')]),
        ], start: 3)
        .insertMedia(4, mediaType: 'image', lessonMediaId: mediaId)
        .insertCta(5, label: 'Open', targetUrl: 'https://example.com/start');

    final parsed = LessonDocument.fromJson(
      document.toJson(),
      mediaTypesByLessonMediaId: const {mediaId: 'image'},
    );

    expect(parsed.toJson(), document.toJson());
  });

  test('positive document corpus covers every required editor capability', () {
    final corpus = loadLessonDocumentFixtureCorpus();

    expect(corpus.raw['status'], 'ACTIVE_REBUILT_EDITOR_AUTHORITY');
    expect(corpus.raw['schema_version'], lessonDocumentSchemaVersion);
    expect(corpus.requiredCapabilities.toSet(), {
      'bold',
      'italic',
      'underline',
      'clear_formatting',
      'heading',
      'bullet_list',
      'ordered_list',
      'image',
      'audio',
      'video',
      'document',
      'magic_link_cta',
      'persisted_preview',
      'etag_concurrency',
    });

    for (final capability in corpus.requiredCapabilities) {
      expect(
        corpus.fixtureIdsForCapability(capability),
        isNotEmpty,
        reason: '$capability must be backed by at least one fixture',
      );
    }
  });

  test('positive document corpus parses through local model validation', () {
    final corpus = loadLessonDocumentFixtureCorpus();

    for (final (fixtureId, field) in corpus.documentFields()) {
      final document = corpus.document(fixtureId, field: field);
      expect(
        document.toJson(),
        corpus.documentJson(fixtureId, field: field),
        reason: '$fixtureId.$field must round-trip as document JSON',
      );
      expect(
        document.validate(
          mediaTypesByLessonMediaId: corpus.mediaTypesByLessonMediaId,
        ),
        same(document),
      );
      expect(
        document.toCanonicalJsonString(),
        isNot(contains('!image(')),
        reason: '$fixtureId.$field must not encode media as Markdown',
      );
      expect(
        document.toCanonicalJsonString(),
        isNot(contains('content_markdown')),
        reason: '$fixtureId.$field must not use legacy content authority',
      );
    }
  });

  test(
    'clear-formatting corpus fixture removes marks without block collapse',
    () {
      final fixture = loadLessonDocumentFixtureCorpus().clearFormattingFixture(
        'clear_formatting_operation',
      );

      final cleared = fixture.source.clearBlockInlineFormatting(
        fixture.blockIndex,
        start: fixture.start,
        end: fixture.end,
      );

      expect(cleared.toJson(), fixture.expected.toJson());
      expect(cleared.blocks, hasLength(2));
      expect(
        (cleared.blocks.first as LessonParagraphBlock).children.single.marks,
        isEmpty,
      );
      expect(
        (cleared.blocks[1] as LessonParagraphBlock).children.single.text,
        'Boundary stays',
      );
    },
  );

  test('canonical JSON is stable across input key order', () {
    final first = LessonDocument.fromJson({
      'schema_version': 'lesson_document_v1',
      'blocks': [
        {
          'type': 'paragraph',
          'children': [
            {
              'text': 'Same',
              'marks': ['bold'],
            },
          ],
        },
      ],
    });
    final second = LessonDocument.fromJson({
      'blocks': [
        {
          'children': [
            {
              'marks': ['bold'],
              'text': 'Same',
            },
          ],
          'type': 'paragraph',
        },
      ],
      'schema_version': 'lesson_document_v1',
    });

    expect(first.toCanonicalJsonString(), second.toCanonicalJsonString());
  });

  test('inline mark operations split ranges without collapsing blocks', () {
    final document = LessonDocument.empty().insertParagraph(0, const [
      LessonTextRun('Hello world'),
    ]);

    final marked = document
        .formatBlockInlineRange(
          0,
          start: 0,
          end: 5,
          mark: LessonInlineMark.bold,
        )
        .formatBlockInlineRange(
          0,
          start: 6,
          end: 11,
          mark: LessonInlineMark.italic,
        )
        .formatBlockInlineRange(
          0,
          start: 6,
          end: 11,
          mark: LessonInlineMark.underline,
        );

    expect(marked.blocks, hasLength(1));
    expect(marked.toJson()['blocks'], [
      {
        'type': 'paragraph',
        'children': [
          {
            'text': 'Hello',
            'marks': ['bold'],
          },
          {'text': ' '},
          {
            'text': 'world',
            'marks': ['italic', 'underline'],
          },
        ],
      },
    ]);

    final cleared = marked.clearBlockInlineFormatting(0, start: 0, end: 11);

    expect(cleared.blocks, hasLength(1));
    expect(cleared.toJson()['blocks'], [
      {
        'type': 'paragraph',
        'children': [
          {'text': 'Hello world'},
        ],
      },
    ]);
  });

  test('link marks carry target URLs as mark objects', () {
    final document = LessonDocument.empty()
        .insertParagraph(0, const [LessonTextRun('Open link')])
        .formatBlockInlineRange(
          0,
          start: 0,
          end: 9,
          mark: LessonInlineMark.link('/courses/example'),
        );

    expect(document.toJson()['blocks'], [
      {
        'type': 'paragraph',
        'children': [
          {
            'text': 'Open link',
            'marks': [
              {'type': 'link', 'href': '/courses/example'},
            ],
          },
        ],
      },
    ]);
  });

  test('list item inline operations preserve list structure', () {
    final document = LessonDocument.empty().insertBulletList(0, const [
      LessonListItem(children: [LessonTextRun('First item')]),
    ]);

    final marked = document.formatListItemInlineRange(
      0,
      itemIndex: 0,
      start: 0,
      end: 5,
      mark: LessonInlineMark.bold,
    );

    expect(marked.toJson()['blocks'], [
      {
        'type': 'bullet_list',
        'items': [
          {
            'children': [
              {
                'text': 'First',
                'marks': ['bold'],
              },
              {'text': ' item'},
            ],
          },
        ],
      },
    ]);
  });

  test('local validation rejects schema drift and invalid nodes', () {
    expect(
      () => LessonDocument.fromJson({'schema_version': 'v0', 'blocks': []}),
      throwsFormatException,
    );
    expect(
      () => LessonDocument.fromJson({
        'schema_version': 'lesson_document_v1',
        'blocks': [
          {'type': 'quote', 'children': <Object?>[]},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => LessonDocument.fromJson({
        'schema_version': 'lesson_document_v1',
        'blocks': [
          {
            'type': 'paragraph',
            'children': [
              {
                'text': 'Nope',
                'marks': ['strike'],
              },
            ],
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('local validation rejects invalid media and CTA shapes', () {
    expect(
      () => LessonDocument.fromJson(
        {
          'schema_version': 'lesson_document_v1',
          'blocks': [
            {
              'type': 'media',
              'media_type': 'audio',
              'lesson_media_id': mediaId,
            },
          ],
        },
        mediaTypesByLessonMediaId: const {mediaId: 'video'},
      ),
      throwsFormatException,
    );
    expect(
      () => LessonDocument.fromJson({
        'schema_version': 'lesson_document_v1',
        'blocks': [
          {
            'type': 'media',
            'media_type': 'audio',
            'lesson_media_id': mediaId,
            'storage_path': 'private/file.mp3',
          },
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => LessonDocument.fromJson({
        'schema_version': 'lesson_document_v1',
        'blocks': [
          {'type': 'cta', 'label': '', 'target_url': 'https://example.com'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => LessonDocument.fromJson({
        'schema_version': 'lesson_document_v1',
        'blocks': [
          {'type': 'cta', 'label': 'Open', 'target_url': 'javascript:alert(1)'},
        ],
      }),
      throwsFormatException,
    );
  });
}
