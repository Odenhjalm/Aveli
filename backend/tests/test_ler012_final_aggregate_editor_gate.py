from __future__ import annotations

import json
import re
from collections.abc import Iterable
from pathlib import Path

from tools.lesson_editor_authority_audit import (
    assert_no_findings,
    dart_source_block,
    forbidden_regex_findings,
    forbidden_token_findings,
    missing_token_findings,
    python_decorated_function_block,
    read_repo_text,
)


REPO_ROOT = Path(__file__).resolve().parents[2]

REQUIRED_TASK_IDS = tuple(f"LER-{index:03d}" for index in range(1, 13))

EXPECTED_DEPENDENCIES = {
    "LER-001": [],
    "LER-002": ["LER-001"],
    "LER-003": ["LER-002"],
    "LER-004": ["LER-002"],
    "LER-005": ["LER-004"],
    "LER-006": ["LER-005"],
    "LER-007": ["LER-006"],
    "LER-008": ["LER-007"],
    "LER-009": ["LER-003", "LER-008"],
    "LER-010": ["LER-003", "LER-006", "LER-008"],
    "LER-011": ["LER-009", "LER-010"],
    "LER-012": ["LER-011"],
}

REQUIRED_CAPABILITIES = {
    "bold",
    "italic",
    "underline",
    "clear_formatting",
    "heading",
    "bullet_list",
    "ordered_list",
    "image",
    "audio",
    "video",
    "document",
    "magic_link_cta",
    "persisted_preview",
    "etag_concurrency",
}

FRONTEND_DOCUMENT_AUTHORITY_FORBIDDEN = (
    "serializeEditorDeltaToCanonicalMarkdown",
    "validateLessonMarkdownIntegrity",
    "editorDeltaToPassivePreviewMarkdown",
    "flutter_quill",
    "FlutterQuillEmbeds",
    "QuillController",
    "quill.Document",
    "EditorOperationQuillController",
    "editor_test_bridge",
    "markdown_to_editor",
    "editor_to_markdown",
    "markdown_quill",
    "markdown_widget",
    "content_markdown",
    "contentMarkdown",
    "!image(",
    "!audio(",
    "!video(",
    "!document(",
)

FRONTEND_DOCUMENT_AUTHORITY_FORBIDDEN_PATTERNS = (r"\bEditorSession\b",)

BACKEND_DOCUMENT_AUTHORITY_FORBIDDEN = (
    "lesson_markdown_validator",
    "validate_lesson_markdown",
    "lesson_content_utils",
    "subprocess",
    "Popen(",
    "markdown_quill",
    "flutter",
)

FRONTEND_MEDIA_AUTHORITY_FORBIDDEN = (
    "/api/lesson-media/previews",
    "/api/lesson-media/$lessonId",
    "ApiPaths.mediaPreviews",
    "mediaPreviews =",
    "resolved_preview_url",
    "storage_path",
    "signed_url",
    "preview_ready",
)

FRONTEND_MEDIA_AUTHORITY_PATHS = (
    "frontend/lib/api/api_paths.dart",
    "frontend/lib/api/api_client.dart",
    "frontend/lib/features/studio/data/studio_repository.dart",
    "frontend/lib/features/studio/data/studio_repository_lesson_media.dart",
    "frontend/lib/features/studio/presentation/course_editor_page.dart",
    "frontend/lib/features/studio/presentation/lesson_media_preview_cache.dart",
)

FORBIDDEN_DEPENDENCY_PATTERNS = (
    r"\bflutter_quill\b",
    r"\bflutter_quill_extensions\b",
    r"\bmarkdown_quill\b",
    r"\bmarkdown_widget\b",
    r"^\s+markdown:\s",
)

