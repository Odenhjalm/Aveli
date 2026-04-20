import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

LessonDetailData _buildLessonData({
  required List<LessonMediaItem> media,
  String? contentMarkdown = '# Lektion',
}) {
  return LessonDetailData(
    lesson: LessonDetail(
      id: 'lesson-1',
      lessonTitle: 'Lektion',
      contentMarkdown: contentMarkdown,
      position: 1,
    ),
    courseId: 'course-1',
    lessons: const [
      LessonSummary(id: 'lesson-1', lessonTitle: 'Lektion', position: 1),
    ],
    media: media,
  );
}

LessonMediaItem _lessonMediaItem({
  required String id,
  required String mediaType,
  required String state,
  String? resolvedUrl,
}) {
  return LessonMediaItem(
    id: id,
    lessonId: 'lesson-1',
    mediaAssetId: 'asset-1',
    position: 1,
    mediaType: mediaType,
    state: state,
    media: resolvedUrl == null
        ? null
        : ResolvedMediaData(
            mediaId: 'asset-1',
            state: state,
            resolvedUrl: resolvedUrl,
          ),
  );
}

Finder _legacyInlineAudioPlayerFinder() {
  return find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == 'InlineAudioPlayer',
    description: 'InlineAudioPlayer',
  );
}

Finder _lessonAudioMediaPlayerFinder() {
  return find.byWidgetPredicate(
    (widget) => widget is AveliLessonMediaPlayer && widget.kind == 'audio',
    description: 'AveliLessonMediaPlayer(kind: audio)',
  );
}

Future<void> _pumpLessonPage(
  WidgetTester tester, {
  required LessonDetailData data,
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
        lessonDetailProvider.overrideWith(
          (ref, lessonId) async => throw StateError('Malformed lesson payload'),
        ),
      ],
      child: const MaterialApp(home: LessonPage(lessonId: 'lesson-1')),
    ),
  );
}

void main() {
  testWidgets('lesson renders empty content state without crashing', (
    tester,
  ) async {
    final data = _buildLessonData(media: const [], contentMarkdown: null);

    await _pumpLessonPage(tester, data: data);
    await tester.pumpAndSettle();

    expect(find.text('Lektionsinnehållet saknas.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson handles provider errors without render exceptions', (
    tester,
  ) async {
    await _pumpLessonPageWithError(tester);
    await tester.pumpAndSettle();

    expect(find.text('Lektionen kunde inte laddas.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded media without backend row renders unavailable state', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: const [],
      contentMarkdown: 'Intro\n\n!video(media-video-missing)\n',
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Lektionsmedia kunde inte laddas.'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

      expect(_legacyInlineAudioPlayerFinder(), findsNothing);
      expect(_lessonAudioMediaPlayerFinder(), findsNothing);
      expect(tester.takeException(), isNull);
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
    expect(_legacyInlineAudioPlayerFinder(), findsNothing);
    expect(tester.takeException(), isNull);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson renders non-embedded trailing document rows', (
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

    expect(find.text('Dokument'), findsOneWidget);
    expect(find.text('Ladda ner dokument'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
