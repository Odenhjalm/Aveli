import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/studio/widgets/cover_upload_card.dart';
import 'package:aveli/features/studio/widgets/cover_upload_source.dart';

class _FakeMediaPipelineRepository implements MediaPipelineRepository {
  _FakeMediaPipelineRepository({required this.uploadTarget});

  final MediaUploadTarget uploadTarget;
  int completeCalls = 0;

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
  Future<MediaStatus> completeUpload({required String mediaId}) async {
    completeCalls += 1;
    return MediaStatus(mediaId: mediaId, state: 'uploaded');
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
  Future<MediaStatus> fetchStatus(String mediaId) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('finalizes cover upload before queuing preview', (tester) async {
    final repo = _FakeMediaPipelineRepository(
      uploadTarget: MediaUploadTarget(
        mediaId: 'cover-1',
        uploadUrl: Uri.parse('https://storage.test/upload'),
        objectPath: 'media/source/cover/courses/course-1/cover.jpg',
        headers: const {},
        expiresAt: DateTime.now().toUtc(),
      ),
    );

    bool queued = false;
    String? queuedMediaId;

    Future<CoverUploadFile?> fakePick() async {
      final file = fs.XFile.fromData(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        name: 'cover.jpg',
        mimeType: 'image/jpeg',
      );
      return CoverUploadFile(file, 'image/jpeg', 4);
    }

    Future<void> fakeUpload({
      required Uri uploadUrl,
      required Map<String, String> headers,
      required CoverUploadFile file,
      required void Function(int sent, int total) onProgress,
    }) async {
      onProgress(4, 4);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaPipelineRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: CoverUploadCard(
              courseId: 'course-1',
              pickFileOverride: fakePick,
              uploadFileOverride: fakeUpload,
              onCoverQueued: (courseId, mediaId, preview) {
                queued = true;
                queuedMediaId = mediaId;
                expect(courseId, 'course-1');
                expect(repo.completeCalls, 1);
                preview.dispose();
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Valj bild'));
    await tester.pumpAndSettle();

    expect(repo.completeCalls, 1);
    expect(queued, isTrue);
    expect(queuedMediaId, 'cover-1');
  });
}
