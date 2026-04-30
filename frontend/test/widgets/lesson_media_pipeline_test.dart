import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/text_bundle.dart';
import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/lesson_view_surface.dart';
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/shared/data/app_render_inputs_repository.dart';
import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

LessonViewSurface _buildLessonData({
  required List<LessonViewMediaItem> media,
  LessonDocument? contentDocument = _defaultLessonDocument,
  String id = 'lesson-1',
  String lessonTitle = 'Backend lesson title',
  int position = 1,
  String? previousLessonId,
  String? nextLessonId,
  LessonViewCTA? cta,
  LessonViewPricing? pricing,
  LessonViewProgression? progression,
}) {
  final unlocked = contentDocument != null;
  return LessonViewSurface(
    lesson: LessonViewLesson(
      id: id,
      courseId: 'course-1',
      lessonTitle: lessonTitle,
      position: position,
      contentDocument: contentDocument,
    ),
    navigation: LessonViewNavigation(
      previousLessonId: previousLessonId,
      nextLessonId: nextLessonId,
    ),
    access: LessonViewAccess(
      hasAccess: unlocked,
      isEnrolled: unlocked,
      isInDrip: !unlocked,
      isPremium: false,
      canEnroll: !unlocked,
      canPurchase: false,
    ),
    cta: cta,
    textBundles: _courseTextBundles,
    pricing: pricing,
    progression:
        progression ??
        LessonViewProgression(
          unlocked: unlocked,
          reason: unlocked ? 'available' : 'drip',
        ),
    media: unlocked ? media : const <LessonViewMediaItem>[],
  );
}

const LessonDocument _defaultLessonDocument = LessonDocument(
  blocks: [
    LessonHeadingBlock(level: 2, children: [LessonTextRun('Lektion')]),
  ],
);

const List<TextBundle> _navigationTextBundles = <TextBundle>[
  TextBundle(
    bundleId: 'global_system.navigation.v1',
    locale: 'sv-SE',
    version: 'catalog_v1',
    hash: 'sha256:test-navigation',
    texts: {
      'global_system.navigation.home': TextNode(value: 'Hem'),
      'global_system.navigation.teacher_home': TextNode(value: 'Lärarhem'),
      'global_system.navigation.profile': TextNode(value: 'Profil'),
    },
  ),
];

const AppRenderInputs _testAppRenderInputs = AppRenderInputs(
  brand: BrandRenderInputs(
    logo: BrandLogoRenderInput(resolvedUrl: 'https://cdn.test/logo.png'),
  ),
  ui: UiRenderInputs(
    backgrounds: UiBackgroundRenderInputs(
      defaultBackground: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/default.jpg',
      ),
      lesson: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/lesson.jpg',
      ),
      observatory: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/observatory.jpg',
      ),
    ),
  ),
  textBundles: _navigationTextBundles,
);

final _pendingLogoRenderInput = Completer<BrandLogoRenderInput>().future;
final _pendingBackgroundRenderInput =
    Completer<UiBackgroundRenderInput>().future;

LessonDocument _paragraphDocument(List<String> paragraphs) {
  return LessonDocument(
    blocks: [
      for (final paragraph in paragraphs)
        LessonParagraphBlock(children: [LessonTextRun(paragraph)]),
    ],
  );
}

LessonDocument _mediaDocument({
  required String mediaType,
  required String lessonMediaId,
  List<String> paragraphs = const <String>[],
}) {
  return LessonDocument(
    blocks: [
      for (final paragraph in paragraphs)
        LessonParagraphBlock(children: [LessonTextRun(paragraph)]),
      LessonMediaBlock(mediaType: mediaType, lessonMediaId: lessonMediaId),
    ],
  );
}

LessonViewMediaItem _lessonMediaItem({
  required String id,
  required String mediaType,
  required String state,
  String? resolvedUrl,
}) {
  return LessonViewMediaItem(
    lessonMediaId: id,
    position: 1,
    mediaType: mediaType,
    media: ResolvedMediaData(
      mediaId: 'asset-1',
      state: state,
      resolvedUrl: resolvedUrl,
    ),
  );
}

Finder _lessonAudioMediaPlayerFinder() {
  return find.byWidgetPredicate(
    (widget) => widget is AveliLessonMediaPlayer && widget.kind == 'audio',
    description: 'AveliLessonMediaPlayer(kind: audio)',
  );
}

