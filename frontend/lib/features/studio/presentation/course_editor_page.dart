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
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:uuid/uuid.dart';

import 'package:aveli/editor/adapter/editor_to_markdown.dart'
    as editor_to_markdown;
import 'package:aveli/editor/debug/editor_debug.dart';
import 'package:aveli/editor/debug/editor_debug_overlay.dart';
import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;
import 'package:aveli/editor/session/editor_operation_controller.dart';
import 'package:aveli/editor/session/editor_session.dart';
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
import 'package:aveli/features/courses/presentation/lesson_page.dart'
    show LearnerLessonContentRenderer;
import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;
import 'package:aveli/shared/utils/lesson_media_render_telemetry.dart';
import 'package:aveli/shared/utils/pdf_link_editor_support.dart';
import 'package:aveli/shared/utils/quill_embed_insertion.dart';
import 'package:aveli/features/studio/presentation/editor_test_bridge.dart'
    as editor_test_bridge;
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

const Map<String, String> _editorFontOptions = <String, String>{
  'Återställ standard': 'Clear',
  'Noto Sans (sans-serif)': 'NotoSans',
  'Merriweather (serif)': 'Merriweather',
  'Lora (serif)': 'Lora',
  'Playfair Display (rubrik)': 'PlayfairDisplay',
};

enum _LessonEditorBootPhase {
  booting,
  applyingLessonDocument,
  error,
  fullyStable,
}

enum _LessonPreviewSource { live, saved }

class _EditorSessionToken {
  const _EditorSessionToken({
    required this.sessionId,
    required this.lessonId,
    required this.selectedLessonId,
  });

  final String sessionId;
  final String lessonId;
  final String selectedLessonId;
}

class _PersistedLessonPreviewSnapshot {
  const _PersistedLessonPreviewSnapshot({
    required this.lessonId,
    required this.courseId,
    required this.title,
    required this.markdown,
    required this.lessonMedia,
    required this.coverResolvedUrl,
  });

  final String lessonId;
  final String courseId;
  final String title;
  final String markdown;
  final List<LessonMediaItem> lessonMedia;
  final String? coverResolvedUrl;
}

class _CourseCreateInput {
  const _CourseCreateInput({
    required this.title,
    required this.slug,
    required this.priceAmountCents,
  });

  final String title;
  final String slug;
  final int? priceAmountCents;
}

class _CourseCreateDialog extends StatefulWidget {
  const _CourseCreateDialog({required this.defaultSlug});

  final String defaultSlug;

  @override
  State<_CourseCreateDialog> createState() => _CourseCreateDialogState();
}

class _CourseCreateDialogState extends State<_CourseCreateDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _slugController;
  late final TextEditingController _priceController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'Ny kurs');
    _slugController = TextEditingController(text: widget.defaultSlug);
    _priceController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _slugController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    final rawPriceText = _priceController.text.trim();
    final priceAmountCents = rawPriceText.isEmpty
        ? null
        : parseSekInputToOre(rawPriceText);

    if (title.isEmpty) {
      setState(() => _errorText = 'Titel krävs.');
      return;
    }
    if (slug.isEmpty) {
      setState(() => _errorText = 'Kursadress krävs.');
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

    Navigator.of(context).pop(
      _CourseCreateInput(
        title: title,
        slug: slug,
        priceAmountCents: priceAmountCents,
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

class _AudioEmbedBuilder implements quill.EmbedBuilder {
  const _AudioEmbedBuilder({this.hydrationListenable});

  final ValueListenable<LessonMediaPreviewHydrationSnapshot>?
  hydrationListenable;

  @override
  String get key => 'audio';

  @override
  bool get expanded => true;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(quill.Embed node) =>
      quill.Embed.kObjectReplacementCharacter;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final node = embedContext.node;
    final dynamic value = node.value.data;
    final lessonMediaId = lesson_pipeline.lessonMediaIdFromEmbedValue(value);
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      return _invalidLessonMediaReferenceWidget('audio');
    }
    return LessonMediaPreview(
      lessonMediaId: lessonMediaId,
      mediaType: 'audio',
      hydrating: false,
      hydrationListenable: hydrationListenable,
    );
  }
}

class _VideoEmbedBuilder implements quill.EmbedBuilder {
  const _VideoEmbedBuilder({this.hydrationListenable});

  final ValueListenable<LessonMediaPreviewHydrationSnapshot>?
  hydrationListenable;

  @override
  String get key => quill.BlockEmbed.videoType;

  @override
  bool get expanded => false;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(quill.Embed node) =>
      quill.Embed.kObjectReplacementCharacter;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final node = embedContext.node;
    final dynamic value = node.value.data;
    final lessonMediaId = lesson_pipeline.lessonMediaIdFromEmbedValue(value);
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      return _invalidLessonMediaReferenceWidget('video');
    }
    return LessonMediaPreview(
      lessonMediaId: lessonMediaId,
      mediaType: 'video',
      hydrating: false,
      hydrationListenable: hydrationListenable,
    );
  }
}

class _ImageEmbedBuilder implements quill.EmbedBuilder {
  const _ImageEmbedBuilder({this.hydrationListenable});

  final ValueListenable<LessonMediaPreviewHydrationSnapshot>?
  hydrationListenable;

  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(quill.Embed node) =>
      quill.Embed.kObjectReplacementCharacter;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final dynamic value = embedContext.node.value.data;
    final lessonMediaId = lesson_pipeline.lessonMediaIdFromEmbedValue(value);
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      return _invalidLessonMediaReferenceWidget('image');
    }
    return LessonMediaPreview(
      lessonMediaId: lessonMediaId,
      mediaType: 'image',
      hydrating: false,
      hydrationListenable: hydrationListenable,
    );
  }
}

