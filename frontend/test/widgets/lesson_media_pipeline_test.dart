import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';

class _FakeMediaPipelineRepository implements MediaPipelineRepository {
  _FakeMediaPipelineRepository(this._lessonPlaybackFuture);

  final Future<String> _lessonPlaybackFuture;
  int playbackCalls = 0;
  int lessonPlaybackCalls = 0;

  @override
  Future<MediaUploadTarget> requestUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    String? purpose,
    String? courseId,
    String? lessonId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MediaUploadTarget> refreshUploadUrl({required String mediaId}) {
    throw UnimplementedError();
  }

  @override
  Future<MediaStatus> completeUpload({required String mediaId}) {
    throw UnimplementedError();
  }

  @override
  Future<MediaStatus> attachUpload({
    required String mediaId,
    required String linkScope,
    String? lessonId,
    String? lessonMediaId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MediaUploadTarget> requestCoverUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String courseId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CoverMediaResponse> requestCoverFromLessonMedia({
    required String courseId,
    required String lessonMediaId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> clearCourseCover(String courseId) {
    throw UnimplementedError();
  }

  @override
  Future<MediaStatus> fetchStatus(String mediaId) {
    throw UnimplementedError();
  }

  @override
  Future<MediaPlaybackUrl> fetchPlaybackUrl(String mediaId) async {
    playbackCalls += 1;
    return MediaPlaybackUrl(
      playbackUrl: Uri.parse(await _lessonPlaybackFuture),
      expiresAt: DateTime.now().toUtc(),
      format: 'mp3',
    );
  }

  @override
  Future<String> fetchRuntimePlaybackUrl(String runtimeMediaId) async {
    playbackCalls += 1;
    return _lessonPlaybackFuture;
  }

  @override
  Future<String> fetchLessonPlaybackUrl(String lessonMediaId) async {
    lessonPlaybackCalls += 1;
    return _lessonPlaybackFuture;
  }
}

LessonDetailData _buildLessonData({required String mediaState}) {
  final lesson = LessonDetail(
    id: 'lesson-1',
    title: 'Lektion',
    contentMarkdown: '# Lektion',
    isIntro: false,
    position: 1,
  );
  final media = [
    LessonMediaItem(
      id: 'media-1',
      kind: 'audio',
      storagePath: 'lesson-1/audio.mp3',
      mediaAssetId: 'asset-1',
      mediaState: mediaState,
      originalName: 'lesson-audio.mp3',
      position: 1,
    ),
  ];
  return LessonDetailData(lesson: lesson, media: media);
}

Finder _legacyInlineAudioPlayerFinder() {
  return find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == 'InlineAudioPlayer',
    description: 'InlineAudioPlayer',
  );
}

Finder _lessonAudioMediaPlayerFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is AveliLessonMediaPlayer &&
        widget.kind.trim().toLowerCase() == 'audio',
    description: 'AveliLessonMediaPlayer(kind: audio)',
  );
}

void main() {
  testWidgets(
    'hides non-embedded processing audio without requesting playback',
    (tester) async {
      final repo = _FakeMediaPipelineRepository(
        Future.value('https://cdn.test/audio.mp3'),
      );
      final data = _buildLessonData(mediaState: 'processing');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'http://localhost',
                stripePublishableKey: '',
                stripeMerchantDisplayName: 'Test',
                subscriptionsEnabled: false,
              ),
            ),
            lessonDetailProvider.overrideWith((ref, lessonId) async => data),
            mediaPipelineRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: LessonPage(lessonId: 'lesson-1')),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Ljudet bearbetas…'), findsNothing);
      expect(_legacyInlineAudioPlayerFinder(), findsNothing);
      expect(_lessonAudioMediaPlayerFinder(), findsNothing);
      expect(repo.lessonPlaybackCalls, 0);
      expect(repo.playbackCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hides non-embedded ready audio without requesting playback', (
    tester,
  ) async {
    final pending = Completer<String>();
    final repo = _FakeMediaPipelineRepository(pending.future);
    final data = _buildLessonData(mediaState: 'ready');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              stripePublishableKey: '',
              stripeMerchantDisplayName: 'Test',
              subscriptionsEnabled: false,
            ),
          ),
          lessonDetailProvider.overrideWith((ref, lessonId) async => data),
          mediaPipelineRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: LessonPage(lessonId: 'lesson-1')),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(repo.lessonPlaybackCalls, 0);
    expect(repo.playbackCalls, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    pending.complete('https://cdn.test/audio.mp3');

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_lessonAudioMediaPlayerFinder(), findsNothing);
    expect(_legacyInlineAudioPlayerFinder(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy lesson video renders placeholder without crash', (
    tester,
  ) async {
    final repo = _FakeMediaPipelineRepository(
      Future.value('https://cdn.test/video.mp4'),
    );
    final data = LessonDetailData(
      lesson: const LessonDetail(
        id: 'lesson-legacy',
        title: 'Legacy',
        contentMarkdown:
            'Introtext\n\n<video src="/studio/media/legacy-path"></video>\n\nEftertext',
        isIntro: false,
        position: 1,
      ),
      media: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              stripePublishableKey: '',
              stripeMerchantDisplayName: 'Test',
              subscriptionsEnabled: false,
            ),
          ),
          lessonDetailProvider.overrideWith((ref, lessonId) async => data),
          mediaPipelineRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: LessonPage(lessonId: 'lesson-legacy')),
      ),
    );

    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(
      find.text('Den här lektionen innehåller äldre videoformat.'),
      findsOneWidget,
    );
    expect(find.byType(AveliLessonMediaPlayer), findsNothing);
  });

  testWidgets('lesson hides non-embedded trailing image rows', (tester) async {
    const imageUrl = 'https://cdn.test/lesson-image.webp';
    final repo = _FakeMediaPipelineRepository(Future.value(imageUrl));
    final data = LessonDetailData(
      lesson: const LessonDetail(
        id: 'lesson-image',
        title: 'Image lesson',
        contentMarkdown: 'Intro\n',
        isIntro: false,
        position: 1,
      ),
      media: const [
        LessonMediaItem(
          id: 'media-image-1',
          kind: 'image',
          storagePath: 'lesson-1/lesson-image.webp',
          originalName: 'lesson-image.webp',
          position: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              stripePublishableKey: '',
              stripeMerchantDisplayName: 'Test',
              subscriptionsEnabled: false,
            ),
          ),
          lessonDetailProvider.overrideWith((ref, lessonId) async => data),
          mediaPipelineRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: LessonPage(lessonId: 'lesson-image')),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AveliLessonImage), findsNothing);
    expect(repo.lessonPlaybackCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson does not render raw image URLs without lesson_media_id', (
    tester,
  ) async {
    final repo = _FakeMediaPipelineRepository(
      Future.value('https://cdn.test/audio.mp3'),
    );
    final data = LessonDetailData(
      lesson: const LessonDetail(
        id: 'lesson-raw-image',
        title: 'Raw image lesson',
        contentMarkdown: 'Intro\n\n![](https://cdn.test/raw-image.webp)\n',
        isIntro: false,
        position: 1,
      ),
      media: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              stripePublishableKey: '',
              stripeMerchantDisplayName: 'Test',
              subscriptionsEnabled: false,
            ),
          ),
          lessonDetailProvider.overrideWith((ref, lessonId) async => data),
          mediaPipelineRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: LessonPage(lessonId: 'lesson-raw-image'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AveliLessonImage), findsNothing);
    expect(find.text('Äldre media blockerat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson renders branded PDF download card without raw URL', (
    tester,
  ) async {
    final repo = _FakeMediaPipelineRepository(
      Future.value('https://cdn.test/guide.pdf?download=1'),
    );
    final data = LessonDetailData(
      lesson: const LessonDetail(
        id: 'lesson-pdf',
        title: 'PDF lesson',
        contentMarkdown: 'Intro\n',
        isIntro: false,
        position: 1,
      ),
      media: const [
        LessonMediaItem(
          id: 'media-pdf',
          kind: 'document',
          storagePath: 'lesson-1/docs/guide.pdf',
          contentType: 'application/pdf',
          signedUrl: '/media/stream/pdf-token',
          originalName: 'guide.pdf',
          position: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              stripePublishableKey: '',
              stripeMerchantDisplayName: 'Test',
              subscriptionsEnabled: false,
            ),
          ),
          lessonDetailProvider.overrideWith((ref, lessonId) async => data),
          mediaPipelineRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: LessonPage(lessonId: 'lesson-pdf')),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('guide.pdf'), findsOneWidget);
    expect(find.text('Ladda ner PDF'), findsOneWidget);
    expect(find.textContaining('https://cdn.test/guide.pdf'), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(repo.lessonPlaybackCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson trailing media only includes supported documents', (
    tester,
  ) async {
    final repo = _FakeMediaPipelineRepository(
      Future.value('https://cdn.test/ignored.mp4'),
    );
    final data = LessonDetailData(
      lesson: const LessonDetail(
        id: 'lesson-trailing-docs',
        title: 'Trailing docs lesson',
        contentMarkdown: 'Intro\n',
        isIntro: false,
        position: 1,
      ),
      media: const [
        LessonMediaItem(
          id: 'media-video',
          kind: 'video',
          storagePath: 'lesson-1/video.mp4',
          originalName: 'video.mp4',
          resolvableForStudent: false,
          position: 1,
        ),
        LessonMediaItem(
          id: 'media-pdf-2',
          kind: 'document',
          storagePath: 'lesson-1/docs/notes.pdf',
          contentType: 'application/pdf',
          signedUrl: '/media/stream/notes-token',
          originalName: 'notes.pdf',
          position: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              stripePublishableKey: '',
              stripeMerchantDisplayName: 'Test',
              subscriptionsEnabled: false,
            ),
          ),
          lessonDetailProvider.overrideWith((ref, lessonId) async => data),
          mediaPipelineRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: LessonPage(lessonId: 'lesson-trailing-docs'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.text('Ladda ner PDF'), findsOneWidget);
    expect(find.text('video.mp4'), findsNothing);
    expect(find.byType(AveliLessonMediaPlayer), findsNothing);
    expect(repo.lessonPlaybackCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lesson media list image does not fall back to direct row URL when resolver fails',
    (tester) async {
      final repo = _FakeMediaPipelineRepository(
        Future.value('/studio/media/media-image'),
      );
      final data = LessonDetailData(
        lesson: const LessonDetail(
          id: 'lesson-image-row',
          title: 'Image row lesson',
          contentMarkdown: 'Intro\n',
          isIntro: false,
          position: 1,
        ),
        media: const [
          LessonMediaItem(
            id: 'media-image',
            kind: 'image',
            storagePath: 'lesson-1/image.webp',
            preferredUrlValue: 'https://cdn.test/raw-row-image.webp',
            originalName: 'row-image.webp',
            position: 1,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'http://localhost',
                stripePublishableKey: '',
                stripeMerchantDisplayName: 'Test',
                subscriptionsEnabled: false,
              ),
            ),
            lessonDetailProvider.overrideWith((ref, lessonId) async => data),
            mediaPipelineRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: LessonPage(lessonId: 'lesson-image-row'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.lessonPlaybackCalls, 0);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AveliLessonImage &&
              widget.src == 'https://cdn.test/raw-row-image.webp',
        ),
        findsNothing,
      );
      expect(find.byType(AveliLessonImage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
