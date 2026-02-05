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
import 'package:aveli/features/studio/widgets/wav_upload_types.dart';

class _FakeMediaPipelineRepository implements MediaPipelineRepository {
  _FakeMediaPipelineRepository({
    required this.uploadTarget,
    required this.statuses,
  });

  final MediaUploadTarget uploadTarget;
  final List<MediaStatus> statuses;
  int _statusCalls = 0;

  @override
  Future<MediaUploadTarget> requestUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    String? purpose,
    String? courseId,
    String? lessonId,
  }) async {
    return uploadTarget;
  }

  @override
  Future<MediaUploadTarget> refreshUploadUrl({required String mediaId}) async {
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
    final index = _statusCalls < statuses.length
        ? _statusCalls
        : statuses.length - 1;
    _statusCalls += 1;
    return statuses[index];
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
      headers: const {},
      expiresAt: DateTime.now().toUtc(),
    );
    final repo = _FakeMediaPipelineRepository(
      uploadTarget: uploadTarget,
      statuses: const [MediaStatus(mediaId: 'media-1', state: 'processing')],
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
      required String mediaId,
      required String courseId,
      required String lessonId,
      required Uri uploadUrl,
      required String objectPath,
      required Map<String, String> headers,
      required WavUploadFile file,
      required String contentType,
      required void Function(int sent, int total) onProgress,
      WavUploadCancelToken? cancelToken,
      void Function(bool resumed)? onResume,
      Future<bool> Function()? ensureAuth,
      Future<WavUploadSigningRefresh> Function(WavResumableSession session)?
      refreshSigning,
      void Function()? onSigningRefresh,
      WavResumableSession? resumableSession,
    }) async {
      onProgress(5, 10);
      await uploadCompleter.future;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaPipelineRepositoryProvider.overrideWithValue(repo)],
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

    await tester.tap(find.text('Ladda upp WAV'));
    await tester.pumpAndSettle();

    expect(find.text('Ge ljudet/videon ett namn'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    uploadCompleter.complete();
    await tester.pump();
  });

  testWidgets('keeps upload action visible while processing and ready', (
    tester,
  ) async {
    final uploadTarget = MediaUploadTarget(
      mediaId: 'media-1',
      uploadUrl: Uri.parse('https://storage.test/upload'),
      objectPath: 'media/source/audio/demo.wav',
      headers: const {},
      expiresAt: DateTime.now().toUtc(),
    );
    final repo = _FakeMediaPipelineRepository(
      uploadTarget: uploadTarget,
      statuses: const [
        MediaStatus(mediaId: 'media-1', state: 'processing'),
        MediaStatus(mediaId: 'media-1', state: 'ready'),
      ],
    );

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
      required String mediaId,
      required String courseId,
      required String lessonId,
      required Uri uploadUrl,
      required String objectPath,
      required Map<String, String> headers,
      required WavUploadFile file,
      required String contentType,
      required void Function(int sent, int total) onProgress,
      WavUploadCancelToken? cancelToken,
      void Function(bool resumed)? onResume,
      Future<bool> Function()? ensureAuth,
      Future<WavUploadSigningRefresh> Function(WavResumableSession session)?
      refreshSigning,
      void Function()? onSigningRefresh,
      WavResumableSession? resumableSession,
    }) async {
      onProgress(10, 10);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaPipelineRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: WavUploadCard(
              courseId: 'course-1',
              lessonId: 'lesson-1',
              pickFileOverride: fakePick,
              uploadFileOverride: fakeUpload,
              pollInterval: const Duration(seconds: 10),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ladda upp WAV'), findsOneWidget);
    expect(find.text('Byt WAV'), findsNothing);

    await tester.tap(find.text('Ladda upp WAV'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Demo');
    await tester.pump();
    await tester.tap(find.text('Fortsätt'));
    await tester.pumpAndSettle();

    expect(find.text('Ladda upp WAV'), findsOneWidget);
    expect(find.text('Byt WAV'), findsNothing);
    expect(find.text('Uppladdning klar – bearbetas till MP3'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(find.text('Ladda upp WAV'), findsOneWidget);
    expect(find.text('Byt WAV'), findsNothing);
    expect(find.text('MP3 klar – ljudet kan spelas upp'), findsOneWidget);
  });

  testWidgets('shows upload action by default', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: WavUploadCard(courseId: 'course-1', lessonId: 'lesson-1'),
          ),
        ),
      ),
    );

    expect(find.text('Ladda upp WAV'), findsOneWidget);
    expect(find.text('Byt WAV'), findsNothing);
    expect(find.text('Uppladdning klar – bearbetas till MP3'), findsNothing);
  });

  testWidgets('shows error when lesson context is missing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: WavUploadCard(courseId: null, lessonId: 'lesson-1'),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Lektionen saknar kurskoppling. Ladda om eller välj lektion igen.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ladda upp WAV'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Ladda upp WAV'),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