Object? _takeUnexpectedException(WidgetTester tester) {
  Object? unexpected;
  Object? current;
  while ((current = tester.takeException()) != null) {
    if (current is NetworkImageLoadException) {
      continue;
    }
    if (current.toString().startsWith('Multiple exceptions')) {
      continue;
    }
    unexpected ??= current;
  }
  return unexpected;
}

Future<void> _pumpLessonPage(
  WidgetTester tester, {
  required LessonViewSurface data,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://localhost',
            subscriptionsEnabled: false,
          ),
        ),
        ..._renderInputOverrides(),
        lessonDetailProvider.overrideWith((ref, lessonId) async => data),
      ],
      child: const MaterialApp(home: LessonPage(lessonId: 'lesson-1')),
    ),
  );
}

Future<void> _pumpLessonPageWithError(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://localhost',
            subscriptionsEnabled: false,
          ),
        ),
        ..._renderInputOverrides(),
        lessonDetailProvider.overrideWith(
          (ref, lessonId) async => throw StateError('Malformed lesson payload'),
        ),
      ],
      child: const MaterialApp(home: LessonPage(lessonId: 'lesson-1')),
    ),
  );
}

List<Override> _renderInputOverrides() {
  return [
    appRenderInputsProvider.overrideWith((ref) async => _testAppRenderInputs),
    brandLogoRenderInputProvider.overrideWith((ref) => _pendingLogoRenderInput),
    uiBackgroundRenderInputProvider.overrideWith(
      (ref, key) => _pendingBackgroundRenderInput,
    ),
  ];
}