RETIRED_LEGACY_AUTHORITY_FILES = (
    "backend/app/utils/lesson_markdown_validator.py",
    "frontend/tool/lesson_markdown_roundtrip.dart",
    "frontend/tool/lesson_markdown_roundtrip_harness_test.dart",
    "frontend/lib/editor/adapter/editor_to_markdown.dart",
    "frontend/lib/editor/adapter/markdown_to_editor.dart",
    "frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart",
    "frontend/lib/editor/normalization/quill_delta_normalizer.dart",
    "frontend/lib/editor/session/editor_session.dart",
    "frontend/lib/editor/session/editor_operation_quill_controller.dart",
    "frontend/lib/editor/debug/editor_test_bridge.dart",
)

REQUIRED_BACKEND_GATE_FILES = (
    "backend/tests/test_ler011_deterministic_audit_gates.py",
    "backend/tests/test_lesson_document_fixture_corpus.py",
    "backend/tests/test_lesson_document_content_backend_contract.py",
    "backend/tests/test_studio_lesson_document_content_api.py",
    "backend/tests/test_course_publish_authority.py",
    "backend/tests/test_lesson_supported_content_fixture_corpus.py",
    "backend/tests/test_write_path_dominance_regression.py",
    "backend/tests/test_surface_based_lesson_reads.py",
    "backend/tests/test_lesson_media_rendering.py",
    "backend/tests/test_protected_lesson_content_surface_gate.py",
)

REQUIRED_FRONTEND_GATE_FILES = (
    "frontend/test/helpers/lesson_document_fixture_corpus.dart",
    "frontend/test/unit/lesson_document_model_test.dart",
    "frontend/test/unit/studio_repository_lesson_content_read_test.dart",
    "frontend/test/unit/studio_repository_lesson_media_routing_test.dart",
    "frontend/test/unit/media_upload_url_contract_test.dart",
    "frontend/test/unit/lesson_media_preview_cache_test.dart",
    "frontend/test/unit/courses_repository_access_test.dart",
    "frontend/test/widgets/lesson_document_editor_test.dart",
    "frontend/test/widgets/lesson_preview_rendering_test.dart",
    "frontend/test/widgets/lesson_media_pipeline_test.dart",
)


def _read_json(relative_path: str) -> dict[str, object]:
    return json.loads(read_repo_text(REPO_ROOT, relative_path))


def _assert_existing_paths(paths: Iterable[str]) -> None:
    missing = [path for path in paths if not (REPO_ROOT / path).exists()]
    assert missing == []


def _assert_absent_paths(paths: Iterable[str]) -> None:
    surviving = [path for path in paths if (REPO_ROOT / path).exists()]
    assert surviving == []


def _source_section(source: str, start: str, end: str | None = None) -> str:
    try:
        start_index = source.index(start)
    except ValueError as exc:
        raise AssertionError(f"Missing source section start: {start}") from exc

    if end is None:
        return source[start_index:]
    try:
        end_index = source.index(end, start_index + len(start))
    except ValueError as exc:
        raise AssertionError(f"Missing source section end: {end}") from exc
    return source[start_index:end_index]


def _frontend_media_authority_text() -> str:
    return "\n".join(
        read_repo_text(REPO_ROOT, path) for path in FRONTEND_MEDIA_AUTHORITY_PATHS
    )


def test_manifest_and_dag_chain_are_complete_before_final_completion() -> None:
    manifest = _read_json(
        "actual_truth/DETERMINED_TASKS/lesson_editor_rebuild/task_manifest.json"
    )
    tasks = {task["task_id"]: task for task in manifest["task_tree"]}  # type: ignore[index]

    assert tuple(tasks)[: len(REQUIRED_TASK_IDS)] == REQUIRED_TASK_IDS
    assert set(REQUIRED_TASK_IDS).issubset(tasks)
    for task_id in REQUIRED_TASK_IDS[:-1]:
        assert tasks[task_id]["status"] == "completed"
    assert tasks["LER-012"]["status"] in {"planned", "completed"}

    for task_id, expected_dependencies in EXPECTED_DEPENDENCIES.items():
        assert tasks[task_id]["depends_on"] == expected_dependencies

    task_docs = sorted(
        (REPO_ROOT / "actual_truth/DETERMINED_TASKS/lesson_editor_rebuild").glob(
            "LER-*.md"
        )
    )
    documented_ids = {path.name[:7] for path in task_docs}
    assert set(REQUIRED_TASK_IDS).issubset(documented_ids)

    for task_id in REQUIRED_TASK_IDS[:-1]:
        task_doc = next(path for path in task_docs if path.name.startswith(task_id))
        text = task_doc.read_text(encoding="utf-8")
        assert "Execution Record" in text
        assert "COMPLETED" in text
        assert "Verification" in text

    final_gate_doc = next(path for path in task_docs if path.name.startswith("LER-012"))
    final_gate_text = final_gate_doc.read_text(encoding="utf-8")
    assert "FINAL AGGREGATE EDITOR GATE" in final_gate_text
    assert "Verify the complete editor rebuild end-to-end" in final_gate_text
    assert "Stop Conditions" in final_gate_text


