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
    fixtures = corpus["supported_canonical_fixtures"]
    assert isinstance(fixtures, dict)
    fixture = fixtures[fixture_id]
    assert isinstance(fixture, dict)
    return fixture


def test_fixture_corpus_artifact_is_active_and_contract_backed() -> None:
    corpus = _load_corpus()

    assert corpus["status"] == "ACTIVE"
    canonical_storage = corpus["canonical_storage"]
    assert isinstance(canonical_storage, dict)
    assert canonical_storage["field"] == "content_markdown"

    contract_text = COURSE_CONTRACT_PATH.read_text(encoding="utf-8")
    assert "lesson_supported_content_fixture_corpus.json" in contract_text
    assert "lesson_supported_content_fixture_corpus.md" in contract_text


def test_backend_validator_binding_points_to_real_repo_boundaries() -> None:
    corpus = _load_corpus()
    validator_group = _binding_group(corpus, "backend_validator_tests")

    runtime_paths = validator_group["runtime_paths"]
    test_paths = validator_group["test_paths"]
    assert isinstance(runtime_paths, list)
    assert isinstance(test_paths, list)

    for relative_path in [*runtime_paths, *test_paths]:
        path = ROOT / str(relative_path)
        assert path.exists(), relative_path

    assert "backend/app/utils/lesson_markdown_validator.py" in runtime_paths
    assert "frontend/tool/lesson_markdown_roundtrip.dart" in runtime_paths
    assert "frontend/tool/lesson_markdown_roundtrip_harness_test.dart" in runtime_paths
    assert "backend/tests/test_lesson_markdown_validator.py" in test_paths


def test_blocker_fixtures_are_now_locked_supported_content() -> None:
    corpus = _load_corpus()

    newline_fixture = _fixture(corpus, "paragraph_blank_line_two_paragraphs")
    document_fixture = _fixture(corpus, "document_token_inline")

    assert newline_fixture["status"] == "locked"
    assert "frontend_newline_tests" in newline_fixture["binding_groups"]
    assert "backend_write_contract_tests" in newline_fixture["binding_groups"]

    assert document_fixture["status"] == "locked"
    assert "preview_learner_parity_tests" in document_fixture["binding_groups"]
    assert "backend_write_contract_tests" in document_fixture["binding_groups"]
