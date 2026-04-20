import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/widgets/wav_upload_card.dart';
import 'package:aveli/features/studio/widgets/wav_upload_source.dart';

class _MockStudioRepository extends Mock implements StudioRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(CancelToken());
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

    expect(find.text('Ladda upp ljud'), findsOneWidget);
    expect(find.text('Byt ljud'), findsNothing);
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
    expect(find.text('Ladda upp ljud'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Ladda upp ljud'),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('uploads audio through canonical studio lesson media pipeline', (
    tester,
  ) async {
    final repo = _MockStudioRepository();
    when(
      () => repo.uploadLessonMedia(
        lessonId: any(named: 'lessonId'),
        data: any(named: 'data'),
        filename: any(named: 'filename'),
        contentType: any(named: 'contentType'),
        mediaType: any(named: 'mediaType'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((invocation) async {
      final onProgress =
          invocation.namedArguments[#onProgress] as void Function(
            UploadProgress progress,
          )?;
      onProgress?.call(const UploadProgress(sent: 5, total: 10));
      return const StudioLessonMediaItem(
        lessonMediaId: 'lesson-media-1',
        lessonId: 'lesson-1',
        position: 1,
        mediaType: 'audio',
        state: 'processing',
        previewReady: false,
        mediaAssetId: 'media-1',
      );
    });

    Future<WavUploadFile?> fakePick() async {
      final data = Uint8List(10);
      final file = fs.XFile.fromData(
        data,
        path: 'demo.mp3',
        name: 'demo.mp3',
        mimeType: 'audio/mpeg',
      );
      return WavUploadFile(file, 'audio/mpeg', 10);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [studioRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: WavUploadCard(
              courseId: 'course-1',
              lessonId: 'lesson-1',
              pickFileOverride: fakePick,
              pollInterval: const Duration(hours: 1),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ladda upp ljud'));
    await tester.pumpAndSettle();

    expect(find.text('demo.mp3'), findsOneWidget);
    expect(find.text('Uppladdning klar – bearbetas till MP3'), findsOneWidget);
    verify(
      () => repo.uploadLessonMedia(
        lessonId: 'lesson-1',
        data: any(named: 'data'),
        filename: 'demo.mp3',
        contentType: 'audio/mpeg',
        mediaType: 'audio',
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
  });
}