def test_contract_layer_and_fixture_corpus_are_final_document_authority() -> None:
    manifest_contract = read_repo_text(
        REPO_ROOT, "actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md"
    )
    editor_contract = read_repo_text(
        REPO_ROOT, "actual_truth/contracts/course_lesson_editor_contract.md"
    )
    public_contract = read_repo_text(
        REPO_ROOT, "actual_truth/contracts/course_public_surface_contract.md"
    )
    media_contract = read_repo_text(
        REPO_ROOT, "actual_truth/contracts/media_pipeline_contract.md"
    )

    combined_contracts = "\n".join(
        [manifest_contract, editor_contract, public_contract, media_contract]
    )
    for token in (
        "lesson_document_v1",
        "app.lesson_contents.content_document",
        "content_document",
        "Markdown SHALL NOT be the new editor authority",
        "Quill Delta SHALL NOT be the new editor authority",
        "Preview Mode must render persisted saved content only",
        "If-Match",
        "ETag",
        "Media nodes in `lesson_document_v1` MUST reference governed lesson media",
        "Magic-link / CTA is first-class editor content",
    ):
        assert token in combined_contracts

    active_corpus = _read_json(
        "actual_truth/contracts/lesson_document_fixture_corpus.json"
    )
    assert active_corpus["status"] == "ACTIVE_REBUILT_EDITOR_AUTHORITY"
    assert active_corpus["schema_version"] == "lesson_document_v1"
    assert active_corpus["storage_authority"] == {
        "table": "app.lesson_contents",
        "field": "content_document",
    }
    assert active_corpus["legacy_authority"] is False
    assert set(active_corpus["required_capabilities"]) == REQUIRED_CAPABILITIES
    assert set(active_corpus["capability_coverage"]) == REQUIRED_CAPABILITIES

    legacy_corpus = _read_json(
        "actual_truth/contracts/lesson_supported_content_fixture_corpus.json"
    )
    assert legacy_corpus["status"] == "LEGACY_COMPATIBILITY_ONLY"
    assert legacy_corpus["rebuilt_editor_authority"] is False
    assert legacy_corpus["rebuilt_editor_storage"] == {
        "table": "app.lesson_contents",
        "field": "content_document",
        "schema_version": "lesson_document_v1",
    }