void main() {
  testWidgets('lesson renders empty content state without crashing', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: const [],
      contentDocument: LessonDocument.empty(),
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pumpAndSettle();

    expect(
      find.text(_catalogText('course_lesson.lesson.content_missing')),
      findsOneWidget,
    );
    expect(_takeUnexpectedException(tester), isNull);
  });

  testWidgets('lesson handles provider errors without render exceptions', (
    tester,
  ) async {
    await _pumpLessonPageWithError(tester);
    await tester.pumpAndSettle();

    expect(find.text('Lektionen kunde inte laddas.'), findsOneWidget);
    expect(_takeUnexpectedException(tester), isNull);
  });

  testWidgets('embedded media without backend row renders unavailable state', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: const [],
      contentDocument: _mediaDocument(
        mediaType: 'video',
        lessonMediaId: 'media-video-missing',
        paragraphs: const ['Intro'],
      ),
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Lektionsmedia kunde inte laddas.'), findsOneWidget);
    expect(_takeUnexpectedException(tester), isNull);
  });

  testWidgets(
    'hides non-embedded processing audio without requesting playback',
    (tester) async {
      final data = _buildLessonData(
        media: [
          _lessonMediaItem(
            id: 'media-audio-1',
            mediaType: 'audio',
            state: 'processing',
          ),
        ],
      );

      await _pumpLessonPage(tester, data: data);
      await tester.pumpAndSettle();

      expect(_lessonAudioMediaPlayerFinder(), findsNothing);
      expect(_takeUnexpectedException(tester), isNull);
    },
  );

  testWidgets('hides non-embedded ready audio without requesting playback', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: [
        _lessonMediaItem(
          id: 'media-audio-1',
          mediaType: 'audio',
          state: 'ready',
          resolvedUrl: 'https://cdn.test/lesson-audio.mp3',
        ),
      ],
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);

    expect(_lessonAudioMediaPlayerFinder(), findsNothing);
    expect(_takeUnexpectedException(tester), isNull);
  });

  testWidgets('lesson hides non-embedded trailing image rows', (tester) async {
    final data = _buildLessonData(
      media: [
        _lessonMediaItem(
          id: 'media-image-1',
          mediaType: 'image',
          state: 'ready',
          resolvedUrl: 'https://cdn.test/lesson-image.webp',
        ),
      ],
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AveliLessonImage), findsNothing);
    expect(_takeUnexpectedException(tester), isNull);
  });

  testWidgets('lesson hides non-embedded trailing document rows', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: [
        _lessonMediaItem(
          id: 'media-document-1',
          mediaType: 'document',
          state: 'ready',
          resolvedUrl: 'https://cdn.test/lesson-document.pdf',
        ),
      ],
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Dokument'), findsNothing);
    expect(find.text('Ladda ner dokument'), findsNothing);
    expect(_takeUnexpectedException(tester), isNull);
  });

  testWidgets('lesson renders locked two-paragraph fixture content', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: const [],
      contentDocument: _paragraphDocument(['Hello world', 'This is a lesson']),
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('Hello world', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('This is a lesson', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('LektionsinnehÃ¥llet kunde inte renderas.'), findsNothing);
    expect(_takeUnexpectedException(tester), isNull);
  });

  testWidgets(
    'lesson renders inline document tokens without trailing fallback duplication',
    (tester) async {
      final data = _buildLessonData(
        media: [
          _lessonMediaItem(
            id: 'media-document-1',
            mediaType: 'document',
            state: 'ready',
            resolvedUrl: 'https://cdn.test/lesson-document.pdf',
          ),
        ],
        contentDocument: _mediaDocument(
          mediaType: 'document',
          lessonMediaId: 'media-document-1',
          paragraphs: const ['Intro', 'Outro'],
        ),
      );

      await _pumpLessonPage(tester, data: data);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Intro', findRichText: true), findsOneWidget);
      expect(find.textContaining('Outro', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('Ladda ner dokument', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('asset-1', findRichText: true), findsNothing);
      expect(
        find.textContaining('media-document-1', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('!document(', findRichText: true),
        findsNothing,
      );
      expect(find.text('Dokument'), findsNothing);
      expect(_takeUnexpectedException(tester), isNull);
    },
  );

  testWidgets('lesson page renders locked backend surface without media', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: const [],
      contentDocument: null,
      cta: const LessonViewCTA(
        type: 'blocked',
        textId: 'lesson.cta.unavailable',
        enabled: false,
        reasonText: 'Tillg\u00e4nglig senare',
      ),
      pricing: const LessonViewPricing(
        priceAmountCents: 9900,
        priceCurrency: 'sek',
        formatted: '99 kr',
      ),
      progression: const LessonViewProgression(unlocked: false, reason: 'drip'),
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pumpAndSettle();

    expect(find.text(_catalogText('lesson.cta.unavailable')), findsOneWidget);
    expect(find.text('blocked'), findsNothing);
    expect(find.text('Tillg\u00e4nglig senare'), findsOneWidget);
    expect(find.text('99 kr'), findsOneWidget);
    expect(find.text('drip'), findsNothing);
    expect(find.byType(LearnerLessonContentRenderer), findsNothing);
    expect(_lessonAudioMediaPlayerFinder(), findsNothing);
    expect(_takeUnexpectedException(tester), isNull);
  });
}

String _catalogText(String textId) => resolveText(textId, _courseTextBundles);

const List<TextBundle> _courseTextBundles = <TextBundle>[
  TextBundle(
    bundleId: 'course_cta.v1',
    locale: 'sv-SE',
    version: 'catalog_v1',
    hash: 'sha256:test',
    texts: <String, TextNode>{
      'course.cta.continue': TextNode(value: 'Fortsätt'),
      'course.cta.enroll': TextNode(value: 'Börja kursen'),
      'course.cta.buy': TextNode(value: 'Köp kursen'),
      'course.cta.unavailable': TextNode(value: 'Inte tillgänglig'),
      'lesson.cta.continue': TextNode(value: 'Fortsätt'),
      'lesson.cta.start': TextNode(value: 'Börja kursen'),
      'lesson.cta.buy': TextNode(value: 'Köp kursen'),
      'lesson.cta.unavailable': TextNode(value: 'Inte tillgänglig'),
    },
  ),
  TextBundle(
    bundleId: 'course_lesson.chrome.v1',
    locale: 'sv-SE',
    version: 'catalog_v1',
    hash: 'sha256:chrome-test',
    texts: <String, TextNode>{
      'course_lesson.course.title_fallback': TextNode(value: 'Kurs'),
      'course_lesson.course.drip_release_notice': TextNode(
        value: 'Kursen släpps stegvis',
      ),
      'course_lesson.lesson.title_fallback': TextNode(value: 'Lektion'),
      'course_lesson.lesson.content_missing': TextNode(
        value: 'Lektionsinnehållet saknas.',
      ),
      'course_lesson.lesson.previous': TextNode(value: 'Föregående'),
      'course_lesson.lesson.next': TextNode(value: 'Nästa'),
    },
  ),
];
