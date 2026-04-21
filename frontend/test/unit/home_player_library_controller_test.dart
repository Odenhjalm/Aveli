import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/features/studio/application/home_player_library_controller.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';

class _FakeApiClient extends Fake implements ApiClient {}

class _RecordingStudioRepository extends StudioRepository {
  _RecordingStudioRepository(this._payload) : super(client: _FakeApiClient());

  HomePlayerLibraryPayload _payload;

  int fetchCalls = 0;
  final List<bool> toggledUploads = <bool>[];
  final List<String> renamedUploads = <String>[];
  final List<String> deletedUploads = <String>[];
  final List<String> createdCourseLinks = <String>[];
  final List<bool> toggledCourseLinks = <bool>[];
  final List<String> deletedCourseLinks = <String>[];

  @override
  Future<HomePlayerLibraryPayload> fetchHomePlayerLibrary() async {
    fetchCalls += 1;
    return _payload;
  }

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
          if (title != null) {
            renamedUploads.add(title);
          }
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
      textBundle: _payload.textBundle,
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
      textBundle: _payload.textBundle,
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
      createdAt: DateTime.utc(2026, 4, 21, 11, 0),
    );
    _payload = HomePlayerLibraryPayload(
      uploads: _payload.uploads,
      courseLinks: <HomePlayerCourseLinkItem>[..._payload.courseLinks, created],
      courseMedia: _payload.courseMedia,
      textBundle: _payload.textBundle,
    );
    return created;
  }

  @override
  Future<HomePlayerCourseLinkItem> updateHomePlayerCourseLink(
    String linkId, {
    bool? enabled,
    String? title,
  }) async {
    final links = _payload.courseLinks
        .map((link) {
          if (link.id != linkId) return link;
          final updated = HomePlayerCourseLinkItem(
            id: link.id,
            title: title ?? link.title,
            courseTitle: link.courseTitle,
            enabled: enabled ?? link.enabled,
            status: link.status,
            kind: link.kind,
            lessonMediaId: link.lessonMediaId,
            createdAt: link.createdAt,
          );
          if (enabled != null) {
            toggledCourseLinks.add(enabled);
          }
          return updated;
        })
        .toList(growable: false);
    _payload = HomePlayerLibraryPayload(
      uploads: _payload.uploads,
      courseLinks: links,
      courseMedia: _payload.courseMedia,
      textBundle: _payload.textBundle,
    );
    return links.firstWhere((link) => link.id == linkId);
  }

  @override
  Future<void> deleteHomePlayerCourseLink(String linkId) async {
    deletedCourseLinks.add(linkId);
    _payload = HomePlayerLibraryPayload(
      uploads: _payload.uploads,
      courseLinks: _payload.courseLinks
          .where((link) => link.id != linkId)
          .toList(growable: false),
      courseMedia: _payload.courseMedia,
      textBundle: _payload.textBundle,
    );
  }
}

void main() {
  test('controller loads home player library through repository', () async {
    final repo = _RecordingStudioRepository(_payload());
    final container = ProviderContainer(
      overrides: [studioRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final state = await container.read(homePlayerLibraryProvider.future);

    expect(repo.fetchCalls, 1);
    expect(state.uploads.single.title, 'Morgonljud');
    expect(state.courseLinks.single.title, 'Kvällsljud');
    expect(
      state.courseMedia.map((item) => item.id),
      contains('lesson-audio-1'),
    );
  });

  test(
    'controller mutations call repository and refresh state when needed',
    () async {
      final repo = _RecordingStudioRepository(_payload());
      final container = ProviderContainer(
        overrides: [studioRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(homePlayerLibraryProvider.future);
      final controller = container.read(homePlayerLibraryProvider.notifier);

      await controller.toggleUpload('upload-1', false);
      expect(repo.toggledUploads, <bool>[false]);
      expect(repo.fetchCalls, 2);
      expect(
        container
            .read(homePlayerLibraryProvider)
            .valueOrNull
            ?.uploads
            .single
            .active,
        isFalse,
      );

      await controller.renameUpload('upload-1', 'Morgonrutin');
      expect(repo.renamedUploads, <String>['Morgonrutin']);
      expect(
        container
            .read(homePlayerLibraryProvider)
            .valueOrNull
            ?.uploads
            .single
            .title,
        'Morgonrutin',
      );

      await controller.createCourseLink(
        lessonMediaId: 'lesson-audio-2',
        title: 'Nytt länkat ljud',
      );
      expect(repo.createdCourseLinks, <String>['lesson-audio-2']);
      expect(repo.fetchCalls, 3);
      expect(
        container.read(homePlayerLibraryProvider).valueOrNull?.courseLinks,
        hasLength(2),
      );

      await controller.toggleCourseLink('link-created', false);
      expect(repo.toggledCourseLinks, <bool>[false]);
      expect(repo.fetchCalls, 4);
      expect(
        container
            .read(homePlayerLibraryProvider)
            .valueOrNull
            ?.courseLinks
            .firstWhere((link) => link.id == 'link-created')
            .enabled,
        isFalse,
      );

      await controller.deleteUpload('upload-1');
      expect(repo.deletedUploads, <String>['upload-1']);
      expect(repo.fetchCalls, 5);
      expect(
        container.read(homePlayerLibraryProvider).valueOrNull?.uploads,
        isEmpty,
      );

      await controller.deleteCourseLink('link-created');
      expect(repo.deletedCourseLinks, <String>['link-created']);
      expect(repo.fetchCalls, 6);
      expect(
        container
            .read(homePlayerLibraryProvider)
            .valueOrNull
            ?.courseLinks
            .map((link) => link.id),
        <String>['link-1'],
      );
    },
  );
}

HomePlayerLibraryPayload _payload() {
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
        id: 'lesson-audio-1',
        lessonId: 'lesson-1',
        lessonTitle: 'Andning',
        courseId: 'course-1',
        courseTitle: 'Kurs ett',
        courseSlug: 'kurs-ett',
        kind: 'audio',
        contentType: 'audio/mpeg',
      ),
      TeacherProfileLessonSource(
        id: 'lesson-audio-2',
        lessonId: 'lesson-2',
        lessonTitle: 'Avslappning',
        courseId: 'course-2',
        courseTitle: 'Kurs två',
        courseSlug: 'kurs-tva',
        kind: 'audio',
        contentType: 'audio/wav',
      ),
    ],
    textBundle: HomePlayerTextBundle(
      entries: const {
        'studio_editor.profile_media.home_player_library_title':
            HomePlayerCatalogTextValue(
              surfaceId: 'TXT-SURF-071',
              textId: 'studio_editor.profile_media.home_player_library_title',
              authorityClass: 'contract_text',
              canonicalOwner: 'backend_text_catalog',
              sourceContract:
                  'actual_truth/contracts/backend_text_catalog_contract.md',
              backendNamespace: 'backend_text_catalog.studio_editor',
              apiSurface: '/studio/home-player/library',
              deliverySurface: '/studio/home-player/library',
              renderSurface:
                  'frontend/lib/features/studio/presentation/profile_media_page.dart',
              language: 'sv',
              value: 'Home-spelarens bibliotek',
            ),
      },
    ),
  );
}