def test_backend_runtime_persists_validates_and_hashes_content_document() -> None:
    _assert_existing_paths(
        (
            "backend/app/utils/lesson_document_validator.py",
            "backend/supabase/baseline_v2_slots/V2_0029_lesson_document_content.sql",
        )
    )
    _assert_absent_paths(("backend/app/utils/lesson_markdown_validator.py",))

    validator = read_repo_text(
        REPO_ROOT, "backend/app/utils/lesson_document_validator.py"
    )
    service = read_repo_text(REPO_ROOT, "backend/app/services/courses_service.py")
    repository = read_repo_text(REPO_ROOT, "backend/app/repositories/courses.py")
    routes = read_repo_text(REPO_ROOT, "backend/app/routes/studio.py")
    schemas = read_repo_text(REPO_ROOT, "backend/app/schemas/__init__.py")
    migration = read_repo_text(
        REPO_ROOT,
        "backend/supabase/baseline_v2_slots/V2_0029_lesson_document_content.sql",
    )

    assert_no_findings(
        missing_token_findings(
            validator,
            scope="lesson_document_validator",
            tokens=(
                "def validate_lesson_document(",
                "def canonical_lesson_document_bytes(",
                'SCHEMA_VERSION = "lesson_document_v1"',
                "lesson_media_id",
                "target_url",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            validator + "\n" + service,
            scope="backend_document_validation_authority",
            tokens=BACKEND_DOCUMENT_AUTHORITY_FORBIDDEN + ("content_markdown",),
        )
    )

    service_write = python_decorated_function_block(service, "update_lesson_content")
    route_write = python_decorated_function_block(routes, "update_lesson_content")
    repository_write = _source_section(
        repository,
        "async def update_lesson_document_if_current(",
        "\n\nasync def update_lesson_content(",
    )

    assert_no_findings(
        missing_token_findings(
            service_write,
            scope="courses_service.update_lesson_content",
            tokens=(
                "lesson_document_validator.validate_lesson_document",
                "build_lesson_content_etag",
                "content_document",
                "if_match",
                "expected_content_document=current_body",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            route_write,
            scope="routes.studio.update_lesson_content",
            tokens=(
                "payload: schemas.StudioLessonContentUpdate",
                "content_document=payload.content_document",
                'request.headers.get("if-match")',
                'response.headers["ETag"]',
                "schemas.StudioLessonContent(**row",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            repository_write,
            scope="repositories.courses.update_lesson_document_if_current",
            tokens=(
                "content_document: dict[str, Any]",
                "expected_content_document: dict[str, Any]",
                "do update set content_document = excluded.content_document",
                "returning lesson_id, content_document",
                "Jsonb(content_document)",
                "Jsonb(expected_content_document)",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            schemas,
            scope="schemas.studio_lesson_content",
            tokens=(
                "class StudioLessonContentUpdate(BaseModel):",
                'model_config = ConfigDict(extra="forbid")',
                "content_document: Dict[str, Any]",
                "class StudioLessonContentRead(BaseModel):",
                "media: List[StudioLessonContentMediaItem]",
                "class StudioLessonContent(BaseModel):",
            ),
        )
    )
    assert (
        "add column if not exists content_document jsonb not null default" in migration
    )
    assert "lesson_document_v1" in migration


def test_frontend_authoring_preview_learner_and_transport_are_document_model() -> None:
    course_editor = read_repo_text(
        REPO_ROOT, "frontend/lib/features/studio/presentation/course_editor_page.dart"
    )
    studio_repository = read_repo_text(
        REPO_ROOT, "frontend/lib/features/studio/data/studio_repository.dart"
    )
    studio_models = read_repo_text(
        REPO_ROOT, "frontend/lib/features/studio/data/studio_models.dart"
    )
    learner_page = read_repo_text(
        REPO_ROOT, "frontend/lib/features/courses/presentation/lesson_page.dart"
    )
    document_model = read_repo_text(
        REPO_ROOT, "frontend/lib/editor/document/lesson_document.dart"
    )
    document_editor = read_repo_text(
        REPO_ROOT, "frontend/lib/editor/document/lesson_document_editor.dart"
    )

    save_block = dart_source_block(
        course_editor, "Future<bool> _saveLessonContent({bool showSuccessSnack = true})"
    )
    preview_loader = dart_source_block(
        course_editor, "Future<void> _loadPersistedLessonPreview({"
    )
    preview_builder = dart_source_block(
        course_editor, "Widget _buildLessonPreviewMode(BuildContext context)"
    )
    media_insert_block = dart_source_block(
        document_editor, "bool _insertMediaBlockFromController({"
    )
    cta_insert_block = dart_source_block(
        course_editor, "Future<void> _insertMagicLink()"
    )
    read_transport = dart_source_block(
        studio_repository, "Future<StudioLessonContentRead> readLessonContent("
    )
    write_transport = dart_source_block(
        studio_repository, "Future<StudioLessonContentWriteResult> updateLessonContent("
    )
    read_model = _source_section(
        studio_models,
        "class StudioLessonContentRead",
        "\n@immutable\nclass StudioLessonContentWriteResult",
    )
    write_model = _source_section(
        studio_models,
        "class StudioLessonContentWriteResult",
        "\nString _requireTransportEtag",
    )

    assert_no_findings(
        missing_token_findings(
            save_block,
            scope="CourseEditor._saveLessonContent",
            tokens=(
                "contentDocument = saveSnapshot.document.validate",
                "contentDocument.toCanonicalJsonString()",
                "updateLessonContent",
                "contentDocument: contentDocument",
                "ifMatch: contentEtag",
            ),
        )
    )
    assert "LessonEditorSessionHost(" in course_editor
    assert "LessonDocumentEditor(" in document_editor
    assert "LessonDocumentPreview(" in course_editor
    assert "const insertionIndex = 0;" in media_insert_block
    assert "_document.insertBlock(insertionIndex, block)" in media_insert_block
    assert "insertionIndex," in media_insert_block
    assert "lessonMediaId: lessonMediaId" in media_insert_block
    assert "_lessonDocument.blocks.length," not in media_insert_block
    assert "_resolvedLessonDocumentInsertionIndex();" not in media_insert_block
    assert "_currentInsertionIndex();" not in media_insert_block
    assert (
        "onHeading: () => _convertSelectedBlock(_BlockConversion.heading)"
        in document_editor
    )
    assert "onHeading: _toggleHeading" not in document_editor
    assert "insertCta(" in cta_insert_block
    assert "targetUrl: url" in cta_insert_block

    assert_no_findings(
        missing_token_findings(
            preview_loader + "\n" + preview_builder,
            scope="CourseEditor.persisted_preview",
            tokens=(
                "readLessonContent",
                "_lessonPreviewDocument = content.contentDocument",
                "preview.source.authority=backend_read",
                "persisted_only=true",
                "LessonDocumentPreview",
                "document: previewDocument",
                "media: previewMedia",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            save_block + "\n" + preview_loader + "\n" + preview_builder,
            scope="CourseEditor.save_preview_no_legacy_authority",
            tokens=FRONTEND_DOCUMENT_AUTHORITY_FORBIDDEN
            + (
                "_lessonPreviewDocument = _lessonDocument",
                "document: _lessonDocument",
            ),
        )
    )

    assert_no_findings(
        missing_token_findings(
            read_transport,
            scope="StudioRepository.readLessonContent",
            tokens=(
                "'/studio/lessons/$id/content'",
                "_requiredEtagHeader(response, 'Studio lesson content read')",
                "StudioLessonContentRead.fromResponse",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            write_transport,
            scope="StudioRepository.updateLessonContent",
            tokens=(
                "'/studio/lessons/$id/content'",
                "data: {'content_document': contentDocument.toJson()}",
                "contentDocument.toJson()",
                "Options(headers: {'If-Match': contentToken})",
                "_requiredEtagHeader(response, 'Updated studio lesson content')",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            read_transport
            + "\n"
            + write_transport
            + "\n"
            + read_model
            + "\n"
            + write_model,
            scope="frontend_content_transport_models",
            tokens=("content_markdown", "contentMarkdown"),
        )
    )

    assert_no_findings(
        missing_token_findings(
            learner_page,
            scope="learner_lesson_document_renderer",
            tokens=(
                "final documentContent = lesson.contentDocument",
                "class LessonPageRenderer extends StatelessWidget",
                "LessonDocumentPreview",
                "document: document",
                "media: previewMedia",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            document_model + "\n" + document_editor,
            scope="frontend_document_runtime",
            tokens=FRONTEND_DOCUMENT_AUTHORITY_FORBIDDEN,
        )
    )
    assert_no_findings(
        forbidden_regex_findings(
            document_model + "\n" + document_editor,
            scope="frontend_document_runtime",
            patterns=FRONTEND_DOCUMENT_AUTHORITY_FORBIDDEN_PATTERNS,
        )
    )


def test_media_block_regression_gates_are_locked_in_final_aggregate() -> None:
    document_model = read_repo_text(
        REPO_ROOT, "frontend/lib/editor/document/lesson_document.dart"
    )
    document_editor = read_repo_text(
        REPO_ROOT, "frontend/lib/editor/document/lesson_document_editor.dart"
    )
    course_editor = read_repo_text(
        REPO_ROOT,
        "frontend/lib/features/studio/presentation/course_editor_page.dart",
    )
    learner_page = read_repo_text(
        REPO_ROOT, "frontend/lib/features/courses/presentation/lesson_page.dart"
    )
    document_renderer = read_repo_text(
        REPO_ROOT, "frontend/lib/editor/document/lesson_document_renderer.dart"
    )
    model_tests = read_repo_text(
        REPO_ROOT, "frontend/test/unit/lesson_document_model_test.dart"
    )
    editor_tests = read_repo_text(
        REPO_ROOT, "frontend/test/widgets/lesson_document_editor_test.dart"
    )
    preview_tests = read_repo_text(
        REPO_ROOT, "frontend/test/widgets/lesson_preview_rendering_test.dart"
    )
    pipeline_tests = read_repo_text(
        REPO_ROOT, "frontend/test/widgets/lesson_media_pipeline_test.dart"
    )
    audit_gate_tests = read_repo_text(
        REPO_ROOT, "backend/tests/test_ler011_deterministic_audit_gates.py"
    )

    media_insert_block = dart_source_block(
        document_editor, "bool _insertMediaBlockFromController({"
    )
    editor_move_block = dart_source_block(document_editor, "void _moveBlock(")

    assert_no_findings(
        missing_token_findings(
            document_model,
            scope="final_gate.document_media_operations",
            tokens=(
                "LessonDocument moveBlock(int fromIndex, int toIndex)",
                "LessonDocument moveBlockUp(int index)",
                "LessonDocument moveBlockDown(int index)",
                "'media_type': mediaType",
                "'lesson_media_id': lessonMediaId",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            media_insert_block,
            scope="final_gate.top_media_insert",
            tokens=(
                "const insertionIndex = 0;",
                "_document.insertBlock(insertionIndex, block)",
                "insertionIndex,",
                "setState(() => _selectedTarget = nextTarget)",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            editor_move_block,
            scope="final_gate.editor_media_movement",
            tokens=(
                "_document.moveBlock(blockIndex, targetIndex)",
                "_insertionIndexForTarget(nextTarget)",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            document_editor,
            scope="final_gate.editor_text_movement",
            tokens=(
                "_buildBlockMoveControls",
                "keyPrefix: 'lesson_document_media'",
                "keyPrefix: 'lesson_document_text'",
                "Flytta text upp",
                "Flytta text ned",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            document_editor,
            scope="final_gate.selection_aware_heading_toolbar",
            tokens=("onHeading: () => _convertSelectedBlock(_BlockConversion.heading)",),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            document_editor,
            scope="final_gate.heading_toolbar_not_block_toggle",
            tokens=("onHeading: _toggleHeading",),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            media_insert_block,
            scope="final_gate.no_append_or_positioned_media_insert",
            tokens=(
                "_lessonDocument.blocks.length,",
                "_resolvedLessonDocumentInsertionIndex();",
                "_currentInsertionIndex();",
            ),
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            document_editor + "\n" + course_editor + "\n" + learner_page,
            scope="final_gate.user_facing_media_no_leak",
            tokens=(
                "Media: ${block.mediaType}",
                "Media saknas: ${block.mediaType}",
                "${block.lessonMediaId}",
                "'Status: $state'",
                "Infogad media\\nFlytta blocket med pilarna.",
                "label: media.originalName ?? media.mediaAssetId",
                "label: item.mediaAssetId",
                "return mediaAssetId;",
            ),
        )
    )
    assert_no_findings(
        missing_token_findings(
            document_editor
            + "\n"
            + course_editor
            + "\n"
            + learner_page
            + "\n"
            + document_renderer,
            scope="final_gate.safe_media_user_copy",
            tokens=(
                "_mediaFileName",
                "_mediaTypeLabel",
                "media: _editorDocumentMedia()",
                "_safeLessonPreviewMediaLabel(media.originalName)",
                "label: null",
                "Lektionsljud",
                "Lektionsvideo",
                "Lektionsfil",
            ),
        )
    )

    regression_test_text = "\n".join(
        [model_tests, editor_tests, preview_tests, pipeline_tests]
    )
    for required_test_marker in (
        "inserts media before, between, and after text blocks",
        "moves media blocks by changing only document order",
        "document editor inserts media at document top",
        "document editor applies heading only to selected range",
        "document editor heading is a no-op for collapsed cursor",
        "document editor moves media blocks deterministically",
        "document editor moves paragraph heading and list blocks",
        "document editor media blocks hide internal metadata",
        "document preview fallback renders video player without metadata",
        "lesson renders inline document tokens without trailing fallback duplication",
    ):
        assert required_test_marker in regression_test_text

    for required_gate_marker in (
        "test_seeded_gate_detects_media_block_regressions",
        "test_media_block_editor_regression_gate_is_top_inserted_and_document_ordered",
        "test_media_block_user_facing_no_leak_regression_gate",
    ):
        assert required_gate_marker in audit_gate_tests


def test_legacy_authority_files_dependencies_and_media_preview_urls_stay_removed() -> (
    None
):
    _assert_absent_paths(RETIRED_LEGACY_AUTHORITY_FILES)

    pubspec = read_repo_text(REPO_ROOT, "frontend/pubspec.yaml")
    lockfile = read_repo_text(REPO_ROOT, "frontend/pubspec.lock")
    assert_no_findings(
        forbidden_regex_findings(
            pubspec + "\n" + lockfile,
            scope="frontend_editor_dependencies",
            patterns=FORBIDDEN_DEPENDENCY_PATTERNS,
        )
    )
    assert_no_findings(
        forbidden_token_findings(
            _frontend_media_authority_text(),
            scope="frontend_lib_media_url_authority",
            tokens=FRONTEND_MEDIA_AUTHORITY_FORBIDDEN,
        )
    )


def test_required_gate_inventory_is_materialized_for_all_editor_capabilities() -> None:
    _assert_existing_paths(
        (
            "tools/lesson_editor_authority_audit.py",
            "actual_truth/contracts/lesson_document_fixture_corpus.json",
            "actual_truth/contracts/lesson_document_fixture_corpus.md",
            "actual_truth/analysis/lesson_editor_rebuild_foundation/DOCUMENT_FIXTURE_CORPUS_AUDIT_LER010.md",
            "actual_truth/analysis/lesson_editor_rebuild_foundation/DETERMINISTIC_AUDIT_GATES_LER011.md",
        )
        + REQUIRED_BACKEND_GATE_FILES
        + REQUIRED_FRONTEND_GATE_FILES
    )

    corpus = _read_json("actual_truth/contracts/lesson_document_fixture_corpus.json")
    binding_groups = corpus["binding_groups"]
    referenced_tests: set[str] = set()
    referenced_runtimes: set[str] = set()
    for group in binding_groups.values():
        referenced_tests.update(group["test_paths"])
        referenced_runtimes.update(group["runtime_paths"])
        fixture_ids = set(group["fixture_ids"])
        assert fixture_ids
        for fixture_id in fixture_ids:
            assert fixture_id in corpus["fixtures"]

    _assert_existing_paths(referenced_tests)
    _assert_existing_paths(referenced_runtimes)

    test_corpus_text = "\n".join(
        read_repo_text(REPO_ROOT, path)
        for path in REQUIRED_BACKEND_GATE_FILES + REQUIRED_FRONTEND_GATE_FILES
    )
    for capability in REQUIRED_CAPABILITIES:
        assert re.search(re.escape(capability), test_corpus_text)
