// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding, SemanticsHandle;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:uuid/uuid.dart';

import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/editor/document/lesson_document_editor.dart';
import 'package:aveli/editor/document/lesson_document_renderer.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/utils/money.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/features/editor/widgets/file_picker_web.dart'
    as web_picker;
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/application/studio_upload_queue.dart';
import 'package:aveli/features/studio/presentation/editor_media_controls.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/courses/application/course_providers.dart'
    show coursesProvider;
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/bootstrap/safe_media.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/features/studio/widgets/cover_upload_card.dart';
import 'package:aveli/features/studio/widgets/wav_replace_dialog.dart';
import 'package:aveli/features/studio/widgets/wav_upload_card.dart';
import 'package:aveli/shared/utils/lesson_media_render_telemetry.dart';
import 'package:aveli/features/studio/presentation/lesson_media_preview.dart';
import 'package:aveli/features/studio/presentation/lesson_media_preview_cache.dart';
import 'package:aveli/features/studio/presentation/lesson_media_preview_hydration.dart';
import 'package:aveli/features/studio/presentation/lesson_editor_test_id_dom.dart'
    as lesson_editor_test_id_dom;

@visibleForTesting
String selectCourseCoverRenderSource({
  required String? resolvedUrl,
  required Uint8List? localPreviewBytes,
}) {
  if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
    return 'resolved_url';
  }
  return 'empty';
}

String? safeString(Map<dynamic, dynamic>? source, Object key) {
  if (source == null) return null;
  final value = source[key];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value == null) return null;
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

bool? safeBool(Map<dynamic, dynamic>? source, Object key) {
  if (source == null) return null;
  final value = source[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'ja') {
      return true;
    }
    if (normalized == 'false' ||
        normalized == '0' ||
        normalized == 'no' ||
        normalized == 'nej') {
      return false;
    }
  }
  return null;
}

enum _LessonEditorBootPhase {
  booting,
  applyingLessonDocument,
  error,
  fullyStable,
}

class _EditorDocumentToken {
  const _EditorDocumentToken({
    required this.lessonId,
    required this.selectedLessonId,
    required this.contentRequestId,
  });

  final String lessonId;
  final String selectedLessonId;
  final int contentRequestId;
}

class _CourseCreateInput {
  const _CourseCreateInput({
    required this.title,
    required this.slug,
    required this.courseGroupId,
    required this.priceAmountCents,
    required this.dripEnabled,
    required this.dripIntervalDays,
  });

  final String title;
  final String slug;
  final String courseGroupId;
  final int? priceAmountCents;
  final bool dripEnabled;
  final int? dripIntervalDays;
}

class _CourseFamilySummary {
  const _CourseFamilySummary({
    required this.courseGroupId,
    required this.name,
    required this.courses,
  });

  final String courseGroupId;
  final String name;
  final List<CourseStudio> courses;
}

const String _defaultCourseFamilyName = 'Course Family';

String _courseStepLabel(int groupPosition) {
  if (groupPosition <= 0) {
    return 'Introduktion';
  }
  return 'Step $groupPosition';
}

Widget _dropdownValueLabel(String text) {
  return Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

int? _parsePositiveIntText(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) return null;
  return int.tryParse(normalized);
}

final TextInputFormatter _courseCustomScheduleInputFormatter =
    TextInputFormatter.withFunction((oldValue, newValue) {
      final text = newValue.text;
      if (text.isEmpty || RegExp(r'^-?\d*$').hasMatch(text)) {
        return newValue;
      }
      return oldValue;
    });

enum _CustomScheduleRowValidationKind {
  missingValue,
  invalidInteger,
  negativeValue,
  firstLessonMustBeZero,
  decreasingOffset,
}

class _CustomScheduleTimelineRowState {
  const _CustomScheduleTimelineRowState({
    required this.lesson,
    required this.index,
    required this.rawValue,
    required this.unlockOffsetDays,
    required this.previousUnlockOffsetDays,
    required this.validationKind,
  });

  final LessonStudio lesson;
  final int index;
  final String rawValue;
  final int? unlockOffsetDays;
  final int? previousUnlockOffsetDays;
  final _CustomScheduleRowValidationKind? validationKind;

  bool get isFirst => index == 0;

  String get dayLabel {
    final offsetDays = unlockOffsetDays;
    if (offsetDays == null) {
      return 'Dag -';
    }
    return 'Dag $offsetDays';
  }

  String? get errorText {
    switch (validationKind) {
      case _CustomScheduleRowValidationKind.missingValue:
        return 'Ange antal dagar innan uppl\u00E5sning.';
      case _CustomScheduleRowValidationKind.invalidInteger:
        return 'Ange ett heltal.';
      case _CustomScheduleRowValidationKind.negativeValue:
        return 'V\u00E4rdet kan inte vara negativt.';
      case _CustomScheduleRowValidationKind.firstLessonMustBeZero:
        return 'F\u00F6rsta lektionen m\u00E5ste starta dag 0.';
      case _CustomScheduleRowValidationKind.decreasingOffset:
        final previousOffsetDays = previousUnlockOffsetDays ?? 0;
        return 'Kan inte vara tidigare \u00E4n dag $previousOffsetDays f\u00F6r f\u00F6reg\u00E5ende lektion.';
      case null:
        return null;
    }
  }
}

class _CustomScheduleSummaryState {
  const _CustomScheduleSummaryState({
    required this.lessonCount,
    required this.startLabel,
    required this.lastLessonLabel,
  });

  final int lessonCount;
  final String startLabel;
  final String lastLessonLabel;
}

const String _courseScheduleLockedMessage =
    'Detta schema är låst eftersom kursen har deltagare.';

String _dripAuthoringModeLabel(DripAuthoringMode mode) {
  switch (mode) {
    case DripAuthoringMode.noDripImmediateAccess:
      return 'Direkt tillgång';
    case DripAuthoringMode.legacyUniformDrip:
      return 'Fast intervall';
    case DripAuthoringMode.customLessonOffsets:
      return 'Anpassat schema';
  }
}

class _CourseDripConfigurationFields extends StatelessWidget {
  const _CourseDripConfigurationFields({
    required this.dripEnabled,
    required this.dripIntervalController,
    required this.onDripEnabledChanged,
  });

  final bool dripEnabled;
  final TextEditingController dripIntervalController;
  final ValueChanged<bool> onDripEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lektionssläpp',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        gap8,
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: dripEnabled,
          onChanged: onDripEnabledChanged,
          title: const Text('Aktivera lektionssläpp (drip)'),
        ),
        if (dripEnabled) ...[
          gap8,
          TextField(
            controller: dripIntervalController,
            keyboardType: const TextInputType.numberWithOptions(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Antal dagar mellan lektioner',
              helperText: 'Ange ett heltal större än 0.',
            ),
          ),
          gap8,
          Text(
            'Ändringar påverkar alla nuvarande deltagare i kursen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _CourseCreateDialog extends StatefulWidget {
  const _CourseCreateDialog({
    required this.defaultSlug,
    required this.courseFamilies,
    required this.initialCourseGroupId,
  });

  final String defaultSlug;
  final List<CourseFamilyStudio> courseFamilies;
  final String? initialCourseGroupId;

  @override
  State<_CourseCreateDialog> createState() => _CourseCreateDialogState();
}

class _CourseCreateDialogState extends State<_CourseCreateDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _slugController;
  late final TextEditingController _priceController;
  late final TextEditingController _dripIntervalController;
  late String _selectedFamilyValue;
  bool _dripEnabled = false;
  String? _errorText;

  CourseFamilyStudio? get _selectedCourseFamily {
    for (final family in widget.courseFamilies) {
      if (family.id == _selectedFamilyValue) {
        return family;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'Ny kurs');
    _slugController = TextEditingController(text: widget.defaultSlug);
    _priceController = TextEditingController();
    _dripIntervalController = TextEditingController();
    final hasInitialFamily =
        widget.initialCourseGroupId != null &&
        widget.courseFamilies.any(
          (family) => family.id == widget.initialCourseGroupId,
        );
    _selectedFamilyValue = hasInitialFamily
        ? widget.initialCourseGroupId!
        : (widget.courseFamilies.isEmpty ? '' : widget.courseFamilies.first.id);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _slugController.dispose();
    _priceController.dispose();
    _dripIntervalController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    final rawPriceText = _priceController.text.trim();
    final rawDripIntervalText = _dripIntervalController.text.trim();
    final priceAmountCents = rawPriceText.isEmpty
        ? null
        : parseSekInputToOre(rawPriceText);
    final dripIntervalDays = _dripEnabled
        ? _parsePositiveIntText(rawDripIntervalText)
        : null;
    if (title.isEmpty) {
      setState(() => _errorText = 'Titel krävs.');
      return;
    }
    if (slug.isEmpty) {
      setState(() => _errorText = 'Kursadress krävs.');
      return;
    }
    if (_selectedFamilyValue.isEmpty) {
      setState(() => _errorText = 'Välj en kursfamilj.');
      return;
    }
    if (rawPriceText.isNotEmpty &&
        (priceAmountCents == null || priceAmountCents < 0)) {
      setState(
        () => _errorText =
            'Pris måste vara ett tal ≥ 0 (t.ex. 490 eller 490.00).',
      );
      return;
    }
    if (_dripEnabled && (dripIntervalDays == null || dripIntervalDays <= 0)) {
      setState(
        () => _errorText = 'Antal dagar måste vara ett heltal större än 0.',
      );
      return;
    }

    Navigator.of(context).pop(
      _CourseCreateInput(
        title: title,
        slug: slug,
        courseGroupId: _selectedFamilyValue,
        priceAmountCents: priceAmountCents,
        dripEnabled: _dripEnabled,
        dripIntervalDays: dripIntervalDays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Skapa ny kurs'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Titel'),
            ),
            gap12,
            TextField(
              controller: _slugController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Kursadress'),
            ),
            gap12,
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('course_create_family_target'),
              isExpanded: true,
              initialValue: _selectedFamilyValue,
              decoration: const InputDecoration(labelText: 'Course Family'),
              selectedItemBuilder: (context) => [
                for (final family in widget.courseFamilies)
                  _dropdownValueLabel(family.name),
              ],
              items: [
                for (final family in widget.courseFamilies)
                  DropdownMenuItem<String>(
                    value: family.id,
                    child: Text(
                      family.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedFamilyValue = value);
              },
            ),
            gap8,
            Text(
              _selectedCourseFamily == null
                  ? 'Skapa en kursfamilj innan du skapar kurser.'
                  : 'Kursen placeras sist i ${_selectedCourseFamily!.name}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            gap12,
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Pris (SEK)',
                helperText: 'Lämna tomt om kursen inte ska prissättas än.',
              ),
            ),
            gap16,
            _CourseDripConfigurationFields(
              dripEnabled: _dripEnabled,
              dripIntervalController: _dripIntervalController,
              onDripEnabledChanged: (value) {
                setState(() {
                  _dripEnabled = value;
                  _errorText = null;
                });
              },
            ),
            if (_errorText != null) ...[
              gap12,
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Skapa kurs')),
      ],
    );
  }
}

class _CourseFamilyCreateDialog extends StatefulWidget {
  const _CourseFamilyCreateDialog();

  @override
  State<_CourseFamilyCreateDialog> createState() =>
      _CourseFamilyCreateDialogState();
}

class _CourseFamilyCreateDialogState extends State<_CourseFamilyCreateDialog> {
  late final TextEditingController _nameController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _defaultCourseFamilyName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Familjenamn krävs.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Skapa kursfamilj'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Familjenamn'),
            ),
            if (_errorText != null) ...[
              gap12,
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Skapa familj')),
      ],
    );
  }
}

class _CourseFamilyRenameDialog extends StatefulWidget {
  const _CourseFamilyRenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_CourseFamilyRenameDialog> createState() =>
      _CourseFamilyRenameDialogState();
}

class _CourseFamilyRenameDialogState extends State<_CourseFamilyRenameDialog> {
  late final TextEditingController _nameController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Familjenamn krävs.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Byt namn på kursfamilj'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Familjenamn'),
            ),
            if (_errorText != null) ...[
              gap12,
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Spara namn')),
      ],
    );
  }
}

bool _isVideoMedia(StudioLessonMediaItem media) {
  return media.mediaType == 'video';
}

enum _UploadKind { image, video, audio, pdf }

typedef CourseEditorWebFilePicker =
    Future<List<web_picker.WebPickedFile>?> Function({
      required List<String> allowedExtensions,
      required bool allowMultiple,
      String? accept,
    });

class CourseEditorScreen extends ConsumerStatefulWidget {
  final String? courseId;
  final StudioRepository? studioRepository;
  final CoursesRepository? coursesRepository;
  @visibleForTesting
  final CourseEditorWebFilePicker? webImagePicker;

  const CourseEditorScreen({
    super.key,
    this.courseId,
    this.studioRepository,
    this.coursesRepository,
    this.webImagePicker,
  });

  @override
  ConsumerState<CourseEditorScreen> createState() => _CourseEditorScreenState();
}

class _CourseEditorScreenState extends ConsumerState<CourseEditorScreen> {
  static const _uuid = Uuid();
  static const int _coverStatusMaxAttempts = 12;
  static const Duration _coverStatusTimeout = Duration(minutes: 2);
  static const String _lessonEditorTestId = 'lesson-editor';
  static const bool _lessonEditorWebTestIdsEnabled = bool.fromEnvironment(
    'AVELI_LESSON_EDITOR_WEB_TEST_IDS',
  );
  static const Duration _lessonEditorTestIdRetryDelay = Duration(
    milliseconds: 250,
  );
  static const int _lessonEditorTestIdMaxSyncAttempts = 40;
  bool _checking = true;
  bool _allowed = false;
  late final StudioRepository _studioRepo;
  List<CourseStudio> _courses = <CourseStudio>[];
  List<CourseFamilyStudio> _courseFamilies = <CourseFamilyStudio>[];
  String? _selectedCourseId;
  String? _managedCourseFamilyId;

  List<LessonStudio> _lessons = <LessonStudio>[];
  String? _selectedLessonId;
  bool _lessonsLoading = false;

  List<StudioLessonMediaItem> _lessonMedia = <StudioLessonMediaItem>[];
  String? _lessonMediaLessonId;
  bool _mediaLoading = false;
  String? _mediaStatus;
  String? _lessonsLoadError;
  String? _mediaLoadError;
  bool _downloadingMedia = false;
  String? _downloadStatus;
  bool _suppressNextMediaPreview = false;
  bool _lessonActionBusy = false;
  static const Duration _lessonMediaPollInterval = Duration(seconds: 5);
  Timer? _lessonMediaPollTimer;
  Timer? _lessonReorderDebounceTimer;
  bool _lessonMediaPollInFlight = false;
  SemanticsHandle? _lessonEditorSemanticsHandle;
  Timer? _lessonEditorTestIdRetryTimer;
  int _lessonEditorTestIdSyncAttempts = 0;
  bool _lessonEditorTestIdSyncScheduled = false;

  final ScrollController _panelScrollController = ScrollController();
  final TextEditingController _lessonTitleCtrl = TextEditingController();
  final LessonDocumentEditorController _lessonEditorController =
      LessonDocumentEditorController();
  static const Duration _lessonPreviewHydrationTimeout = Duration(seconds: 5);
  late final LessonMediaPreviewHydrationController _previewHydrationController;
  _LessonEditorBootPhase _lessonEditorBootPhase =
      _LessonEditorBootPhase.booting;
  String? _documentReadyLessonId;
  int? _documentReadyRequestId;
  bool _lessonPreviewMode = false;
  LessonDocumentReadingMode _lessonPreviewReadingMode =
      LessonDocumentReadingMode.glass;
  bool _lessonPreviewLoading = false;
  bool _lessonContentDirty = false;
  bool _lessonContentSaving = false;
  String _lastSavedLessonTitle = '';
  LessonDocument _lessonDocument = LessonDocument.empty();
  int? _lessonDocumentInsertionIndex;
  LessonDocument _lastSavedLessonDocument = LessonDocument.empty();
  String? _lastSavedLessonContentEtag;
  LessonDocument? _lessonPreviewDocument;
  List<LessonDocumentPreviewMedia> _lessonPreviewMedia =
      <LessonDocumentPreviewMedia>[];
  String? _lessonPreviewError;
  String? _lessonContentHydratedLessonId;
  String? _lessonContentLoadError;

  final TextEditingController _courseTitleCtrl = TextEditingController();
  final TextEditingController _courseSlugCtrl = TextEditingController();
  final TextEditingController _courseDescriptionCtrl = TextEditingController();
  final TextEditingController _coursePriceCtrl = TextEditingController();
  final TextEditingController _courseDripIntervalCtrl = TextEditingController();
  final Map<String, TextEditingController> _courseCustomScheduleCtrls =
      <String, TextEditingController>{};
  DripAuthoringMode _courseDripMode = DripAuthoringMode.noDripImmediateAccess;
  DripAuthoringMode? _courseCustomTimelineEntrySourceMode;
  bool _courseScheduleLocked = false;

  bool _courseMetaLoading = false;
  bool _savingCourseMeta = false;
  bool _savingCoursePublicContent = false;
  bool _savingCourseDripAuthoring = false;
  bool _creatingCourse = false;
  bool _creatingCourseFamily = false;
  bool _publishingCourse = false;
  bool _updatingCourseFamily = false;
  String? _courseCoverPath;
  bool _updatingCourseCover = false;
  String? _coverPipelineMediaId;
  String? _coverPipelineState;
  String? _coverPipelineError;
  int _coverPollAttempts = 0;
  DateTime? _coverPollStartedAt;
  int _coverPollRequestId = 0;
  int _coverActionRequestId = 0;
  String? _coverActionCourseId;
  Timer? _coverPollTimer;
  String? _lastCourseCoverRenderSignature;

  ProviderSubscription<List<UploadJob>>? _uploadSubscription;
  final Set<String> _lessonsNeedingRefresh = <String>{};
  int _courseMetaRequestId = 0;
  int _lessonsRequestId = 0;
  int _lessonMediaRequestId = 0;
  int _lessonContentRequestId = 0;
  int _lessonPreviewRequestId = 0;
  int _saveCourseRequestId = 0;
  int _saveCoursePublicContentRequestId = 0;
  int _saveCourseDripRequestId = 0;
  int _publishCourseRequestId = 0;

  void _showFriendlyErrorSnack(
    String prefix,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    if (!mounted || !context.mounted) return;
    final failure = AppFailure.from(error, stackTrace);
    final detail = failure.message.trim();
    final message = detail.isEmpty ? prefix : '$prefix: $detail';
    showSnack(context, message);
  }

  bool get _courseScheduleControlsDisabled =>
      _lessonPreviewMode || _courseScheduleLocked || _savingCourseDripAuthoring;

  bool get _courseHasLessonsForCustomSchedule => _lessons.isNotEmpty;

  bool get _courseScheduleSaveDisabled =>
      _courseScheduleControlsDisabled ||
      (_courseDripMode == DripAuthoringMode.customLessonOffsets &&
          !_courseHasLessonsForCustomSchedule);

  String get _customScheduleLessonDependencyMessage =>
      'Lägg till minst en lektion för att använda anpassat schema.';

  List<DripAuthoringMode> _availableCourseDripModes() {
    final modes = <DripAuthoringMode>[
      DripAuthoringMode.noDripImmediateAccess,
      DripAuthoringMode.legacyUniformDrip,
    ];
    if (_courseHasLessonsForCustomSchedule ||
        _courseDripMode == DripAuthoringMode.customLessonOffsets) {
      modes.add(DripAuthoringMode.customLessonOffsets);
    }
    return modes;
  }

  bool _isStaleRequest({
    required int requestId,
    required int currentId,
    String? courseId,
    String? lessonId,
  }) {
    // Discard async results if selection changed while the request was in-flight.
    if (requestId != currentId) return true;
    if (courseId != null && courseId != _selectedCourseId) return true;
    if (lessonId != null && lessonId != _selectedLessonId) return true;
    return false;
  }

  void _setSelectedLessonId(String? lessonId) {
    if (_selectedLessonId == lessonId) return;
    _selectedLessonId = lessonId;
    _lessonPreviewMode = false;
  }

  void _ensureLessonEditorWebTestIdSupport() {
    if (!kIsWeb || !_lessonEditorWebTestIdsEnabled) return;
    _lessonEditorSemanticsHandle ??= SemanticsBinding.instance
        .ensureSemantics();
    _scheduleLessonEditorTestIdSync(resetAttempts: true);
  }

