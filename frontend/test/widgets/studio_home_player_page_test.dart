import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/profile_media_page.dart';

class _FakeApiClient extends Fake implements ApiClient {}

class _PageStudioRepository extends StudioRepository {
  _PageStudioRepository(this._payload) : super(client: _FakeApiClient());

  HomePlayerLibraryPayload _payload;

  final List<bool> toggledUploads = <bool>[];
  final List<String> deletedUploads = <String>[];
  final List<String> createdCourseLinks = <String>[];

  @override
  Future<HomePlayerLibraryPayload> fetchHomePlayerLibrary() async => _payload;

  @override
  Future<HomePlayerUploadItem> updateHomePlayerUpload(
    String uploadId, {
    String? title,
    bool? active,
  }) async {
    final uploads = _payload.uploads
        .map((upload) {
          if (upload.id != uploadId) return upload;
          final updated = upload.copyWith(
            title: title ?? upload.title,
            active: active ?? upload.active,
          );
          if (active != null) {
            toggledUploads.add(active);
          }
          return updated;
        })
        .toList(growable: false);
    _payload = HomePlayerLibraryPayload(
      uploads: uploads,
      courseLinks: _payload.courseLinks,
      courseMedia: _payload.courseMedia,
    );
    return uploads.firstWhere((upload) => upload.id == uploadId);
  }

  @override
  Future<void> deleteHomePlayerUpload(String uploadId) async {
    deletedUploads.add(uploadId);
    _payload = HomePlayerLibraryPayload(
      uploads: _payload.uploads
          .where((upload) => upload.id != uploadId)
          .toList(growable: false),
      courseLinks: _payload.courseLinks,
      courseMedia: _payload.courseMedia,
    );
  }

  @override
  Future<HomePlayerCourseLinkItem> createHomePlayerCourseLink({
    required String lessonMediaId,
    required String title,
    bool enabled = true,
  }) async {
    createdCourseLinks.add(lessonMediaId);
    final created = HomePlayerCourseLinkItem(
      id: 'link-created',
      lessonMediaId: lessonMediaId,
      title: title,
      courseTitle: 'Kurs två',
      enabled: enabled,
      status: HomePlayerCourseLinkStatus.active,
      kind: 'audio',
      createdAt: DateTime.utc(2026, 4, 21, 11, 30),
    );
    _payload = HomePlayerLibraryPayload(
      uploads: _payload.uploads,
      courseLinks: <HomePlayerCourseLinkItem>[..._payload.courseLinks, created],
      courseMedia: _payload.courseMedia,
    );
    return created;
  }
}

void main() {
  testWidgets(
    'page renders backend-backed library and only offers audio course media',
    (tester) async {
      final repo = _PageStudioRepository(_pagePayload());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'http://localhost:8080',
                subscriptionsEnabled: false,
              ),
            ),
            studioRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: StudioProfilePage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Morgonljud'), findsOneWidget);
      expect(find.text('Kvällsljud'), findsOneWidget);
      expect(find.text('Ljud för Home-spelaren'), findsOneWidget);
      expect(find.text('Länkat ljud från kurser'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Länka ljud'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Länka ljud'));
      await tester.pumpAndSettle();

      expect(find.text('Välj kursljud att länka'), findsOneWidget);
      expect(find.text('Andningspass'), findsOneWidget);
      expect(find.text('Videolektion'), findsNothing);

      await tester.tap(find.text('Andningspass'));
      await tester.pumpAndSettle();

      expect(find.text('Namn på länkat ljud'), findsOneWidget);
      await tester.tap(find.text('Länka ljud').last);
      await tester.pumpAndSettle();

      expect(repo.createdCourseLinks, <String>['lesson-audio-2']);
      expect(find.text('Andningspass'), findsOneWidget);
    },
  );

  testWidgets('page toggles and deletes uploads through the controller', (
    tester,
  ) async {
    final repo = _PageStudioRepository(
      HomePlayerLibraryPayload(
        uploads: <HomePlayerUploadItem>[
          HomePlayerUploadItem(
            id: 'upload-1',
            mediaAssetId: 'media-1',
            title: 'Morgonljud',
            kind: 'audio',
            active: true,
            createdAt: DateTime.utc(2026, 4, 21, 10, 0),
            mediaState: 'ready',
          ),
        ],
        courseLinks: const <HomePlayerCourseLinkItem>[],
        courseMedia: const <TeacherProfileLessonSource>[],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: false,
            ),
          ),
          studioRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: StudioProfilePage()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(Switch).first);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(repo.toggledUploads, <bool>[false]);

    await tester.ensureVisible(find.byIcon(Icons.delete_outline));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ta bort').last);
    await tester.pumpAndSettle();

    expect(repo.deletedUploads, <String>['upload-1']);
    expect(find.text('Morgonljud'), findsNothing);
    expect(find.text('Inga uppladdningar ännu.'), findsOneWidget);
  });
}

HomePlayerLibraryPayload _pagePayload() {
  return HomePlayerLibraryPayload(
    uploads: <HomePlayerUploadItem>[
      HomePlayerUploadItem(
        id: 'upload-1',
        mediaAssetId: 'media-1',
        title: 'Morgonljud',
        kind: 'audio',
        active: true,
        createdAt: DateTime.utc(2026, 4, 21, 10, 0),
        mediaState: 'ready',
      ),
    ],
    courseLinks: <HomePlayerCourseLinkItem>[
      HomePlayerCourseLinkItem(
        id: 'link-1',
        lessonMediaId: 'lesson-audio-1',
        title: 'Kvällsljud',
        courseTitle: 'Kurs ett',
        enabled: true,
        status: HomePlayerCourseLinkStatus.active,
        kind: 'audio',
        createdAt: DateTime.utc(2026, 4, 21, 9, 0),
      ),
    ],
    courseMedia: <TeacherProfileLessonSource>[
      TeacherProfileLessonSource(
        id: 'lesson-audio-2',
        lessonId: 'lesson-2',
        lessonTitle: 'Andningspass',
        courseId: 'course-2',
        courseTitle: 'Kurs två',
        courseSlug: 'kurs-tva',
        kind: 'audio',
        contentType: 'audio/mpeg',
      ),
      TeacherProfileLessonSource(
        id: 'lesson-video-1',
        lessonId: 'lesson-3',
        lessonTitle: 'Videolektion',
        courseId: 'course-3',
        courseTitle: 'Kurs tre',
        courseSlug: 'kurs-tre',
        kind: 'video',
        contentType: 'video/mp4',
      ),
    ],
  );
}
