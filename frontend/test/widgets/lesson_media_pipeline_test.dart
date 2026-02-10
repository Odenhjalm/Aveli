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
import 'package:aveli/shared/widgets/aveli_video_player.dart';

class _FakeMediaPipelineRepository implements MediaPipelineRepository {
  _FakeMediaPipelineRepository(this._future);

  final Future<MediaPlaybackUrl> _future;
  int playbackCalls = 0;

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
    return _future;
  }
}

LessonDetailData _buildLessonData({required String mediaState}) {
  final lesson = LessonDetail(
    id: 'lesson-1',
    title: 'Lektion',
    contentMarkdown: '# Lektion',
    isIntro: false,
    moduleId: null,
    position: 1,
  );
  final media = [
    LessonMediaItem(
      id: 'media-1',
      kind: 'audio',
      storagePath: '',
      mediaAssetId: 'asset-1',
      mediaState: mediaState,
      position: 1,
    ),
  ];
  return LessonDetailData(lesson: lesson, media: media);
}

void main() {
  testWidgets('shows processing state without requesting playback', (
    tester,
  ) async {
    final repo = _FakeMediaPipelineRepository(
      Future.value(
        MediaPlaybackUrl(
          playbackUrl: Uri.parse('https://cdn.test/audio.mp3'),
          expiresAt: DateTime.now().toUtc(),
          format: 'mp3',
        ),
      ),
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

    expect(find.text('Ljudet bearbetas…'), findsOneWidget);
    expect(repo.playbackCalls, 0);
  });

  testWidgets('requests playback only when ready', (tester) async {
    final pending = Completer<MediaPlaybackUrl>();
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

    expect(repo.playbackCalls, 1);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });

  testWidgets('legacy lesson video renders placeholder without crash', (
    tester,
  ) async {
    final repo = _FakeMediaPipelineRepository(
      Future.value(
        MediaPlaybackUrl(
          playbackUrl: Uri.parse('https://cdn.test/video.mp4'),
          expiresAt: DateTime.now().toUtc(),
          format: 'mp4',
        ),
      ),
    );
    final data = LessonDetailData(
      lesson: const LessonDetail(
        id: 'lesson-legacy',
        title: 'Legacy',
        contentMarkdown:
            'Introtext\n\n<video src="/studio/media/legacy-path"></video>\n\nEftertext',
        isIntro: false,
        moduleId: null,
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
    expect(find.byType(AveliVideoPlayer), findsNothing);
  });
}
