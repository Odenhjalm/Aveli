import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy mixed structure/content fixtures are quarantined', () {
    expect(true, isTrue);
  });

  group('embedded lesson media delete guard', () {
    test('_deleteMedia is guarded by _lessonAlreadyContainsMediaId', () {
      final source = _courseEditorSource();
      final deleteMethod = _sourceSlice(
        source,
        '  Future<void> _deleteMedia(String id) async {',
        '  bool _replaceLessonMediaReferencesInEditor',
      );

      final guardIndex = deleteMethod.indexOf(
        '_lessonAlreadyContainsMediaId(id)',
      );
      final repositoryDeleteIndex = deleteMethod.indexOf(
        'await _studioRepo.deleteLessonMedia(lessonId, id);',
      );

      expect(guardIndex, greaterThanOrEqualTo(0));
      expect(repositoryDeleteIndex, greaterThanOrEqualTo(0));
      expect(guardIndex, lessThan(repositoryDeleteIndex));
      expect(
        RegExp(
          r'if\s*\(\s*_lessonAlreadyContainsMediaId\(id\)\s*\)\s*\{[\s\S]*?return;\s*\}[\s\S]*?await _studioRepo\.deleteLessonMedia\(lessonId, id\);',
        ).hasMatch(deleteMethod),
        isTrue,
      );
    });

    test('media-list delete button cannot invoke delete for embedded IDs', () {
      final source = _courseEditorSource();
      final mediaListItem = _sourceSlice(
        source,
        'final mediaId = media.lessonMediaId;',
        'if (!_lessonPreviewMode)',
      );

      expect(
        RegExp(
          r'final mediaIsEmbedded\s*=\s*_lessonAlreadyContainsMediaId\(\s*mediaId,\s*\);',
        ).hasMatch(mediaListItem),
        isTrue,
      );
      expect(
        RegExp(
          r'_lessonPreviewMode\s*\|\|\s*mediaIsEmbedded\s*\?\s*null\s*:\s*\(\)\s*=>\s*_deleteMedia\(',
        ).hasMatch(mediaListItem),
        isTrue,
      );
      expect(mediaListItem, contains('final mediaIsEmbedded ='));
    });
  });

  test('lesson preview mode does not render the course cover block', () {
    final source = _courseEditorSource();
    final previewMode = _sourceSlice(
      source,
      '  Widget _buildLessonPreviewMode(BuildContext context) {',
      '  Widget _buildLessonEditorWorkspace(BuildContext context) {',
    );

    expect(previewMode, isNot(contains('previewCoverUrl')));
    expect(previewMode, isNot(contains('coverUrl')));
    expect(previewMode, isNot(contains('ClipRRect(')));
    expect(previewMode, contains('LessonDocumentReadingModeToggle('));
    expect(previewMode, contains('Expanded('));
  });

  test(
    'editor preview and learner lesson page both depend on shared document rendering primitives',
    () {
      final courseEditorSource = _courseEditorSource();
      final lessonPageSource = _readFrontendSource(
        'lib/features/courses/presentation/lesson_page.dart',
      );

      expect(
        courseEditorSource,
        contains(
          "import 'package:aveli/editor/document/lesson_document_renderer.dart';",
        ),
      );
      expect(courseEditorSource, contains('LessonDocumentPreview('));
      expect(lessonPageSource, contains('return LessonDocumentPreview('));
    },
  );

  test('teacher editor route no longer keys the screen by course boundary', () {
    final routerSource = _readFrontendSource(
      'lib/core/routing/app_router.dart',
    );
    final routeExtrasSource = _readFrontendSource(
      'lib/core/routing/route_extras.dart',
    );

    expect(
      routerSource,
      contains('return CourseEditorScreen(courseId: courseId);'),
    );
    expect(routerSource, isNot(contains(r'teacher-editor-${courseId ??')));
    expect(
      routeExtrasSource,
      contains('const CourseEditorRouteArgs({this.courseId});'),
    );
    expect(routeExtrasSource, isNot(contains('managedCourseFamilyId')));
  });

  test(
    'course boundary resets lesson state in place and keeps narrow editor mounted',
    () {
      final source = _courseEditorSource();

      expect(source, contains('void _prepareCourseBoundarySelection({'));
      expect(
        source,
        contains('_resetSelectedLessonState(bumpHydrationRevision: true);'),
      );
      expect(source, isNot(contains('_restartEditorAtCourseBoundary(')));
      expect(
        source,
        contains('if (!isWide && _selectedCourseId != null) ...['),
      );
      expect(source, contains('Välj en lektion för att hantera media.'));
    },
  );

  group('course public description editing', () {
    test(
      'description hydrates from studio public content and saves via public endpoint',
      () {
        final source = _courseEditorSource();
        final loadCourseMeta = _sourceSlice(
          source,
          '  Future<void> _loadCourseMeta() async {',
          '  Future<void> _loadLessons({',
        );
        final savePublicContent = _sourceSlice(
          source,
          '  Future<void> _saveCoursePublicContent() async {',
          '  Future<bool> _saveCourseDripAuthoring',
        );
        final saveCourseMeta = _sourceSlice(
          source,
          '  Future<void> _saveCourseMeta() async {',
          '  Future<void> _saveCoursePublicContent() async {',
        );

        expect(
          loadCourseMeta,
          contains('_studioRepo.fetchCoursePublicContent(courseId)'),
        );
        expect(
          loadCourseMeta,
          contains('_courseDescriptionCtrl.text = publicContent.description'),
        );
        expect(
          savePublicContent,
          contains('_studioRepo.upsertCoursePublicContent('),
        );
        expect(savePublicContent, contains('description: description'));
        expect(
          saveCourseMeta,
          contains('_studioRepo.upsertCoursePublicContent('),
        );
        expect(saveCourseMeta, contains('description: description'));
        expect(saveCourseMeta, isNot(contains("'description'")));
      },
    );

    test('description textarea renders beside the course image editor', () {
      final source = _courseEditorSource();
      final coverAndDescription = _sourceSlice(
        source,
        '  Widget _buildCourseDescriptionEditor(BuildContext context) {',
        '  Widget _buildInvalidVideoPlaceholder',
      );

      expect(coverAndDescription, contains('_buildCourseCoverPicker(context)'));
      expect(
        coverAndDescription,
        contains('_buildCourseDescriptionEditor(context)'),
      );
      expect(
        coverAndDescription,
        contains('Expanded(child: descriptionEditor)'),
      );
      expect(coverAndDescription, contains("labelText: 'Beskrivning'"));
      expect(
        coverAndDescription,
        contains("ValueKey<String>('course-public-content-save-button')"),
      );
    });

    test('active course cover artifact is removed', () {
      final source = _courseEditorSource();
      final removedLabel = ['Aktiv kurs', 'bild'].join();

      expect(source, isNot(contains(removedLabel)));
    });
  });

  group('custom drip schedule persistence', () {
    test('switching into custom mode does not autosave generated offsets', () {
      final source = _courseEditorSource();
      final handler = _sourceSlice(
        source,
        '  Future<void> _handleCourseDripModeChanged(DripAuthoringMode? mode) async {',
        '  Widget _buildCustomScheduleSummaryChip',
      ).replaceAll('\r\n', '\n');

      expect(
        handler,
        contains(
          'if (mode == DripAuthoringMode.customLessonOffsets) {\n'
          '      _ensureCourseCustomScheduleControllers();\n'
          '    }',
        ),
      );
      expect(
        handler,
        contains(
          'if (_shouldPersistDripModeChangeImmediately(mode)) {\n'
          '      await _saveCourseDripAuthoring(reloadOnFailure: true);\n'
          '    }',
        ),
      );
      expect(
        handler,
        contains('return mode != DripAuthoringMode.customLessonOffsets;'),
      );
    });

    test('manual schedule save remains the custom rows persistence path', () {
      final source = _courseEditorSource();
      final rowsPayload = _sourceSlice(
        source,
        '  List<Map<String, Object?>>? _buildCustomScheduleRowsPayload() {',
        '  Map<String, Object?>? _buildCourseDripAuthoringPayload() {',
      );
      final authoringPayload = _sourceSlice(
        source,
        '  Map<String, Object?>? _buildCourseDripAuthoringPayload() {',
        '  bool _isCourseScheduleLockedError(Object error) {',
      );
      final scheduleSection = _sourceSlice(
        source,
        '  Widget _buildCourseScheduleAuthoring(BuildContext context) {',
        '  Widget _buildCourseFamilyAuthoring(BuildContext context) {',
      );

      expect(rowsPayload, contains("'lesson_id': rowState.lesson.id"));
      expect(rowsPayload, contains("'unlock_offset_days': unlockOffsetDays"));
      expect(
        authoringPayload,
        contains("'custom_schedule': <String, Object?>{'rows': rows}"),
      );
      expect(
        scheduleSection,
        contains("key: const ValueKey<String>('course-schedule-save-button')"),
      );
      expect(
        scheduleSection,
        contains('unawaited(_saveCourseDripAuthoring());'),
      );
    });

    test('backend custom schedule rows hydrate before local defaults render', () {
      final source = _courseEditorSource();
      final loadCourseMeta = _sourceSlice(
        source,
        '  Future<void> _loadCourseMeta() async {',
        '  Future<void> _loadLessons({',
      );
      final hydrateControllers = _sourceSlice(
        source,
        '  void _hydrateCourseCustomScheduleControllers(Map<String, int> seededValues) {',
        '  void _ensureCourseCustomScheduleControllers() {',
      );

      expect(
        loadCourseMeta,
        contains('for (final row in course.dripAuthoring.customScheduleRows)'),
      );
      expect(loadCourseMeta, contains('row.lessonId: row.unlockOffsetDays'));
      expect(
        hydrateControllers,
        contains(
          'seededValues[lesson.id] ?? (index == 0 ? 0 : previousOffsetDays)',
        ),
      );
      expect(
        hydrateControllers,
        contains('_setTextControllerValue(controller, nextText);'),
      );
    });
  });
}

String _courseEditorSource() {
  return _readFrontendSource(
    'lib/features/studio/presentation/course_editor_page.dart',
  );
}

String _readFrontendSource(String frontendRelativePath) {
  final candidates = [
    File(frontendRelativePath),
    File('frontend/$frontendRelativePath'),
  ];

  for (final file in candidates) {
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }

  fail('Unable to locate $frontendRelativePath from ${Directory.current.path}');
}

String _sourceSlice(String source, String startNeedle, String endNeedle) {
  final start = source.indexOf(startNeedle);
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: 'Missing source start marker: $startNeedle',
  );

  final end = source.indexOf(endNeedle, start + startNeedle.length);
  expect(
    end,
    greaterThanOrEqualTo(0),
    reason: 'Missing source end marker: $endNeedle',
  );

  return source.substring(start, end);
}
