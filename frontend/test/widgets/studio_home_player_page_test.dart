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
      createdAt: DateTime.utc(2026, 4, 21, 11, 30),
    );
    _payload = HomePlayerLibraryPayload(
      uploads: _payload.uploads,
      courseLinks: <HomePlayerCourseLinkItem>[..._payload.courseLinks, created],
      courseMedia: _payload.courseMedia,
      textBundle: _payload.textBundle,
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
        textBundle: _textBundle(),
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
    textBundle: _textBundle(),
  );
}

HomePlayerTextBundle _textBundle() {
  const sourceContract = 'actual_truth/contracts/backend_text_catalog_contract.md';
  const apiSurface = '/studio/home-player/library';
  const renderSurface =
      'frontend/lib/features/studio/presentation/profile_media_page.dart';
  HomePlayerCatalogTextValue entry(
    String textId,
    String authorityClass,
    String value,
  ) {
    return HomePlayerCatalogTextValue(
      surfaceId: 'TXT-SURF-071',
      textId: textId,
      authorityClass: authorityClass,
      canonicalOwner: 'backend_text_catalog',
      sourceContract: sourceContract,
      backendNamespace: 'backend_text_catalog.studio_editor',
      apiSurface: apiSurface,
      deliverySurface: apiSurface,
      renderSurface: renderSurface,
      language: 'sv',
      value: value,
    );
  }

  return HomePlayerTextBundle(
    entries: <String, HomePlayerCatalogTextValue>{
      'studio_editor.profile_media.home_player_library_title': entry(
        'studio_editor.profile_media.home_player_library_title',
        'contract_text',
        'Home-spelarens bibliotek',
      ),
      'studio_editor.profile_media.home_player_uploads_title': entry(
        'studio_editor.profile_media.home_player_uploads_title',
        'contract_text',
        'Ljud för Home-spelaren',
      ),
      'studio_editor.profile_media.home_player_uploads_description': entry(
        'studio_editor.profile_media.home_player_uploads_description',
        'contract_text',
        'Ladda upp ljud direkt för Home-spelaren.',
      ),
      'studio_editor.profile_media.home_player_links_title': entry(
        'studio_editor.profile_media.home_player_links_title',
        'contract_text',
        'Länkat ljud från kurser',
      ),
      'studio_editor.profile_media.home_player_links_description': entry(
        'studio_editor.profile_media.home_player_links_description',
        'contract_text',
        'Här ser du ljud som är länkat från kursmaterial.',
      ),
      'studio_editor.profile_media.home_player_links_empty_title': entry(
        'studio_editor.profile_media.home_player_links_empty_title',
        'backend_status_text',
        'Inga länkar ännu.',
      ),
      'studio_editor.profile_media.home_player_links_empty_status': entry(
        'studio_editor.profile_media.home_player_links_empty_status',
        'backend_status_text',
        'Länka in ljud från dina kurser.',
      ),
      'studio_editor.profile_media.home_player_link_action': entry(
        'studio_editor.profile_media.home_player_link_action',
        'contract_text',
        'Länka ljud',
      ),
      'studio_editor.profile_media.refresh_action': entry(
        'studio_editor.profile_media.refresh_action',
        'contract_text',
        'Uppdatera',
      ),
      'studio_editor.profile_media.cancel_action': entry(
        'studio_editor.profile_media.cancel_action',
        'contract_text',
        'Avbryt',
      ),
      'studio_editor.profile_media.link_delete_title': entry(
        'studio_editor.profile_media.link_delete_title',
        'contract_text',
        'Ta bort länk',
      ),
      'studio_editor.profile_media.link_delete_message': entry(
        'studio_editor.profile_media.link_delete_message',
        'contract_text',
        'Originalfilen i kursen påverkas inte.',
      ),
      'studio_editor.profile_media.link_delete_action': entry(
        'studio_editor.profile_media.link_delete_action',
        'contract_text',
        'Ta bort',
      ),
      'studio_editor.profile_media.home_player_uploads_empty_title': entry(
        'studio_editor.profile_media.home_player_uploads_empty_title',
        'backend_status_text',
        'Inga uppladdningar ännu.',
      ),
      'studio_editor.profile_media.home_player_uploads_empty_status': entry(
        'studio_editor.profile_media.home_player_uploads_empty_status',
        'backend_status_text',
        'Ladda upp ljud som bara ska användas i Home-spelaren.',
      ),
      'studio_editor.profile_media.upload_delete_title': entry(
        'studio_editor.profile_media.upload_delete_title',
        'contract_text',
        'Ta bort uppladdad fil',
      ),
      'studio_editor.profile_media.upload_delete_message': entry(
        'studio_editor.profile_media.upload_delete_message',
        'contract_text',
        'Filen raderas helt och går inte att ångra.',
      ),
      'studio_editor.profile_media.upload_delete_action': entry(
        'studio_editor.profile_media.upload_delete_action',
        'contract_text',
        'Ta bort',
      ),
      'studio_editor.profile_media.upload_prompt_title': entry(
        'studio_editor.profile_media.upload_prompt_title',
        'contract_text',
        'Namn på ljudfil',
      ),
      'studio_editor.profile_media.upload_prompt_hint': entry(
        'studio_editor.profile_media.upload_prompt_hint',
        'contract_text',
        'T.ex. "Andningsövning"',
      ),
      'studio_editor.profile_media.upload_ready_status': entry(
        'studio_editor.profile_media.upload_ready_status',
        'backend_status_text',
        'Uppladdning klar.',
      ),
      'studio_editor.profile_media.no_course_audio_status': entry(
        'studio_editor.profile_media.no_course_audio_status',
        'backend_status_text',
        'Inga kursljud hittades.',
      ),
      'studio_editor.profile_media.link_prompt_title': entry(
        'studio_editor.profile_media.link_prompt_title',
        'contract_text',
        'Namn på länkat ljud',
      ),
      'studio_editor.profile_media.link_prompt_hint': entry(
        'studio_editor.profile_media.link_prompt_hint',
        'contract_text',
        'T.ex. "Meditation kväll"',
      ),
      'studio_editor.profile_media.link_created_status': entry(
        'studio_editor.profile_media.link_created_status',
        'backend_status_text',
        'Ljudet har länkats.',
      ),
      'studio_editor.profile_media.course_picker_title': entry(
        'studio_editor.profile_media.course_picker_title',
        'contract_text',
        'Välj kursljud att länka',
      ),
      'studio_editor.profile_media.course_picker_search_hint': entry(
        'studio_editor.profile_media.course_picker_search_hint',
        'contract_text',
        'Sök på kurs eller lektion...',
      ),
      'studio_editor.profile_media.course_picker_empty_status': entry(
        'studio_editor.profile_media.course_picker_empty_status',
        'backend_status_text',
        'Inga ljudfiler matchar sökningen.',
      ),
      'studio_editor.profile_media.audio_kind_label': entry(
        'studio_editor.profile_media.audio_kind_label',
        'contract_text',
        'Ljudfil',
      ),
      'studio_editor.profile_media.processing_status': entry(
        'studio_editor.profile_media.processing_status',
        'backend_status_text',
        'Bearbetar ljud…',
      ),
      'studio_editor.profile_media.processing_failed_error': entry(
        'studio_editor.profile_media.processing_failed_error',
        'backend_error_text',
        'Bearbetningen misslyckades.',
      ),
      'studio_editor.profile_media.title_required_error': entry(
        'studio_editor.profile_media.title_required_error',
        'backend_error_text',
        'Filnamn kan inte vara tomt.',
      ),
      'studio_editor.profile_media.course_link_active_status': entry(
        'studio_editor.profile_media.course_link_active_status',
        'backend_status_text',
        'Aktiv',
      ),
      'studio_editor.profile_media.course_link_source_missing_error': entry(
        'studio_editor.profile_media.course_link_source_missing_error',
        'backend_error_text',
        'Källa saknas',
      ),
      'studio_editor.profile_media.course_link_unpublished_status': entry(
        'studio_editor.profile_media.course_link_unpublished_status',
        'backend_status_text',
        'Kurs ej publicerad',
      ),
      'studio_editor.profile_media.action_failed_error': entry(
        'studio_editor.profile_media.action_failed_error',
        'backend_error_text',
        'Åtgärden kunde inte genomföras. Försök igen.',
      ),
      'home.player_upload.submit_action': HomePlayerCatalogTextValue(
        surfaceId: 'TXT-SURF-075',
        textId: 'home.player_upload.submit_action',
        authorityClass: 'contract_text',
        canonicalOwner: 'backend_text_catalog',
        sourceContract: sourceContract,
        backendNamespace: 'backend_text_catalog.home',
        apiSurface: apiSurface,
        deliverySurface: apiSurface,
        renderSurface:
            'frontend/lib/features/studio/widgets/home_player_upload_dialog.dart',
        language: 'sv',
        value: 'Ladda upp',
      ),
    },
  );
}