Widget _invalidLessonMediaReferenceWidget(String mediaType) {
  return Padding(
    padding: const EdgeInsets.all(12),
    child: Text('Ogiltig $mediaType-referens', textAlign: TextAlign.center),
  );
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
  String? _selectedCourseId;

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

  late EditorSession _editorSession;
  late final FocusNode _lessonContentFocusNodeHandle;
  late final ScrollController _lessonEditorScrollControllerHandle;
  final ScrollController _panelScrollController = ScrollController();
  final TextEditingController _lessonTitleCtrl = TextEditingController();
  static const Duration _lessonPreviewHydrationTimeout = Duration(seconds: 5);
  late final LessonMediaPreviewHydrationController _previewHydrationController;
  _LessonEditorBootPhase _lessonEditorBootPhase =
      _LessonEditorBootPhase.booting;
  String? _documentReadyLessonId;
  int? _documentReadyRequestId;
  bool _lessonPreviewMode = false;
  _LessonPreviewSource _lessonPreviewSource = _LessonPreviewSource.live;

  int _persistedLessonPreviewRequestId = 0;
  bool _persistedLessonPreviewLoading = false;
  String? _persistedLessonPreviewError;
  _PersistedLessonPreviewSnapshot? _persistedLessonPreviewSnapshot;
  bool _lessonContentDirty = false;
  bool _lessonContentSaving = false;
  String _lastSavedLessonTitle = '';
  String _lastSavedLessonMarkdown = '';
  String? _lastSavedLessonContentEtag;
  String? _lessonContentHydratedLessonId;
  String? _lessonContentLoadError;
  TextSelection? _lastLessonSelection;
  bool _lessonContentControllerInitialized = false;
  int _lessonContentControllerGeneration = 0;
  VoidCallback? _controllerListener;
  StreamSubscription<quill.DocChange>? _controllerChangesSubscription;

  final TextEditingController _courseTitleCtrl = TextEditingController();
  final TextEditingController _courseSlugCtrl = TextEditingController();
  final TextEditingController _coursePriceCtrl = TextEditingController();

  bool _courseMetaLoading = false;
  bool _savingCourseMeta = false;
  bool _creatingCourse = false;
  bool _publishingCourse = false;
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
  bool _lessonEditorFocusRestoreScheduled = false;
  final Set<String> _lessonsNeedingRefresh = <String>{};
  int _courseMetaRequestId = 0;
  int _lessonsRequestId = 0;
  int _lessonMediaRequestId = 0;
  int _lessonContentRequestId = 0;
  int _saveCourseRequestId = 0;
  int _publishCourseRequestId = 0;

  quill.QuillController get _lessonContentController =>
      _editorSession.controller;

  FocusNode get _lessonContentFocusNode => _editorSession.focusNode;

  ScrollController get _lessonEditorScrollController =>
      _editorSession.scrollController;

  int _controllerIdentity(quill.QuillController controller) =>
      identityHashCode(controller);

  String _editorLessonIdValue(String? lessonId) {
    final value = lessonId;
    if (value == null) return 'null';
    return value.isEmpty ? 'empty' : value;
  }

  String _editorLessonId([String? lessonId]) =>
      _editorLessonIdValue(lessonId ?? _editorSession.lessonId);

  void _logEditorPageEvent({
    required String event,
    quill.QuillController? controller,
    TextSelection? selection,
    String? sessionId,
    String? lessonId,
    String? extraContext,
  }) {
    if (!kEditorDebug) return;
    final activeController = controller ?? _lessonContentController;
    final buffer = StringBuffer('event=$event');
    buffer.write(' controller=${_controllerIdentity(activeController)}');
    buffer.write(' session=${sessionId ?? _editorSession.sessionId}');
    buffer.write(' lesson=${_editorLessonId(lessonId)}');
    buffer.write(
      ' selection=${formatEditorSelection(selection ?? activeController.selection)}',
    );
    buffer.write(' focus=${_lessonContentFocusNode.hasFocus}');
    if (extraContext != null && extraContext.isNotEmpty) {
      buffer.write(' $extraContext');
    }
    logEditor(buffer.toString());
  }

  void _warnIfSelectionInvalid(
    TextSelection selection, {
    quill.QuillController? controller,
    required String source,
  }) {
    if (!kEditorDebug) return;
    final activeController = controller ?? _lessonContentController;
    final normalized = _clampEditorSelection(selection, activeController);
    final isValid =
        selection.baseOffset == normalized.baseOffset &&
        selection.extentOffset == normalized.extentOffset;
    if (isValid) return;
    _logEditorPageEvent(
      event: 'warning',
      controller: activeController,
      selection: selection,
      extraContext:
          'warning=selection_invalid '
          'source=$source '
          'normalized=${formatEditorSelection(normalized)}',
    );
  }

  void _handleLessonContentFocusChanged() {
    if (!kEditorDebug || !_lessonContentControllerInitialized) return;
    _logEditorPageEvent(event: 'focus_changed');
    if (!mounted) return;
    setState(() {});
  }

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
    _resetPersistedLessonPreview();
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

  void _resetPersistedLessonPreview() {
    _persistedLessonPreviewRequestId += 1;
    _persistedLessonPreviewLoading = false;
    _persistedLessonPreviewError = null;
    _persistedLessonPreviewSnapshot = null;
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
    _lessonContentLoadError = errorMessage;
    _resetLessonPreviewHydrationValues(bumpRevision: bumpHydrationRevision);
    _lessonPreviewMode = false;
    _lessonPreviewSource = _LessonPreviewSource.live;
    _resetPersistedLessonPreview();
    _lessonEditorBootPhase = phase;
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

  int _editorDocumentExtent([quill.QuillController? controller]) {
    return max((controller ?? _lessonContentController).document.length - 1, 0);
  }

  _EditorSessionToken? _captureEditorToken() {
    final lessonId = _editorSession.lessonId;
    final selectedLessonId = _selectedLessonId;
    if (lessonId == null || selectedLessonId == null) return null;
    return _EditorSessionToken(
      sessionId: _editorSession.sessionId,
      lessonId: lessonId,
      selectedLessonId: selectedLessonId,
    );
  }

  bool _isEditorTokenValid(_EditorSessionToken? token) {
    if (token == null) return false;
    return token.sessionId == _editorSession.sessionId &&
        token.lessonId == _editorSession.lessonId &&
        token.selectedLessonId == _selectedLessonId;
  }

  void _handleObservedControllerChange(
    quill.QuillController controller,
    quill.DocChange event,
  ) {
    if (!identical(controller, _lessonContentController)) return;
    if (event.source != quill.ChangeSource.local) return;
    if (event.change.isEmpty) return;

    final selection = controller.selection;
    final normalizedSelection = _clampEditorSelection(selection, controller);

    if (normalizedSelection.start >= 0 && normalizedSelection.end >= 0) {
      _lastLessonSelection = normalizedSelection;
    }
    final shouldRefreshLivePreview =
        _lessonPreviewMode && _lessonPreviewSource == _LessonPreviewSource.live;
    if (!_lessonContentDirty) {
      _markLessonContentDirty(refreshPreview: shouldRefreshLivePreview);
    } else if (shouldRefreshLivePreview && mounted) {
      setState(() {});
    }

    if (kEditorDebug) {
      _logEditorPageEvent(
        event: 'document_changed',
        controller: controller,
        selection: selection,
        extraContext: 'source=${event.source.name}',
      );
    }
  }

  int _clampEditorOffset(int offset, [quill.QuillController? controller]) {
    return min(max(offset, 0), _editorDocumentExtent(controller));
  }

  TextSelection _clampEditorSelection(
    TextSelection selection, [
    quill.QuillController? controller,
  ]) {
    final activeController = controller ?? _lessonContentController;
    return clampQuillSelection(activeController, selection);
  }

  void _attachControllerListener() {
    _detachControllerListener();
    _controllerChangesSubscription = _lessonContentController.changes.listen((
      event,
    ) {
      _handleObservedControllerChange(_lessonContentController, event);
    });
    _controllerListener = () {
      final selection = _lessonContentController.selection;
      if (selection.start < 0 || selection.end < 0) return;
      final normalized = _clampEditorSelection(selection);
      final previousSelection = _lastLessonSelection;
      if (previousSelection != null &&
          previousSelection.baseOffset == normalized.baseOffset &&
          previousSelection.extentOffset == normalized.extentOffset) {
        return;
      }
      _lastLessonSelection = normalized;
    };
    _lessonContentController.addListener(_controllerListener!);
  }

  void _detachControllerListener() {
    _controllerChangesSubscription?.cancel();
    _controllerChangesSubscription = null;
    final listener = _controllerListener;
    if (listener != null && _lessonContentControllerInitialized) {
      _lessonContentController.removeListener(listener);
      _controllerListener = null;
      return;
    }
    _controllerListener = null;
  }

  bool _canRequestLessonEditorFocus() {
    return mounted &&
        !_lessonPreviewMode &&
        _isSelectedLessonDocumentReady() &&
        _lessonEditorBootPhase == _LessonEditorBootPhase.fullyStable &&
        _selectedLessonId != null;
  }

  void _ensureLessonEditorFocus({String reason = 'mutation'}) {
    if (!_canRequestLessonEditorFocus()) return;
    if (_lessonContentFocusNode.hasFocus ||
        _lessonEditorFocusRestoreScheduled) {
      return;
    }
    _lessonEditorFocusRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lessonEditorFocusRestoreScheduled = false;
      if (!_canRequestLessonEditorFocus()) return;
      if (_lessonContentFocusNode.hasFocus ||
          !_lessonContentFocusNode.canRequestFocus) {
        return;
      }
      _logEditorPageEvent(
        event: 'warning',
        controller: _lessonContentController,
        extraContext:
            'warning=editor_not_focused action=request_focus reason=$reason',
      );
      _lessonContentFocusNode.requestFocus();
    });
  }

  void _markLessonContentDirty({bool refreshPreview = false}) {
    if (!_isSelectedLessonDocumentReady()) {
      return;
    }
    if (!mounted) {
      _lessonContentDirty = true;
      return;
    }
    if (!_lessonContentDirty || refreshPreview) {
      setState(() {
        _lessonContentDirty = true;
      });
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

  void _runEditorMutation(
    void Function(quill.QuillController controller) mutation, {
    bool requestFocus = false,
    bool refreshPage = false,
  }) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (!_isSelectedLessonDocumentReady()) {
      if (mounted && context.mounted) {
        showSnack(context, 'Lektionsinnehållet är inte färdigladdat.');
      }
      return;
    }
    mutation(_lessonContentController);
    _snapshotLessonSelection();
    if (requestFocus) {
      _ensureLessonEditorFocus();
    }
    if (refreshPage && mounted) {
      setState(() {});
    }
  }

  ({int start, int length}) _currentEditorReplacementRange() {
    final selection = _clampEditorSelection(_lessonContentController.selection);
    final start = min(selection.start, selection.end);
    final end = max(selection.start, selection.end);
    return (start: start, length: end - start);
  }

  void _replaceEditorTextLocally(
    quill.QuillController controller, {
    required int index,
    required int length,
    required Object data,
    required TextSelection selection,
  }) {
    controller.replaceText(
      index,
      length,
      data,
      _clampEditorSelection(selection, controller),
      ignoreFocus: false,
      shouldNotifyListeners: true,
    );
  }

  void _formatEditorRangeSelection(
    quill.QuillController controller, {
    required int start,
    required int length,
    required quill.Attribute attribute,
  }) {
    if (length <= 0) return;
    controller.formatText(
      start,
      length,
      attribute,
      shouldNotifyListeners: true,
    );
  }

  void _setEditorSelectionLocally(
    quill.QuillController controller, {
    required TextSelection selection,
    quill.ChangeSource source = quill.ChangeSource.local,
  }) {
    final normalizedSelection = _clampEditorSelection(selection, controller);
    _warnIfSelectionInvalid(
      selection,
      controller: controller,
      source: 'selection_request',
    );
    controller.updateSelection(normalizedSelection, source);
  }

  void _handleInlineFormatToolbarPressed() {
    _snapshotLessonSelection();
    _ensureLessonEditorFocus(reason: 'toolbar_format');
  }

  void _insertTextViaTestBridge(String text) {
    final replacementRange = _currentEditorReplacementRange();
    _runEditorMutation((controller) {
      _replaceEditorTextLocally(
        controller,
        index: replacementRange.start,
        length: replacementRange.length,
        data: text,
        selection: TextSelection.collapsed(
          offset: replacementRange.start + text.length,
        ),
      );
    }, requestFocus: true);
  }

  void _backspaceViaTestBridge() {
    final replacementRange = _currentEditorReplacementRange();
    if (replacementRange.length > 0) {
      _deleteSelectionViaTestBridge();
      return;
    }
    if (replacementRange.start <= 0) return;

    final deleteOffset = replacementRange.start - 1;
    _runEditorMutation((controller) {
      _replaceEditorTextLocally(
        controller,
        index: deleteOffset,
        length: 1,
        data: '',
        selection: TextSelection.collapsed(offset: deleteOffset),
      );
    }, requestFocus: true);
  }

  void _deleteSelectionViaTestBridge() {
    final replacementRange = _currentEditorReplacementRange();
    if (replacementRange.length <= 0) return;

    _runEditorMutation((controller) {
      _replaceEditorTextLocally(
        controller,
        index: replacementRange.start,
        length: replacementRange.length,
        data: '',
        selection: TextSelection.collapsed(offset: replacementRange.start),
      );
    }, requestFocus: true);
  }

  void _setEditorCursorViaTestBridge(int offset) {
    _runEditorMutation(
      (controller) {
        _setEditorSelectionLocally(
          controller,
          selection: TextSelection.collapsed(
            offset: _clampEditorOffset(offset),
          ),
        );
      },
      requestFocus: true,
      refreshPage: true,
    );
  }

  void _setEditorSelectionViaTestBridge(int start, int end) {
    _runEditorMutation(
      (controller) {
        _setEditorSelectionLocally(
          controller,
          selection: TextSelection(
            baseOffset: _clampEditorOffset(start),
            extentOffset: _clampEditorOffset(end),
          ),
        );
      },
      requestFocus: true,
      refreshPage: true,
    );
  }

  int _getEditorCursorViaTestBridge() {
    return _clampEditorOffset(_lessonContentController.selection.baseOffset);
  }

  String _getEditorDocumentViaTestBridge() {
    return _lessonContentController.document.toPlainText();
  }

  int _getEditorSelectionStartViaTestBridge() {
    return _clampEditorOffset(_lessonContentController.selection.start);
  }

  int _getEditorSelectionEndViaTestBridge() {
    return _clampEditorOffset(_lessonContentController.selection.end);
  }

  int _getEditorControllerIdentityViaTestBridge() {
    return identityHashCode(_lessonContentController);
  }

  int _getEditorControllerGenerationViaTestBridge() {
    return _lessonContentControllerGeneration;
  }

  void _setPreviewModeViaTestBridge(bool enabled) {
    unawaited(_setLessonPreviewMode(enabled));
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
      if (!mounted) {
        _lessonPreviewMode = false;
        _lessonPreviewSource = _LessonPreviewSource.live;
        _resetPersistedLessonPreview();
        return;
      }
      setState(() {
        _lessonPreviewMode = false;
        _lessonPreviewSource = _LessonPreviewSource.live;
        _resetPersistedLessonPreview();
      });
      _ensureLessonEditorFocus(reason: 'preview_mode_disabled');
      return;
    }

    if (!_isSelectedLessonDocumentReady()) {
      return;
    }
    final lessonId = _selectedLessonId;
    final courseId = _selectedCourseId;
    if (lessonId == null || courseId == null) {
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
    if (_lessonPreviewMode &&
        _lessonPreviewSource == _LessonPreviewSource.live) {
      return;
    }

    if (_lessonContentFocusNode.hasFocus) {
      _lessonContentFocusNode.unfocus();
    }
    if (!mounted) {
      _lessonPreviewMode = true;
      _lessonPreviewSource = _LessonPreviewSource.live;
      _resetPersistedLessonPreview();
      return;
    }
    setState(() {
      _lessonPreviewMode = true;
      _lessonPreviewSource = _LessonPreviewSource.live;
      _resetPersistedLessonPreview();
    });
  }

  Future<void> _setLessonPreviewSource(_LessonPreviewSource source) async {
    if (!_lessonPreviewMode) return;
    final lessonId = _selectedLessonId;
    final courseId = _selectedCourseId;
    if (lessonId == null || courseId == null) {
      return;
    }

    if (!mounted) {
      _lessonPreviewSource = source;
    } else if (_lessonPreviewSource != source) {
      setState(() {
        _lessonPreviewSource = source;
      });
    }

    if (source != _LessonPreviewSource.saved) {
      return;
    }

    if (_persistedLessonPreviewLoading ||
        _currentPersistedLessonPreviewSnapshot() != null) {
      return;
    }

    await _loadPersistedLessonPreview(courseId: courseId, lessonId: lessonId);
  }

  Future<void> _loadPersistedLessonPreview({
    required String courseId,
    required String lessonId,
  }) async {
    final requestId = ++_persistedLessonPreviewRequestId;
    if (!mounted) {
      _persistedLessonPreviewLoading = true;
      _persistedLessonPreviewError = null;
      _persistedLessonPreviewSnapshot = null;
      return;
    }
    setState(() {
      _persistedLessonPreviewLoading = true;
      _persistedLessonPreviewError = null;
      _persistedLessonPreviewSnapshot = null;
    });

    try {
      final snapshot = await _readPersistedLessonPreview(
        courseId: courseId,
        lessonId: lessonId,
      );
      if (!mounted ||
          _isStaleRequest(
            requestId: requestId,
            currentId: _persistedLessonPreviewRequestId,
            courseId: courseId,
            lessonId: lessonId,
          )) {
        return;
      }
      setState(() {
        _persistedLessonPreviewSnapshot = snapshot;
        _persistedLessonPreviewLoading = false;
        _persistedLessonPreviewError = null;
      });
    } catch (error, stackTrace) {
      if (!mounted ||
          _isStaleRequest(
            requestId: requestId,
            currentId: _persistedLessonPreviewRequestId,
            courseId: courseId,
            lessonId: lessonId,
          )) {
        return;
      }
      final message = AppFailure.from(error, stackTrace).message.trim();
      setState(() {
        _persistedLessonPreviewSnapshot = null;
        _persistedLessonPreviewLoading = false;
        _persistedLessonPreviewError = message.isEmpty
            ? 'Kunde inte läsa sparad förhandsgranskning.'
            : 'Kunde inte läsa sparad förhandsgranskning: $message';
      });
    }
  }

  bool _matchesCurrentLessonRequest({
    required String lessonId,
    required int requestId,
  }) {
    if (!mounted) return false;
    return _selectedLessonId == lessonId &&
        _lessonContentRequestId == requestId;
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

  void _resetCoverState({bool clearPreview = false}) {
    _coverPollTimer?.cancel();
    _coverPollTimer = null;
    _coverPollAttempts = 0;
    _coverPollStartedAt = null;
    _coverPollRequestId = 0;
    _coverActionRequestId += 1;
    _coverActionCourseId = null;
    _updatingCourseCover = false;
    _coverPipelineMediaId = null;
    _coverPipelineState = null;
    _coverPipelineError = null;
    if (clearPreview) {
      _courseCoverPath = null;
    }
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

  void _resetCourseContext({bool clearLists = false}) {
    _lessonReorderDebounceTimer?.cancel();
    _lessonReorderDebounceTimer = null;
    _resetCoverState(clearPreview: true);
    _lessonsLoadError = null;
    _mediaLoadError = null;
    _mediaStatus = null;
    _downloadStatus = null;
    _courseMetaLoading = false;
    _lessonsLoading = false;
    _mediaLoading = false;
    _lessonsNeedingRefresh.clear();
    if (clearLists) {
      _lessons = <LessonStudio>[];
      _setSelectedLessonId(null);
      _lessonMedia = <StudioLessonMediaItem>[];
      _lessonMediaLessonId = null;
      _resetLessonEditorBootValues(phase: _LessonEditorBootPhase.booting);
      _replaceLessonDocument(quill.Document(), resetDirty: true);
      _lessonTitleCtrl
        ..removeListener(_handleLessonTitleChanged)
        ..text = ''
        ..addListener(_handleLessonTitleChanged);
      _lastSavedLessonTitle = '';
      _lastSavedLessonMarkdown = '';
      _lessonContentDirty = false;
    }
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
    _lessonContentFocusNodeHandle = FocusNode();
    _lessonContentFocusNodeHandle.addListener(_handleLessonContentFocusChanged);
    _lessonEditorScrollControllerHandle = ScrollController();
    _previewHydrationController = LessonMediaPreviewHydrationController(
      timeout: _lessonPreviewHydrationTimeout,
    );
    _studioRepo = widget.studioRepository ?? ref.read(studioRepositoryProvider);
    _lessonTitleCtrl.addListener(_handleLessonTitleChanged);
    _replaceLessonDocument(quill.Document());
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
    _coursePriceCtrl.dispose();
    if (_lessonContentControllerInitialized) {
      _detachControllerListener();
      _lessonContentController.dispose();
    }
    _lessonContentFocusNodeHandle.removeListener(
      _handleLessonContentFocusChanged,
    );
    _lessonContentFocusNodeHandle.dispose();
    _lessonEditorScrollControllerHandle.dispose();
    _panelScrollController.dispose();
    _lessonTitleCtrl.dispose();
    _coverPollTimer?.cancel();
    _lessonMediaPollTimer?.cancel();
    _lessonReorderDebounceTimer?.cancel();
    _lessonEditorTestIdRetryTimer?.cancel();
    _lessonEditorSemanticsHandle?.dispose();
    _previewHydrationController.dispose();
    editor_test_bridge.unregisterAveliEditorTestBridge();
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
      if (allowed) {
        myCourses = await _studioRepo.myCourses();
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
        _selectedCourseId = selected;
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
      final course = await _studioRepo.fetchCourseMeta(courseId);
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
      final priceOre = course.priceAmountCents;
      _coursePriceCtrl.text = priceOre == null
          ? ''
          : formatSekInputFromOre(priceOre);
      if (mounted) {
        setState(() {
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
      _replaceLessonDocument(quill.Document(), resetDirty: true);
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
      if (_selectedLessonId != null) {
        await _bootSelectedLesson();
      } else if (mounted) {
        setState(() {
          _lessonMedia = <StudioLessonMediaItem>[];
          _lessonMediaLessonId = null;
          _resetLessonEditorBootValues(phase: _LessonEditorBootPhase.booting);
        });
        _replaceLessonDocument(quill.Document(), resetDirty: true);
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
      _replaceLessonDocument(quill.Document(), resetDirty: true);
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
    for (final course in _courses) {
      final id = course.id;
      if (id.isEmpty) continue;
      final title = course.title;
      items.add(DropdownMenuItem<String>(value: id, child: Text(title)));
    }
    return items;
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

  void _replaceLessonDocument(
    quill.Document document, {
    bool resetDirty = true,
  }) {
    final hadController = _lessonContentControllerInitialized;
    final previousControllerIdentity = hadController
        ? _controllerIdentity(_lessonContentController)
        : null;
    final previousSessionId = hadController ? _editorSession.sessionId : null;
    final previousLessonId = hadController ? _editorSession.lessonId : null;
    final warnOnUnexpectedReplacement =
        hadController &&
        previousLessonId == _selectedLessonId &&
        _lessonEditorBootPhase == _LessonEditorBootPhase.fullyStable;

    if (hadController) {
      _detachControllerListener();
      _lessonContentController.dispose();
    }
    final controller = EditorOperationQuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    final sessionId = _uuid.v4();
    _editorSession = EditorSession(
      sessionId: sessionId,
      lessonId: _selectedLessonId,
      controller: controller,
      focusNode: _lessonContentFocusNodeHandle,
      scrollController: _lessonEditorScrollControllerHandle,
    );
    _lessonContentControllerInitialized = true;
    _lessonContentControllerGeneration += 1;
    _attachControllerListener();
    _syncLessonEditorTestBridge();
    _lastLessonSelection = _clampEditorSelection(
      controller.selection,
      controller,
    );
    if (warnOnUnexpectedReplacement && previousControllerIdentity != null) {
      logEditor(
        'event=warning '
        'warning=controller_replaced_unexpectedly '
        'previous_controller=$previousControllerIdentity '
        'next_controller=${_controllerIdentity(controller)} '
        'previous_session=${previousSessionId ?? 'null'} '
        'next_session=$sessionId '
        'lesson=${_editorLessonIdValue(previousLessonId)} '
        'generation=$_lessonContentControllerGeneration',
      );
    }
    _logEditorPageEvent(
      event: 'session_started',
      controller: controller,
      sessionId: sessionId,
      lessonId: _selectedLessonId,
      selection: controller.selection,
      extraContext: 'generation=$_lessonContentControllerGeneration',
    );
    if (resetDirty) {
      _lessonContentDirty = false;
    }
  }

  void _syncLessonEditorTestBridge() {
    editor_test_bridge.registerAveliEditorTestBridge(
      insertText: _insertTextViaTestBridge,
      backspace: _backspaceViaTestBridge,
      deleteSelection: _deleteSelectionViaTestBridge,
      setCursor: _setEditorCursorViaTestBridge,
      setSelection: _setEditorSelectionViaTestBridge,
      getCursor: _getEditorCursorViaTestBridge,
      getDocument: _getEditorDocumentViaTestBridge,
      getSelectionStart: _getEditorSelectionStartViaTestBridge,
      getSelectionEnd: _getEditorSelectionEndViaTestBridge,
      getControllerIdentity: _getEditorControllerIdentityViaTestBridge,
      getControllerGeneration: _getEditorControllerGenerationViaTestBridge,
      setPreviewMode: _setPreviewModeViaTestBridge,
    );
  }

  void _snapshotLessonSelection() {
    final selection = _lessonContentController.selection;
    if (selection.start >= 0 && selection.end >= 0) {
      _lastLessonSelection = _clampEditorSelection(selection);
    }
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

  String _prepareLessonMarkdownForEditing(String markdown) {
    return markdown_to_editor.canonicalizeMarkdownForEditor(
      markdown: markdown,
      apiFilesPathToStudioMediaUrl: const <String, String>{},
      lessonMediaDocumentLabelsById:
          _lessonMediaDocumentLabelsByIdForSelectedLesson(),
    );
  }

  quill.Document _documentFromLessonMarkdown(String markdown) {
    return markdown_to_editor.markdownToEditorDocument(
      markdown: markdown,
      apiFilesPathToStudioMediaUrl: const <String, String>{},
      lessonMediaDocumentLabelsById:
          _lessonMediaDocumentLabelsByIdForSelectedLesson(),
    );
  }

  Map<String, String> _lessonMediaDocumentLabelsByIdForSelectedLesson() {
    final lessonId = _selectedLessonId;
    if (lessonId == null) return const <String, String>{};
    if (_lessonMediaLessonId != lessonId) return const <String, String>{};
    if (_lessonMedia.isEmpty) return const <String, String>{};

    final labels = <String, String>{};
    for (final media in _lessonMedia) {
      labels[media.lessonMediaId] = _fileNameFromMedia(media);
    }
    return labels;
  }

  LessonMediaItem _lessonMediaItemFromStudioMedia(StudioLessonMediaItem media) {
    return LessonMediaItem(
      id: media.lessonMediaId,
      lessonId: media.lessonId,
      mediaAssetId: media.mediaAssetId,
      position: media.position,
      mediaType: media.mediaType,
      state: media.state,
      media: media.media,
    );
  }

  List<LessonMediaItem> _lessonMediaItemsFromStudioMedia(
    Iterable<StudioLessonMediaItem> mediaItems,
  ) {
    return mediaItems
        .map(_lessonMediaItemFromStudioMedia)
        .toList(growable: false);
  }

  Future<_PersistedLessonPreviewSnapshot> _readPersistedLessonPreview({
    required String courseId,
    required String lessonId,
  }) async {
    final content = await _studioRepo.readLessonContent(lessonId);
    if (content.lessonId != lessonId) {
      throw StateError('Lektionsinnehållet hör till fel lektion.');
    }

    final lessonMediaIds = _lessonMediaIdsFromContent(content);
    final placements = await _studioRepo.fetchLessonMediaPlacements(
      lessonMediaIds,
    );
    final course = await _studioRepo.fetchCourseMeta(courseId);
    final lesson = _lessonById(lessonId);
    final title = lesson?.lessonTitle.trim() ?? '';
    return _PersistedLessonPreviewSnapshot(
      lessonId: lessonId,
      courseId: courseId,
      title: title.isEmpty ? 'Lektion' : title,
      markdown: content.contentMarkdown,
      lessonMedia: _lessonMediaItemsFromStudioMedia(placements),
      coverResolvedUrl: course.cover?.resolvedUrl,
    );
  }

  _PersistedLessonPreviewSnapshot? _currentPersistedLessonPreviewSnapshot() {
    final snapshot = _persistedLessonPreviewSnapshot;
    final selectedLessonId = _selectedLessonId;
    final selectedCourseId = _selectedCourseId;
    if (snapshot == null ||
        selectedLessonId == null ||
        selectedCourseId == null) {
      return null;
    }
    if (snapshot.lessonId != selectedLessonId ||
        snapshot.courseId != selectedCourseId) {
      return null;
    }
    return snapshot;
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

  String _serializeLessonMarkdownFromController(
    quill.QuillController controller,
  ) {
    return editor_to_markdown.editorDeltaToCanonicalMarkdown(
      delta: controller.document.toDelta(),
    );
  }

  Set<String> _embeddedLessonMediaIdsFromController(
    quill.QuillController controller,
  ) {
    final ids = <String>{};
    for (final operation in controller.document.toDelta().toList()) {
      if (!operation.isInsert) {
        continue;
      }
      final value = operation.value;
      if (value is quill.Embeddable) {
        final lessonMediaId = lesson_pipeline.lessonMediaIdFromEmbedValue(
          value.data,
        );
        if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
          ids.add(lessonMediaId);
        }
        continue;
      }
      if (value is! String) continue;
      final attributes = operation.attributes;
      if (attributes == null) continue;
      final rawLink = attributes[quill.Attribute.link.key];
      if (rawLink is! String) continue;
      final lessonMediaId = lesson_pipeline.lessonMediaIdFromDocumentLinkUrl(
        rawLink,
      );
      if (lessonMediaId != null && lessonMediaId.isNotEmpty) {
        ids.add(lessonMediaId);
      }
    }

    return ids;
  }

  Set<String> _currentLessonEmbeddedMediaIds() {
    if (_lessonContentControllerInitialized) {
      return _embeddedLessonMediaIdsFromController(_lessonContentController);
    }
    return lesson_pipeline.extractLessonEmbeddedMediaIds(
      _lastSavedLessonMarkdown,
    );
  }

  bool _lessonAlreadyContainsMediaId(String lessonMediaId) {
    if (lessonMediaId.isEmpty) return false;
    return _currentLessonEmbeddedMediaIds().contains(lessonMediaId);
  }

  Future<void> _launchLessonPreviewUrl(String url) async {
    await _launchLessonEditorUrl(url);
  }

  String? _canonicalLessonMediaUrl(StudioLessonMediaItem media) {
    final resolvedUrl = media.media?.resolvedUrl?.trim();
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }
    return resolvedUrl;
  }

  Future<String?> _resolveLessonMediaDeliveryUrl(String lessonMediaId) async {
    if (lessonMediaId.isEmpty) {
      return null;
    }

    for (final media in _lessonMedia) {
      if (media.lessonMediaId != lessonMediaId) {
        continue;
      }
      return _canonicalLessonMediaUrl(media);
    }
    return null;
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

  Future<String?> _resolveLessonEditorLaunchUrl(String rawUrl) async {
    final lessonMediaId = lesson_pipeline.lessonMediaIdFromDocumentLinkUrl(
      rawUrl,
    );
    if (lessonMediaId == null || lessonMediaId.isEmpty) {
      final uri = Uri.tryParse(rawUrl);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return null;
      }
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return null;
      }
      return uri.toString();
    }

    return _resolveLessonMediaDeliveryUrl(lessonMediaId);
  }

  Future<void> _launchLessonEditorUrl(String url) async {
    final rawUrl = url;
    if (rawUrl.isEmpty) return;

    final resolved = await _resolveLessonEditorLaunchUrl(rawUrl);
    if (resolved == null) {
      if (mounted && context.mounted) {
        showSnack(context, 'Kunde inte öppna länken.');
      }
      return;
    }

    final opened = await launchUrlString(
      resolved,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted && context.mounted) {
      showSnack(context, 'Kunde inte öppna länken.');
    }
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
    required String storedMarkdown,
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
    final prepared = _prepareLessonMarkdownForEditing(storedMarkdown);
    if (!mounted ||
        _isStaleRequest(
          requestId: requestId,
          currentId: _lessonContentRequestId,
          courseId: _selectedCourseId,
          lessonId: lessonId,
        )) {
      return;
    }
    final initialHydrationIds = lesson_pipeline.extractLessonEmbeddedMediaIds(
      prepared,
    );
    final document = _documentFromLessonMarkdown(prepared);

    if (kDebugMode) {
      _traceLessonString('load.stored_markdown', storedMarkdown);
      _traceLessonString('load.prepared_markdown', prepared);
      _traceLessonString('load.document_plain_text', document.toPlainText());
    }

    _setLessonTitleFieldValue(storedTitle);
    _replaceLessonDocument(document);
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
      _lastSavedLessonMarkdown = storedMarkdown;
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
      storedMarkdown: content.contentMarkdown,
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
      storedMarkdown: _lastSavedLessonMarkdown,
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
    final uiPlainText = _lessonContentController.document.toPlainText();
    late final String markdown;
    late final String rawMarkdown;
    try {
      markdown = _serializeLessonMarkdownFromController(
        _lessonContentController,
      );
      rawMarkdown = markdown;
    } catch (error, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte spara lektion', error, stackTrace);
      return false;
    }

    if (kDebugMode) {
      debugPrint(
        '[LessonTrace] save.trigger=${showSuccessSnack ? 'manual' : 'auto'} '
        'dirty=$_lessonContentDirty saving=$_lessonContentSaving',
      );
      _traceLessonString('ui.plain_text', uiPlainText);
      _traceLessonString('save.payload.content_markdown', markdown);
      _traceLessonString('save.payload.raw_markdown', rawMarkdown);
      _traceLessonString('state.last_saved_markdown', _lastSavedLessonMarkdown);
      debugPrint(
        '[LessonTrace] compare.payload_vs_last_saved '
        'equal=${markdown == _lastSavedLessonMarkdown}',
      );
      debugPrint(
        '[LessonEditor] saving lesson=$lessonId course=$courseId '
        'delta_ops=${_lessonContentController.document.toDelta().length} '
        'rawMarkdownLen=${rawMarkdown.length} normalizedLen=${markdown.length}',
      );
      debugPrint(
        '[LessonEditor] payload.content_markdown (normalized) preview: '
        '${markdown.length > 400 ? '${markdown.substring(0, 400)}…' : markdown}',
      );
    }

    setState(() => _lessonContentSaving = true);
    final token = _captureEditorToken();
    try {
      StudioLessonContentWriteResult? updatedContent;
      if (markdown != _lastSavedLessonMarkdown) {
        updatedContent = await _studioRepo.updateLessonContent(
          lessonId,
          contentMarkdown: markdown,
          ifMatch: contentEtag,
        );
      }
      final updatedStructure = await _studioRepo.updateLessonStructure(
        lessonId,
        lessonTitle: title,
        position: _currentLessonPosition(),
      );

      if (!mounted || !_isEditorTokenValid(token)) return false;

      setState(() {
        _lessons = _lessons
            .map((lesson) => lesson.id == lessonId ? updatedStructure : lesson)
            .toList();
        if (updatedContent != null) {
          _lastSavedLessonMarkdown = updatedContent.contentMarkdown;
        }
        _lastSavedLessonTitle = title;
        if (updatedContent != null) {
          _lastSavedLessonContentEtag = updatedContent.etag;
        }
        _lessonContentDirty = false;
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
    final controller = _lessonContentController;

    final labelController = TextEditingController(text: 'Boka nu');
    final urlController = TextEditingController(text: 'aveliapp://');

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
                hintText: 'aveliapp://checkout?service_id=...',
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

    final selection = controller.selection;
    final baseOffset = selection.start;
    final extentOffset = selection.end;
    final length = extentOffset - baseOffset;

    _runEditorMutation((controller) {
      _replaceEditorTextLocally(
        controller,
        index: baseOffset,
        length: length,
        data: label,
        selection: TextSelection.collapsed(offset: baseOffset + label.length),
      );
      _formatEditorRangeSelection(
        controller,
        start: baseOffset,
        length: label.length,
        attribute: quill.LinkAttribute(url),
      );
      _setEditorSelectionLocally(
        controller,
        selection: TextSelection.collapsed(offset: baseOffset + label.length),
      );
    }, requestFocus: true);
  }

  Widget _buildLessonContentEditor(
    BuildContext context, {
    bool expandEditor = false,
    double editorHeight = 320,
  }) {
    final controller = _lessonContentController;

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

    final toolbarConfig = quill.QuillSimpleToolbarConfig(
      multiRowsDisplay: false,
      showDividers: false,
      showFontFamily: false,
      showFontSize: false,
      showBoldButton: true,
      showItalicButton: true,
      showUnderLineButton: true,
      showStrikeThrough: false,
      showColorButton: false,
      showBackgroundColorButton: false,
      showClearFormat: true,
      showHeaderStyle: true,
      showListNumbers: true,
      showListBullets: true,
      showListCheck: false,
      showCodeBlock: false,
      showQuote: false,
      showIndent: false,
      showLink: false,
      showUndo: true,
      showRedo: true,
      showSubscript: false,
      showSuperscript: false,
      showSmallButton: false,
      showInlineCode: false,
      showClipboardCopy: false,
      showClipboardPaste: false,
      showClipboardCut: false,
      showSearchButton: false,
      buttonOptions: quill.QuillSimpleToolbarButtonOptions(
        bold: quill.QuillToolbarToggleStyleButtonOptions(
          afterButtonPressed: _handleInlineFormatToolbarPressed,
        ),
        italic: quill.QuillToolbarToggleStyleButtonOptions(
          afterButtonPressed: _handleInlineFormatToolbarPressed,
        ),
        fontFamily: const quill.QuillToolbarFontFamilyButtonOptions(
          items: _editorFontOptions,
          renderFontFamilies: true,
          overrideTooltipByFontFamily: true,
          defaultDisplayText: 'Typsnitt',
        ),
      ),
      customButtons: [
        quill.QuillToolbarCustomButtonOptions(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          tooltip: 'Ladda upp dokument (PDF)',
          onPressed: () => _handleMediaToolbarUpload(_UploadKind.pdf),
        ),
        quill.QuillToolbarCustomButtonOptions(
          icon: const Icon(Icons.auto_fix_high_rounded),
          tooltip: 'Infoga magic-link-knapp',
          onPressed: _insertMagicLink,
        ),
      ],
    );

    _scheduleLessonEditorTestIdSync();
    final editorSurface = Stack(
      children: [
        Container(
          key: const ValueKey<String>('lesson_editor_live_surface'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            color: Colors.white.withValues(alpha: 0.92),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              key: const ValueKey<String>(_lessonEditorTestId),
              child: _wrapLessonEditorForWebTestIds(
                KeyedSubtree(
                  key: ValueKey<int>(_controllerIdentity(controller)),
                  child: RepaintBoundary(
                    child: quill.QuillEditor.basic(
                      controller: controller,
                      focusNode: _lessonContentFocusNode,
                      scrollController: _lessonEditorScrollController,
                      config: quill.QuillEditorConfig(
                        minHeight: 280,
                        padding: const EdgeInsets.all(16),
                        placeholder:
                            'Skriv eller klistra in lektionsinnehåll...',
                        onKeyPressed: _handleLessonEditorKeyPressed,
                        onLaunchUrl: (url) =>
                            unawaited(_launchLessonEditorUrl(url)),
                        embedBuilders: [
                          ...FlutterQuillEmbeds.defaultEditorBuilders().where(
                            (builder) =>
                                builder.key != quill.BlockEmbed.videoType &&
                                builder.key != quill.BlockEmbed.imageType,
                          ),
                          _ImageEmbedBuilder(
                            hydrationListenable: _previewHydrationController,
                          ),
                          _VideoEmbedBuilder(
                            hydrationListenable: _previewHydrationController,
                          ),
                          _AudioEmbedBuilder(
                            hydrationListenable: _previewHydrationController,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (kEditorDebug)
          Positioned(
            top: 12,
            right: 12,
            child: EditorDebugOverlay(
              sessionId: _editorSession.sessionId,
              controllerIdentity: _controllerIdentity(controller),
              hasFocus: _lessonContentFocusNode.hasFocus,
              selection: controller.selection,
            ),
          ),
      ],
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
        TooltipVisibility(
          visible: false,
          child: quill.QuillSimpleToolbar(
            controller: controller,
            config: toolbarConfig,
          ),
        ),
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
    final snapshot = _currentPersistedLessonPreviewSnapshot();
    final previewTitle = snapshot?.title ?? 'Lektion';
    final previewError = _persistedLessonPreviewError;

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
          'Skrivskyddad förhandsgranskning med samma renderingspipeline som elevvyn.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        gap12,
        if (snapshot?.coverResolvedUrl case final coverUrl?)
          if (coverUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: double.infinity,
                height: 120,
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            gap12,
          ],
        Expanded(
          child: _persistedLessonPreviewLoading
              ? const Center(child: CircularProgressIndicator())
              : snapshot == null
              ? Center(
                  child: Text(
                    previewError ??
                        'Förhandsgranskningen behöver läsa sparat innehåll.',
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
                  child: LearnerLessonContentRenderer(
                    markdown: snapshot.markdown,
                    lessonMedia: snapshot.lessonMedia,
                    onLaunchUrl: (url) =>
                        unawaited(_launchLessonPreviewUrl(url)),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildActiveLessonPreviewMode(BuildContext context) {
    final theme = Theme.of(context);
    final isLivePreview = _lessonPreviewSource == _LessonPreviewSource.live;
    final snapshot = _currentPersistedLessonPreviewSnapshot();
    final liveLessonTitle = _lessonTitleCtrl.text.trim();
    final savedLessonTitle = snapshot?.title.trim() ?? '';
    final fallbackLessonTitle =
        _lessonById(_selectedLessonId)?.lessonTitle.trim() ?? '';
    final previewTitle = isLivePreview
        ? (liveLessonTitle.isNotEmpty
              ? liveLessonTitle
              : fallbackLessonTitle.isNotEmpty
              ? fallbackLessonTitle
              : 'Lektion')
        : (savedLessonTitle.isNotEmpty
              ? savedLessonTitle
              : fallbackLessonTitle.isNotEmpty
              ? fallbackLessonTitle
              : 'Lektion');
    final previewCoverUrl = isLivePreview
        ? (_courseCoverPath?.trim().isNotEmpty ?? false
              ? _courseCoverPath!.trim()
              : null)
        : snapshot?.coverResolvedUrl;
    final previewMedia = isLivePreview
        ? (_lessonMediaLessonId == _selectedLessonId
              ? _lessonMediaItemsFromStudioMedia(_lessonMedia)
              : const <LessonMediaItem>[])
        : snapshot?.lessonMedia ?? const <LessonMediaItem>[];
    String? previewMarkdown;
    String? previewError;

    if (isLivePreview) {
      try {
        previewMarkdown = _serializeLessonMarkdownFromController(
          _lessonContentController,
        );
      } catch (error, stackTrace) {
        final message = AppFailure.from(error, stackTrace).message.trim();
        previewError = message.isEmpty
            ? 'Kunde inte rendera live preview.'
            : 'Kunde inte rendera live preview: $message';
      }
    } else {
      previewMarkdown = snapshot?.markdown;
      previewError = _persistedLessonPreviewError;
    }

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
          isLivePreview
              ? 'Live preview av osparat lektionsinnehåll med samma renderingspipeline som elevvyn.'
              : 'Saved mirror av sparat backend-innehåll med samma renderingspipeline som elevvyn.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        gap12,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey<String>('lesson_preview_live_source_chip'),
              label: const Text('Live preview'),
              selected: isLivePreview,
              onSelected: (selected) {
                if (!selected || isLivePreview) return;
                unawaited(_setLessonPreviewSource(_LessonPreviewSource.live));
              },
            ),
            ChoiceChip(
              key: const ValueKey<String>('lesson_preview_saved_source_chip'),
              label: const Text('Saved mirror'),
              selected: !isLivePreview,
              onSelected: (selected) {
                if (!selected || !isLivePreview) return;
                unawaited(_setLessonPreviewSource(_LessonPreviewSource.saved));
              },
            ),
          ],
        ),
        gap12,
        if (previewCoverUrl case final coverUrl?)
          if (coverUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: double.infinity,
                height: 120,
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            gap12,
          ],
        Expanded(
          child: !isLivePreview && _persistedLessonPreviewLoading
              ? const Center(child: CircularProgressIndicator())
              : previewMarkdown == null
              ? Center(
                  child: Text(
                    previewError ??
                        (isLivePreview
                            ? 'Live preview kunde inte byggas från editorn.'
                            : 'Saved mirror behöver läsa sparat innehåll.'),
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
                  child: LearnerLessonContentRenderer(
                    markdown: previewMarkdown,
                    lessonMedia: previewMedia,
                    onLaunchUrl: (url) =>
                        unawaited(_launchLessonPreviewUrl(url)),
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
                ? Center(
                    child: Text(
                      'Välj en lektion för att redigera innehållet.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  )
                : !isDocumentReady
                ? _buildLessonEditorBootShell(context)
                : _lessonPreviewMode
                ? _buildActiveLessonPreviewMode(context)
                : _buildLessonContentEditor(context, expandEditor: true),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLessonEditorSurface(
    BuildContext context, {
    required double editorHeight,
  }) {
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
        child: _buildActiveLessonPreviewMode(context),
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
            ] else if (hasCover) ...[
              Chip(
                label: const Text('Aktiv kursbild'),
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  Icons.star,
                  color: theme.colorScheme.primary,
                  size: 16,
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
    // Remember cursor position before we open pickers and start uploads,
    // so auto-insert can happen where the user intended.
    _snapshotLessonSelection();
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
    _snapshotLessonSelection();
    final selectionBeforePicker = _lastLessonSelection;
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
          targetSelection: selectionBeforePicker,
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

  bool _insertImageIntoLesson({
    String? lessonMediaId,
    TextSelection? targetSelection,
  }) {
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
    _runEditorMutation((controller) {
      replaceSelectionWithBlockEmbed(
        controller: controller,
        embed: quill.BlockEmbed.image(
          lesson_pipeline.imageBlockEmbedValueFromLessonMedia(
            lessonMediaId: lessonMediaId,
          ),
        ),
        selection: targetSelection ?? controller.selection,
      );
    }, requestFocus: true);
    return true;
  }

  void _insertVideoIntoLesson(
    String embedValue, {
    TextSelection? targetSelection,
  }) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    _runEditorMutation((controller) {
      replaceSelectionWithBlockEmbed(
        controller: controller,
        embed: quill.BlockEmbed.video(embedValue),
        selection: targetSelection ?? controller.selection,
      );
    }, requestFocus: true);
  }

  void _insertAudioIntoLesson(
    lesson_pipeline.AudioBlockEmbed embed, {
    TextSelection? targetSelection,
  }) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    _runEditorMutation((controller) {
      replaceSelectionWithBlockEmbed(
        controller: controller,
        embed: embed,
        selection: targetSelection ?? controller.selection,
      );
    }, requestFocus: true);
  }

  KeyEventResult? _handleLessonEditorKeyPressed(
    KeyEvent event,
    quill.Node? node,
  ) {
    if (event is! KeyDownEvent) return null;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      final handled = _removePdfLinkLineAroundSelection(forward: false);
      return handled ? KeyEventResult.handled : null;
    }
    if (key == LogicalKeyboardKey.delete) {
      final handled = _removePdfLinkLineAroundSelection(forward: true);
      return handled ? KeyEventResult.handled : null;
    }
    return null;
  }

  bool _removePdfLinkLineAroundSelection({required bool forward}) {
    final controller = _lessonContentController;

    final selection = controller.selection;
    if (!selection.isCollapsed || selection.baseOffset < 0) return false;

    final plainText = controller.document.toPlainText();
    final range = findPdfLinkDeletionRange(
      plainText: plainText,
      cursorOffset: selection.baseOffset,
      forward: forward,
    );
    if (range == null || range.isCollapsed) return false;

    _runEditorMutation((controller) {
      _replaceEditorTextLocally(
        controller,
        index: range.start,
        length: range.end - range.start,
        data: '',
        selection: TextSelection.collapsed(offset: range.start),
      );
      _setEditorSelectionLocally(
        controller,
        selection: TextSelection.collapsed(
          offset: _clampEditorOffset(range.start),
        ),
      );
    });
    return true;
  }

  void _insertDocumentLinkIntoLesson({
    required String lessonMediaId,
    required String fileName,
    TextSelection? targetSelection,
  }) {
    if (!_requireEditModeForMutation()) {
      return;
    }
    final controller = _lessonContentController;

    final label = '📄 $fileName';
    final selection = resolveQuillInsertionSelection(
      controller,
      targetSelection ?? controller.selection,
    );

    final start = max(0, min(selection.start, selection.end));
    final end = max(0, max(selection.start, selection.end));
    final maxOffset = max(0, controller.document.length - 1);
    final baseIndex = min(start, maxOffset);
    final extentIndex = min(end, maxOffset);
    final deleteLength = max(0, extentIndex - baseIndex);

    _runEditorMutation((controller) {
      _replaceEditorTextLocally(
        controller,
        index: baseIndex,
        length: deleteLength,
        data: label,
        selection: TextSelection.collapsed(offset: baseIndex + label.length),
      );
      _formatEditorRangeSelection(
        controller,
        start: baseIndex,
        length: label.length,
        attribute: quill.LinkAttribute(
          lesson_pipeline.lessonMediaDocumentLinkUrl(lessonMediaId),
        ),
      );
      _replaceEditorTextLocally(
        controller,
        index: baseIndex + label.length,
        length: 0,
        data: '\n',
        selection: TextSelection.collapsed(
          offset: baseIndex + label.length + 1,
        ),
      );
      _setEditorSelectionLocally(
        controller,
        selection: TextSelection.collapsed(
          offset: baseIndex + label.length + 1,
        ),
      );
    }, requestFocus: true);
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
    _snapshotLessonSelection();
    if (_isImageMedia(media) || kind == 'image') {
      final inserted = _insertImageIntoLesson(
        lessonMediaId: lessonMediaId,
        targetSelection: _lastLessonSelection,
      );
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
      final fileName = _fileNameFromMedia(media);
      _insertDocumentLinkIntoLesson(
        lessonMediaId: lessonMediaId,
        fileName: fileName,
        targetSelection: _lastLessonSelection,
      );
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
      final videoEmbedValue = lesson_pipeline
          .videoBlockEmbedValueFromLessonMedia(lessonMediaId: lessonMediaId);
      _insertVideoIntoLesson(
        videoEmbedValue,
        targetSelection: _lastLessonSelection,
      );
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
    // Audio: inline player embed
    final audioEmbed = lesson_pipeline.AudioBlockEmbed.fromLessonMedia(
      lessonMediaId: lessonMediaId,
    );
    _insertAudioIntoLesson(audioEmbed, targetSelection: _lastLessonSelection);
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

    var contentChanged = false;
    _runEditorMutation((controller) {
      contentChanged = replaceLessonMediaEmbedsInPlace(
        controller: controller,
        fromLessonMediaId: fromId,
        toLessonMediaId: toId,
        replacementBuilder: (embed, _) {
          switch (embed.value.type) {
            case lesson_pipeline.AudioBlockEmbed.embedType:
              return lesson_pipeline.AudioBlockEmbed.fromLessonMedia(
                lessonMediaId: toId,
              );
            case quill.BlockEmbed.videoType:
              return quill.BlockEmbed.video(
                lesson_pipeline.videoBlockEmbedValueFromLessonMedia(
                  lessonMediaId: toId,
                ),
              );
            case quill.BlockEmbed.imageType:
              return quill.BlockEmbed.image(
                lesson_pipeline.imageBlockEmbedValueFromLessonMedia(
                  lessonMediaId: toId,
                ),
              );
            default:
              return null;
          }
        },
      );
    }, requestFocus: true);
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

  String _defaultDraftCourseSlug() {
    final suffix = _uuid.v4().replaceAll('-', '').substring(0, 8);
    return 'ny-kurs-$suffix';
  }

  Future<_CourseCreateInput?> _showCourseCreateDialog() async {
    return showDialog<_CourseCreateInput>(
      context: context,
      builder: (_) =>
          _CourseCreateDialog(defaultSlug: _defaultDraftCourseSlug()),
    );
  }

  Future<void> _promptCreateCourse() async {
    if (!_requireEditModeForMutation()) {
      return;
    }
    if (_creatingCourse) return;
    if (!await _maybeSaveLessonEdits()) return;
    if (!mounted) return;

    final input = await _showCourseCreateDialog();
    if (input == null || !mounted) return;

    setState(() => _creatingCourse = true);
    try {
      final created = await _studioRepo.createCourse(
        title: input.title,
        slug: input.slug,
        courseGroupId: _uuid.v4(),
        groupPosition: 0,
        priceAmountCents: input.priceAmountCents,
        dripEnabled: false,
        dripIntervalDays: null,
        coverMediaId: null,
      );
      final refreshedCourses = await _studioRepo.myCourses();
      final canonicalCourse =
          _courseById(created.id, refreshedCourses) ?? created;
      if (!mounted) return;
      setState(() {
        _resetCourseContext(clearLists: true);
        _courses = _adoptCourseById(refreshedCourses, canonicalCourse);
        _selectedCourseId = canonicalCourse.id;
        _courseTitleCtrl.text = canonicalCourse.title;
        _courseSlugCtrl.text = canonicalCourse.slug;
        final priceOre = canonicalCourse.priceAmountCents;
        _coursePriceCtrl.text = priceOre == null
            ? ''
            : formatSekInputFromOre(priceOre);
        _courseCoverPath = canonicalCourse.cover?.resolvedUrl;
      });
      ref.invalidate(myCoursesProvider);
      ref.invalidate(studioCoursesProvider);
      ref.invalidate(landing.popularCoursesProvider);
      ref.invalidate(coursesProvider);
      await _loadCourseMeta();
      await _loadLessons(preserveSelection: false);
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Kurs skapad.');
    } catch (e, stackTrace) {
      _showFriendlyErrorSnack('Kunde inte skapa kurs', e, stackTrace);
    } finally {
      if (mounted) setState(() => _creatingCourse = false);
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
    setState(() => _savingCourseMeta = true);
    try {
      final updated = await _studioRepo.updateCourse(courseId, patch);
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
      });
      ref.invalidate(myCoursesProvider);
      ref.invalidate(studioCoursesProvider);
      ref.invalidate(landing.popularCoursesProvider);
      ref.invalidate(coursesProvider);
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
      if (mounted) setState(() => _savingCourseMeta = false);
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
        _courseCoverPath = published.cover?.resolvedUrl;
      });
      ref.invalidate(myCoursesProvider);
      ref.invalidate(studioCoursesProvider);
      ref.invalidate(landing.popularCoursesProvider);
      ref.invalidate(coursesProvider);
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
                  title: 'Välj kurs',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: _creatingCourse || _lessonPreviewMode
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
                            _resetCourseContext(clearLists: true);
                            _selectedCourseId = value;
                          });
                          await _loadCourseMeta();
                          await _loadLessons(preserveSelection: false);
                          if (!mounted) return;
                          setState(() {});
                        },
                        decoration: const InputDecoration(
                          hintText: 'Välj kurs',
                        ),
                      ),
                      if (courseItems.isEmpty) ...[
                        gap8,
                        const Text(
                          'Inga kurser tillgängliga i monterad runtime.',
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
                              const SizedBox.shrink(),
                              _buildCourseCoverPicker(context),
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
                              if (!isWide && _selectedLessonId != null) ...[
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
                                                          _lessonPreviewMode
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