  void _scheduleLessonEditorTestIdSync({bool resetAttempts = false}) {
    if (!kIsWeb ||
        !_lessonEditorWebTestIdsEnabled ||
        _lessonEditorTestIdSyncScheduled) {
      return;
    }
    if (resetAttempts) {
      _lessonEditorTestIdSyncAttempts = 0;
      _lessonEditorTestIdRetryTimer?.cancel();
      _lessonEditorTestIdRetryTimer = null;
    }
    _lessonEditorTestIdSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lessonEditorTestIdSyncScheduled = false;
      if (!mounted) return;
      final synced = _syncLessonEditorTestId();
      if (synced ||
          _lessonEditorTestIdSyncAttempts >=
              _lessonEditorTestIdMaxSyncAttempts) {
        return;
      }
      _lessonEditorTestIdRetryTimer?.cancel();
      _lessonEditorTestIdRetryTimer = Timer(_lessonEditorTestIdRetryDelay, () {
        if (!mounted) return;
        _scheduleLessonEditorTestIdSync();
      });
    });
  }

  // Mirror Flutter's semantics identifier to Playwright's expected selector.
  bool _syncLessonEditorTestId() {
    if (!kIsWeb || !_lessonEditorWebTestIdsEnabled) return false;
    _lessonEditorTestIdSyncAttempts += 1;
    return lesson_editor_test_id_dom.syncLessonEditorTestId(
      testId: _lessonEditorTestId,
    );
  }

  Widget _wrapLessonEditorForWebTestIds(Widget child) {
    if (!_lessonEditorWebTestIdsEnabled) {
      return child;
    }
    return Semantics(identifier: _lessonEditorTestId, child: child);
  }

  void _resetLessonPreviewHydrationValues({bool bumpRevision = false}) {
    _previewHydrationController.reset(bumpRevision: bumpRevision);
  }

  void _resetLessonEditorBootValues({
    required _LessonEditorBootPhase phase,
    bool bumpHydrationRevision = false,
    String? errorMessage,
  }) {
    _documentReadyLessonId = null;
    _documentReadyRequestId = null;
    _lessonContentHydratedLessonId = null;
    _lastSavedLessonContentEtag = null;
    _lessonDocument = LessonDocument.empty();
    _lessonDocumentInsertionIndex = null;
    _lessonContentLoadError = errorMessage;
    _resetLessonPreviewHydrationValues(bumpRevision: bumpHydrationRevision);
    _lessonPreviewRequestId += 1;
    _lessonPreviewMode = false;
    _lessonPreviewLoading = false;
    _lessonPreviewDocument = null;
    _lessonPreviewMedia = <LessonDocumentPreviewMedia>[];
    _lessonPreviewError = null;
    _lessonEditorBootPhase = phase;
  }

  void _resetSelectedLessonState({bool bumpHydrationRevision = false}) {
    _stopLessonMediaPolling();
    _lessonContentRequestId += 1;
    _lessonMediaRequestId += 1;
    _setSelectedLessonId(null);
    _lessonPreviewReadingMode = LessonDocumentReadingMode.glass;
    _lessonMedia = <StudioLessonMediaItem>[];
    _lessonMediaLessonId = null;
    _mediaLoading = false;
    _mediaLoadError = null;
    _mediaStatus = null;
    _downloadStatus = null;
    _downloadingMedia = false;
    _suppressNextMediaPreview = false;
    _lessonContentDirty = false;
    _lastSavedLessonTitle = '';
    _lastSavedLessonDocument = LessonDocument.empty();
    _resetLessonEditorBootValues(
      phase: _LessonEditorBootPhase.booting,
      bumpHydrationRevision: bumpHydrationRevision,
    );
    _setLessonTitleFieldValue('');
  }

  void _prepareCourseBoundarySelection({
    required String? courseId,
    String? managedCourseFamilyId,
  }) {
    final normalizedCourseId = courseId?.trim();
    final normalizedManagedCourseFamilyId = managedCourseFamilyId?.trim();
    final nextCourseId =
        normalizedCourseId == null || normalizedCourseId.isEmpty
        ? null
        : normalizedCourseId;
    final preferredManagedCourseFamilyId =
        normalizedManagedCourseFamilyId != null &&
            normalizedManagedCourseFamilyId.isNotEmpty
        ? normalizedManagedCourseFamilyId
        : _courseById(nextCourseId)?.courseGroupId ?? _managedCourseFamilyId;
    _selectedCourseId = nextCourseId;
    _managedCourseFamilyId = _courseFamilyManagementTarget(
      selectedCourseId: nextCourseId,
      currentValue: preferredManagedCourseFamilyId,
      courses: _courses,
      courseFamilies: _courseFamilies,
    );
    _courseMetaLoading = nextCourseId != null;
    _lessonsLoading = nextCourseId != null;
    _lessonsLoadError = null;
    _resetSelectedLessonState(bumpHydrationRevision: true);
  }

  Future<void> _awaitBootShellFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 1), () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
    });
    return completer.future;
  }

  _EditorDocumentToken? _captureEditorToken() {
    final selectedLessonId = _selectedLessonId;
    final lessonId = _documentReadyLessonId;
    final contentRequestId = _documentReadyRequestId;
    if (lessonId == null ||
        selectedLessonId == null ||
        contentRequestId == null) {
      return null;
    }
    return _EditorDocumentToken(
      lessonId: lessonId,
      selectedLessonId: selectedLessonId,
      contentRequestId: contentRequestId,
    );
  }

  bool _isEditorTokenValid(_EditorDocumentToken? token) {
    if (token == null) return false;
    return token.lessonId == _documentReadyLessonId &&
        token.selectedLessonId == _selectedLessonId &&
        token.contentRequestId == _documentReadyRequestId &&
        token.contentRequestId == _lessonContentRequestId &&
        _lessonContentLoadError == null;
  }

  void _handleLessonDocumentDirtyChanged(bool dirty) {
    if (!_isSelectedLessonDocumentReady()) {
      return;
    }
    final titleDirty = _lessonTitleCtrl.text.trim() != _lastSavedLessonTitle;
    final nextDirty = dirty || titleDirty;
    if (!mounted) {
      _lessonContentDirty = nextDirty;
      return;
    }
    if (_lessonContentDirty != nextDirty) {
      setState(() => _lessonContentDirty = nextDirty);
    }
  }

  bool _requireEditModeForMutation() {
    if (!_lessonPreviewMode) {
      return true;
    }
    if (mounted && context.mounted) {
      showSnack(context, 'Växla till Redigera för att ändra innehåll.');
    }
    return false;
  }

  bool _isSelectedLessonDocumentReady() {
    final selectedLessonId = _selectedLessonId;
    final documentReadyRequestId = _documentReadyRequestId;
    final contentEtag = _lastSavedLessonContentEtag;
    if (selectedLessonId == null || documentReadyRequestId == null) {
      return false;
    }
    if (contentEtag == null || contentEtag.trim().isEmpty) {
      return false;
    }
    return _documentReadyLessonId == selectedLessonId &&
        _lessonContentHydratedLessonId == selectedLessonId &&
        _lessonContentLoadError == null &&
        documentReadyRequestId == _lessonContentRequestId;
  }

  Future<void> _setLessonPreviewMode(bool enabled) async {
    if (!enabled) {
      _lessonPreviewRequestId += 1;
      if (!mounted) {
        _lessonPreviewMode = false;
        _lessonPreviewLoading = false;
        _lessonPreviewDocument = null;
        _lessonPreviewMedia = <LessonDocumentPreviewMedia>[];
        _lessonPreviewError = null;
        return;
      }
      setState(() {
        _lessonPreviewMode = false;
        _lessonPreviewLoading = false;
        _lessonPreviewDocument = null;
        _lessonPreviewMedia = <LessonDocumentPreviewMedia>[];
        _lessonPreviewError = null;
      });
      return;
    }

    if (!_isSelectedLessonDocumentReady()) {
      return;
    }
    final lessonId = _selectedLessonId;
    if (lessonId == null) {
      return;
    }
    if (_lessonContentSaving) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'Vänta tills lektionen har sparats innan du förhandsgranskar.',
        );
      }
      return;
    }
    if (_savingCourseMeta) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'Vänta tills kursinformationen har sparats innan du förhandsgranskar.',
        );
      }
      return;
    }
    if (_lessonActionBusy) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'Vänta tills lektionen har uppdaterats innan du förhandsgranskar.',
        );
      }
      return;
    }
    if (_updatingCourseCover) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'Vänta tills kursbilden har uppdaterats innan du förhandsgranskar.',
        );
      }
      return;
    }
    if (_lessonPreviewMode) {
      return;
    }

    final requestId = ++_lessonPreviewRequestId;
    if (!mounted) {
      _lessonPreviewMode = true;
      _lessonPreviewLoading = true;
      _lessonPreviewDocument = null;
      _lessonPreviewMedia = <LessonDocumentPreviewMedia>[];
      _lessonPreviewError = null;
      return;
    }
    setState(() {
      _lessonPreviewMode = true;
      _lessonPreviewLoading = true;
      _lessonPreviewDocument = null;
      _lessonPreviewMedia = <LessonDocumentPreviewMedia>[];
      _lessonPreviewError = null;
    });
    await _loadPersistedLessonPreview(lessonId: lessonId, requestId: requestId);
  }

  bool _matchesCurrentLessonRequest({
    required String lessonId,
    required int requestId,
  }) {
    if (!mounted) return false;
    return _selectedLessonId == lessonId &&
        _lessonContentRequestId == requestId;
  }

  bool _isStaleLessonPreviewRequest({
    required String lessonId,
    required int requestId,
  }) {
    if (!mounted) return true;
    return !_lessonPreviewMode ||
        _selectedLessonId != lessonId ||
        _lessonPreviewRequestId != requestId;
  }

  List<String> _persistedPreviewMediaIds(StudioLessonContentRead content) {
    return _embeddedLessonMediaIdsFromDocument(
      content.contentDocument,
    ).toList(growable: false);
  }

  Future<List<LessonDocumentPreviewMedia>> _readPersistedPreviewMedia(
    StudioLessonContentRead content,
  ) async {
    final mediaIds = _persistedPreviewMediaIds(content);
    if (mediaIds.isEmpty) return const <LessonDocumentPreviewMedia>[];
    final placements = await _studioRepo.fetchLessonMediaPlacements(mediaIds);
    return placements.map(_previewMediaFromPlacement).toList(growable: false);
  }

  LessonDocumentPreviewMedia _previewMediaFromPlacement(
    StudioLessonMediaItem media,
  ) {
    return LessonDocumentPreviewMedia(
      lessonMediaId: media.lessonMediaId,
      mediaType: media.mediaType,
      state: media.state,
      label: _safeLessonPreviewMediaLabel(media.originalName),
      resolvedUrl: media.media?.resolvedUrl,
    );
  }

  List<LessonDocumentPreviewMedia> _editorDocumentMedia() {
    return [
      for (final media in _lessonMedia)
        LessonDocumentPreviewMedia(
          lessonMediaId: media.lessonMediaId,
          mediaType: media.mediaType,
          state: media.state,
          label: _safeLessonPreviewMediaLabel(media.originalName),
          resolvedUrl: media.media?.resolvedUrl,
        ),
    ];
  }

  String? _safeLessonPreviewMediaLabel(String? label) {
    final normalized = label?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> _loadPersistedLessonPreview({
    required String lessonId,
    required int requestId,
  }) async {
    try {
      final content = await _studioRepo.readLessonContent(lessonId);
      if (content.lessonId != lessonId) {
        throw StateError('Lektionsinnehållet hör till fel lektion.');
      }
      if (_isStaleLessonPreviewRequest(
        lessonId: lessonId,
        requestId: requestId,
      )) {
        return;
      }
      final media = await _readPersistedPreviewMedia(content);
      if (_isStaleLessonPreviewRequest(
        lessonId: lessonId,
        requestId: requestId,
      )) {
        return;
      }

      if (kDebugMode) {
        final persistedJson = content.contentDocument.toCanonicalJsonString();
        _traceLessonString('preview.source.persisted_document', persistedJson);
        debugPrint(
          '[LessonTrace] preview.source.authority=backend_read '
          'lesson=$lessonId persisted_only=true media_count=${media.length}',
        );
      }

      setState(() {
        _lessonPreviewLoading = false;
        _lessonPreviewDocument = content.contentDocument;
        _lessonPreviewMedia = media;
        _lessonPreviewError = null;
      });
    } catch (error, stackTrace) {
      if (_isStaleLessonPreviewRequest(
        lessonId: lessonId,
        requestId: requestId,
      )) {
        return;
      }
      final failure = AppFailure.from(error, stackTrace);
      setState(() {
        _lessonPreviewLoading = false;
        _lessonPreviewDocument = null;
        _lessonPreviewMedia = <LessonDocumentPreviewMedia>[];
        _lessonPreviewError =
            'Kunde inte läsa sparad förhandsgranskning: ${failure.message}';
      });
    }
  }

  void _startInitialLessonPreviewHydration({
    required String lessonId,
    required int requestId,
    required Set<String> initialHydrationIds,
  }) {
    final cache = ref.read(lessonMediaPreviewCacheProvider);
    final batch = cache.beginHydrationBatch(initialHydrationIds);
    if (!_matchesCurrentLessonRequest(
      lessonId: lessonId,
      requestId: requestId,
    )) {
      return;
    }
    _previewHydrationController.start(
      lessonId: lessonId,
      requestId: requestId,
      initialHydrationIds: initialHydrationIds,
      hydratingEmbedIds: batch.hydratingIds,
      settled: batch.settled,
    );
  }

  int _beginCoverAction({required String courseId}) {
    _coverPollTimer?.cancel();
    _coverPollTimer = null;
    _coverPollAttempts = 0;
    _coverPollStartedAt = null;
    _coverActionRequestId += 1;
    _coverActionCourseId = courseId;
    return _coverActionRequestId;
  }

  Future<String?> _resolveStudioCourseImageUrl(CourseStudio course) {
    return Future<String?>.value(course.cover?.resolvedUrl);
  }

  void _logCourseMetaPatchPayload({
    required String courseId,
    required Map<String, Object?> patch,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[COURSE_COVER_META_PATCH] course_id=$courseId '
      'cover_media_id=${patch['cover_media_id'] ?? '<absent>'} '
      'cover=<patch-body-only>',
    );
  }

  void _logCourseMetaPatchResponse({
    required String courseId,
    required CourseStudio response,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[COURSE_COVER_META_PATCH_RESPONSE] course_id=$courseId '
      'cover_media_id=${response.coverMediaId ?? '<absent>'}',
    );
  }

  void _logCourseMetaReloadResponse({
    required String courseId,
    required CourseStudio response,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[COURSE_COVER_META_RELOAD] course_id=$courseId '
      'cover_media_id=${response.coverMediaId ?? '<absent>'}',
    );
  }

  void _logCourseCoverRender({required String source, String? resolvedUrl}) {
    if (!kDebugMode) return;
    final signature = '$source|${resolvedUrl ?? '<none>'}';
    if (_lastCourseCoverRenderSignature == signature) {
      return;
    }
    _lastCourseCoverRenderSignature = signature;
    debugPrint('[COURSE_COVER_RENDER] using=$source');
  }

  void _handleMediaPreviewTap(StudioLessonMediaItem media) {
    if (_suppressNextMediaPreview) {
      _suppressNextMediaPreview = false;
      return;
    }
    if (_isWavMedia(media)) {
      return;
    }
    _previewMedia(media);
  }

  @override
  void initState() {
    super.initState();
    _ensureLessonEditorWebTestIdSupport();
    _previewHydrationController = LessonMediaPreviewHydrationController(
      timeout: _lessonPreviewHydrationTimeout,
    );
    _studioRepo = widget.studioRepository ?? ref.read(studioRepositoryProvider);
    _lessonTitleCtrl.addListener(_handleLessonTitleChanged);
    _bootstrap();
    _uploadSubscription = ref.listenManual<List<UploadJob>>(
      studioUploadQueueProvider,
      _onUploadQueueChanged,
    );
  }

  @override
  void dispose() {
    _uploadSubscription?.close();
    _courseTitleCtrl.dispose();
    _courseSlugCtrl.dispose();
    _courseDescriptionCtrl.dispose();
    _coursePriceCtrl.dispose();
    _courseDripIntervalCtrl.dispose();
    for (final controller in _courseCustomScheduleCtrls.values) {
      _disposeCourseCustomScheduleController(controller);
    }
    _courseCustomScheduleCtrls.clear();
    _panelScrollController.dispose();
    _lessonTitleCtrl.dispose();
    _coverPollTimer?.cancel();
    _lessonMediaPollTimer?.cancel();
    _lessonReorderDebounceTimer?.cancel();
    _lessonEditorTestIdRetryTimer?.cancel();
    _lessonEditorSemanticsHandle?.dispose();
    _lessonEditorController.dispose();
    _previewHydrationController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final authState = ref.read(authControllerProvider);
    if (!authState.canEnterApp) {
      if (!mounted) return;
      setState(() {
        _allowed = false;
        _checking = false;
      });
      return;
    }
    try {
      final status = await ref.read(studioRepositoryProvider).fetchStatus();
      final allowed = status.isTeacher;
      List<CourseStudio> myCourses = <CourseStudio>[];
      List<CourseFamilyStudio> myCourseFamilies = <CourseFamilyStudio>[];
      if (allowed) {
        final results = await Future.wait<Object>([
          _studioRepo.myCourses(),
          _studioRepo.myCourseFamilies(),
        ]);
        myCourses = List<CourseStudio>.from(results[0] as List<CourseStudio>);
        myCourseFamilies = List<CourseFamilyStudio>.from(
          results[1] as List<CourseFamilyStudio>,
        );
      }
      if (!mounted) return;
      final initialId = widget.courseId?.trim();
      final selected =
          (initialId != null &&
              initialId.isNotEmpty &&
              _courseById(initialId, myCourses) != null)
          ? initialId
          : _firstCourseId(myCourses);
      setState(() {
        _allowed = allowed;
        _courses = myCourses;
        _courseFamilies = myCourseFamilies;
        _selectedCourseId = selected;
        _managedCourseFamilyId = _courseFamilyManagementTarget(
          selectedCourseId: selected,
          currentValue: null,
          courses: myCourses,
          courseFamilies: myCourseFamilies,
        );
        _checking = false;
      });
      if (_selectedCourseId != null) {
        await _loadCourseMeta();
        await _loadLessons(preserveSelection: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allowed = false;
        _checking = false;
      });
    }
  }

  Future<void> _loadCourseMeta() async {
    final courseId = _selectedCourseId;
    if (courseId == null) return;
    final requestId = ++_courseMetaRequestId;
    setState(() => _courseMetaLoading = true);
    try {
      final results = await Future.wait<Object>([
        _studioRepo.fetchCourseMeta(courseId),
        _studioRepo.fetchCoursePublicContent(courseId),
      ]);
      final course = results[0] as CourseStudio;
      final publicContent = results[1] as StudioCoursePublicContent;
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _courseMetaRequestId,
        courseId: courseId,
      )) {
        return;
      }
      String? resolvedCoverUrl;
      String? coverError;
      try {
        resolvedCoverUrl = await _resolveStudioCourseImageUrl(course);
      } catch (error, stackTrace) {
        coverError = AppFailure.from(error, stackTrace).message;
      }
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _courseMetaRequestId,
        courseId: courseId,
      )) {
        return;
      }
      _logCourseMetaReloadResponse(courseId: courseId, response: course);
      _courseTitleCtrl.text = course.title;
      _courseSlugCtrl.text = course.slug;
      _courseDescriptionCtrl.text = publicContent.description;
      final priceOre = course.priceAmountCents;
      _coursePriceCtrl.text = priceOre == null
          ? ''
          : formatSekInputFromOre(priceOre);
      _courseDripIntervalCtrl.text =
          course.dripAuthoring.dripIntervalDays?.toString() ?? '';
      _hydrateCourseCustomScheduleControllers(<String, int>{
        for (final row in course.dripAuthoring.customScheduleRows)
          row.lessonId: row.unlockOffsetDays,
      });
      if (mounted) {
        setState(() {
          _courses = _adoptCourseById(_courses, course);
          _courseDripMode = course.dripAuthoring.mode;
          _courseCustomTimelineEntrySourceMode = null;
          _courseScheduleLocked = course.dripAuthoring.scheduleLocked;
          _courseCoverPath = resolvedCoverUrl;
          if (!_updatingCourseCover) {
            _coverPipelineError = coverError;
          }
        });
      }
    } catch (e, stackTrace) {
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _courseMetaRequestId,
        courseId: courseId,
      )) {
        return;
      }
      _showFriendlyErrorSnack('Kunde inte läsa kursmetadata', e, stackTrace);
    } finally {
      if (mounted &&
          !_isStaleRequest(
            requestId: requestId,
            currentId: _courseMetaRequestId,
            courseId: courseId,
          )) {
        setState(() => _courseMetaLoading = false);
      }
    }
  }

  Future<void> _loadLessons({
    bool preserveSelection = true,
    bool mergeResults = false,
  }) async {
    final courseId = _selectedCourseId;
    if (courseId == null) {
      if (mounted) {
        setState(() {
          _lessons = <LessonStudio>[];
          _setSelectedLessonId(null);
          _lessonMedia = <StudioLessonMediaItem>[];
          _lessonMediaLessonId = null;
          _lessonsLoadError = null;
          _mediaLoadError = null;
          _resetLessonEditorBootValues(phase: _LessonEditorBootPhase.booting);
        });
      }
      _lessonTitleCtrl
        ..removeListener(_handleLessonTitleChanged)
        ..text = ''
        ..addListener(_handleLessonTitleChanged);
      return;
    }
    final requestId = ++_lessonsRequestId;
    if (mounted) {
      setState(() {
        _lessonsLoading = true;
        _lessonsLoadError = null;
      });
    }
    try {
      final list = await _studioRepo.listCourseLessons(courseId);
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _lessonsRequestId,
        courseId: courseId,
      )) {
        return;
      }
      final lessons = _sortByPosition(
        mergeResults ? _mergeById(_lessons, list) : list,
      );
      final selected =
          preserveSelection &&
              _selectedLessonId != null &&
              _lessonById(_selectedLessonId, lessons) != null
          ? _selectedLessonId
          : _firstLessonId(lessons);
      final selectedChanged = selected != _lessonMediaLessonId;
      setState(() {
        _lessons = lessons;
        _setSelectedLessonId(selected);
        _lessonsLoadError = null;
        _mediaLoadError = null;
        _resetLessonEditorBootValues(
          phase: selected == null
              ? _LessonEditorBootPhase.booting
              : _LessonEditorBootPhase.applyingLessonDocument,
        );
        if (selectedChanged) {
          _lessonMedia = <StudioLessonMediaItem>[];
          _lessonMediaLessonId = selected;
        }
      });
      _ensureCourseCustomScheduleControllers();
      if (_selectedLessonId != null) {
        await _bootSelectedLesson();
      } else if (mounted) {
        setState(() {
          _lessonMedia = <StudioLessonMediaItem>[];
          _lessonMediaLessonId = null;
          _resetLessonEditorBootValues(phase: _LessonEditorBootPhase.booting);
        });
        _lessonTitleCtrl
          ..removeListener(_handleLessonTitleChanged)
          ..text = ''
          ..addListener(_handleLessonTitleChanged);
      }
    } catch (e, stackTrace) {
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _lessonsRequestId,
        courseId: courseId,
      )) {
        return;
      }
      final failure = AppFailure.from(e, stackTrace);
      if (mounted) {
        setState(
          () => _lessonsLoadError =
              'Kunde inte läsa lektioner: ${failure.message}',
        );
      }
    } finally {
      if (mounted &&
          !_isStaleRequest(
            requestId: requestId,
            currentId: _lessonsRequestId,
            courseId: courseId,
          )) {
        setState(() => _lessonsLoading = false);
      }
    }
  }

  Future<void> _loadLessonMedia({String? lessonId}) async {
    final selectedLessonId = lessonId ?? _selectedLessonId;
    if (selectedLessonId == null) {
      _stopLessonMediaPolling();
      if (mounted) {
        setState(() {
          _lessonMedia = <StudioLessonMediaItem>[];
          _lessonMediaLessonId = null;
          _mediaLoadError = null;
          _resetLessonEditorBootValues(phase: _LessonEditorBootPhase.booting);
        });
      }
      _lessonTitleCtrl
        ..removeListener(_handleLessonTitleChanged)
        ..text = ''
        ..addListener(_handleLessonTitleChanged);
      return;
    }
    final courseId = _selectedCourseId;
    final requestId = ++_lessonMediaRequestId;
    if (_lessonMediaLessonId != selectedLessonId) {
      _stopLessonMediaPolling();
    }
    if (mounted) {
      setState(() {
        _mediaLoading = true;
        _mediaLoadError = null;
        if (_lessonMediaLessonId != selectedLessonId) {
          _lessonMedia = <StudioLessonMediaItem>[];
          _lessonMediaLessonId = selectedLessonId;
        }
      });
    }
    try {
      final media = await _readCanonicalLessonMedia(selectedLessonId);
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _lessonMediaRequestId,
        courseId: courseId,
        lessonId: selectedLessonId,
      )) {
        return;
      }
      final previousMedia = List<StudioLessonMediaItem>.from(_lessonMedia);
      _syncLessonMediaPreviewCache(
        previousMedia: previousMedia,
        nextMedia: media,
      );
      setState(() {
        _lessonMedia = media;
        _lessonMediaLessonId = selectedLessonId;
        _mediaLoadError = null;
        if (_lessonsNeedingRefresh.remove(selectedLessonId)) {
          _mediaStatus = 'Media uppdaterad för lektionen.';
        }
      });
      _invalidateCurrentLessonEditorMediaHydration(
        lessonId: selectedLessonId,
        previousMedia: previousMedia,
        nextMedia: media,
      );
      unawaited(
        _refreshLessonMediaAuthoritativeState(
          lessonId: selectedLessonId,
          requestId: requestId,
          mediaItems: media,
        ),
      );
    } catch (e, stackTrace) {
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _lessonMediaRequestId,
        courseId: courseId,
        lessonId: selectedLessonId,
      )) {
        return;
      }
      final failure = AppFailure.from(e, stackTrace);
      if (mounted) {
        setState(
          () => _mediaLoadError = 'Kunde inte läsa media: ${failure.message}',
        );
      }
    } finally {
      if (mounted &&
          !_isStaleRequest(
            requestId: requestId,
            currentId: _lessonMediaRequestId,
            courseId: courseId,
            lessonId: selectedLessonId,
          )) {
        setState(() => _mediaLoading = false);
        _updateLessonMediaPolling();
      }
    }
  }

  String? _pipelineStateFromDb(StudioLessonMediaItem media) {
    final trimmed = media.state.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _lessonMediaHasProcessingPipelineItems() {
    for (final media in _lessonMedia) {
      if (!_isPipelineMedia(media)) continue;
      final state = _pipelineStateFromDb(media);
      if (state == 'uploaded' || state == 'processing') return true;
    }
    return false;
  }

  void _updateLessonMediaPolling() {
    final selectedLessonId = _selectedLessonId;
    final shouldPoll =
        selectedLessonId != null &&
        _lessonMediaLessonId == selectedLessonId &&
        _lessonMediaHasProcessingPipelineItems();

    if (!shouldPoll) {
      _stopLessonMediaPolling();
      return;
    }

    _lessonMediaPollTimer ??= Timer.periodic(_lessonMediaPollInterval, (_) {
      unawaited(_refreshLessonMediaSilently());
    });
  }

  void _stopLessonMediaPolling() {
    _lessonMediaPollTimer?.cancel();
    _lessonMediaPollTimer = null;
  }

  Future<void> _refreshLessonMediaSilently() async {
    if (_lessonMediaPollInFlight || _mediaLoading) return;
    final lessonId = _selectedLessonId;
    if (lessonId == null) return;

    _lessonMediaPollInFlight = true;
    final courseId = _selectedCourseId;
    final requestId = ++_lessonMediaRequestId;
    try {
      final media = await _readCanonicalLessonMedia(lessonId);
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _lessonMediaRequestId,
        courseId: courseId,
        lessonId: lessonId,
      )) {
        return;
      }
      final previousMedia = List<StudioLessonMediaItem>.from(_lessonMedia);
      if (!mounted) return;
      setState(() {
        _lessonMedia = media;
        _lessonMediaLessonId = lessonId;
        _mediaLoadError = null;
      });
      _syncLessonMediaPreviewCache(
        previousMedia: previousMedia,
        nextMedia: media,
      );
      _invalidateCurrentLessonEditorMediaHydration(
        lessonId: lessonId,
        previousMedia: previousMedia,
        nextMedia: media,
      );
      unawaited(
        _refreshLessonMediaAuthoritativeState(
          lessonId: lessonId,
          requestId: requestId,
          mediaItems: media,
        ),
      );
    } catch (_) {
      // Silent refresh failures shouldn't block the editor.
    } finally {
      _lessonMediaPollInFlight = false;
      if (mounted) {
        _updateLessonMediaPolling();
      }
    }
  }

  Future<void> _selectLesson(String lessonId) async {
    if (lessonId == _selectedLessonId) return;
    final canSwitch = await _maybeSaveLessonEdits();
    if (!canSwitch || !mounted) return;
    final needsRefresh = _lessonsNeedingRefresh.remove(lessonId);
    setState(() {
      _setSelectedLessonId(lessonId);
      _lessonMedia = <StudioLessonMediaItem>[];
      _lessonMediaLessonId = lessonId;
      _mediaLoadError = null;
      _resetLessonEditorBootValues(
        phase: _LessonEditorBootPhase.applyingLessonDocument,
      );
    });
    await _bootSelectedLesson();
    if (needsRefresh && mounted) {
      setState(() => _mediaStatus = 'Media uppdaterad för lektionen.');
    }
  }

  Widget _buildLessonListTile(
    BuildContext context,
    LessonStudio lesson, {
    required int index,
  }) {
    final theme = Theme.of(context);
    final lessonId = lesson.id;
    final title = lesson.lessonTitle;
    final position = lesson.position;
    final isSelected = lessonId == _selectedLessonId;
    final canMutateLessons = !_lessonPreviewMode && !_lessonActionBusy;

    return Material(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          foregroundColor: theme.colorScheme.onSurface,
          child: Text(
            position <= 0 ? '•' : '$position',
            style: theme.textTheme.labelSmall,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Ta bort lektion',
              onPressed: !canMutateLessons
                  ? null
                  : () => _deleteLesson(lessonId),
              icon: const Icon(Icons.delete_outline),
            ),
            if (canMutateLessons)
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle_rounded),
              ),
          ],
        ),
        onTap: () => _selectLesson(lessonId),
      ),
    );
  }

  List<LessonStudio> _reindexLessons(List<LessonStudio> lessons) {
    return List<LessonStudio>.generate(lessons.length, (index) {
      final lesson = lessons[index];
      return lesson.copyWith(position: index + 1);
    }, growable: false);
  }

  void _scheduleLessonReorderSave() {
    _lessonReorderDebounceTimer?.cancel();
    _lessonReorderDebounceTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistLessonOrder());
    });
  }

  Future<void> _persistLessonOrder() async {
    if (_lessonPreviewMode) {
      return;
    }
    final courseId = _selectedCourseId;
    if (courseId == null || _lessons.isEmpty) return;

    final updates = <Map<String, Object?>>[];
    for (var index = 0; index < _lessons.length; index += 1) {
      final lessonId = _lessons[index].id;
      if (lessonId.isEmpty) {
        return;
      }
      updates.add(<String, Object?>{'id': lessonId, 'position': index + 1});
    }

    try {
      await _studioRepo.reorderCourseLessons(courseId, updates);
    } catch (error, stackTrace) {
      if (!mounted || _selectedCourseId != courseId) return;
      _showFriendlyErrorSnack('Kunde inte spara ordningen', error, stackTrace);
      await _loadLessons(preserveSelection: true);
    }
  }

  void _handleLessonReorder(int oldIndex, int newIndex) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_lessonActionBusy || oldIndex == newIndex) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final reordered = [..._lessons];
      final lesson = reordered.removeAt(oldIndex);
      reordered.insert(newIndex, lesson);
      _lessons = _reindexLessons(reordered);
    });
    _scheduleLessonReorderSave();
  }

  LessonStudio? _lessonById(String? id, [List<LessonStudio>? source]) {
    if (id == null || id.isEmpty) return null;
    for (final item in source ?? _lessons) {
      if (item.id == id) return item;
    }
    return null;
  }

  CourseStudio? _courseById(String? id, [List<CourseStudio>? source]) {
    if (id == null || id.isEmpty) return null;
    for (final item in source ?? _courses) {
      if (item.id == id) return item;
    }
    return null;
  }

  CourseFamilyStudio? _courseFamilyById(
    String? id, [
    List<CourseFamilyStudio>? source,
  ]) {
    if (id == null || id.isEmpty) return null;
    for (final item in source ?? _courseFamilies) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<CourseStudio> _adoptCourseById(
    List<CourseStudio> courses,
    CourseStudio course,
  ) {
    var replaced = false;
    final merged = courses
        .map((existing) {
          if (existing.id != course.id) return existing;
          replaced = true;
          return course;
        })
        .toList(growable: true);
    if (!replaced) {
      merged.insert(0, course);
    }
    return merged;
  }

  List<CourseStudio> _sortCoursesWithinFamily(List<CourseStudio> courses) {
    final sorted = [...courses];
    sorted.sort((left, right) {
      final positionCompare = left.groupPosition.compareTo(right.groupPosition);
      if (positionCompare != 0) {
        return positionCompare;
      }
      final titleCompare = left.title.toLowerCase().compareTo(
        right.title.toLowerCase(),
      );
      if (titleCompare != 0) {
        return titleCompare;
      }
      return left.id.compareTo(right.id);
    });
    return sorted;
  }

  List<_CourseFamilySummary> _courseFamilySummaries([
    List<CourseStudio>? source,
  ]) {
    final grouped = <String, List<CourseStudio>>{};
    final order = <String>[];
    for (final course in source ?? _courses) {
      final courseGroupId = course.courseGroupId.trim();
      if (courseGroupId.isEmpty) {
        continue;
      }
      final bucket = grouped.putIfAbsent(courseGroupId, () {
        order.add(courseGroupId);
        return <CourseStudio>[];
      });
      bucket.add(course);
    }
    return [
      for (final courseGroupId in order)
        _CourseFamilySummary(
          courseGroupId: courseGroupId,
          name:
              _courseFamilyById(courseGroupId)?.name ??
              _defaultCourseFamilyName,
          courses: _sortCoursesWithinFamily(grouped[courseGroupId]!),
        ),
    ];
  }

  _CourseFamilySummary? _selectedCourseFamilySummary([
    List<CourseStudio>? source,
  ]) {
    final selectedCourse = _courseById(_selectedCourseId, source);
    if (selectedCourse == null) {
      return null;
    }
    for (final family in _courseFamilySummaries(source)) {
      if (family.courseGroupId == selectedCourse.courseGroupId) {
        return family;
      }
    }
    return null;
  }

  String _coursePositionSummary(CourseStudio course) {
    return _courseStepLabel(course.groupPosition);
  }

  CourseFamilyStudio? _currentCourseFamily([
    List<CourseStudio>? courses,
    List<CourseFamilyStudio>? families,
  ]) {
    final selectedCourse = _courseById(_selectedCourseId, courses);
    if (selectedCourse != null) {
      return _courseFamilyById(selectedCourse.courseGroupId, families);
    }
    final activeFamilyId = _selectedCourseFamilyIdForCourseSelection(
      courses: courses,
      courseFamilies: families,
    );
    return _courseFamilyById(activeFamilyId, families);
  }

  String? _courseFamilyManagementTarget({
    required String? selectedCourseId,
    required String? currentValue,
    List<CourseStudio>? courses,
    List<CourseFamilyStudio>? courseFamilies,
  }) {
    final availableFamilies = courseFamilies ?? _courseFamilies;
    if (currentValue != null &&
        currentValue.isNotEmpty &&
        _courseFamilyById(currentValue, availableFamilies) != null) {
      return currentValue;
    }
    final selectedCourse = _courseById(selectedCourseId, courses);
    if (selectedCourse != null &&
        _courseFamilyById(selectedCourse.courseGroupId, availableFamilies) !=
            null) {
      return selectedCourse.courseGroupId;
    }
    if (availableFamilies.isEmpty) {
      return null;
    }
    return availableFamilies.first.id;
  }

  CourseFamilyStudio? _managedCourseFamily([
    List<CourseFamilyStudio>? families,
  ]) {
    final targetId = _courseFamilyManagementTarget(
      selectedCourseId: _selectedCourseId,
      currentValue: _managedCourseFamilyId,
      courseFamilies: families,
    );
    return _courseFamilyById(targetId, families);
  }

  String? _selectedCourseFamilyIdForCourseSelection({
    List<CourseStudio>? courses,
    List<CourseFamilyStudio>? courseFamilies,
  }) {
    return _courseFamilyManagementTarget(
      selectedCourseId: _selectedCourseId,
      currentValue: _managedCourseFamilyId,
      courses: courses,
      courseFamilies: courseFamilies,
    );
  }

  List<CourseStudio> _coursesForSelectedFamily([
    List<CourseStudio>? source,
    List<CourseFamilyStudio>? courseFamilies,
  ]) {
    // Temporary non-canonical frontend filtering until GET /studio/courses
    // accepts course_group_id as a canonical request filter.
    final selectedFamilyId = _selectedCourseFamilyIdForCourseSelection(
      courses: source,
      courseFamilies: courseFamilies,
    );
    if (selectedFamilyId == null || selectedFamilyId.isEmpty) {
      return const <CourseStudio>[];
    }
    return _sortCoursesWithinFamily([
      for (final course in source ?? _courses)
        if (course.courseGroupId == selectedFamilyId) course,
    ]);
  }

  String? _firstCourseId(List<CourseStudio> items) {
    for (final item in items) {
      if (item.id.isNotEmpty) {
        return item.id;
      }
    }
    return null;
  }

  String? _firstLessonId(List<LessonStudio> items) {
    for (final item in items) {
      if (item.id.isNotEmpty) {
        return item.id;
      }
    }
    return null;
  }

  List<DropdownMenuItem<String>> _courseDropdownItems() {
    final items = <DropdownMenuItem<String>>[];
    for (final course in _coursesForSelectedFamily()) {
      final id = course.id;
      if (id.isEmpty) continue;
      final title = course.title;
      items.add(DropdownMenuItem<String>(value: id, child: Text(title)));
    }
    return items;
  }

  Future<void> _handleManagedCourseFamilyChanged(String familyId) async {
    final nextFamilyId = familyId.trim();
    if (nextFamilyId.isEmpty) {
      return;
    }
    final currentFamilyId = _selectedCourseFamilyIdForCourseSelection();
    if (nextFamilyId == currentFamilyId) {
      return;
    }
    final canSwitch = await _maybeSaveLessonEdits();
    if (!canSwitch || !mounted) {
      return;
    }

    final selectedCourse = _courseById(_selectedCourseId);
    final clearSelectedCourse =
        selectedCourse != null && selectedCourse.courseGroupId != nextFamilyId;

    if (clearSelectedCourse) {
      setState(() {
        _prepareCourseBoundarySelection(
          courseId: null,
          managedCourseFamilyId: nextFamilyId,
        );
      });
      return;
    }

    setState(() {
      _managedCourseFamilyId = nextFamilyId;
    });
  }

  String? _lessonCourseId(String? lessonId) {
    // Lesson is the source of truth for course_id in lesson-scoped media actions.
    final lesson = _lessonById(lessonId);
    final courseId = lesson?.courseId;
    if (courseId != null && courseId.isNotEmpty) return courseId;
    return _selectedCourseId;
  }

  int _positionValue(LessonStudio item) {
    return item.position;
  }

  List<LessonStudio> _sortByPosition(List<LessonStudio> items) {
    final sorted = [...items];
    sorted.sort((a, b) => _positionValue(a).compareTo(_positionValue(b)));
    return sorted;
  }

  List<LessonStudio> _mergeById(
    List<LessonStudio> existing,
    List<LessonStudio> incoming,
  ) {
    final existingById = <String, LessonStudio>{};
    for (final item in existing) {
      existingById[item.id] = item;
    }
    final merged = <LessonStudio>[];
    for (final item in incoming) {
      final existingItem = existingById[item.id];
      if (existingItem != null) {
        merged.add(
          existingItem.copyWith(
            courseId: item.courseId,
            lessonTitle: item.lessonTitle,
            position: item.position,
          ),
        );
        existingById.remove(item.id);
      } else {
        merged.add(item);
      }
    }
    for (final item in existingById.values) {
      merged.add(item);
    }
    return merged;
  }

  void _handleLessonTitleChanged() {
    if (_lessonPreviewMode) return;
    if (!_isSelectedLessonDocumentReady()) return;
    if (!_lessonContentDirty &&
        _lessonTitleCtrl.text.trim() != _lastSavedLessonTitle) {
      setState(() => _lessonContentDirty = true);
    }
  }

  List<String> _lessonMediaIdsFromContent(StudioLessonContentRead content) {
    final ids = <String>[];
    final seen = <String>{};
    for (final media in content.media) {
      final id = media.lessonMediaId.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      ids.add(id);
    }
    return ids;
  }

  Future<List<StudioLessonMediaItem>> _readCanonicalLessonMedia(
    String lessonId,
  ) async {
    final content = await _studioRepo.readLessonContent(lessonId);
    if (content.lessonId != lessonId) {
      throw StateError('Lektionsinnehållet hör till fel lektion.');
    }
    return _studioRepo.fetchLessonMediaPlacements(
      _lessonMediaIdsFromContent(content),
    );
  }

  Map<String, String> _lessonMediaTypesByIdForSelectedLesson() {
    final lessonId = _selectedLessonId;
    if (lessonId == null) return const <String, String>{};
    if (_lessonMediaLessonId != lessonId) return const <String, String>{};
    if (_lessonMedia.isEmpty) return const <String, String>{};

    return <String, String>{
      for (final media in _lessonMedia) media.lessonMediaId: media.mediaType,
    };
  }

  bool _requiresAuthoritativeEditorReadiness(StudioLessonMediaItem media) {
    final mediaType = media.mediaType;
    return mediaType == 'image' || mediaType == 'video' || mediaType == 'audio';
  }

  LessonMediaPreviewData? _authoritativePreviewForMedia(
    StudioLessonMediaItem media,
  ) {
    final preview = ref
        .read(lessonMediaPreviewCacheProvider)
        .peek(media.lessonMediaId);
    if (preview?.authoritativeEditorReady != true) {
      return null;
    }
    return preview;
  }

  LessonMediaPreviewStatus? _previewStatusForMedia(
    StudioLessonMediaItem media,
  ) {
    final lessonMediaId = media.lessonMediaId;
    if (lessonMediaId.isEmpty) return null;
    return ref.read(lessonMediaPreviewCacheProvider).peekStatus(lessonMediaId);
  }

  bool _isAuthoritativelyReadyForEditor(StudioLessonMediaItem media) {
    if (!_requiresAuthoritativeEditorReadiness(media)) {
      return true;
    }
    return _previewStatusForMedia(media)?.state ==
        LessonMediaPreviewState.ready;
  }

  bool _hasCanonicalDeliveryMedia(StudioLessonMediaItem media) {
    return media.state == 'ready' && _canonicalLessonMediaUrl(media) != null;
  }

  bool _canInsertLessonMedia(StudioLessonMediaItem media) {
    if (media.lessonMediaId.isEmpty) {
      return false;
    }
    if (_isWavMedia(media)) {
      return false;
    }
    if (_isDocumentMedia(media)) {
      return _hasCanonicalDeliveryMedia(media);
    }
    return _isAuthoritativelyReadyForEditor(media);
  }

  bool _canPreviewLessonMedia({
    required StudioLessonMediaItem media,
    required bool isWavMedia,
  }) {
    if (media.lessonMediaId.isEmpty) {
      return false;
    }
    if (isWavMedia) {
      return false;
    }
    final previewStatus = _previewStatusForMedia(media);
    if (_requiresAuthoritativeEditorReadiness(media)) {
      final previewState = previewStatus?.state;
      if (_isImageMedia(media) || _isVideoMedia(media)) {
        if (previewState != LessonMediaPreviewState.ready &&
            previewState != LessonMediaPreviewState.failed) {
          return false;
        }
      } else if (previewState != LessonMediaPreviewState.ready) {
        return false;
      }
    }
    return _hasCanonicalDeliveryMedia(media);
  }

  Set<String> _lessonMediaIdsFromRows(
    Iterable<StudioLessonMediaItem> mediaItems,
  ) {
    return mediaItems
        .map((media) => media.lessonMediaId)
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  void _syncLessonMediaPreviewCache({
    required List<StudioLessonMediaItem> previousMedia,
    required List<StudioLessonMediaItem> nextMedia,
  }) {
    final cache = ref.read(lessonMediaPreviewCacheProvider);
    if (_didLessonMediaPreviewStateChange(previousMedia, nextMedia)) {
      cache.invalidate(
        _lessonMediaIdsFromRows(<StudioLessonMediaItem>[
          ...previousMedia,
          ...nextMedia,
        ]),
      );
    }
    cache.primeFromLessonMedia(nextMedia);
  }

  Future<void> _refreshLessonMediaAuthoritativeState({
    required String lessonId,
    required int requestId,
    required Iterable<StudioLessonMediaItem> mediaItems,
  }) async {
    final ids = mediaItems
        .where(_requiresAuthoritativeEditorReadiness)
        .map((media) => media.lessonMediaId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;

    await ref.read(lessonMediaPreviewCacheProvider).prefetch(ids);
    if (_isStaleRequest(
      requestId: requestId,
      currentId: _lessonMediaRequestId,
      courseId: _selectedCourseId,
      lessonId: lessonId,
    )) {
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  bool _didLessonMediaPreviewStateChange(
    List<StudioLessonMediaItem> previousMedia,
    List<StudioLessonMediaItem> nextMedia,
  ) {
    if (previousMedia.length != nextMedia.length) return true;
    for (var index = 0; index < nextMedia.length; index += 1) {
      if (_lessonMediaPreviewStateToken(previousMedia[index]) !=
          _lessonMediaPreviewStateToken(nextMedia[index])) {
        return true;
      }
    }
    return false;
  }

  String _lessonMediaPreviewStateToken(StudioLessonMediaItem media) {
    return <String>[
      media.lessonMediaId,
      media.mediaType,
      media.state,
    ].join('|');
  }

  void _invalidateCurrentLessonEditorMediaHydration({
    required String lessonId,
    required List<StudioLessonMediaItem> previousMedia,
    required List<StudioLessonMediaItem> nextMedia,
  }) {
    if (_selectedLessonId != lessonId) return;
    if (!_didLessonMediaPreviewStateChange(previousMedia, nextMedia)) return;
    _resetLessonPreviewHydrationValues(bumpRevision: true);
  }

  Set<String> _embeddedLessonMediaIdsFromDocument(LessonDocument document) {
    final ids = <String>{};
    for (final block in document.blocks) {
      if (block is LessonMediaBlock && block.lessonMediaId.isNotEmpty) {
        ids.add(block.lessonMediaId);
      }
    }
    return ids;
  }

  Set<String> _currentLessonEmbeddedMediaIds() {
    return _embeddedLessonMediaIdsFromDocument(
      _lessonEditorController.currentDocument ?? _lessonDocument,
    );
  }

  bool _lessonAlreadyContainsMediaId(String lessonMediaId) {
    if (lessonMediaId.isEmpty) return false;
    return _currentLessonEmbeddedMediaIds().contains(lessonMediaId);
  }

  String? _canonicalLessonMediaUrl(StudioLessonMediaItem media) {
    final resolvedUrl = media.media?.resolvedUrl?.trim();
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }
    return resolvedUrl;
  }

  Future<String?> _resolveLessonMediaDeliveryUrlForMedia(
    StudioLessonMediaItem media,
  ) async {
    return _canonicalLessonMediaUrl(media);
  }

  Future<String?> _resolveLessonMediaPreviewUrlForMedia(
    StudioLessonMediaItem media,
  ) async {
    final preview = await ref
        .read(lessonMediaPreviewCacheProvider)
        .getSettledOrFetch(media.lessonMediaId);
    return preview?.visualUrl;
  }

  String _visibleLessonTextForLog(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
  }

  void _traceLessonString(String label, String value) {
    if (!kDebugMode) return;
    const maxChars = 1200;
    final visible = _visibleLessonTextForLog(value);
    final preview = visible.length > maxChars
        ? '${visible.substring(0, maxChars)}…'
        : visible;
    debugPrint('[LessonTrace] $label="$preview" (length=${value.length})');
  }

  void _setLessonTitleFieldValue(String title) {
    _lessonTitleCtrl.removeListener(_handleLessonTitleChanged);
    _lessonTitleCtrl.text = title;
    _lessonTitleCtrl.addListener(_handleLessonTitleChanged);
  }

  Future<void> _finishLessonDocumentBoot({
    required String lessonId,
    required int requestId,
    required LessonDocument storedDocument,
    required String storedTitle,
    required String contentEtag,
  }) async {
    final normalizedEtag = contentEtag.trim();
    if (normalizedEtag.isEmpty) {
      if (mounted) {
        setState(() {
          _lessonContentLoadError =
              'Lektionsinnehållet saknar giltig versionsmarkör.';
          _lessonEditorBootPhase = _LessonEditorBootPhase.error;
          _lessonContentDirty = false;
        });
      }
      return;
    }
    if (!mounted ||
        _isStaleRequest(
          requestId: requestId,
          currentId: _lessonContentRequestId,
          courseId: _selectedCourseId,
          lessonId: lessonId,
        )) {
      return;
    }
    final initialHydrationIds = _embeddedLessonMediaIdsFromDocument(
      storedDocument,
    );

    if (kDebugMode) {
      _traceLessonString(
        'load.stored_document',
        storedDocument.toCanonicalJsonString(),
      );
    }

    _setLessonTitleFieldValue(storedTitle);
    if (!mounted ||
        _isStaleRequest(
          requestId: requestId,
          currentId: _lessonContentRequestId,
          courseId: _selectedCourseId,
          lessonId: lessonId,
        )) {
      return;
    }
    setState(() {
      _documentReadyLessonId = lessonId;
      _documentReadyRequestId = requestId;
      _lessonContentHydratedLessonId = lessonId;
      _lessonDocument = storedDocument;
      _lessonDocumentInsertionIndex = null;
      _lastSavedLessonDocument = storedDocument;
      _lastSavedLessonTitle = storedTitle;
      _lastSavedLessonContentEtag = normalizedEtag;
      _lessonContentLoadError = null;
      _lessonContentDirty = false;
      _lessonEditorBootPhase = _LessonEditorBootPhase.fullyStable;
    });
    if (initialHydrationIds.isNotEmpty) {
      _startInitialLessonPreviewHydration(
        lessonId: lessonId,
        requestId: requestId,
        initialHydrationIds: initialHydrationIds,
      );
    }
  }

  Future<void> _bootSelectedLesson() async {
    final lessonId = _selectedLessonId;
    if (lessonId == null) {
      if (mounted) {
        setState(() {
          _resetLessonEditorBootValues(phase: _LessonEditorBootPhase.booting);
        });
      }
      return;
    }
    final lesson = _lessonById(lessonId);
    if (lesson == null) {
      if (mounted) {
        setState(() {
          _resetLessonEditorBootValues(
            phase: _LessonEditorBootPhase.error,
            errorMessage: 'Lektionen kunde inte hittas i strukturdata.',
          );
          _lessonContentDirty = false;
        });
      }
      return;
    }
    final storedTitle = lesson.lessonTitle;
    _setLessonTitleFieldValue(storedTitle);

    final requestId = ++_lessonContentRequestId;
    if (mounted) {
      setState(() {
        _resetLessonEditorBootValues(
          phase: _LessonEditorBootPhase.applyingLessonDocument,
        );
      });
    }
    await _awaitBootShellFrame();
    if (!mounted ||
        _isStaleRequest(
          requestId: requestId,
          currentId: _lessonContentRequestId,
          courseId: _selectedCourseId,
          lessonId: lessonId,
        )) {
      return;
    }
    await _loadLessonMedia(lessonId: lessonId);
    if (!mounted ||
        _isStaleRequest(
          requestId: requestId,
          currentId: _lessonContentRequestId,
          courseId: _selectedCourseId,
          lessonId: lessonId,
        )) {
      return;
    }
    late final StudioLessonContentRead content;
    try {
      content = await _studioRepo.readLessonContent(lessonId);
    } catch (error, stackTrace) {
      if (!mounted ||
          _isStaleRequest(
            requestId: requestId,
            currentId: _lessonContentRequestId,
            courseId: _selectedCourseId,
            lessonId: lessonId,
          )) {
        return;
      }
      final failure = AppFailure.from(error, stackTrace);
      setState(() {
        _resetLessonEditorBootValues(
          phase: _LessonEditorBootPhase.error,
          errorMessage: 'Kunde inte läsa lektionsinnehåll: ${failure.message}',
        );
        _lessonContentDirty = false;
      });
      return;
    }
    if (content.lessonId != lessonId) {
      if (mounted) {
        setState(() {
          _resetLessonEditorBootValues(
            phase: _LessonEditorBootPhase.error,
            errorMessage: 'Lektionsinnehållet hör till fel lektion.',
          );
          _lessonContentDirty = false;
        });
      }
      return;
    }
    await _finishLessonDocumentBoot(
      lessonId: lessonId,
      requestId: requestId,
      storedDocument: content.contentDocument,
      storedTitle: storedTitle,
      contentEtag: content.etag,
    );
  }

  Future<void> _resetLessonEdits() async {
    final requestId = ++_lessonContentRequestId;
    final lessonId = _selectedLessonId;
    if (lessonId == null) return;
    final contentEtag = _lastSavedLessonContentEtag;
    if (contentEtag == null || contentEtag.trim().isEmpty) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'Lektionsinnehållet måste laddas innan det kan återställas.',
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _resetLessonEditorBootValues(
          phase: _LessonEditorBootPhase.applyingLessonDocument,
        );
      });
    }
    await _awaitBootShellFrame();
    if (!mounted ||
        _isStaleRequest(
          requestId: requestId,
          currentId: _lessonContentRequestId,
          courseId: _selectedCourseId,
          lessonId: lessonId,
        )) {
      return;
    }
    await _loadLessonMedia(lessonId: lessonId);
    if (!mounted ||
        _isStaleRequest(
          requestId: requestId,
          currentId: _lessonContentRequestId,
          courseId: _selectedCourseId,
          lessonId: lessonId,
        )) {
      return;
    }
    await _finishLessonDocumentBoot(
      lessonId: lessonId,
      requestId: requestId,
      storedDocument: _lastSavedLessonDocument,
      storedTitle: _lastSavedLessonTitle,
      contentEtag: contentEtag,
    );
  }

  int _currentLessonPosition() {
    final lesson = _lessonById(_selectedLessonId);
    return lesson?.position ?? 0;
  }

  Future<bool> _saveLessonContent({bool showSuccessSnack = true}) async {
    if (!_requireEditModeForMutation()) {
      return false;
    }
    final lessonId = _selectedLessonId;
    final courseId = _selectedCourseId;

    if (lessonId == null || courseId == null) {
      showSnack(context, 'Välj en kurs och lektion att spara.');
      return false;
    }
    if (_lessonContentSaving) return false;
    final contentEtag = _lastSavedLessonContentEtag;
    if (!_isSelectedLessonDocumentReady() ||
        contentEtag == null ||
        contentEtag.trim().isEmpty) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'Lektionsinnehållet måste laddas innan det kan sparas.',
        );
      }
      return false;
    }

    final title = _lessonTitleCtrl.text.trim().isEmpty
        ? 'Lektion'
        : _lessonTitleCtrl.text.trim();
    late final LessonEditorSaveSnapshot saveSnapshot;
    late final LessonDocument contentDocument;
    try {
      saveSnapshot = _lessonEditorController.snapshotForSave();
      if (saveSnapshot.lessonId != lessonId) {
        throw StateError('Lektionsinnehållet hör till fel redigeringssession.');
      }
      contentDocument = saveSnapshot.document.validate(
        mediaTypesByLessonMediaId: _lessonMediaTypesByIdForSelectedLesson(),
      );
    } catch (error, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte spara lektion', error, stackTrace);
      return false;
    }

    final contentJson = contentDocument.toCanonicalJsonString();
    final lastSavedJson = _lastSavedLessonDocument.toCanonicalJsonString();

    if (kDebugMode) {
      debugPrint(
        '[LessonTrace] save.trigger=${showSuccessSnack ? 'manual' : 'auto'} '
        'dirty=$_lessonContentDirty saving=$_lessonContentSaving',
      );
      _traceLessonString('save.payload.content_document', contentJson);
      _traceLessonString('state.last_saved_document', lastSavedJson);
      debugPrint(
        '[LessonTrace] compare.payload_vs_last_saved '
        'equal=${contentJson == lastSavedJson}',
      );
      debugPrint(
        '[LessonEditor] saving lesson=$lessonId course=$courseId '
        'contentDocumentLen=${contentJson.length}',
      );
    }

    setState(() => _lessonContentSaving = true);
    final token = _captureEditorToken();
    try {
      StudioLessonContentWriteResult? updatedContent;
      if (contentJson != lastSavedJson) {
        updatedContent = await _studioRepo.updateLessonContent(
          lessonId,
          contentDocument: contentDocument,
          ifMatch: contentEtag,
        );
      }
      final updatedStructure = await _studioRepo.updateLessonStructure(
        lessonId,
        lessonTitle: title,
        position: _currentLessonPosition(),
      );

      if (!mounted || !_isEditorTokenValid(token)) return false;

      final canonicalContentDocument =
          updatedContent?.contentDocument ?? _lastSavedLessonDocument;
      final saveAcknowledged = _lessonEditorController.acknowledgeSave(
        snapshot: saveSnapshot,
        document: canonicalContentDocument,
      );

      setState(() {
        _lessons = _lessons
            .map((lesson) => lesson.id == lessonId ? updatedStructure : lesson)
            .toList();
        if (updatedContent != null) {
          _lessonDocument = updatedContent.contentDocument;
          _lessonDocumentInsertionIndex = _clampedLessonDocumentInsertionIndex(
            _lessonDocumentInsertionIndex,
            updatedContent.contentDocument,
          );
          _lastSavedLessonDocument = updatedContent.contentDocument;
        }
        _lastSavedLessonTitle = title;
        if (updatedContent != null) {
          _lastSavedLessonContentEtag = updatedContent.etag;
        }
        _lessonContentDirty = saveAcknowledged
            ? _lessonEditorController.dirty
            : true;
      });

      if (mounted && context.mounted && showSuccessSnack) {
        showSnack(context, 'Lektion sparad.');
      }
      return true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 412 ||
          error.response?.statusCode == 428) {
        if (mounted) {
          setState(() {
            _resetLessonEditorBootValues(
              phase: _LessonEditorBootPhase.error,
              errorMessage:
                  'Lektionsinnehållet har ändrats. Ladda om innehållet innan du sparar igen.',
            );
            _lessonContentDirty = true;
          });
        }
      }
      final message = _friendlyDioMessage(error);
      if (mounted && context.mounted) {
        showSnack(context, 'Kunde inte spara lektion: $message');
      }
      return false;
    } catch (e, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte spara lektion', e, stackTrace);
      return false;
    } finally {
      if (mounted) setState(() => _lessonContentSaving = false);
    }
  }

  Future<bool> _maybeSaveLessonEdits() async {
    if (kDebugMode) {
      debugPrint(
        '[LessonTrace] maybeSaveLessonEdits dirty=$_lessonContentDirty '
        'selectedLessonId=${_selectedLessonId ?? 'none'}',
      );
    }
    if (_lessonPreviewMode) {
      if (_lessonContentDirty && mounted && context.mounted) {
        showSnack(
          context,
          'Växla till Redigera för att spara eller återställa ändringar.',
        );
      }
      return !_lessonContentDirty;
    }
    if (!_lessonContentDirty) return true;
    return _saveLessonContent(showSuccessSnack: false);
  }

  Future<void> _insertMagicLink() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final labelController = TextEditingController(text: 'Boka nu');
    final urlController = TextEditingController(text: '/');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Magic-link-knapp'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Knapptext',
                hintText: 'Till exempel: Boka session',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Deeplink',
                hintText: 'https://example.com/boka eller /boka',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Avbryt'),
          ),
          GradientButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Infoga'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      labelController.dispose();
      urlController.dispose();
      return;
    }

    final label = labelController.text.trim().isEmpty
        ? 'Magic CTA'
        : labelController.text.trim();
    final url = urlController.text.trim();

    labelController.dispose();
    urlController.dispose();

    if (url.isEmpty) {
      if (mounted && context.mounted) {
        showSnack(context, 'Deeplink krävs.');
      }
      return;
    }

    final inserted = _lessonEditorController.insertCta(
      label: label,
      targetUrl: url,
    );
    if (!inserted && mounted && context.mounted) {
      showSnack(context, 'Lektionsinnehållet är inte redo för CTA.');
    }
  }

  Widget _buildLessonContentEditor(
    BuildContext context, {
    bool expandEditor = false,
    double editorHeight = 320,
  }) {
    final hasVideo = _lessonMedia.any((media) => media.mediaType == 'video');
    final hasAudio = _lessonMedia.any((media) => media.mediaType == 'audio');

    final badges = <Widget>[];
    if (hasVideo || hasAudio) {
      final label = hasVideo && hasAudio
          ? 'Innehåller video & ljud'
          : hasVideo
          ? 'Innehåller video'
          : 'Innehåller ljud';
      badges.add(
        Chip(
          label: Text(label),
          visualDensity: VisualDensity.compact,
          avatar: Icon(
            hasVideo
                ? Icons.movie_creation_outlined
                : Icons.audiotrack_outlined,
            size: 16,
          ),
        ),
      );
    }
    final canInsertLessonMedia =
        _selectedCourseId != null && _selectedLessonId != null;

    _scheduleLessonEditorTestIdSync();
    final editorSurface = Container(
      key: const ValueKey<String>('lesson_editor_live_surface'),
      child: _wrapLessonEditorForWebTestIds(
        LessonEditorSessionHost(
          key: const ValueKey<String>(_lessonEditorTestId),
          lessonId: _selectedLessonId ?? '',
          document: _lessonDocument,
          controller: _lessonEditorController,
          rehydrationKey: _documentReadyRequestId,
          media: _editorDocumentMedia(),
          enabled: !_lessonPreviewMode && _isSelectedLessonDocumentReady(),
          minHeight: 280,
          onDirtyChanged: _handleLessonDocumentDirtyChanged,
          onInsertionIndexChanged: _rememberLessonDocumentInsertionIndex,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _lessonTitleCtrl,
          decoration: const InputDecoration(
            labelText: 'Lektionstitel',
            hintText: 'Till exempel: Introduktion',
          ),
        ),
        if (badges.isNotEmpty) ...[
          gap8,
          Wrap(spacing: 8, runSpacing: 4, children: badges),
        ],
        _buildPreviewHydrationBanner(context),
        gap12,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            EditorMediaControls(
              onInsertVideo: canInsertLessonMedia
                  ? () => _handleMediaToolbarUpload(_UploadKind.video)
                  : null,
              onInsertAudio: canInsertLessonMedia
                  ? () => _handleMediaToolbarUpload(_UploadKind.audio)
                  : null,
            ),
            FilledButton.icon(
              key: const Key('editor_media_controls_insert_image'),
              onPressed: canInsertLessonMedia
                  ? () => _handleMediaToolbarUpload(_UploadKind.image)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Infoga bild'),
            ),
            FilledButton.icon(
              key: const Key('editor_media_controls_upload_pdf'),
              onPressed: canInsertLessonMedia
                  ? () => _handleMediaToolbarUpload(_UploadKind.pdf)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Infoga PDF'),
            ),
            OutlinedButton.icon(
              key: const Key('editor_insert_cta'),
              onPressed: canInsertLessonMedia ? _insertMagicLink : null,
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Infoga CTA'),
            ),
          ],
        ),
        gap12,
        if (expandEditor)
          Expanded(child: editorSurface)
        else
          SizedBox(height: editorHeight, child: editorSurface),
        gap12,
        Row(
          children: [
            GradientButton.icon(
              onPressed: !_lessonContentDirty || _lessonContentSaving
                  ? null
                  : _saveLessonContent,
              icon: _lessonContentSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Spara lektionsinnehåll'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: !_lessonContentDirty || _lessonContentSaving
                  ? null
                  : _resetLessonEdits,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Återställ'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewHydrationBanner(BuildContext context) {
    final selectedLessonId = _selectedLessonId;
    final requestId = _lessonContentRequestId;
    if (selectedLessonId == null) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<LessonMediaPreviewHydrationSnapshot>(
      valueListenable: _previewHydrationController,
      builder: (context, snapshot, _) {
        if (!snapshot.matchesRequest(
              lessonId: selectedLessonId,
              requestId: requestId,
            ) ||
            snapshot.hydratingEmbedIds.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final pendingCount = snapshot.hydratingEmbedIds.length;
        final totalCount = snapshot.initialHydrationIds.length;
        final countLabel = pendingCount <= 0
            ? ''
            : totalCount > 0
            ? ' ($pendingCount/$totalCount)'
            : ' ($pendingCount)';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            gap12,
            DecoratedBox(
              key: const ValueKey<String>('lesson_preview_hydration_banner'),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Förhandsvisningar laddas$countLabel',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                          Text(
                            'Du kan fortsätta skriva medan miniatyrerna hämtas.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLessonEditorBootShell(BuildContext context) {
    final theme = Theme.of(context);
    final isApplying =
        _lessonEditorBootPhase == _LessonEditorBootPhase.applyingLessonDocument;
    final isError = _lessonEditorBootPhase == _LessonEditorBootPhase.error;
    final title = isError
        ? 'Lektionsinnehållet kunde inte laddas'
        : isApplying
        ? 'Laddar lektionsinnehåll…'
        : 'Förbereder editorn…';
    final detail = isError
        ? (_lessonContentLoadError ??
              'Ladda om innehållet innan du fortsätter.')
        : isApplying
        ? 'Editorn blir redigerbar så snart rätt lektion har laddats.'
        : 'Välj en lektion för att börja redigera.';

    Widget actionPlaceholder({required IconData icon, required String label}) {
      return FilledButton.icon(
        onPressed: null,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return Semantics(
      identifier: 'editor-boot-shell',
      child: Column(
        key: const ValueKey<String>('lesson_editor_boot_shell'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          gap12,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              actionPlaceholder(
                icon: Icons.image_outlined,
                label: 'Infoga bild',
              ),
              actionPlaceholder(
                icon: Icons.movie_creation_outlined,
                label: 'Infoga video',
              ),
              actionPlaceholder(
                icon: Icons.audiotrack_outlined,
                label: 'Infoga ljud',
              ),
            ],
          ),
          gap12,
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
                color: Colors.white.withValues(alpha: 0.92),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isError)
                        Icon(
                          Icons.error_outline_rounded,
                          size: 32,
                          color: theme.colorScheme.error,
                        )
                      else
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detail,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isError) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _selectedLessonId == null
                              ? null
                              : _bootSelectedLesson,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Ladda om innehåll'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          gap12,
          Row(
            children: [
              GradientButton.icon(
                onPressed: null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Spara lektionsinnehåll'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Återställ'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLessonPreviewMode(BuildContext context) {
    final theme = Theme.of(context);
    final persistedLessonTitle = _lastSavedLessonTitle.trim();
    final fallbackLessonTitle =
        _lessonById(_selectedLessonId)?.lessonTitle.trim() ?? '';
    final previewTitle = persistedLessonTitle.isNotEmpty
        ? persistedLessonTitle
        : fallbackLessonTitle.isNotEmpty
        ? fallbackLessonTitle
        : 'Lektion';
    final previewDocument = _lessonPreviewDocument;
    final previewMedia = _lessonPreviewMedia;
    final previewError = _lessonPreviewError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          previewTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        gap6,
        Text(
          'Skrivskyddad förhandsgranskning av sparat innehåll.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        gap12,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            Chip(
              key: ValueKey<String>('lesson_preview_live_badge'),
              label: Text('Live preview'),
            ),
          ],
        ),
        gap12,
        LessonDocumentReadingModeToggle(
          value: _lessonPreviewReadingMode,
          onChanged: (mode) {
            setState(() => _lessonPreviewReadingMode = mode);
          },
        ),
        gap12,
        Expanded(
          child: _lessonPreviewLoading
              ? const Center(child: CircularProgressIndicator())
              : previewDocument == null
              ? Center(
                  child: Text(
                    previewError ??
                        'Sparad förhandsgranskning kunde inte läsas.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: previewError == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: LessonDocumentPreview(
                    document: previewDocument,
                    media: previewMedia,
                    readingMode: _lessonPreviewReadingMode,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLessonEditorWorkspace(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final hasSelectedLesson = _selectedLessonId != null;
    final isDocumentReady = _isSelectedLessonDocumentReady();
    final canSwitchModes = hasSelectedLesson && isDocumentReady;

    return GlassCard(
      padding: p16,
      borderRadius: BorderRadius.circular(20),
      opacity: 0.16,
      borderColor: Colors.white.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final modeChips = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey<String>('lesson_edit_mode_chip'),
                    label: const Text('Redigera'),
                    selected: !_lessonPreviewMode,
                    onSelected: !canSwitchModes
                        ? null
                        : (_) {
                            if (_lessonPreviewMode) {
                              unawaited(_setLessonPreviewMode(false));
                            }
                          },
                  ),
                  ChoiceChip(
                    key: const ValueKey<String>('lesson_preview_mode_chip'),
                    label: const Text('Förhandsgranska'),
                    selected: _lessonPreviewMode,
                    onSelected: !canSwitchModes
                        ? null
                        : (_) {
                            if (!_lessonPreviewMode) {
                              unawaited(_setLessonPreviewMode(true));
                            }
                          },
                  ),
                ],
              );
              final stackHeader = constraints.maxWidth < 720;
              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lessonPreviewMode ? 'Förhandsgranskning' : 'Texteditor',
                      style: titleStyle,
                    ),
                    const SizedBox(height: 8),
                    modeChips,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _lessonPreviewMode ? 'Förhandsgranskning' : 'Texteditor',
                      style: titleStyle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: modeChips,
                    ),
                  ),
                ],
              );
            },
          ),
          gap12,
          Expanded(
            child: !hasSelectedLesson
                ? _buildNoSelectedLessonState(context)
                : !isDocumentReady
                ? _buildLessonEditorBootShell(context)
                : _lessonPreviewMode
                ? _buildLessonPreviewMode(context)
                : _buildLessonContentEditor(context, expandEditor: true),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelectedLessonState(BuildContext context) {
    return Center(
      child: Text(
        'Välj en lektion för att redigera innehållet.',
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildNarrowLessonEditorSurface(
    BuildContext context, {
    required double editorHeight,
  }) {
    if (_selectedLessonId == null) {
      return SizedBox(
        height: editorHeight + 180,
        child: _buildNoSelectedLessonState(context),
      );
    }
    final isDocumentReady = _isSelectedLessonDocumentReady();
    if (!isDocumentReady) {
      return SizedBox(
        height: editorHeight + 180,
        child: _buildLessonEditorBootShell(context),
      );
    }
    if (_lessonPreviewMode) {
      return SizedBox(
        height: editorHeight + 180,
        child: _buildLessonPreviewMode(context),
      );
    }
    return _buildLessonContentEditor(context, editorHeight: editorHeight);
  }

  Widget _buildCourseCoverPicker(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final bodyStyle = theme.textTheme.bodySmall;
    final resolvedCoverUrl = _courseCoverPath;
    final renderSource = selectCourseCoverRenderSource(
      resolvedUrl: resolvedCoverUrl,
      localPreviewBytes: null,
    );
    final hasCover = renderSource != 'empty';
    final status = _coverPipelineState;
    final statusText = status == null ? null : _coverStatusLabel(status);
    final coverPipelineError = _coverPipelineError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kursbild', style: titleStyle),
        const SizedBox(height: 8),
        SizedBox(
          width: 140,
          height: 96,
          child: GlassCard(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(14),
            opacity: 0.16,
            borderColor: Colors.white.withValues(alpha: 0.28),
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (SafeMedia.enabled) {
                        SafeMedia.markThumbnails();
                      }
                      const emptyState = Center(
                        child: Icon(Icons.image_outlined, size: 28),
                      );
                      _logCourseCoverRender(
                        source: renderSource,
                        resolvedUrl: resolvedCoverUrl,
                      );
                      if (renderSource == 'empty') {
                        return emptyState;
                      }

                      final cacheWidth = SafeMedia.cacheDimension(
                        context,
                        constraints.maxWidth,
                        max: 600,
                      );
                      final cacheHeight = SafeMedia.cacheDimension(
                        context,
                        constraints.maxHeight,
                        max: 600,
                      );

                      return Image.network(
                        resolvedCoverUrl!,
                        fit: BoxFit.cover,
                        filterQuality: SafeMedia.filterQuality(
                          full: FilterQuality.high,
                        ),
                        cacheWidth: cacheWidth,
                        cacheHeight: cacheHeight,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            emptyState,
                      );
                    },
                  ),
                ),
                if (_updatingCourseCover)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed:
                  hasCover && !_updatingCourseCover && !_lessonPreviewMode
                  ? () => unawaited(_clearCourseCover())
                  : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Ta bort kursbild'),
            ),
            if (_updatingCourseCover) ...[
              const Chip(
                label: Text('Uppdaterar...'),
                visualDensity: VisualDensity.compact,
                avatar: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ],
        ),
        if (statusText != null) ...[
          const SizedBox(height: 6),
          Text(statusText, style: bodyStyle),
        ],
        if (coverPipelineError != null && coverPipelineError.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            coverPipelineError,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (!_lessonPreviewMode && _selectedCourseId != null) ...[
          const SizedBox(height: 12),
          CoverUploadCard(
            courseId: _selectedCourseId,
            onCoverQueued: (courseId, mediaId) {
              _queueCoverUpload(courseId, mediaId);
            },
            onUploadError: (courseId, message) {
              if (!mounted || _selectedCourseId != courseId) return;
              setState(() {
                _coverPipelineError = message;
                _updatingCourseCover = false;
              });
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCourseDescriptionEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _courseDescriptionCtrl,
          readOnly: _lessonPreviewMode,
          minLines: 6,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Beskrivning',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('course-public-content-save-button'),
            onPressed: _savingCoursePublicContent || _lessonPreviewMode
                ? null
                : _saveCoursePublicContent,
            icon: _savingCoursePublicContent
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _savingCoursePublicContent ? 'Sparar...' : 'Spara beskrivning',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCourseCoverAndDescriptionEditor(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverPicker = _buildCourseCoverPicker(context);
        final descriptionEditor = _buildCourseDescriptionEditor(context);
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [coverPicker, gap12, descriptionEditor],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 280, child: coverPicker),
            gap16,
            Expanded(child: descriptionEditor),
          ],
        );
      },
    );
  }

  Widget _buildInvalidVideoPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: br16,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.ondemand_video_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                'Video saknas eller stöds inte längre',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildLessonVideoPreview(BuildContext context) {
    if (_selectedLessonId == null || _lessonMedia.isEmpty) return null;
    StudioLessonMediaItem? video;
    for (final media in _lessonMedia) {
      if (media.mediaType == 'video') {
        video = media;
        break;
      }
    }
    final media = video;
    if (media == null) return null;
    final label = _fileNameFromMedia(media);
    final mediaUrl = _authoritativePreviewForMedia(media)?.visualUrl;

    return _SectionCard(
      title: 'Lektionsvideo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: br16,
            child: mediaUrl == null
                ? _buildInvalidVideoPlaceholder(context)
                : AveliLessonMediaPlayer(
                    mediaUrl: mediaUrl,
                    title: label,
                    kind: 'video',
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _downloadingMedia ? null : () => _downloadMedia(media),
              icon: Icon(
                _downloadingMedia
                    ? Icons.downloading_outlined
                    : Icons.download_outlined,
              ),
              label: Text(
                _downloadingMedia ? 'Hämtar...' : 'Ladda ner original',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptCreateLesson() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final courseId = _selectedCourseId;
    if (courseId == null || _lessonActionBusy) return;
    if (!await _maybeSaveLessonEdits()) return;
    if (!mounted) return;
    setState(() => _lessonActionBusy = true);
    try {
      final nextPos = _lessons.isEmpty
          ? 1
          : _lessons
                    .map((lesson) => lesson.position)
                    .fold<int>(0, (a, b) => a > b ? a : b) +
                1;
      final lesson = await _studioRepo.createLessonStructure(
        courseId: courseId,
        lessonTitle: 'Ny lektion',
        position: nextPos,
      );
      if (!mounted) return;
      setState(() {
        _lessons = _sortByPosition(_mergeById(_lessons, [lesson]));
        _setSelectedLessonId(lesson.id);
        _lessonMedia = <StudioLessonMediaItem>[];
        _lessonMediaLessonId = null;
        _mediaLoadError = null;
        _mediaStatus = null;
        _downloadStatus = null;
        _resetLessonEditorBootValues(
          phase: _LessonEditorBootPhase.applyingLessonDocument,
        );
      });
      await _bootSelectedLesson();
      await _loadLessons(preserveSelection: true, mergeResults: true);
      if (mounted && context.mounted) {
        showSnack(context, 'Lektion skapad.');
      }
    } catch (e, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte skapa lektion', e, stackTrace);
    } finally {
      if (mounted) setState(() => _lessonActionBusy = false);
    }
  }

  Future<void> _deleteLesson(String id) async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_lessonActionBusy) return;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ta bort lektion?'),
        content: const Text('Detta tar bort lektionen och dess media.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Avbryt'),
          ),
          GradientButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _lessonActionBusy = true);
    try {
      await _studioRepo.deleteLesson(id);
      if (!mounted) return;
      setState(() {
        if (_selectedLessonId == id) {
          _setSelectedLessonId(null);
        }
      });
      await _loadLessons(preserveSelection: false);
      if (mounted && context.mounted) {
        showSnack(context, 'Lektion borttagen.');
      }
    } catch (e, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte ta bort lektion', e, stackTrace);
    } finally {
      if (mounted) setState(() => _lessonActionBusy = false);
    }
  }

  String _suggestMediaDisplayName(String filename) {
    final trimmed = filename.trim();
    if (trimmed.isEmpty) return '';
    final questionIndex = trimmed.indexOf('?');
    final withoutQuery = questionIndex >= 0
        ? trimmed.substring(0, questionIndex)
        : trimmed;
    final segments = withoutQuery.split('/');
    final last = segments.isNotEmpty ? segments.last : withoutQuery;
    final parts = last.split('.');
    final stem = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join('.')
        : last;
    return stem.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  Future<String?> _promptRequiredMediaDisplayName(String suggested) async {
    final controller = TextEditingController(text: suggested);
    String current = controller.text.trim();

    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Ge ljudet/videon ett namn'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Namn',
              hintText: 'Till exempel: Introduktion',
            ),
            onChanged: (_) => setDialogState(() {
              current = controller.text.trim();
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Avbryt'),
            ),
            GradientButton(
              onPressed: current.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(current),
              child: const Text('Fortsätt'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result?.trim();
  }

  Future<void> _pickAndUploadWith(
    List<String> extensions, {
    String? acceptHint,
    required String mediaType,
  }) async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final courseId = _selectedCourseId;
    final lessonId = _selectedLessonId;
    if (courseId == null || lessonId == null) {
      showSnack(context, 'Välj kurs och lektion innan du laddar upp.');
      return;
    }

    Future<void> enqueue(
      String name,
      Uint8List bytes, {
      String? mimeType,
    }) async {
      if (!_requireEditModeForMutation()) {
        return;
      }
      final contentType = (mimeType?.isNotEmpty ?? false)
          ? mimeType!
          : _guessContentType(name);
      if (contentType == 'audio/wav' || contentType == 'audio/x-wav') {
        showSnack(
          context,
          'WAV-filer laddas upp via WAV-uppladdningen längre ned.',
        );
        return;
      }
      String? displayName;
      final lower = contentType.toLowerCase();
      if (lower.startsWith('audio/') || lower.startsWith('video/')) {
        displayName = await _promptRequiredMediaDisplayName(
          _suggestMediaDisplayName(name),
        );
        if (!_requireEditModeForMutation()) {
          return;
        }
        if (displayName == null) return;
        if (displayName.trim().isEmpty) {
          if (!mounted) return;
          showSnack(context, 'Namn krävs för ljud och video.');
          return;
        }
      }
      ref
          .read(studioUploadQueueProvider.notifier)
          .enqueueUpload(
            courseId: courseId,
            lessonId: lessonId,
            data: bytes,
            filename: name,
            displayName: displayName,
            contentType: contentType,
            mediaType: mediaType,
          );
      if (mounted) {
        setState(() => _mediaStatus = 'Köade $name');
      }
      if (mounted) {
        setState(() => _mediaStatus = 'Uppladdning pågår…');
      }
    }

    if (kIsWeb) {
      final picked = await web_picker.pickFilesFromHtml(
        allowedExtensions: extensions,
        allowMultiple: false,
        accept: acceptHint,
      );

      if (!mounted) return;
      if (!_requireEditModeForMutation()) {
        return;
      }

      debugPrint('Studio pick result (web): ${picked?.length ?? 0} files');
      if (picked == null || picked.isEmpty) {
        setState(() => _mediaStatus = 'Ingen fil vald.');
        return;
      }

      final file = picked[0];
      debugPrint(
        'Picked file name=${file.name} bytes=${file.bytes.length} mime=${file.mimeType}',
      );
      try {
        await enqueue(file.name, file.bytes, mimeType: file.mimeType);
      } catch (e, stackTrace) {
        if (kDebugMode) {
          debugPrint('enqueue failed for ${file.name}: $e\n$stackTrace');
        }
        final message = AppFailure.from(e, stackTrace).message;
        setState(() => _mediaStatus = 'Fel vid läsning av fil: $message');
        _showFriendlyErrorSnack('Kunde inte läsa filen', e, stackTrace);
      }
      return;
    }

    final typeGroup = fs.XTypeGroup(label: 'media', extensions: extensions);
    final file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (file == null) {
      if (mounted) {
        setState(() => _mediaStatus = 'Ingen fil vald.');
      }
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      await enqueue(file.name, bytes);
    } catch (e, stackTrace) {
      final message = AppFailure.from(e, stackTrace).message;
      if (mounted) {
        setState(() => _mediaStatus = 'Fel vid läsning av fil: $message');
      }
      _showFriendlyErrorSnack('Kunde inte läsa filen', e, stackTrace);
    }
  }

  Future<void> _handleMediaToolbarUpload(_UploadKind kind) async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_selectedCourseId == null || _selectedLessonId == null) {
      showSnack(context, 'Välj kurs och lektion innan du laddar upp media.');
      return;
    }
    switch (kind) {
      case _UploadKind.image:
        await _uploadImageFromToolbar();
        break;
      case _UploadKind.video:
        await _pickAndUploadWith(
          const ['mp4', 'mov', 'm4v', 'webm', 'mkv'],
          acceptHint: 'video/*',
          mediaType: 'video',
        );
        break;
      case _UploadKind.audio:
        await _pickAndUploadWith(
          const ['mp3', 'm4a', 'aac', 'ogg'],
          acceptHint: 'audio/mpeg,audio/mp4,audio/aac,audio/ogg',
          mediaType: 'audio',
        );
        break;
      case _UploadKind.pdf:
        await _pickAndUploadWith(
          const ['pdf'],
          acceptHint: 'application/pdf',
          mediaType: 'document',
        );
        break;
    }
  }

  String _guessContentType(String filename) {
    final segments = filename.toLowerCase().split('.');
    final ext = segments.length > 1 ? segments.last : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'heic':
        return 'image/heic';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  String _friendlyDioMessage(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) {
      return 'Sessionen verkar ha gått ut. Logga in igen och försök på nytt.';
    }
    if (status == 403) {
      return 'Du har inte behörighet att utföra den här åtgärden.';
    }
    if (status == 422) {
      return 'Vissa uppgifter saknas eller är ogiltiga. Kontrollera och försök igen.';
    }
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'] ?? data['message'] ?? data['error'];
      if (detail is String && detail.isNotEmpty) {
        return detail;
      }
    }
    final reason = error.response?.statusMessage;
    if (reason != null && reason.isNotEmpty) {
      return reason;
    }
    return error.message ?? 'Nätverksfel';
  }

  bool _isImageMedia(StudioLessonMediaItem media) {
    return media.mediaType == 'image';
  }

  bool _isDocumentMedia(StudioLessonMediaItem media) {
    return media.mediaType == 'document';
  }

  bool _isPipelineMedia(StudioLessonMediaItem media) {
    return media.mediaAssetId != null;
  }

  String _pipelineLabel(String state) {
    switch (state) {
      case 'uploaded':
        return 'Uppladdad • väntar på bearbetning';
      case 'processing':
        return 'Bearbetas';
      case 'ready':
        return 'Klar för uppspelning';
      case 'failed':
        return 'Bearbetning misslyckades';
      default:
        return 'Okänd status';
    }
  }

  String _mediaStatusLabel(String state) {
    switch (state) {
      case 'ready':
        return 'Klar';
      case 'failed':
        return 'Misslyckades';
      case 'checking':
        return 'Kontrolleras';
      case 'processing':
        return 'Bearbetas';
      default:
        return 'Status okänd';
    }
  }

  bool _isWavMedia(StudioLessonMediaItem media) {
    if (media.state == 'ready') {
      return false;
    }
    return media.mediaType == 'audio';
  }

  Future<void> _uploadImageFromToolbar() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final lessonId = _selectedLessonId;
    if (lessonId == null) {
      showSnack(context, 'Välj kurs och lektion innan du laddar upp media.');
      return;
    }
    final token = _captureEditorToken();
    const extensions = ['png', 'jpg', 'jpeg', 'webp', 'svg'];

    Future<StudioLessonMediaItem> uploadImage(
      Uint8List bytes,
      String filename,
      String contentType,
    ) async {
      return _studioRepo.uploadLessonMedia(
        lessonId: lessonId,
        data: bytes,
        filename: filename,
        contentType: contentType,
        mediaType: 'image',
      );
    }

    Future<void> uploadBytes(Uint8List bytes, String filename) async {
      if (!_requireEditModeForMutation()) {
        return;
      }
      final contentType = _guessContentType(filename);
      if (mounted) {
        setState(() => _mediaStatus = 'Laddar upp $filename…');
      }
      try {
        final media = await uploadImage(bytes, filename, contentType);
        if (!_requireEditModeForMutation()) {
          return;
        }
        if (!mounted || !_isEditorTokenValid(token)) return;
        final previousMedia = List<StudioLessonMediaItem>.from(_lessonMedia);
        List<StudioLessonMediaItem> nextMedia = const <StudioLessonMediaItem>[];
        setState(() {
          final updated = [..._lessonMedia];
          final index = updated.indexWhere(
            (item) => item.lessonMediaId == media.lessonMediaId,
          );
          if (index >= 0) {
            updated[index] = media;
          } else {
            updated.add(media);
          }
          nextMedia = updated;
          _lessonMedia = updated;
        });
        _syncLessonMediaPreviewCache(
          previousMedia: previousMedia,
          nextMedia: nextMedia,
        );
        _invalidateCurrentLessonEditorMediaHydration(
          lessonId: lessonId,
          previousMedia: previousMedia,
          nextMedia: nextMedia,
        );
        final inserted = _insertImageIntoLesson(
          lessonMediaId: media.lessonMediaId,
        );
        if (!inserted) {
          setState(
            () => _mediaStatus = 'Bild finns redan i lektionen: $filename',
          );
          return;
        }
        final postInsertToken = _captureEditorToken();
        unawaited(_refreshLessonMediaSilently());
        final saved = await _saveLessonContent(showSuccessSnack: false);
        if (!mounted ||
            !context.mounted ||
            !_isEditorTokenValid(postInsertToken)) {
          return;
        }
        setState(
          () => _mediaStatus = saved
              ? 'Bild uppladdad och sparad: $filename'
              : 'Bild uppladdad men kunde inte sparas: $filename',
        );
        if (context.mounted) {
          showSnack(
            context,
            saved
                ? 'Bild infogad och sparad i lektionen.'
                : 'Bild infogad men kunde inte sparas i lektionen.',
          );
        }
      } catch (error, stackTrace) {
        final message = AppFailure.from(error, stackTrace).message;
        if (mounted) {
          setState(() => _mediaStatus = 'Fel vid uppladdning: $message');
        }
        _showFriendlyErrorSnack('Kunde inte ladda upp bild', error, stackTrace);
      }
    }

    if (kIsWeb) {
      final picked =
          await (widget.webImagePicker ?? web_picker.pickFilesFromHtml)(
            allowedExtensions: extensions,
            allowMultiple: false,
            accept: 'image/*',
          );

      if (!mounted || !_isEditorTokenValid(token)) return;
      if (!_requireEditModeForMutation()) {
        return;
      }

      if (picked == null || picked.isEmpty) {
        setState(() => _mediaStatus = 'Ingen bild vald.');
        return;
      }
      final file = picked[0];
      await uploadBytes(file.bytes, file.name);
      return;
    }

    const typeGroup = fs.XTypeGroup(label: 'images', extensions: extensions);
    final file = await fs.openFile(acceptedTypeGroups: [typeGroup]);
    if (!mounted || !_isEditorTokenValid(token)) return;
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (file == null) {
      if (mounted) {
        setState(() => _mediaStatus = 'Ingen bild vald.');
      }
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      if (!mounted || !_isEditorTokenValid(token)) return;
      await uploadBytes(bytes, file.name);
    } catch (error, stackTrace) {
      final message = AppFailure.from(error, stackTrace).message;
      if (mounted) {
        setState(() => _mediaStatus = 'Fel vid uppladdning: $message');
      }
      _showFriendlyErrorSnack('Kunde inte ladda upp bild', error, stackTrace);
    }
  }

  int? _clampedLessonDocumentInsertionIndex(
    int? index,
    LessonDocument document,
  ) {
    if (index == null) return null;
    return index.clamp(0, document.blocks.length).toInt();
  }

  void _rememberLessonDocumentInsertionIndex(int index) {
    _lessonDocumentInsertionIndex = _clampedLessonDocumentInsertionIndex(
      index,
      _lessonEditorController.currentDocument ?? _lessonDocument,
    );
  }

  void _insertMediaBlockIntoDocument({
    required String mediaType,
    required String lessonMediaId,
  }) {
    final inserted = _lessonEditorController.insertMediaBlock(
      mediaType: mediaType,
      lessonMediaId: lessonMediaId,
    );
    if (inserted) {
      _lessonDocumentInsertionIndex = 1;
    }
  }

  bool _insertImageIntoLesson({String? lessonMediaId}) {
    if (!_requireEditModeForMutation()) {
      return false;
    }
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      if (mounted && context.mounted) {
        showSnack(context, 'Bild saknar media-ID och kan inte bäddas in.');
      }
      return false;
    }
    if (_lessonAlreadyContainsMediaId(lessonMediaId)) {
      if (mounted && context.mounted) {
        showSnack(context, 'Media finns redan i lektionen.');
      }
      return false;
    }
    _insertMediaBlockIntoDocument(
      mediaType: 'image',
      lessonMediaId: lessonMediaId,
    );
    return true;
  }

  void _insertVideoIntoLesson({required String lessonMediaId}) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (lessonMediaId.isEmpty) return;
    _insertMediaBlockIntoDocument(
      mediaType: 'video',
      lessonMediaId: lessonMediaId,
    );
  }

  void _insertAudioIntoLesson({required String lessonMediaId}) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (lessonMediaId.isEmpty) return;
    _insertMediaBlockIntoDocument(
      mediaType: 'audio',
      lessonMediaId: lessonMediaId,
    );
  }

  void _insertDocumentIntoLesson({required String lessonMediaId}) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    _insertMediaBlockIntoDocument(
      mediaType: 'document',
      lessonMediaId: lessonMediaId,
    );
  }

  bool _insertMediaIntoLesson(
    StudioLessonMediaItem media, {
    bool showSaveHint = true,
  }) {
    if (!_requireEditModeForMutation()) {
      return false;
    }
    if (_isWavMedia(media)) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'WAV-filer kan inte bäddas in. De spelas upp via lektionens media.',
        );
      }
      return false;
    }
    final kind = media.mediaType;
    final lessonMediaId = media.lessonMediaId;
    if (lessonMediaId.isEmpty) {
      if (mounted && context.mounted) {
        showSnack(context, 'Media saknar ID och kan inte bäddas in.');
      }
      return false;
    }
    if (_lessonAlreadyContainsMediaId(lessonMediaId)) {
      if (mounted && context.mounted) {
        showSnack(context, 'Media finns redan i lektionen.');
      }
      return false;
    }
    if (!_canInsertLessonMedia(media)) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'Mediet kan inte bäddas in eftersom det inte är redo i editorn.',
        );
      }
      return false;
    }
    debugPrint(
      '[CourseEditor] insert media kind=$kind lessonMediaId=$lessonMediaId',
    );
    if (_isImageMedia(media) || kind == 'image') {
      final inserted = _insertImageIntoLesson(lessonMediaId: lessonMediaId);
      if (!inserted) {
        return false;
      }
      if (mounted && context.mounted) {
        showSnack(
          context,
          showSaveHint
              ? 'Bild infogad i lektionen. Kom ihåg att spara.'
              : 'Bild infogad i lektionen.',
        );
      }
      return true;
    }
    if (_isDocumentMedia(media)) {
      _insertDocumentIntoLesson(lessonMediaId: lessonMediaId);
      if (mounted && context.mounted) {
        showSnack(
          context,
          showSaveHint
              ? 'PDF-länk infogad i lektionen. Kom ihåg att spara.'
              : 'PDF-länk infogad i lektionen.',
        );
      }
      return true;
    }
    if (_isVideoMedia(media)) {
      _insertVideoIntoLesson(lessonMediaId: lessonMediaId);
      if (mounted && context.mounted) {
        showSnack(
          context,
          showSaveHint
              ? 'Video infogad i lektionen. Kom ihåg att spara.'
              : 'Video infogad i lektionen.',
        );
      }
      return true;
    }
    _insertAudioIntoLesson(lessonMediaId: lessonMediaId);
    if (mounted && context.mounted) {
      showSnack(
        context,
        showSaveHint
            ? 'Ljud infogat i lektionen. Kom ihåg att spara.'
            : 'Ljud infogat i lektionen.',
      );
    }
    return true;
  }

  String _coverStatusLabel(String state) {
    switch (state) {
      case 'uploaded':
        return 'Uppladdad. Bearbetas…';
      case 'processing':
        return 'Bearbetas…';
      case 'ready':
        return 'Kursbilden är klar.';
      case 'failed':
        return 'Bearbetningen misslyckades.';
      default:
        return 'Status okänd.';
    }
  }

  void _queueCoverUpload(String courseId, String mediaId) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (courseId.isEmpty) {
      if (context.mounted) {
        showSnack(
          context,
          'Spara kursen först för att kunna ladda upp kursbild.',
        );
      }
      return;
    }
    if (_selectedCourseId != courseId) {
      return;
    }
    final requestId = _beginCoverAction(courseId: courseId);
    setState(() {
      _coverPipelineMediaId = mediaId;
      _coverPipelineState = 'uploaded';
      _coverPipelineError = null;
      _updatingCourseCover = true;
    });
    _startCoverPolling(mediaId, requestId: requestId);
  }

  void _startCoverPolling(String mediaId, {required int requestId}) {
    _coverPollTimer?.cancel();
    _coverPollAttempts = 0;
    _coverPollStartedAt = DateTime.now();
    _coverPollRequestId = requestId;
    _coverPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollCoverStatus(mediaId, requestId: requestId);
    });
    _pollCoverStatus(mediaId, requestId: requestId);
  }

  void _endCoverPollingWithError(String message, {required int requestId}) {
    if (_coverPollRequestId != requestId) return;
    _coverPollTimer?.cancel();
    _coverPollTimer = null;
    if (!mounted) return;
    setState(() {
      _updatingCourseCover = false;
      _coverPipelineState = 'failed';
      _coverPipelineError = message;
    });
  }

  Future<void> _pollCoverStatus(
    String mediaId, {
    required int requestId,
  }) async {
    if (_lessonPreviewMode) {
      return;
    }
    if (_coverPollRequestId != requestId) return;
    if (_coverPollAttempts >= _coverStatusMaxAttempts) {
      _endCoverPollingWithError(
        'Bearbetningen tog för lång tid. Försök igen.',
        requestId: requestId,
      );
      return;
    }
    final startedAt = _coverPollStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) > _coverStatusTimeout) {
      _endCoverPollingWithError(
        'Bearbetningen tog för lång tid. Försök igen.',
        requestId: requestId,
      );
      return;
    }
    _coverPollAttempts += 1;
    try {
      final courseId = _coverActionCourseId ?? _selectedCourseId;
      if (courseId == null || courseId.isEmpty) {
        _endCoverPollingWithError(
          'Spara kursen först för att kunna ladda upp kursbild.',
          requestId: requestId,
        );
        return;
      }
      final repo = ref.read(mediaPipelineRepositoryProvider);
      final status = await repo.fetchStatus(mediaId);
      if (_lessonPreviewMode) {
        return;
      }
      if (!mounted || _coverPollRequestId != requestId) return;
      if (_coverActionCourseId != null &&
          _coverActionCourseId != _selectedCourseId) {
        return;
      }
      setState(() {
        _coverPipelineState = status.state;
        _coverPipelineError = status.errorMessage;
      });
      if (status.state == 'ready') {
        if (_lessonPreviewMode) {
          return;
        }
        _coverPollTimer?.cancel();
        _coverPollTimer = null;
        final patch = <String, Object?>{'cover_media_id': mediaId};
        _logCourseMetaPatchPayload(courseId: courseId, patch: patch);
        final updated = await _studioRepo.updateCourse(courseId, patch);
        if (!mounted || _coverPollRequestId != requestId) return;
        if (_selectedCourseId != courseId) return;
        _logCourseMetaPatchResponse(courseId: courseId, response: updated);
        setState(() {
          _courses = _courses
              .map((course) => course.id == courseId ? updated : course)
              .toList();
          _coverPipelineState = updated.cover?.state ?? status.state;
          _coverPipelineError = null;
        });
        ref.invalidate(myCoursesProvider);
        ref.invalidate(studioCoursesProvider);
        ref.invalidate(landing.popularCoursesProvider);
        ref.invalidate(coursesProvider);
        await _loadCourseMeta();
        if (!mounted) return;
        if (!context.mounted) return;
        setState(() => _updatingCourseCover = false);
        showSnack(context, 'Kursbilden är klar.');
      } else if (status.state == 'failed') {
        _coverPollTimer?.cancel();
        _coverPollTimer = null;
        if (mounted) {
          setState(() => _updatingCourseCover = false);
        }
        final detail = status.errorMessage;
        if (!mounted) return;
        if (!context.mounted) return;
        showSnack(
          context,
          detail == null || detail.isEmpty
              ? 'Bearbetningen misslyckades.'
              : 'Bearbetningen misslyckades: $detail',
        );
      }
    } catch (e) {
      _endCoverPollingWithError(
        'Kunde inte uppdatera kursbilden. Försök igen.',
        requestId: requestId,
      );
    }
  }

  Future<void> _clearCourseCover() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_updatingCourseCover) return;
    final courseId = _selectedCourseId;
    if (courseId == null) return;
    var resumePolling = false;
    final previousMediaId = _coverPipelineMediaId;
    final previousState = _coverPipelineState;
    final previousError = _coverPipelineError;

    _coverPollTimer?.cancel();
    _coverPollTimer = null;

    if (mounted) {
      setState(() {
        _updatingCourseCover = true;
        _coverPipelineMediaId = null;
        _coverPipelineState = null;
        _coverPipelineError = null;
      });
    }

    try {
      final repo = ref.read(mediaPipelineRepositoryProvider);
      await repo.clearCourseCover(courseId);
      await _loadCourseMeta();
      if (!mounted) return;
      if (!context.mounted) return;
      showSnack(context, 'Kursbild borttagen.');
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() {
        _coverPipelineMediaId = previousMediaId;
        _coverPipelineState = previousState;
        _coverPipelineError = previousError;
      });
      if (previousMediaId != null &&
          previousState != null &&
          previousState != 'ready' &&
          previousState != 'failed') {
        resumePolling = true;
        final requestId = _beginCoverAction(courseId: courseId);
        setState(() => _updatingCourseCover = true);
        _startCoverPolling(previousMediaId, requestId: requestId);
      }
      _showFriendlyErrorSnack('Kunde inte uppdatera kursbild', e, stackTrace);
    } finally {
      if (mounted && !resumePolling) {
        setState(() => _updatingCourseCover = false);
      }
    }
  }

  void _onUploadQueueChanged(List<UploadJob>? previous, List<UploadJob> next) {
    if (!mounted) return;
    final lessonId = _selectedLessonId;
    for (final job in next) {
      final old = _findJob(previous, job.id);
      if (job.status == UploadJobStatus.success &&
          old?.status != UploadJobStatus.success) {
        if (lessonId != null && job.lessonId == lessonId) {
          unawaited(_afterUploadSuccess(job));
        } else {
          _lessonsNeedingRefresh.add(job.lessonId);
          if (context.mounted) {
            showSnack(
              context,
              'Media uppladdad i en annan lektion. Byt lektion för att uppdatera.',
            );
          }
        }
      } else if (job.status == UploadJobStatus.failed &&
          old?.status != UploadJobStatus.failed) {
        if (lessonId != null && job.lessonId == lessonId) {
          final detail = job.error?.trim();
          final suffix = detail == null || detail.isEmpty ? '' : ' ($detail)';
          if (context.mounted) {
            showSnack(
              context,
              'Uppladdning misslyckades: ${job.filename}$suffix',
            );
          }
          setState(
            () => _mediaStatus =
                'Uppladdning misslyckades: ${job.filename}$suffix',
          );
        } else {
          _lessonsNeedingRefresh.add(job.lessonId);
        }
      }
    }
  }

  Future<void> _afterUploadSuccess(UploadJob job) async {
    if (job.lessonId != _selectedLessonId) {
      _lessonsNeedingRefresh.add(job.lessonId);
      return;
    }
    if (_lessonPreviewMode) {
      await _loadLessonMedia();
      if (!mounted || job.lessonId != _selectedLessonId) return;
      if (context.mounted) {
        showSnack(
          context,
          'Media uppladdad. Växla till Redigera för att infoga och spara.',
        );
      }
      setState(() => _mediaStatus = 'Media uppladdad: ${job.filename}');
      return;
    }
    final authoritativeUpload = job.uploadedMedia;
    final authoritativeUploadId = authoritativeUpload?.lessonMediaId;
    if (authoritativeUpload == null ||
        authoritativeUploadId == null ||
        authoritativeUploadId.isEmpty) {
      if (context.mounted) {
        showSnack(
          context,
          'Uppladdningen saknade kanonisk mediaidentitet. Uppdatera listan.',
        );
      }
      if (mounted) {
        setState(
          () => _mediaStatus =
              'Uppladdning klar men kanonisk media saknas: ${job.filename}',
        );
      }
      return;
    }

    final token = _captureEditorToken();
    await _loadLessonMedia();
    if (!mounted || !_isEditorTokenValid(token)) return;
    if (!_requireEditModeForMutation()) {
      return;
    }
    StudioLessonMediaItem? uploaded;
    for (final media in _lessonMedia) {
      if (media.lessonMediaId == authoritativeUploadId) {
        uploaded = media;
        break;
      }
    }

    if (uploaded == null) {
      if (context.mounted) {
        showSnack(
          context,
          'Uppladdningen är klar men media saknas i lektionens sparade medialista.',
        );
      }
      if (mounted) {
        setState(
          () => _mediaStatus =
              'Uppladdning klar men sparad medialista saknar media: ${job.filename}',
        );
      }
      return;
    }

    final mediaType = authoritativeUpload.mediaType;
    final requiresAuthoritativeReadiness =
        mediaType == 'video' || mediaType == 'audio' || mediaType == 'image';
    if (requiresAuthoritativeReadiness) {
      await ref.read(lessonMediaPreviewCacheProvider).prefetch([
        authoritativeUploadId,
      ]);
      if (!mounted || !_isEditorTokenValid(token)) return;
      if (!_requireEditModeForMutation()) {
        return;
      }
      setState(() {});
    }

    var inserted = false;
    if (mediaType == 'video' ||
        mediaType == 'audio' ||
        mediaType == 'image' ||
        mediaType == 'document') {
      inserted = _insertMediaIntoLesson(uploaded, showSaveHint: false);
    }
    final postInsertToken = inserted ? _captureEditorToken() : token;

    final saved = inserted
        ? await _saveLessonContent(showSuccessSnack: false)
        : false;

    if (!mounted || !context.mounted || !_isEditorTokenValid(postInsertToken)) {
      return;
    }
    final message = inserted
        ? (saved
              ? 'Media infogat och sparat i lektionen.'
              : 'Media infogat men kunde inte sparas i lektionen.')
        : 'Media uppladdad: ${job.filename}';
    showSnack(context, message);
    if (mounted) {
      setState(
        () => _mediaStatus = inserted
            ? (saved
                  ? 'Media uppladdad och sparad: ${job.filename}'
                  : 'Media uppladdad men inte sparad: ${job.filename}')
            : 'Media uppladdad: ${job.filename}',
      );
    }
  }

  UploadJob? _findJob(List<UploadJob>? jobs, String id) {
    if (jobs == null) return null;
    for (final job in jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  Widget _buildUploadJobCard(UploadJob job) {
    final queue = ref.read(studioUploadQueueProvider.notifier);
    final theme = Theme.of(context);
    final status = job.status;
    final now = DateTime.now();
    final kind = _kindForContentType(job.contentType);
    final icon = _iconForMedia(kind);

    String statusText;
    Color? statusColor;
    Widget? progress;
    Widget leadingIcon = Icon(icon, size: 32);
    final actions = <Widget>[];

    switch (status) {
      case UploadJobStatus.uploading:
        final percent = (job.progress * 100)
            .clamp(0.0, 100.0)
            .toStringAsFixed(0);
        statusText = 'Laddar upp $percent%';
        progress = LinearProgressIndicator(value: job.progress.clamp(0, 1));
        leadingIcon = SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            value: job.progress.clamp(0.0, 1.0),
            strokeWidth: 3,
          ),
        );
        actions.add(
          TextButton.icon(
            onPressed: _lessonPreviewMode
                ? null
                : () => queue.cancelUpload(job.id),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Avbryt'),
          ),
        );
        break;
      case UploadJobStatus.pending:
        final scheduledAt = job.scheduledAt;
        if (scheduledAt != null && scheduledAt.isAfter(now)) {
          final rawRemaining = scheduledAt.difference(now).inSeconds;
          final remaining = rawRemaining <= 0 ? 1 : rawRemaining;
          statusText = 'Försök igen om ${remaining}s';
        } else {
          statusText = 'Köad';
        }
        leadingIcon = SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        );
        actions.add(
          TextButton.icon(
            onPressed: _lessonPreviewMode
                ? null
                : () => queue.cancelUpload(job.id),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Avbryt'),
          ),
        );
        break;
      case UploadJobStatus.failed:
        statusText = job.error ?? 'Uppladdningen misslyckades';
        statusColor = theme.colorScheme.error;
        actions.add(
          TextButton.icon(
            onPressed: _lessonPreviewMode
                ? null
                : () => queue.retryUpload(job.id),
            icon: const Icon(Icons.refresh),
            label: const Text('Försök igen'),
          ),
        );
        actions.add(
          IconButton(
            tooltip: 'Rensa',
            icon: const Icon(Icons.clear),
            onPressed: _lessonPreviewMode
                ? null
                : () => queue.removeJob(job.id),
          ),
        );
        break;
      case UploadJobStatus.cancelled:
        statusText = job.error ?? 'Avbruten';
        statusColor = theme.colorScheme.outline;
        actions.add(
          IconButton(
            tooltip: 'Rensa',
            icon: const Icon(Icons.clear),
            onPressed: _lessonPreviewMode
                ? null
                : () => queue.removeJob(job.id),
          ),
        );
        break;
      case UploadJobStatus.success:
        statusText = 'Uppladdning klar';
        statusColor = theme.colorScheme.secondary;
        actions.add(
          IconButton(
            tooltip: 'Rensa',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: _lessonPreviewMode
                ? null
                : () => queue.removeJob(job.id),
          ),
        );
        break;
    }

    final attemptInfo =
        'Försök ${job.attempts}/${job.maxAttempts} • ${job.createdAt.toLocal()}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: BorderRadius.circular(16),
        opacity: 0.16,
        borderColor: Colors.white.withValues(alpha: 0.28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                leadingIcon,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    job.filename,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (actions.isNotEmpty)
                  TooltipVisibility(
                    visible: false,
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: theme.textTheme.bodyMedium?.copyWith(color: statusColor),
            ),
            const SizedBox(height: 4),
            Text(attemptInfo, style: theme.textTheme.labelSmall),
            if (progress != null) ...[const SizedBox(height: 8), progress],
          ],
        ),
      ),
    );
  }

  Future<void> _downloadMedia(StudioLessonMediaItem media) async {
    if (_downloadingMedia) return;
    if (_isWavMedia(media)) {
      return;
    }
    final name = _fileNameFromMedia(media);

    final resolved = await _resolveLessonMediaDeliveryUrlForMedia(media);
    if (!mounted) return;
    if (resolved == null || resolved.isEmpty) {
      setState(() => _downloadStatus = 'Ladda ner stöds inte för detta media.');
      if (context.mounted) {
        showSnack(context, 'Kunde inte hämta leveranslänk för mediet.');
      }
      return;
    }

    if (kIsWeb) {
      setState(() => _downloadStatus = 'Öppnar fil i ny flik…');
      if (context.mounted) {
        showSnack(context, 'Media öppnas i en ny flik.');
      }
      unawaited(launchUrlString(resolved));
      if (!mounted) return;
      setState(() => _downloadStatus = null);
      return;
    }

    setState(() {
      _downloadingMedia = true;
      _downloadStatus = 'Hämtar $name…';
    });
    try {
      final response = await Dio().get<List<int>>(
        resolved,
        options: Options(responseType: ResponseType.bytes),
      );
      final responseBytes = response.data;
      if (responseBytes == null || responseBytes.isEmpty) {
        throw StateError('Tomt svar från medieleverans.');
      }
      final bytes = Uint8List.fromList(responseBytes);
      final location = await fs.getSaveLocation(suggestedName: name);
      if (location == null) {
        if (mounted) {
          setState(() {
            _downloadingMedia = false;
            _downloadStatus = 'Hämtning avbruten.';
          });
        }
        return;
      }
      final file = fs.XFile.fromData(
        bytes,
        mimeType: _mimeForKind(media.mediaType),
        name: name,
      );
      await file.saveTo(location.path);
      if (mounted) {
        setState(() {
          _downloadingMedia = false;
          _downloadStatus = 'Sparad till ${location.path}';
        });
      }
      if (mounted && context.mounted) {
        showSnack(context, 'Media sparad till ${location.path}');
      }
    } catch (e, stackTrace) {
      final failure = AppFailure.from(e, stackTrace);
      if (mounted) {
        setState(() {
          _downloadingMedia = false;
          _downloadStatus = 'Fel vid hämtning: ${failure.message}';
        });
      }
      _showFriendlyErrorSnack('Kunde inte hämta media', e, stackTrace);
    }
  }

  String _fileNameFromMedia(StudioLessonMediaItem media) {
    return 'media_${media.lessonMediaId}';
  }

  String _mimeForKind(String? kind) {
    switch (kind) {
      case 'image':
        return 'image/*';
      case 'video':
        return 'video/*';
      case 'audio':
        return 'audio/*';
      case 'document':
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  String _kindForContentType(String contentType) {
    if (contentType.startsWith('image/')) return 'image';
    if (contentType.startsWith('video/')) return 'video';
    if (contentType.startsWith('audio/')) return 'audio';
    if (contentType == 'application/pdf') return 'pdf';
    return 'other';
  }

  IconData _iconForMedia(String? kind) {
    switch (kind) {
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.movie_creation_outlined;
      case 'audio':
        return Icons.audiotrack_outlined;
      case 'document':
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Future<void> _showVideoPreviewSheet(
    StudioLessonMediaItem media, {
    required String? mediaUrl,
  }) async {
    if (!mounted || !context.mounted) return;
    final fileName = _fileNameFromMedia(media);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final padding = EdgeInsets.fromLTRB(
          16,
          20,
          16,
          16 + MediaQuery.of(sheetContext).viewPadding.bottom,
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mediaUrl == null)
                  _buildInvalidVideoPlaceholder(sheetContext)
                else
                  AveliLessonMediaPlayer(
                    mediaUrl: mediaUrl,
                    title: fileName,
                    kind: 'video',
                  ),
                const SizedBox(height: 8),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _downloadingMedia
                        ? null
                        : () => _downloadMedia(media),
                    icon: Icon(
                      _downloadingMedia
                          ? Icons.downloading_outlined
                          : Icons.download_outlined,
                    ),
                    label: Text(
                      _downloadingMedia ? 'Hämtar...' : 'Ladda ner original',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAudioPreviewSheet(
    StudioLessonMediaItem media, {
    required String mediaUrl,
  }) async {
    if (!mounted || !context.mounted) return;
    final fileName = _fileNameFromMedia(media);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final padding = EdgeInsets.fromLTRB(
          16,
          20,
          16,
          16 + MediaQuery.of(sheetContext).viewPadding.bottom,
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AveliLessonMediaPlayer(
                  mediaUrl: mediaUrl,
                  title: fileName,
                  kind: 'audio',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _downloadingMedia
                        ? null
                        : () => _downloadMedia(media),
                    icon: Icon(
                      _downloadingMedia
                          ? Icons.downloading_outlined
                          : Icons.download_outlined,
                    ),
                    label: Text(
                      _downloadingMedia ? 'Hämtar...' : 'Ladda ner original',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _previewMedia(StudioLessonMediaItem media) async {
    final kind = media.mediaType;
    final lessonMediaId = media.lessonMediaId;
    if (_isWavMedia(media)) {
      return;
    }

    String? url;
    if (kind == 'image' || kind == 'video') {
      url = await _resolveLessonMediaPreviewUrlForMedia(media);
      if (mounted) {
        setState(() {});
      }
    } else {
      url = await _resolveLessonMediaDeliveryUrlForMedia(media);
    }
    final previewStatus = _previewStatusForMedia(media);
    if (!mounted) return;
    if (kind == 'image' && url != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: InteractiveViewer(
            child: Image.network(url!, fit: BoxFit.contain),
          ),
        ),
      );
    } else if (url != null && kind == 'audio') {
      await _showAudioPreviewSheet(media, mediaUrl: url);
    } else if (url != null && kind == 'video') {
      await _showVideoPreviewSheet(media, mediaUrl: url);
    } else {
      final shouldLogUnresolved =
          previewStatus?.state == LessonMediaPreviewState.failed &&
          previewStatus?.failureKind ==
              LessonMediaPreviewFailureKind.unresolved;
      if (shouldLogUnresolved) {
        logUnresolvedLessonMediaRender(
          event: 'UNRESOLVED_LESSON_MEDIA_RENDER',
          surface: 'studio_media_list_preview',
          mediaType: kind,
          lessonMediaId: lessonMediaId,
        );
      }
      if (mounted && context.mounted) {
        showSnack(context, 'Förhandsvisning kunde inte laddas.');
      }
    }
  }

  Future<void> _handleMediaReorder(int oldIndex, int newIndex) async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final lessonId = _selectedLessonId;
    if (lessonId == null) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _lessonMedia.removeAt(oldIndex);
      _lessonMedia.insert(newIndex, item);
    });
    try {
      final mediaIds = _lessonMedia
          .map((media) => media.lessonMediaId)
          .toList();
      if (mediaIds.length != _lessonMedia.length) {
        throw StateError('Ett eller flera media saknar id.');
      }
      await _studioRepo.reorderLessonMedia(lessonId, mediaIds);
    } catch (e, stackTrace) {
      if (!mounted) return;
      _showFriendlyErrorSnack('Kunde inte spara ordning', e, stackTrace);
      await _loadLessonMedia();
    }
  }

  Future<void> _deleteMedia(String id) async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final lessonId = _selectedLessonId;
    if (lessonId == null) return;
    if (_lessonAlreadyContainsMediaId(id)) {
      if (mounted && context.mounted) {
        showSnack(
          context,
          'Ta bort media från lektionsinnehållet innan du tar bort filen.',
        );
      }
      return;
    }
    try {
      await _studioRepo.deleteLessonMedia(lessonId, id);
      await _loadLessonMedia();
      if (mounted && context.mounted) {
        showSnack(context, 'Media borttagen.');
      }
    } catch (e, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte ta bort media', e, stackTrace);
    }
  }

  bool _replaceLessonMediaReferencesInEditor({
    required String fromLessonMediaId,
    required StudioLessonMediaItem replacementMedia,
  }) {
    if (!_requireEditModeForMutation()) {
      return false;
    }
    final fromId = fromLessonMediaId;
    final toId = replacementMedia.lessonMediaId;
    if (fromId.isEmpty || toId.isEmpty) return false;

    final contentChanged = _lessonEditorController.replaceMediaReference(
      fromLessonMediaId: fromId,
      toLessonMediaId: toId,
      mediaType: replacementMedia.mediaType,
    );
    if (!contentChanged) return false;
    _resetLessonPreviewHydrationValues(bumpRevision: true);
    return true;
  }

  Future<void> _replaceAudioMedia(
    StudioLessonMediaItem media,
    int index,
  ) async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final lessonId = _selectedLessonId;
    final courseId = _lessonCourseId(lessonId);
    if (lessonId == null || courseId == null || courseId.isEmpty) {
      if (mounted && context.mounted) {
        showSnack(context, 'Spara lektionen för att kunna byta ljud.');
      }
      return;
    }

    final oldLessonMediaId = media.lessonMediaId;
    if (oldLessonMediaId.isEmpty) {
      if (mounted && context.mounted) {
        showSnack(context, 'Media saknar ID och kan inte bytas ut.');
      }
      return;
    }

    final fileName = _fileNameFromMedia(media);
    var token = _captureEditorToken();

    final newLessonMediaId = await showDialog<String?>(
      context: context,
      builder: (context) => WavReplaceDialog(
        courseId: courseId,
        lessonId: lessonId,
        existingFileName: fileName,
        replacementLessonMediaId: oldLessonMediaId,
        onMediaUpdated: _loadLessonMedia,
      ),
    );
    if (!mounted || !_isEditorTokenValid(token)) return;
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (newLessonMediaId == null || newLessonMediaId.isEmpty) return;

    setState(() => _mediaStatus = 'Ersätter ljud…');

    try {
      await _loadLessonMedia();
      if (!mounted || !_isEditorTokenValid(token)) return;
      if (!_requireEditModeForMutation()) {
        return;
      }

      StudioLessonMediaItem? newMedia;
      for (final item in _lessonMedia) {
        if (item.lessonMediaId == newLessonMediaId) {
          newMedia = item;
          break;
        }
      }

      if (newMedia == null) {
        if (mounted && context.mounted) {
          showSnack(context, 'Kunde inte hitta den nya ljudfilen.');
        }
        setState(() => _mediaStatus = null);
        return;
      }

      if (newMedia.lessonMediaId == oldLessonMediaId) {
        await _loadLessonMedia();
        if (!mounted || !_isEditorTokenValid(token)) return;
        if (mounted && context.mounted) {
          showSnack(context, 'Ljud ersatt.');
        }
        if (mounted) {
          setState(() => _mediaStatus = 'Ljud ersatt.');
        }
        return;
      }

      final contentChanged = _replaceLessonMediaReferencesInEditor(
        fromLessonMediaId: oldLessonMediaId,
        replacementMedia: newMedia,
      );
      if (contentChanged) {
        token = _captureEditorToken();
        final saved = await _saveLessonContent(showSuccessSnack: false);
        if (!saved) {
          if (mounted && context.mounted) {
            showSnack(
              context,
              'Kunde inte spara lektionen – den gamla ljudfilen är kvar.',
            );
          }
          setState(() => _mediaStatus = null);
          return;
        }
        if (!_isEditorTokenValid(token)) return;
      }

      final ids = _lessonMedia.map((item) => item.lessonMediaId).toList();
      final oldIndex = ids.indexOf(oldLessonMediaId);
      final newIndex = ids.indexOf(newLessonMediaId);
      if (newIndex < 0) {
        if (mounted && context.mounted) {
          showSnack(context, 'Kunde inte hitta den nya ljudfilen i listan.');
        }
        setState(() => _mediaStatus = null);
        return;
      }

      var insertIndex = oldIndex >= 0 ? oldIndex : index;
      insertIndex = insertIndex.clamp(0, ids.length - 1);

      final reordered = [...ids];
      reordered.removeAt(newIndex);
      final adjustedInsertIndex = newIndex < insertIndex
          ? max(0, insertIndex - 1)
          : insertIndex;
      reordered.insert(
        adjustedInsertIndex.clamp(0, reordered.length),
        newLessonMediaId,
      );

      await _studioRepo.reorderLessonMedia(lessonId, reordered);
      if (!_isEditorTokenValid(token)) return;
      await _studioRepo.deleteLessonMedia(lessonId, oldLessonMediaId);
      if (!_isEditorTokenValid(token)) return;
      await _loadLessonMedia();
      if (!mounted || !_isEditorTokenValid(token)) return;

      if (mounted && context.mounted) {
        showSnack(context, 'Ljud ersatt.');
      }
      if (mounted) {
        setState(() => _mediaStatus = 'Ljud ersatt.');
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() => _mediaStatus = null);
      }
      _showFriendlyErrorSnack('Kunde inte byta ljud', e, stackTrace);
    }
  }

  int? _parseCoursePriceOre() {
    final text = _coursePriceCtrl.text.trim();
    if (text.isEmpty) return null;
    return parseSekInputToOre(text);
  }

  int? _parseCourseDripIntervalDays() {
    return _parsePositiveIntText(_courseDripIntervalCtrl.text);
  }

  void _setTextControllerValue(
    TextEditingController controller,
    String nextText,
  ) {
    if (controller.text == nextText) {
      return;
    }
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  TextEditingController _createCourseCustomScheduleController(String text) {
    final controller = TextEditingController(text: text);
    controller.addListener(_handleCustomScheduleControllerUpdated);
    return controller;
  }

  void _disposeCourseCustomScheduleController(
    TextEditingController controller,
  ) {
    controller.removeListener(_handleCustomScheduleControllerUpdated);
    controller.dispose();
  }

  void _handleCustomScheduleControllerUpdated() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _hydrateCourseCustomScheduleControllers(Map<String, int> seededValues) {
    final validLessonIds = _lessons.isEmpty
        ? seededValues.keys.toSet()
        : <String>{for (final lesson in _lessons) lesson.id};
    for (final lessonId in _courseCustomScheduleCtrls.keys.toList()) {
      if (!validLessonIds.contains(lessonId)) {
        final removed = _courseCustomScheduleCtrls.remove(lessonId);
        if (removed != null) {
          _disposeCourseCustomScheduleController(removed);
        }
      }
    }

    if (_lessons.isEmpty) {
      for (final entry in seededValues.entries) {
        final controller = _courseCustomScheduleCtrls[entry.key];
        final nextText = '${entry.value}';
        if (controller == null) {
          _courseCustomScheduleCtrls[entry.key] =
              _createCourseCustomScheduleController(nextText);
        } else {
          _setTextControllerValue(controller, nextText);
        }
      }
      return;
    }

    var previousOffsetDays = 0;
    for (var index = 0; index < _lessons.length; index += 1) {
      final lesson = _lessons[index];
      final nextValue =
          seededValues[lesson.id] ?? (index == 0 ? 0 : previousOffsetDays);
      final nextText = '$nextValue';
      final controller = _courseCustomScheduleCtrls[lesson.id];
      if (controller == null) {
        _courseCustomScheduleCtrls[lesson.id] =
            _createCourseCustomScheduleController(nextText);
      } else {
        _setTextControllerValue(controller, nextText);
      }
      previousOffsetDays = nextValue;
    }
  }

  void _ensureCourseCustomScheduleControllers() {
    if (_lessons.isEmpty) {
      return;
    }
    final validLessonIds = <String>{for (final lesson in _lessons) lesson.id};
    for (final lessonId in _courseCustomScheduleCtrls.keys.toList()) {
      if (!validLessonIds.contains(lessonId)) {
        final removed = _courseCustomScheduleCtrls.remove(lessonId);
        if (removed != null) {
          _disposeCourseCustomScheduleController(removed);
        }
      }
    }

    var previousOffsetDays = 0;
    for (var index = 0; index < _lessons.length; index += 1) {
      final lesson = _lessons[index];
      final controller = _courseCustomScheduleCtrls[lesson.id];
      if (controller == null) {
        _courseCustomScheduleCtrls[lesson.id] =
            _createCourseCustomScheduleController(
              '${index == 0 ? 0 : previousOffsetDays}',
            );
        continue;
      }
      final parsedValue = _parsePositiveIntText(controller.text);
      previousOffsetDays = parsedValue ?? (index == 0 ? 0 : previousOffsetDays);
    }
  }

  TextEditingController _customScheduleControllerForLesson(
    LessonStudio lesson,
    int index,
  ) {
    final existing = _courseCustomScheduleCtrls[lesson.id];
    if (existing != null) {
      return existing;
    }
    final previousOffsetDays = index <= 0
        ? 0
        : (_parsePositiveIntText(
                _courseCustomScheduleCtrls[_lessons[index - 1].id]?.text ?? '',
              ) ??
              0);
    final controller = _createCourseCustomScheduleController(
      '${index == 0 ? 0 : previousOffsetDays}',
    );
    _courseCustomScheduleCtrls[lesson.id] = controller;
    return controller;
  }

  List<_CustomScheduleTimelineRowState>
  _buildCustomScheduleTimelineRowStates() {
    if (_lessons.isEmpty) {
      return const <_CustomScheduleTimelineRowState>[];
    }

    final rows = <_CustomScheduleTimelineRowState>[];
    for (var index = 0; index < _lessons.length; index += 1) {
      final lesson = _lessons[index];
      final controller = _customScheduleControllerForLesson(lesson, index);
      final rawValue = controller.text.trim();
      final unlockOffsetDays = int.tryParse(rawValue);
      final previousUnlockOffsetDays = index <= 0
          ? null
          : int.tryParse(
              _customScheduleControllerForLesson(
                _lessons[index - 1],
                index - 1,
              ).text.trim(),
            );
      _CustomScheduleRowValidationKind? validationKind;
      if (rawValue.isEmpty) {
        validationKind = _CustomScheduleRowValidationKind.missingValue;
      } else if (unlockOffsetDays == null) {
        validationKind = _CustomScheduleRowValidationKind.invalidInteger;
      } else if (unlockOffsetDays < 0) {
        validationKind = _CustomScheduleRowValidationKind.negativeValue;
      } else if (index == 0 && unlockOffsetDays != 0) {
        validationKind = _CustomScheduleRowValidationKind.firstLessonMustBeZero;
      } else if (previousUnlockOffsetDays != null &&
          previousUnlockOffsetDays >= 0 &&
          unlockOffsetDays < previousUnlockOffsetDays) {
        validationKind = _CustomScheduleRowValidationKind.decreasingOffset;
      }

      rows.add(
        _CustomScheduleTimelineRowState(
          lesson: lesson,
          index: index,
          rawValue: rawValue,
          unlockOffsetDays: unlockOffsetDays,
          previousUnlockOffsetDays: previousUnlockOffsetDays,
          validationKind: validationKind,
        ),
      );
    }
    return rows;
  }

  _CustomScheduleSummaryState _buildCustomScheduleSummaryState(
    List<_CustomScheduleTimelineRowState> rows,
  ) {
    final firstOffsetDays = rows.isEmpty ? null : rows.first.unlockOffsetDays;
    final lastOffsetDays = rows.isEmpty ? null : rows.last.unlockOffsetDays;
    final startLabel = firstOffsetDays == null
        ? 'dag -'
        : 'dag $firstOffsetDays';
    final lastLessonLabel = lastOffsetDays == null
        ? 'dag -'
        : 'dag $lastOffsetDays';
    return _CustomScheduleSummaryState(
      lessonCount: rows.length,
      startLabel: startLabel,
      lastLessonLabel: lastLessonLabel,
    );
  }

  String? _customTimelineTransitionExplanationText() {
    if (_courseDripMode != DripAuthoringMode.customLessonOffsets) {
      return null;
    }
    switch (_courseCustomTimelineEntrySourceMode) {
      case DripAuthoringMode.legacyUniformDrip:
        return 'Anpassat schema ers\u00E4tter fast intervall f\u00F6r kursen.';
      case DripAuthoringMode.noDripImmediateAccess:
        return 'Du anger nu n\u00E4r varje lektion blir tillg\u00E4nglig i kursens ordning.';
      case DripAuthoringMode.customLessonOffsets:
      case null:
        return null;
    }
  }

  String _lessonCountLabel(int lessonCount) {
    if (lessonCount == 1) {
      return '1 lektion';
    }
    return '$lessonCount lektioner';
  }

  List<Map<String, Object?>>? _buildCustomScheduleRowsPayload() {
    if (_lessonsLoading) {
      showSnack(context, 'Lektionerna laddas fortfarande.');
      return null;
    }
    final rowStates = _buildCustomScheduleTimelineRowStates();
    for (final rowState in rowStates) {
      switch (rowState.validationKind) {
        case _CustomScheduleRowValidationKind.missingValue:
          showSnack(
            context,
            'Alla lektioner måste ha ett antal dagar innan upplåsning.',
          );
          return null;
        case _CustomScheduleRowValidationKind.invalidInteger:
        case _CustomScheduleRowValidationKind.negativeValue:
          showSnack(
            context,
            'Varje lektion måste ha ett heltal större än eller lika med 0.',
          );
          return null;
        case _CustomScheduleRowValidationKind.firstLessonMustBeZero:
          showSnack(context, 'Första lektionen måste ha värdet 0.');
          return null;
        case _CustomScheduleRowValidationKind.decreasingOffset:
          showSnack(
            context,
            'Anpassat schema måste vara icke-minskande i lektionsordning.',
          );
          return null;
        case null:
          break;
      }
    }
    final rows = <Map<String, Object?>>[];
    for (final rowState in rowStates) {
      final unlockOffsetDays = rowState.unlockOffsetDays;
      if (unlockOffsetDays == null) {
        return null;
      }
      rows.add(<String, Object?>{
        'lesson_id': rowState.lesson.id,
        'unlock_offset_days': unlockOffsetDays,
      });
    }
    return rows;
  }

  Map<String, Object?>? _buildCourseDripAuthoringPayload() {
    switch (_courseDripMode) {
      case DripAuthoringMode.noDripImmediateAccess:
        return <String, Object?>{'mode': _courseDripMode.apiValue};
      case DripAuthoringMode.legacyUniformDrip:
        final intervalDays = _parseCourseDripIntervalDays();
        if (intervalDays == null || intervalDays <= 0) {
          showSnack(context, 'Antal dagar måste vara ett heltal större än 0.');
          return null;
        }
        return <String, Object?>{
          'mode': _courseDripMode.apiValue,
          'legacy_uniform': <String, Object?>{
            'drip_interval_days': intervalDays,
          },
        };
      case DripAuthoringMode.customLessonOffsets:
        final rows = _buildCustomScheduleRowsPayload();
        if (rows == null) {
          return null;
        }
        return <String, Object?>{
          'mode': _courseDripMode.apiValue,
          'custom_schedule': <String, Object?>{'rows': rows},
        };
    }
  }

  bool _isCourseScheduleLockedError(Object error) {
    if (error is! DioException) {
      return false;
    }
    final data = error.response?.data;
    if (data is Map) {
      if (data['code'] == 'studio_course_schedule_locked') {
        return true;
      }
      if (data['schedule_locked'] == true) {
        return true;
      }
      final detail = data['detail'];
      if (detail is String &&
          detail.toLowerCase().contains(
            'schedule-affecting edits are locked',
          )) {
        return true;
      }
    }
    return error.response?.statusCode == 409;
  }

  String _defaultDraftCourseSlug() {
    final suffix = _uuid.v4().replaceAll('-', '').substring(0, 8);
    return 'ny-kurs-$suffix';
  }

  void _invalidateCourseReadProviders() {
    ref.invalidate(myCoursesProvider);
    ref.invalidate(studioCoursesProvider);
    ref.invalidate(landing.popularCoursesProvider);
    ref.invalidate(coursesProvider);
  }

  Future<_CourseCreateInput?> _showCourseCreateDialog() async {
    return showDialog<_CourseCreateInput>(
      context: context,
      builder: (_) => _CourseCreateDialog(
        defaultSlug: _defaultDraftCourseSlug(),
        courseFamilies: _courseFamilies,
        initialCourseGroupId: _currentCourseFamily()?.id,
      ),
    );
  }

  Future<String?> _showCourseFamilyCreateDialog() async {
    return showDialog<String>(
      context: context,
      builder: (_) => const _CourseFamilyCreateDialog(),
    );
  }

  Future<String?> _showCourseFamilyRenameDialog(String initialName) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _CourseFamilyRenameDialog(initialName: initialName),
    );
  }

  Future<void> _refreshCourseFamiliesOnly() async {
    final refreshedFamilies = await _studioRepo.myCourseFamilies();
    if (!mounted) {
      return;
    }
    setState(() {
      _courseFamilies = refreshedFamilies;
      _managedCourseFamilyId = _courseFamilyManagementTarget(
        selectedCourseId: _selectedCourseId,
        currentValue: _managedCourseFamilyId,
        courseFamilies: refreshedFamilies,
      );
    });
  }

  Future<CourseStudio?> _refreshSelectedCourseAuthoringState({
    required String selectedCourseId,
    bool reloadLessons = false,
    String? preferredManagedCourseFamilyId,
  }) async {
    final results = await Future.wait<Object>([
      _studioRepo.myCourses(),
      _studioRepo.myCourseFamilies(),
    ]);
    final refreshedCourses = List<CourseStudio>.from(
      results[0] as List<CourseStudio>,
    );
    final refreshedFamilies = List<CourseFamilyStudio>.from(
      results[1] as List<CourseFamilyStudio>,
    );
    final canonicalCourse = _courseById(selectedCourseId, refreshedCourses);
    if (!mounted) {
      return canonicalCourse;
    }
    final effectiveSelectedCourseId =
        canonicalCourse?.id ?? _firstCourseId(refreshedCourses);
    final nextCourses = canonicalCourse == null
        ? refreshedCourses
        : _adoptCourseById(refreshedCourses, canonicalCourse);
    setState(() {
      _courses = nextCourses;
      _courseFamilies = refreshedFamilies;
      _selectedCourseId = effectiveSelectedCourseId;
      _managedCourseFamilyId = _courseFamilyManagementTarget(
        selectedCourseId: effectiveSelectedCourseId,
        currentValue: preferredManagedCourseFamilyId ?? _managedCourseFamilyId,
        courses: nextCourses,
        courseFamilies: refreshedFamilies,
      );
    });
    _invalidateCourseReadProviders();
    if (effectiveSelectedCourseId != null) {
      await _loadCourseMeta();
      if (reloadLessons) {
        await _loadLessons(preserveSelection: false);
      }
    }
    return canonicalCourse;
  }

  Future<void> _reorderSelectedCourseWithinFamily(int newPosition) async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final course = _courseById(_selectedCourseId);
    final family = _selectedCourseFamilySummary();
    if (course == null || family == null || _updatingCourseFamily) {
      return;
    }
    if (newPosition < 0 || newPosition >= family.courses.length) {
      return;
    }

    setState(() => _updatingCourseFamily = true);
    try {
      final updated = await _studioRepo.reorderCourseWithinFamily(
        course.id,
        groupPosition: newPosition,
      );
      await _refreshSelectedCourseAuthoringState(selectedCourseId: updated.id);
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Kursordningen uppdaterad.');
    } catch (error, stackTrace) {
      _showFriendlyErrorSnack(
        'Kunde inte uppdatera kursordningen',
        error,
        stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _updatingCourseFamily = false);
      }
    }
  }

  Future<void> _promptCreateCourse() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_creatingCourse) return;
    if (_courseFamilies.isEmpty) {
      showSnack(context, 'Skapa en kursfamilj först.');
      return;
    }
    if (!await _maybeSaveLessonEdits()) return;
    if (!mounted) return;

    final input = await _showCourseCreateDialog();
    if (input == null || !mounted) return;

    setState(() => _creatingCourse = true);
    try {
      final created = await _studioRepo.createCourse(
        title: input.title,
        slug: input.slug,
        courseGroupId: input.courseGroupId,
        priceAmountCents: input.priceAmountCents,
        dripEnabled: input.dripEnabled,
        dripIntervalDays: input.dripIntervalDays,
        coverMediaId: null,
      );
      if (!mounted) return;
      setState(() {
        _prepareCourseBoundarySelection(
          courseId: created.id,
          managedCourseFamilyId: input.courseGroupId,
        );
      });
      await _refreshSelectedCourseAuthoringState(
        selectedCourseId: created.id,
        reloadLessons: true,
        preferredManagedCourseFamilyId: input.courseGroupId,
      );
      if (mounted && context.mounted) {
        showSnack(context, 'Kurs skapad.');
      }
    } catch (e, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte skapa kurs', e, stackTrace);
    } finally {
      if (mounted) setState(() => _creatingCourse = false);
    }
  }

  Future<void> _promptCreateCourseFamily() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_creatingCourseFamily) return;
    if (!await _maybeSaveLessonEdits()) return;
    if (!mounted) return;

    final name = await _showCourseFamilyCreateDialog();
    if (name == null || !mounted) {
      return;
    }

    setState(() => _creatingCourseFamily = true);
    try {
      final family = await _studioRepo.createCourseFamily(name: name);
      await _refreshCourseFamiliesOnly();
      if (!mounted || !context.mounted) {
        return;
      }
      showSnack(context, 'Kursfamilj skapad: ${family.name}.');
    } catch (error, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte skapa kursfamilj', error, stackTrace);
    } finally {
      if (mounted) {
        setState(() => _creatingCourseFamily = false);
      }
    }
  }

  Future<void> _renameManagedCourseFamily() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_updatingCourseFamily) return;
    final family = _managedCourseFamily();
    if (family == null) {
      return;
    }
    if (!await _maybeSaveLessonEdits()) return;
    if (!mounted) return;

    final name = await _showCourseFamilyRenameDialog(family.name);
    if (name == null || !mounted) {
      return;
    }

    setState(() => _updatingCourseFamily = true);
    try {
      final renamed = await _studioRepo.renameCourseFamily(
        family.id,
        name: name,
      );
      await _refreshCourseFamiliesOnly();
      if (!mounted || !context.mounted) {
        return;
      }
      showSnack(context, 'Kursfamilj uppdaterad: ${renamed.name}.');
    } catch (error, stackTrace) {
      _showFriendlyErrorSnack(
        'Kunde inte byta namn på kursfamiljen',
        error,
        stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _updatingCourseFamily = false);
      }
    }
  }

  Future<void> _deleteManagedCourseFamily() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_updatingCourseFamily) return;
    final family = _managedCourseFamily();
    if (family == null || family.courseCount > 0) {
      return;
    }
    if (!await _maybeSaveLessonEdits()) return;
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ta bort kursfamilj?'),
        content: Text(
          'Detta tar bort den tomma kursfamiljen "${family.name}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Avbryt'),
          ),
          GradientButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _updatingCourseFamily = true);
    try {
      await _studioRepo.deleteCourseFamily(family.id);
      await _refreshCourseFamiliesOnly();
      if (!mounted || !context.mounted) {
        return;
      }
      showSnack(context, 'Kursfamilj borttagen.');
    } catch (error, stackTrace) {
      _showFriendlyErrorSnack(
        'Kunde inte ta bort kursfamiljen',
        error,
        stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() => _updatingCourseFamily = false);
      }
    }
  }

  Future<void> _saveCourseMeta() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final courseId = _selectedCourseId;
    if (courseId == null || _savingCourseMeta) return;
    final title = _courseTitleCtrl.text.trim();
    final slug = _courseSlugCtrl.text.trim();
    final description = _courseDescriptionCtrl.text.trim();
    final rawPriceText = _coursePriceCtrl.text.trim();
    final effectivePriceOre = _parseCoursePriceOre();

    if (title.isEmpty) {
      showSnack(context, 'Titel krävs.');
      return;
    }
    if (rawPriceText.isNotEmpty &&
        (effectivePriceOre == null || effectivePriceOre < 0)) {
      showSnack(
        context,
        'Pris måste vara ett tal ≥ 0 (t.ex. 490 eller 490.00).',
      );
      return;
    }
    final patch = <String, Object?>{
      'title': title,
      'price_amount_cents': effectivePriceOre,
    };
    if (slug.isNotEmpty) {
      patch['slug'] = slug;
    }
    _logCourseMetaPatchPayload(courseId: courseId, patch: patch);

    final requestId = ++_saveCourseRequestId;
    setState(() {
      _savingCourseMeta = true;
      _savingCoursePublicContent = true;
    });
    try {
      final updated = await _studioRepo.updateCourse(courseId, patch);
      final updatedPublicContent = await _studioRepo.upsertCoursePublicContent(
        courseId,
        description: description,
      );
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _saveCourseRequestId,
        courseId: courseId,
      )) {
        return;
      }
      _logCourseMetaPatchResponse(courseId: courseId, response: updated);
      setState(() {
        _courses = _courses
            .map((course) => course.id == courseId ? updated : course)
            .toList();
        _setTextControllerValue(
          _courseDescriptionCtrl,
          updatedPublicContent.description,
        );
      });
      _invalidateCourseReadProviders();
      await _loadCourseMeta();
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Kursinformation sparad.');
    } catch (e, stackTrace) {
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _saveCourseRequestId,
        courseId: courseId,
      )) {
        return;
      }
      _showFriendlyErrorSnack('Kunde inte spara kurs', e, stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _savingCourseMeta = false;
          _savingCoursePublicContent = false;
        });
      }
    }
  }

  Future<void> _saveCoursePublicContent() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final courseId = _selectedCourseId;
    if (courseId == null || _savingCoursePublicContent) return;
    final description = _courseDescriptionCtrl.text.trim();

    final requestId = ++_saveCoursePublicContentRequestId;
    setState(() => _savingCoursePublicContent = true);
    try {
      final updated = await _studioRepo.upsertCoursePublicContent(
        courseId,
        description: description,
      );
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _saveCoursePublicContentRequestId,
        courseId: courseId,
      )) {
        return;
      }
      setState(() {
        _setTextControllerValue(_courseDescriptionCtrl, updated.description);
      });
      _invalidateCourseReadProviders();
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Kursbeskrivning sparad.');
    } catch (e, stackTrace) {
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _saveCoursePublicContentRequestId,
        courseId: courseId,
      )) {
        return;
      }
      _showFriendlyErrorSnack(
        'Kunde inte spara kursbeskrivning',
        e,
        stackTrace,
      );
    } finally {
      if (mounted) setState(() => _savingCoursePublicContent = false);
    }
  }

  Future<bool> _saveCourseDripAuthoring({bool reloadOnFailure = false}) async {
    if (!_requireEditModeForMutation()) {
      return false;
    }
    final courseId = _selectedCourseId;
    if (courseId == null || _savingCourseDripAuthoring) {
      return false;
    }
    if (_courseScheduleLocked) {
      showSnack(context, _courseScheduleLockedMessage);
      return false;
    }

    final payload = _buildCourseDripAuthoringPayload();
    if (payload == null) {
      if (reloadOnFailure) {
        await _loadCourseMeta();
      }
      return false;
    }

    final requestId = ++_saveCourseDripRequestId;
    setState(() => _savingCourseDripAuthoring = true);
    try {
      final updated = await _studioRepo.updateCourseDripAuthoring(
        courseId,
        payload,
      );
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _saveCourseDripRequestId,
        courseId: courseId,
      )) {
        return false;
      }
      setState(() {
        _courses = _adoptCourseById(_courses, updated);
        _courseDripMode = updated.dripAuthoring.mode;
        _courseCustomTimelineEntrySourceMode = null;
        _courseScheduleLocked = updated.dripAuthoring.scheduleLocked;
      });
      _invalidateCourseReadProviders();
      await _loadCourseMeta();
      if (!mounted || !context.mounted) {
        return true;
      }
      showSnack(context, 'Lektionsschema sparat.');
      return true;
    } catch (error, stackTrace) {
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _saveCourseDripRequestId,
        courseId: courseId,
      )) {
        return false;
      }
      if (_isCourseScheduleLockedError(error)) {
        if (mounted && context.mounted) {
          showSnack(context, _courseScheduleLockedMessage);
        }
        await _loadCourseMeta();
        return false;
      }
      _showFriendlyErrorSnack(
        'Kunde inte spara lektionsschema',
        error,
        stackTrace,
      );
      if (reloadOnFailure) {
        await _loadCourseMeta();
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _savingCourseDripAuthoring = false);
      }
    }
  }

  Future<void> _publishSelectedCourse() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final courseId = _selectedCourseId;
    if (courseId == null || _publishingCourse) return;
    if (!await _maybeSaveLessonEdits()) return;
    if (!mounted) return;

    final requestId = ++_publishCourseRequestId;
    setState(() => _publishingCourse = true);
    try {
      final published = await _studioRepo.publishCourse(courseId);
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _publishCourseRequestId,
        courseId: courseId,
      )) {
        return;
      }
      setState(() {
        _courses = _adoptCourseById(_courses, published);
        _courseTitleCtrl.text = published.title;
        _courseSlugCtrl.text = published.slug;
        final priceOre = published.priceAmountCents;
        _coursePriceCtrl.text = priceOre == null
            ? ''
            : formatSekInputFromOre(priceOre);
        _courseDripMode = published.dripAuthoring.mode;
        _courseCustomTimelineEntrySourceMode = null;
        _courseScheduleLocked = published.dripAuthoring.scheduleLocked;
        _courseDripIntervalCtrl.text =
            published.dripAuthoring.dripIntervalDays?.toString() ?? '';
        _courseCoverPath = published.cover?.resolvedUrl;
      });
      _invalidateCourseReadProviders();
      await _loadCourseMeta();
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Kurs publicerad.');
    } catch (e, stackTrace) {
      if (_isStaleRequest(
        requestId: requestId,
        currentId: _publishCourseRequestId,
        courseId: courseId,
      )) {
        return;
      }
      _showFriendlyErrorSnack('Kunde inte publicera kurs', e, stackTrace);
    } finally {
      if (mounted) setState(() => _publishingCourse = false);
    }
  }

  Future<void> _handleCourseDripModeChanged(DripAuthoringMode? mode) async {
    if (mode == null || mode == _courseDripMode) {
      return;
    }
    if (mode == DripAuthoringMode.customLessonOffsets &&
        !_courseHasLessonsForCustomSchedule) {
      showSnack(context, _customScheduleLessonDependencyMessage);
      return;
    }
    final previousMode = _courseDripMode;
    if (mode == DripAuthoringMode.customLessonOffsets) {
      _ensureCourseCustomScheduleControllers();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _courseDripMode = mode;
      if (mode == DripAuthoringMode.customLessonOffsets &&
          previousMode != DripAuthoringMode.customLessonOffsets) {
        _courseCustomTimelineEntrySourceMode = previousMode;
      } else if (mode != DripAuthoringMode.customLessonOffsets) {
        _courseCustomTimelineEntrySourceMode = null;
      }
      if (mode == DripAuthoringMode.legacyUniformDrip &&
          _courseDripIntervalCtrl.text.trim().isEmpty) {
        _courseDripIntervalCtrl.text = '7';
      }
    });
    if (_shouldPersistDripModeChangeImmediately(mode)) {
      await _saveCourseDripAuthoring(reloadOnFailure: true);
    }
  }

  bool _shouldPersistDripModeChangeImmediately(DripAuthoringMode mode) {
    // Custom-mode controllers can contain local defaults; only the explicit
    // save button may promote custom_schedule.rows to canonical backend state.
    return mode != DripAuthoringMode.customLessonOffsets;
  }

  Widget _buildCustomScheduleSummaryChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomCourseTimelineRow(
    BuildContext context,
    _CustomScheduleTimelineRowState rowState,
    int rowCount,
  ) {
    final theme = Theme.of(context);
    final isFirst = rowState.isFirst;
    final isLast = rowState.index == rowCount - 1;
    final isLocked = _courseScheduleControlsDisabled;
    final cardColor = isLocked
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72)
        : theme.colorScheme.surface;
    final borderColor = rowState.errorText != null
        ? theme.colorScheme.error
        : (isFirst
              ? theme.colorScheme.primary.withValues(alpha: 0.42)
              : theme.colorScheme.outlineVariant);
    final timelineColor = isFirst
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final controller = _customScheduleControllerForLesson(
      rowState.lesson,
      rowState.index,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: timelineColor.withValues(alpha: isFirst ? 0.14 : 0.1),
                  border: Border.all(color: timelineColor),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${rowState.lesson.position}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isFirst
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 92,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: timelineColor.withValues(alpha: 0.4),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            key: ValueKey<String>(
              'course-custom-timeline-row-${rowState.lesson.id}',
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useVerticalLayout = constraints.maxWidth < 720;
                final metadata = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: isFirst ? 0.14 : 0.08,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isFirst
                                ? 'Startpunkt'
                                : 'Lektion ${rowState.lesson.position}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        Container(
                          key: ValueKey<String>(
                            'course-custom-day-label-${rowState.lesson.id}',
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            rowState.dayLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    gap8,
                    Text(
                      rowState.lesson.lessonTitle.isEmpty
                          ? 'Lektion ${rowState.lesson.position}'
                          : rowState.lesson.lessonTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    gap4,
                    Text(
                      isFirst
                          ? 'Första lektionen startar direkt.'
                          : 'Upplåsningen följer kursens ordning och kan inte gå bakåt.',
                      key: isFirst
                          ? const ValueKey<String>(
                              'course-custom-first-lesson-note',
                            )
                          : null,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isFirst
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isFirst ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                );
                final field = SizedBox(
                  width: useVerticalLayout ? double.infinity : 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: ValueKey<String>(
                          'course-custom-offset-${rowState.lesson.id}',
                        ),
                        controller: controller,
                        readOnly: isLocked,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        inputFormatters: [_courseCustomScheduleInputFormatter],
                        decoration: InputDecoration(
                          labelText: 'Upplåses dag',
                          helperText: isFirst
                              ? 'Dag 0 är kursstart.'
                              : 'Ange samma dag eller senare än föregående lektion.',
                        ),
                      ),
                      if (rowState.errorText != null) ...[
                        gap4,
                        Text(
                          rowState.errorText!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                );

                if (useVerticalLayout) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [metadata, gap12, field],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: metadata),
                    const SizedBox(width: 16),
                    field,
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomCourseScheduleFields(BuildContext context) {
    final theme = Theme.of(context);
    if (_lessonsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Laddar lektionsordning...')),
          ],
        ),
      );
    }
    if (_lessons.isEmpty) {
      return Text(
        _customScheduleLessonDependencyMessage,
        style: theme.textTheme.bodyMedium,
      );
    }

    _ensureCourseCustomScheduleControllers();
    final scheduleControllers = <TextEditingController>[
      for (var index = 0; index < _lessons.length; index += 1)
        _customScheduleControllerForLesson(_lessons[index], index),
    ];
    final scheduleListenable = Listenable.merge(scheduleControllers);
    return ListenableBuilder(
      listenable: scheduleListenable,
      builder: (context, child) {
        final rowStates = _buildCustomScheduleTimelineRowStates();
        final summary = _buildCustomScheduleSummaryState(rowStates);
        final transitionText = _customTimelineTransitionExplanationText();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (transitionText != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  transitionText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              gap12,
            ],
            Text(
              'Bygg kursens tidslinje genom att ange hur många dagar efter kursstart varje lektion blir tillgänglig. Ordningen följer lektionerna och kan inte minska.',
              style: theme.textTheme.bodyMedium,
            ),
            gap12,
            Container(
              key: const ValueKey<String>('course-custom-summary'),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildCustomScheduleSummaryChip(
                    context,
                    icon: Icons.format_list_numbered,
                    label: _lessonCountLabel(summary.lessonCount),
                  ),
                  _buildCustomScheduleSummaryChip(
                    context,
                    icon: Icons.play_circle_outline,
                    label: 'Start: ${summary.startLabel}',
                  ),
                  _buildCustomScheduleSummaryChip(
                    context,
                    icon: Icons.flag_outlined,
                    label: 'Sista lektionen: ${summary.lastLessonLabel}',
                  ),
                ],
              ),
            ),
            gap16,
            for (var index = 0; index < rowStates.length; index += 1) ...[
              _buildCustomCourseTimelineRow(
                context,
                rowStates[index],
                rowStates.length,
              ),
              if (index < rowStates.length - 1) gap12,
            ],
          ],
        );
      },
    );
  }

  Widget _buildCourseScheduleAuthoring(BuildContext context) {
    final theme = Theme.of(context);
    final availableModes = _availableCourseDripModes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<DripAuthoringMode>(
          key: ValueKey<String>('course-drip-mode-${_courseDripMode.apiValue}'),
          initialValue: _courseDripMode,
          items: availableModes
              .map(
                (mode) => DropdownMenuItem<DripAuthoringMode>(
                  value: mode,
                  child: Text(_dripAuthoringModeLabel(mode)),
                ),
              )
              .toList(growable: false),
          onChanged: _courseScheduleControlsDisabled
              ? null
              : (mode) {
                  unawaited(_handleCourseDripModeChanged(mode));
                },
          decoration: const InputDecoration(labelText: 'Schema'),
        ),
        if (!_courseHasLessonsForCustomSchedule &&
            _courseDripMode != DripAuthoringMode.customLessonOffsets) ...[
          gap12,
          Text(
            _customScheduleLessonDependencyMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (_courseScheduleLocked) ...[
          gap12,
          Text(
            _courseScheduleLockedMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        gap16,
        if (_courseDripMode == DripAuthoringMode.legacyUniformDrip) ...[
          TextField(
            key: const ValueKey<String>('course-legacy-interval-field'),
            controller: _courseDripIntervalCtrl,
            readOnly: _courseScheduleControlsDisabled,
            keyboardType: const TextInputType.numberWithOptions(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Antal dagar mellan lektioner',
              helperText: 'Ange ett heltal större än 0.',
            ),
          ),
        ],
        if (_courseDripMode == DripAuthoringMode.customLessonOffsets) ...[
          _buildCustomCourseScheduleFields(context),
        ],
        if (_courseDripMode == DripAuthoringMode.noDripImmediateAccess) ...[
          Text(
            'Alla lektioner blir tillgängliga direkt vid kursstart.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        gap16,
        GradientButton.icon(
          key: const ValueKey<String>('course-schedule-save-button'),
          onPressed: _courseScheduleSaveDisabled
              ? null
              : () {
                  unawaited(_saveCourseDripAuthoring());
                },
          icon: _savingCourseDripAuthoring
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(
            _savingCourseDripAuthoring ? 'Sparar...' : 'Spara schema',
          ),
        ),
      ],
    );
  }

  Widget _buildCourseFamilyAuthoring(BuildContext context) {
    final selectedCourse = _courseById(_selectedCourseId);
    final selectedFamily = _selectedCourseFamilySummary();
    final currentFamily = _currentCourseFamily();
    final managedFamily = _managedCourseFamily();
    final theme = Theme.of(context);
    final availableFamilies = _courseFamilies;

    if (availableFamilies.isEmpty) {
      return const Text(
        'Skapa en kursfamilj innan du skapar kurser eller hanterar ordning.',
      );
    }

    final canManageFamily = !_lessonPreviewMode && !_updatingCourseFamily;
    final managedFamilyItems = <DropdownMenuItem<String>>[
      for (final family in availableFamilies)
        DropdownMenuItem<String>(
          value: family.id,
          child: Text(
            family.courseCount == 1
                ? family.name
                : '${family.name} · ${family.courseCount} kurser',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    final managedFamilyValue =
        managedFamilyItems.any((item) => item.value == managedFamily?.id)
        ? managedFamily?.id
        : (managedFamilyItems.isEmpty ? null : managedFamilyItems.first.value);
    final managedFamilySummaryText = managedFamily == null
        ? 'Välj en kursfamilj för att byta namn eller ta bort en tom familj.'
        : managedFamily.courseCount > 0
        ? 'Familjen innehåller ${managedFamily.courseCount == 1 ? '1 kurs' : '${managedFamily.courseCount} kurser'} och kan inte tas bort förrän den är tom.'
        : 'Tomma kursfamiljer kan tas bort.';

    if (selectedCourse == null || selectedFamily == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Family: ${currentFamily?.name ?? _defaultCourseFamilyName}',
            style: theme.textTheme.bodyMedium,
          ),
          gap8,
          Text(
            'Manage Family: ${managedFamily?.name ?? _defaultCourseFamilyName}',
            style: theme.textTheme.bodyMedium,
          ),
          gap8,
          DropdownButtonFormField<String>(
            key: ValueKey<String>(
              'course_family_manage_target-${managedFamilyValue ?? 'none'}',
            ),
            isExpanded: true,
            initialValue: managedFamilyValue,
            decoration: const InputDecoration(labelText: 'Hantera kursfamilj'),
            selectedItemBuilder: (context) => availableFamilies
                .map((family) => _dropdownValueLabel(family.name))
                .toList(growable: false),
            items: managedFamilyItems,
            onChanged: canManageFamily && managedFamilyValue != null
                ? (value) {
                    if (value == null) return;
                    _handleManagedCourseFamilyChanged(value);
                  }
                : null,
          ),
          gap8,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final family in availableFamilies)
                Chip(
                  label: Text(
                    family.courseCount == 1
                        ? family.name
                        : '${family.name} · ${family.courseCount} kurser',
                  ),
                  backgroundColor: currentFamily?.id == family.id
                      ? theme.colorScheme.primary.withValues(alpha: 0.14)
                      : null,
                ),
            ],
          ),
          gap8,
          Text(managedFamilySummaryText, style: theme.textTheme.bodySmall),
          gap12,
          Text(
            'Skapa en kurs i en befintlig familj eller välj en kurs för att hantera ordning.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    final canMutateFamily = !_lessonPreviewMode && !_updatingCourseFamily;
    final canMoveUp = canMutateFamily && selectedCourse.groupPosition > 0;
    final canMoveDown =
        canMutateFamily &&
        selectedCourse.groupPosition < selectedFamily.courses.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Current Family: ${currentFamily?.name ?? _defaultCourseFamilyName}',
          style: theme.textTheme.bodyMedium,
        ),
        gap8,
        Text(
          'Manage Family: ${managedFamily?.name ?? _defaultCourseFamilyName}',
          style: theme.textTheme.bodyMedium,
        ),
        gap8,
        DropdownButtonFormField<String>(
          key: ValueKey<String>(
            'course_family_manage_target-${managedFamilyValue ?? 'none'}',
          ),
          isExpanded: true,
          initialValue: managedFamilyValue,
          decoration: const InputDecoration(labelText: 'Hantera kursfamilj'),
          selectedItemBuilder: (context) => availableFamilies
              .map((family) => _dropdownValueLabel(family.name))
              .toList(growable: false),
          items: managedFamilyItems,
          onChanged: canManageFamily && managedFamilyValue != null
              ? (value) {
                  if (value == null) return;
                  _handleManagedCourseFamilyChanged(value);
                }
              : null,
        ),
        gap8,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final family in availableFamilies)
              Chip(
                label: Text(
                  family.courseCount == 1
                      ? family.name
                      : '${family.name} · ${family.courseCount} kurser',
                ),
                backgroundColor: currentFamily?.id == family.id
                    ? theme.colorScheme.primary.withValues(alpha: 0.14)
                    : null,
              ),
          ],
        ),
        gap8,
        Text(managedFamilySummaryText, style: theme.textTheme.bodySmall),
        gap8,
        Text(
          'Stage: ${_coursePositionSummary(selectedCourse)}',
          style: theme.textTheme.bodyMedium,
        ),
        gap12,
        Text('Family sequence', style: theme.textTheme.labelLarge),
        gap8,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final course in selectedFamily.courses)
              Chip(
                label: Text(
                  '${_courseStepLabel(course.groupPosition)} · ${course.title.trim().isEmpty ? 'Untitled course' : course.title}',
                ),
                backgroundColor: course.id == selectedCourse.id
                    ? theme.colorScheme.primary.withValues(alpha: 0.14)
                    : null,
                side: BorderSide(
                  color: course.id == selectedCourse.id
                      ? theme.colorScheme.primary.withValues(alpha: 0.35)
                      : theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
          ],
        ),
        gap12,
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey<String>('course_family_move_up_button'),
              onPressed: canMoveUp
                  ? () => _reorderSelectedCourseWithinFamily(
                      selectedCourse.groupPosition - 1,
                    )
                  : null,
              icon: const Icon(Icons.arrow_upward),
              label: const Text('Flytta upp'),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('course_family_move_down_button'),
              onPressed: canMoveDown
                  ? () => _reorderSelectedCourseWithinFamily(
                      selectedCourse.groupPosition + 1,
                    )
                  : null,
              icon: const Icon(Icons.arrow_downward),
              label: const Text('Flytta ned'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return AppScaffold(
        title: 'Kursstudio',
        logoSize: 0,
        showHomeAction: false,
        onBack: () => context.goNamed(AppRoute.teacherHome),
        maxContentWidth: 1920,
        contentPadding: EdgeInsets.zero,
        actions: [TopNavActionButtons()],
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_allowed) {
      return AppScaffold(
        title: 'Kursstudio',
        logoSize: 0,
        showHomeAction: false,
        onBack: () => context.goNamed(AppRoute.teacherHome),
        maxContentWidth: 1920,
        contentPadding: EdgeInsets.zero,
        actions: const [TopNavActionButtons()],
        body: Center(
          child: GlassCard(
            padding: const EdgeInsets.all(32),
            borderRadius: BorderRadius.circular(24),
            opacity: 0.18,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48),
                SizedBox(height: 16),
                Text(
                  'Endast certifierade lärare har åtkomst till kurseditorn.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    final uploadJobs = ref.watch(studioUploadQueueProvider);
    final lessonUploadJobs = _selectedLessonId == null
        ? const <UploadJob>[]
        : (uploadJobs.where((job) => job.lessonId == _selectedLessonId).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    final wavLessonId = _selectedLessonId;
    final wavCourseId = _lessonCourseId(_selectedLessonId);

    final lessonVideoPreview = _buildLessonVideoPreview(context);
    final courseItems = _courseDropdownItems();
    final selectedCourseInItems =
        _selectedCourseId != null &&
        courseItems.any((item) => item.value == _selectedCourseId);
    final selectedCourseValue = selectedCourseInItems
        ? _selectedCourseId
        : null;
    final lessonsLoadError = _lessonsLoadError;
    final mediaStatus = _mediaStatus;
    final downloadStatus = _downloadStatus;
    final mediaLoadError = _mediaLoadError;

    final editorContent = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1200;
        final editorHeight = max(420.0, constraints.maxHeight * 0.55);

        final panel = Scrollbar(
          controller: _panelScrollController,
          thumbVisibility: isWide,
          child: SingleChildScrollView(
            controller: _panelScrollController,
            padding: p16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionCard(
                  title: 'Course Family',
                  actions: [
                    OutlinedButton.icon(
                      onPressed:
                          _creatingCourseFamily ||
                              _updatingCourseFamily ||
                              _lessonPreviewMode
                          ? null
                          : _promptCreateCourseFamily,
                      icon: _creatingCourseFamily
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.create_new_folder_outlined),
                      label: Text(
                        _creatingCourseFamily ? 'Skapar...' : 'Skapa familj',
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'course_family_rename_button',
                      ),
                      onPressed:
                          _updatingCourseFamily ||
                              _creatingCourseFamily ||
                              _lessonPreviewMode ||
                              _managedCourseFamily() == null
                          ? null
                          : _renameManagedCourseFamily,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Byt namn'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'course_family_delete_button',
                      ),
                      onPressed:
                          _updatingCourseFamily ||
                              _creatingCourseFamily ||
                              _lessonPreviewMode ||
                              _managedCourseFamily() == null ||
                              _managedCourseFamily()!.courseCount > 0
                          ? null
                          : _deleteManagedCourseFamily,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Ta bort'),
                    ),
                  ],
                  child: _buildCourseFamilyAuthoring(context),
                ),
                gap12,
                _SectionCard(
                  title: 'Välj kurs',
                  actions: [
                    OutlinedButton.icon(
                      onPressed:
                          _creatingCourse ||
                              _lessonPreviewMode ||
                              _courseFamilies.isEmpty
                          ? null
                          : _promptCreateCourse,
                      icon: _creatingCourse
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: const Text('Skapa kurs'),
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'course-${selectedCourseValue ?? 'none'}',
                        ),
                        isExpanded: true,
                        initialValue: selectedCourseValue,
                        items: courseItems,
                        onChanged: (value) async {
                          if (value == _selectedCourseId) return;
                          final canSwitch = await _maybeSaveLessonEdits();
                          if (!canSwitch || !mounted) return;
                          setState(() {
                            _prepareCourseBoundarySelection(courseId: value);
                          });
                          await _loadCourseMeta();
                          await _loadLessons(preserveSelection: false);
                        },
                        decoration: const InputDecoration(
                          hintText: 'Välj kurs',
                        ),
                      ),
                      if (courseItems.isEmpty) ...[
                        gap8,
                        Text(
                          _courseFamilies.isEmpty
                              ? 'Skapa en kursfamilj först. Kurser kan bara skapas i en befintlig familj.'
                              : 'Inga kurser i vald kursfamilj.',
                        ),
                      ],
                    ],
                  ),
                ),
                if (_selectedCourseId != null) ...[
                  gap12,
                  _SectionCard(
                    title: 'Kursinformation',
                    child: _courseMetaLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _courseTitleCtrl,
                                readOnly: _lessonPreviewMode,
                                decoration: const InputDecoration(
                                  labelText: 'Titel',
                                ),
                              ),
                              gap12,
                              _buildCourseCoverAndDescriptionEditor(context),
                              gap12,
                              TextField(
                                controller: _coursePriceCtrl,
                                readOnly: _lessonPreviewMode,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Pris (SEK)',
                                ),
                              ),
                              gap16,
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  GradientButton.icon(
                                    onPressed:
                                        _savingCourseMeta || _lessonPreviewMode
                                        ? null
                                        : _saveCourseMeta,
                                    icon: _savingCourseMeta
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.save_outlined),
                                    label: const Text('Spara kurs'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed:
                                        _publishingCourse ||
                                            _savingCourseMeta ||
                                            _lessonPreviewMode
                                        ? null
                                        : _publishSelectedCourse,
                                    icon: _publishingCourse
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.publish_outlined),
                                    label: Text(
                                      _publishingCourse
                                          ? 'Publicerar...'
                                          : 'Publicera kurs',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                  gap12,
                  _SectionCard(
                    title: 'Lektionsschema',
                    child: _courseMetaLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _buildCourseScheduleAuthoring(context),
                  ),
                  if (lessonVideoPreview != null) ...[
                    gap12,
                    lessonVideoPreview,
                  ],
                ],
                gap16,
                _SectionCard(
                  title: 'Lektioner i kursen',
                  actions: [
                    if (_selectedCourseId != null)
                      OutlinedButton.icon(
                        onPressed: _lessonActionBusy || _lessonPreviewMode
                            ? null
                            : _promptCreateLesson,
                        icon: const Icon(Icons.add),
                        label: const Text('Lägg till lektion'),
                      ),
                  ],
                  child: _selectedCourseId == null
                      ? const Text('Välj en kurs för att hantera lektioner.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (lessonsLoadError != null) ...[
                              Text(
                                lessonsLoadError,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                              ),
                              TextButton(
                                onPressed: _lessonsLoading
                                    ? null
                                    : () => _loadLessons(
                                        preserveSelection: true,
                                        mergeResults: true,
                                      ),
                                child: const Text('Försök igen'),
                              ),
                              gap8,
                            ],
                            if (_lessonsLoading)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else ...[
                              if (_lessons.isNotEmpty) ...[
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _lessons.length,
                                  onReorder: _handleLessonReorder,
                                  buildDefaultDragHandles: false,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  itemBuilder: (context, index) {
                                    final lesson = _lessons[index];
                                    final lessonId = lesson.id;
                                    return Padding(
                                      key: ValueKey(lessonId),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: _buildLessonListTile(
                                        context,
                                        lesson,
                                        index: index,
                                      ),
                                    );
                                  },
                                ),
                              ],
                              if (!isWide && _selectedCourseId != null) ...[
                                gap12,
                                _buildNarrowLessonEditorSurface(
                                  context,
                                  editorHeight: editorHeight,
                                ),
                              ],
                              if (_lessons.isEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Inga lektioner ännu.'),
                                    gap8,
                                    OutlinedButton.icon(
                                      onPressed:
                                          _lessonActionBusy ||
                                              _lessonPreviewMode
                                          ? null
                                          : _promptCreateLesson,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Lägg till lektion'),
                                    ),
                                  ],
                                )
                              else ...[
                                Builder(
                                  builder: (context) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Använd verktygsfältet ovan för bild, video och ljud. PDF laddas upp via knappen Infoga PDF.',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    );
                                  },
                                ),
                                if (lessonUploadJobs.isNotEmpty) ...[
                                  gap8,
                                  Column(
                                    children: [
                                      for (final job in lessonUploadJobs)
                                        _buildUploadJobCard(job),
                                    ],
                                  ),
                                ],
                                if (mediaStatus != null) ...[
                                  gap8,
                                  Text(mediaStatus),
                                ],
                                if (downloadStatus != null) ...[
                                  gap4,
                                  Text(
                                    downloadStatus,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                        ),
                                  ),
                                ],
                                if (mediaLoadError != null) ...[
                                  gap8,
                                  Text(
                                    mediaLoadError,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                  ),
                                  TextButton(
                                    onPressed: _mediaLoading
                                        ? null
                                        : () => _loadLessonMedia(),
                                    child: const Text('Försök igen'),
                                  ),
                                ],
                                if (!_lessonPreviewMode &&
                                    _selectedLessonId != null) ...[
                                  gap12,
                                  WavUploadCard(
                                    key: ValueKey(
                                      'wav-${wavLessonId ?? 'none'}-${wavCourseId ?? 'none'}',
                                    ),
                                    // Lesson is the source of truth for course_id.
                                    courseId: wavCourseId,
                                    lessonId: wavLessonId,
                                    onMediaUpdated: _loadLessonMedia,
                                  ),
                                ],
                                const Divider(height: 24),
                                if (_mediaLoading)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (_selectedLessonId == null)
                                  const Text(
                                    'Välj en lektion för att hantera media.',
                                  )
                                else if (_lessonMedia.isEmpty)
                                  const Text('Inget media uppladdat ännu.')
                                else
                                  SizedBox(
                                    height: 260,
                                    child: ReorderableListView.builder(
                                      itemCount: _lessonMedia.length,
                                      onReorder: _handleMediaReorder,
                                      buildDefaultDragHandles: false,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      itemBuilder: (context, index) {
                                        final media = _lessonMedia[index];
                                        final theme = Theme.of(context);
                                        final kind = media.mediaType;
                                        final position = media.position;
                                        final isWavMedia = _isWavMedia(media);
                                        final mediaState = media.state;
                                        final previewStatus =
                                            _previewStatusForMedia(media);
                                        final usesAuthoritativeStatus =
                                            _requiresAuthoritativeEditorReadiness(
                                              media,
                                            );
                                        final statusKey =
                                            usesAuthoritativeStatus
                                            ? switch (previewStatus?.state ??
                                                  LessonMediaPreviewState
                                                      .loading) {
                                                LessonMediaPreviewState.ready =>
                                                  'ready',
                                                LessonMediaPreviewState
                                                    .failed =>
                                                  'failed',
                                                LessonMediaPreviewState
                                                    .loading =>
                                                  mediaState != 'ready' &&
                                                          mediaState != 'failed'
                                                      ? 'processing'
                                                      : 'checking',
                                              }
                                            : mediaState == 'ready'
                                            ? 'ready'
                                            : mediaState == 'failed'
                                            ? 'failed'
                                            : 'processing';
                                        final statusColor = statusKey == 'ready'
                                            ? theme.colorScheme.primary
                                            : statusKey == 'failed'
                                            ? theme.colorScheme.error
                                            : theme.colorScheme.secondary;
                                        final statusLabel = _mediaStatusLabel(
                                          statusKey,
                                        );
                                        final mediaId = media.lessonMediaId;
                                        final mediaIsEmbedded =
                                            _lessonAlreadyContainsMediaId(
                                              mediaId,
                                            );
                                        final canPreview =
                                            _canPreviewLessonMedia(
                                              media: media,
                                              isWavMedia: isWavMedia,
                                            );
                                        final fileName = _fileNameFromMedia(
                                          media,
                                        );
                                        final canInsertIntoLesson =
                                            !_lessonPreviewMode &&
                                            !isWavMedia &&
                                            _canInsertLessonMedia(media);
                                        final isDocument = _isDocumentMedia(
                                          media,
                                        );
                                        final canDownload =
                                            !isWavMedia &&
                                            _hasCanonicalDeliveryMedia(media);

                                        Widget leading;
                                        leading = ClipRRect(
                                          borderRadius: const BorderRadius.all(
                                            Radius.circular(8),
                                          ),
                                          child: SizedBox.square(
                                            dimension: 48,
                                            child: LessonMediaPreview(
                                              lessonMediaId: mediaId,
                                              mediaType: kind,
                                            ),
                                          ),
                                        );

                                        return Padding(
                                          key: ValueKey(mediaId),
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: GlassCard(
                                            padding: EdgeInsets.zero,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            opacity: 0.16,
                                            borderColor: Colors.white
                                                .withValues(alpha: 0.28),
                                            child: ListTile(
                                              onTap:
                                                  isDocument &&
                                                      canInsertIntoLesson
                                                  ? () =>
                                                        _insertMediaIntoLesson(
                                                          media,
                                                        )
                                                  : canPreview
                                                  ? () =>
                                                        _handleMediaPreviewTap(
                                                          media,
                                                        )
                                                  : null,
                                              leading: SizedBox(
                                                width: 64,
                                                child: Center(child: leading),
                                              ),
                                              title: Text(
                                                fileName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    children: [
                                                      Chip(
                                                        label: Text(
                                                          statusLabel,
                                                        ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        backgroundColor:
                                                            statusColor
                                                                .withValues(
                                                                  alpha: 0.14,
                                                                ),
                                                        side: BorderSide(
                                                          color: statusColor
                                                              .withValues(
                                                                alpha: 0.35,
                                                              ),
                                                        ),
                                                        labelStyle: theme
                                                            .textTheme
                                                            .labelSmall
                                                            ?.copyWith(
                                                              color:
                                                                  statusColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    'Lektionsmedia',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelSmall,
                                                  ),
                                                  Text(
                                                    'Position $position • ${kind.toUpperCase()}',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelSmall,
                                                  ),
                                                  Text(
                                                    _pipelineLabel(mediaState),
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelSmall,
                                                  ),
                                                ],
                                              ),
                                              trailing: TooltipVisibility(
                                                visible: false,
                                                child: Wrap(
                                                  spacing: 4,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    IconButton(
                                                      tooltip:
                                                          'Infoga i lektionen',
                                                      icon: Icon(
                                                        _isImageMedia(media)
                                                            ? Icons
                                                                  .add_photo_alternate_outlined
                                                            : isDocument
                                                            ? Icons
                                                                  .picture_as_pdf_outlined
                                                            : kind == 'video'
                                                            ? Icons
                                                                  .movie_creation_outlined
                                                            : Icons
                                                                  .audiotrack_outlined,
                                                      ),
                                                      onPressed:
                                                          canInsertIntoLesson
                                                          ? () =>
                                                                _insertMediaIntoLesson(
                                                                  media,
                                                                )
                                                          : null,
                                                    ),
                                                    if (kind == 'audio')
                                                      IconButton(
                                                        tooltip: 'Byt ljud',
                                                        icon: const Icon(
                                                          Icons.sync,
                                                        ),
                                                        onPressed:
                                                            _lessonPreviewMode
                                                            ? null
                                                            : () =>
                                                                  _replaceAudioMedia(
                                                                    media,
                                                                    index,
                                                                  ),
                                                      ),
                                                    IconButton(
                                                      tooltip: 'Ladda ner',
                                                      icon: const Icon(
                                                        Icons.download_outlined,
                                                      ),
                                                      onPressed: canDownload
                                                          ? () =>
                                                                _downloadMedia(
                                                                  media,
                                                                )
                                                          : null,
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Ta bort',
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                      ),
                                                      onPressed:
                                                          _lessonPreviewMode ||
                                                              mediaIsEmbedded
                                                          ? null
                                                          : () => _deleteMedia(
                                                              mediaId,
                                                            ),
                                                    ),
                                                    if (!_lessonPreviewMode)
                                                      ReorderableDragStartListener(
                                                        index: index,
                                                        child: const Icon(
                                                          Icons
                                                              .drag_handle_rounded,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        );

        if (!isWide) return panel;

        final panelWidth = min(460.0, max(340.0, constraints.maxWidth * 0.34));

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: panelWidth, child: panel),
              const SizedBox(width: 16),
              Expanded(child: _buildLessonEditorWorkspace(context)),
            ],
          ),
        );
      },
    );

    return AppScaffold(
      title: 'Kursstudio',
      logoSize: 0,
      showHomeAction: false,
      onBack: () => context.goNamed(AppRoute.teacherHome),
      maxContentWidth: 1920,
      contentPadding: EdgeInsets.zero,
      useBasePage: false,
      actions: const [TopNavActionButtons()],
      body: editorContent,
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  const _SectionCard({required this.title, required this.child, this.actions});

  @override
  Widget build(BuildContext context) {
    final sectionActions = actions;
    return GlassCard(
      padding: p16,
      borderRadius: BorderRadius.circular(20),
      opacity: 0.18,
      borderColor: Colors.white.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final titleText = Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              );
              if (sectionActions == null || sectionActions.isEmpty) {
                return titleText;
              }

              final actionsWrap = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sectionActions,
              );
              final stackHeader = constraints.maxWidth < 520;
              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleText, gap8, actionsWrap],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleText),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: actionsWrap,
                    ),
                  ),
                ],
              );
            },
          ),
          gap12,
          child,
        ],
      ),
    );
  }
}
