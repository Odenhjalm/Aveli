import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/studio/widgets/wav_upload_card.dart';
import 'package:aveli/features/studio/widgets/wav_upload_source.dart';

class _FakeMediaPipelineRepository implements MediaPipelineRepository {
  _FakeMediaPipelineRepository({required this.uploadTarget, required this.status});

  final MediaUploadTarget uploadTarget;
  final MediaStatus status;

  @override
  Future<MediaUploadTarget> requestUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    String? courseId,
    String? lessonId,
  }) async {
    return uploadTarget;
  }

  @override
  Future<MediaUploadTarget> requestCoverUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String courseId,
  }) async {
    return uploadTarget;
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
  Future<MediaStatus> fetchStatus(String mediaId) async {
    return status;
  }

  @override
  Future<MediaPlaybackUrl> fetchPlaybackUrl(String mediaId) async {
    return MediaPlaybackUrl(
      playbackUrl: Uri.parse('https://cdn.test/audio.mp3'),
      expiresAt: DateTime.now().toUtc(),
      format: 'mp3',
    );
  }
}

void main() {
  testWidgets('shows upload progress for WAV uploads', (tester) async {
    final uploadTarget = MediaUploadTarget(
      mediaId: 'media-1',
      uploadUrl: Uri.parse('https://storage.test/upload'),
      objectPath: 'media/source/audio/demo.wav',
      expiresAt: DateTime.now().toUtc(),
    );
    final repo = _FakeMediaPipelineRepository(
      uploadTarget: uploadTarget,
      status: MediaStatus(mediaId: 'media-1', state: 'processing'),
    );

    final uploadCompleter = Completer<void>();

    Future<WavUploadFile?> fakePick() async {
      final data = Uint8List(10);
      final file = fs.XFile.fromData(
        data,
        name: 'demo.wav',
        mimeType: 'audio/wav',
      );
      return WavUploadFile(file, 'audio/wav', 10);
    }

    Future<void> fakeUpload({
      required Uri uploadUrl,
      required Map<String, String> headers,
      required WavUploadFile file,
      required void Function(int sent, int total) onProgress,
    }) async {
      onProgress(5, 10);
      await uploadCompleter.future;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaPipelineRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WavUploadCard(
              courseId: 'course-1',
              lessonId: 'lesson-1',
              pickFileOverride: fakePick,
              uploadFileOverride: fakeUpload,
              pollInterval: const Duration(hours: 1),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ladda upp studiomaster (WAV)'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    uploadCompleter.complete();
    await tester.pump();
  });
}
