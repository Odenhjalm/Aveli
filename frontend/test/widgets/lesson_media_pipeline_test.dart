import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
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

LessonDetailData _buildLessonData({required List<LessonMediaItem> media}) {
  return LessonDetailData(
    lesson: const LessonDetail(
      id: 'lesson-1',
      lessonTitle: 'Lektion',
      contentMarkdown: '# Lektion',
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
  required bool previewReady,
  String? originalName,
}) {
  return LessonMediaItem(
    id: id,
    lessonId: 'lesson-1',
    mediaAssetId: 'asset-1',
    position: 1,
    mediaType: mediaType,
    state: state,
    originalName: originalName ?? '$id.$mediaType',
    previewReady: previewReady,
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
  required MediaPipelineRepository repository,
}) async {
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
        mediaPipelineRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: LessonPage(lessonId: 'lesson-1')),
    ),
  );
}

void main() {
  testWidgets(
    'hides non-embedded processing audio without requesting playback',
    (tester) async {
      final repository = _FakeMediaPipelineRepository(
        Future.value('https://cdn.test/audio.mp3'),
      );
      final data = _buildLessonData(
        media: [
          _lessonMediaItem(
            id: 'media-audio-1',
            mediaType: 'audio',
            state: 'processing',
            previewReady: false,
            originalName: 'lesson-audio.mp3',
          ),
        ],
      );

      await _pumpLessonPage(tester, data: data, repository: repository);
      await tester.pumpAndSettle();

      expect(_legacyInlineAudioPlayerFinder(), findsNothing);
      expect(_lessonAudioMediaPlayerFinder(), findsNothing);
      expect(repository.lessonPlaybackCalls, 0);
      expect(repository.playbackCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hides non-embedded ready audio without requesting playback', (
    tester,
  ) async {
    final pending = Completer<String>();
    final repository = _FakeMediaPipelineRepository(pending.future);
    final data = _buildLessonData(
      media: [
        _lessonMediaItem(
          id: 'media-audio-1',
          mediaType: 'audio',
          state: 'ready',
          previewReady: true,
          originalName: 'lesson-audio.mp3',
        ),
      ],
    );

    await _pumpLessonPage(tester, data: data, repository: repository);
    await tester.pump();
    await tester.pump();

    expect(repository.lessonPlaybackCalls, 0);
    expect(repository.playbackCalls, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    pending.complete('https://cdn.test/audio.mp3');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_lessonAudioMediaPlayerFinder(), findsNothing);
    expect(_legacyInlineAudioPlayerFinder(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson hides non-embedded trailing image rows', (tester) async {
    final repository = _FakeMediaPipelineRepository(
      Future.value('https://cdn.test/lesson-image.webp'),
    );
    final data = _buildLessonData(
      media: [
        _lessonMediaItem(
          id: 'media-image-1',
          mediaType: 'image',
          state: 'ready',
          previewReady: true,
          originalName: 'lesson-image.webp',
        ),
      ],
    );

    await _pumpLessonPage(tester, data: data, repository: repository);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AveliLessonImage), findsNothing);
    expect(repository.lessonPlaybackCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
