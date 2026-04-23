from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CORPUS_PATH = (
    ROOT / "actual_truth" / "contracts" / "lesson_supported_content_fixture_corpus.json"
)
COURSE_CONTRACT_PATH = (
    ROOT / "actual_truth" / "contracts" / "course_lesson_editor_contract.md"
)


def _load_corpus() -> dict[str, object]:
    return json.loads(CORPUS_PATH.read_text(encoding="utf-8"))


def _binding_group(corpus: dict[str, object], group_id: str) -> dict[str, object]:
    groups = corpus["binding_groups"]
    assert isinstance(groups, dict)
    group = groups[group_id]
    assert isinstance(group, dict)
    return group


def _fixture(corpus: dict[str, object], fixture_id: str) -> dict[str, object]:
    fixtures = corpus["legacy_supported_markdown_fixtures"]
    assert isinstance(fixtures, dict)
    fixture = fixtures[fixture_id]
    assert isinstance(fixture, dict)
    return fixture


def test_fixture_corpus_artifact_is_active_and_contract_backed() -> None:
    corpus = _load_corpus()

    assert corpus["status"] == "LEGACY_COMPATIBILITY_ONLY"
    assert corpus["rebuilt_editor_authority"] is False

    rebuilt_storage = corpus["rebuilt_editor_storage"]
    assert isinstance(rebuilt_storage, dict)
    assert rebuilt_storage["field"] == "content_document"
    assert rebuilt_storage["schema_version"] == "lesson_document_v1"

    legacy_storage = corpus["legacy_markdown_storage"]
    assert isinstance(legacy_storage, dict)
    assert legacy_storage["field"] == "content_markdown"

    authority_contracts = corpus["authority_contracts"]
    assert isinstance(authority_contracts, list)
    assert (
        "actual_truth/contracts/course_lesson_editor_contract.md" in authority_contracts
    )

    contract_text = COURSE_CONTRACT_PATH.read_text(encoding="utf-8")
    assert "`lesson_document_v1` fixture corpus" in contract_text
    assert "legacy Markdown fixtures may remain only as compatibil" in contract_text


def test_rebuilt_document_bindings_point_to_real_repo_boundaries() -> None:
    corpus = _load_corpus()
    group_ids = [
        "frontend_document_model_tests",
        "frontend_document_editor_tests",
        "frontend_document_save_tests",
        "backend_document_contract_tests",
        "rebuilt_preview_learner_document_tests",
        "legacy_markdown_tooling_tests",
    ]

    retired_paths = {
        "frontend/test/unit/editor_markdown_adapter_test.dart",
        "frontend/test/unit/lesson_content_serialization_test.dart",
        "frontend/test/unit/lesson_newline_persistence_test.dart",
        "frontend/test/unit/lesson_markdown_integrity_guard_test.dart",
        "frontend/test/widgets/lesson_editor_quill_input_test.dart",
        "frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart",
        "frontend/test/unit/editor_operation_controller_test.dart",
        "backend/tests/test_lesson_markdown_validator.py",
        "backend/tests/test_lesson_markdown_write_contract.py",
        "backend/tests/test_studio_lesson_content_authority.py",
    }
    declared_paths: set[str] = set()

    for group_id in group_ids:
        group = _binding_group(corpus, group_id)
        runtime_paths = group["runtime_paths"]
        test_paths = group["test_paths"]
        assert isinstance(runtime_paths, list)
        assert isinstance(test_paths, list)

        for relative_path in [*runtime_paths, *test_paths]:
            declared_paths.add(str(relative_path))
            path = ROOT / str(relative_path)
            assert path.exists(), relative_path

    assert "frontend/lib/editor/document/lesson_document.dart" in declared_paths
    assert "backend/app/utils/lesson_document_validator.py" in declared_paths
    assert "frontend/test/widgets/lesson_document_editor_test.dart" in declared_paths
    assert (
        "backend/tests/test_lesson_document_content_backend_contract.py"
        in declared_paths
    )
    assert declared_paths.isdisjoint(retired_paths)


def test_blocker_fixtures_are_now_locked_supported_content() -> None:
    corpus = _load_corpus()

    newline_fixture = _fixture(corpus, "paragraph_blank_line_two_paragraphs")
    document_fixture = _fixture(corpus, "document_token_inline")

    assert newline_fixture["status"] == "legacy_compatibility_locked"
    assert "frontend_document_model_tests" in newline_fixture["binding_groups"]
    assert "backend_document_contract_tests" in newline_fixture["binding_groups"]

    assert document_fixture["status"] == "legacy_compatibility_locked"
    assert "frontend_document_save_tests" in document_fixture["binding_groups"]
    assert "backend_document_contract_tests" in document_fixture["binding_groups"]

    cta_fixture = _fixture(corpus, "cta_magic_link")
    assert cta_fixture["status"] == "rebuilt_document_only"
    assert "frontend_document_editor_tests" in cta_fixture["binding_groups"]
