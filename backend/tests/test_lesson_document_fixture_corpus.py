from __future__ import annotations

import json
from collections.abc import Iterator, Mapping
from pathlib import Path
from typing import Any
from uuid import UUID

from app.services import courses_service
from app.utils import lesson_document_validator


ROOT = Path(__file__).resolve().parents[2]
CORPUS_PATH = (
    ROOT / "actual_truth" / "contracts" / "lesson_document_fixture_corpus.json"
)

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

DOCUMENT_FIELDS = {
    "document",
    "expected_document",
    "saved_document",
    "draft_document",
    "initial_document",
    "updated_document",
    "stale_attempt_document",
}

FORBIDDEN_KEYS = {
    "canonical_markdown",
    "content_markdown",
    "markdown",
    "delta",
    "quill",
}

FORBIDDEN_DOCUMENT_STRINGS = (
    "!image(",
    "!audio(",
    "!video(",
    "!document(",
    "storage_path",
    "signed_url",
    "preview_url",
    "runtime_media",
    "media_asset_id",
    "resolved_url",
)


def _load_corpus() -> dict[str, Any]:
    return json.loads(CORPUS_PATH.read_text(encoding="utf-8"))


def _fixtures(corpus: Mapping[str, Any]) -> Mapping[str, Mapping[str, Any]]:
    fixtures = corpus["fixtures"]
    assert isinstance(fixtures, Mapping)
    return fixtures


def _media_rows(corpus: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    rows = corpus["media_rows"]
    assert isinstance(rows, list)
    return [row for row in rows if isinstance(row, Mapping)]


def _document_payloads(
    fixture: Mapping[str, Any],
) -> Iterator[tuple[str, Mapping[str, Any]]]:
    for field in DOCUMENT_FIELDS:
        payload = fixture.get(field)
        if payload is None:
            continue
        assert isinstance(payload, Mapping), field
        yield field, payload


def _walk(value: Any) -> Iterator[Any]:
    yield value
    if isinstance(value, Mapping):
        for key, item in value.items():
            yield key
            yield from _walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from _walk(item)


def test_document_fixture_corpus_is_active_document_authority() -> None:
    corpus = _load_corpus()

    assert corpus["contract_id"] == "lesson_document_fixture_corpus"
    assert corpus["status"] == "ACTIVE_REBUILT_EDITOR_AUTHORITY"
    assert corpus["schema_version"] == lesson_document_validator.SCHEMA_VERSION
    assert corpus["legacy_authority"] is False

    storage_authority = corpus["storage_authority"]
    assert isinstance(storage_authority, Mapping)
    assert storage_authority["table"] == "app.lesson_contents"
    assert storage_authority["field"] == "content_document"

    assert set(corpus["required_capabilities"]) == REQUIRED_CAPABILITIES

    for item in _walk(corpus):
        if isinstance(item, str):
            assert item not in FORBIDDEN_KEYS
        if isinstance(item, str) and item in {
            "canonical_markdown",
            "content_markdown",
        }:
            raise AssertionError(f"Forbidden legacy key/string in corpus: {item}")


def test_every_required_capability_has_positive_fixture_coverage() -> None:
    corpus = _load_corpus()
    fixtures = _fixtures(corpus)
    coverage = corpus["capability_coverage"]
    assert isinstance(coverage, Mapping)

    assert set(coverage) == REQUIRED_CAPABILITIES
    for capability in REQUIRED_CAPABILITIES:
        fixture_ids = coverage[capability]
        assert isinstance(fixture_ids, list)
        assert fixture_ids, capability
        for fixture_id in fixture_ids:
            assert fixture_id in fixtures, f"{capability} -> {fixture_id}"
            features = fixtures[fixture_id]["features"]
            assert capability in features, f"{fixture_id} must declare {capability}"


def test_every_corpus_document_validates_with_backend_validator() -> None:
    corpus = _load_corpus()
    media_rows = _media_rows(corpus)

    for fixture_id, fixture in _fixtures(corpus).items():
        for field, document in _document_payloads(fixture):
            validated = lesson_document_validator.validate_lesson_document(
                document,
                media_rows=media_rows,
            )
            assert validated == document, f"{fixture_id}.{field}"
            assert not any(
                token in json.dumps(document, sort_keys=True)
                for token in FORBIDDEN_DOCUMENT_STRINGS
            ), f"{fixture_id}.{field} contains forbidden document authority"


def test_media_rows_are_governed_read_projection_not_document_truth() -> None:
    corpus = _load_corpus()
    rows = _media_rows(corpus)

    media_types = {row["media_type"] for row in rows}
    assert media_types == {"image", "audio", "video", "document"}

    for row in rows:
        UUID(str(row["lesson_media_id"]))
        assert row["state"] == "ready"
        assert str(row["media_asset_id"]).startswith("asset-")
        assert str(row["resolved_url"]).startswith("https://cdn.test/")

    for fixture in _fixtures(corpus).values():
        for _, document in _document_payloads(fixture):
            document_text = json.dumps(document, sort_keys=True)
            assert "media_asset_id" not in document_text
            assert "resolved_url" not in document_text


def test_clear_formatting_fixture_preserves_text_and_block_boundaries() -> None:
    corpus = _load_corpus()
    fixture = _fixtures(corpus)["clear_formatting_operation"]
    source = fixture["document"]
    expected = fixture["expected_document"]

    validated_source = lesson_document_validator.validate_lesson_document(source)
    validated_expected = lesson_document_validator.validate_lesson_document(expected)

    assert len(validated_source["blocks"]) == 2
    assert len(validated_expected["blocks"]) == 2
    assert validated_expected["blocks"][0] == {
        "type": "paragraph",
        "children": [{"text": "Clear me"}],
    }
    assert validated_expected["blocks"][1] == validated_source["blocks"][1]


def test_etag_concurrency_fixture_uses_canonical_document_bytes() -> None:
    corpus = _load_corpus()
    fixture = _fixtures(corpus)["etag_concurrency"]
    lesson_id = "00000000-0000-4000-8000-000000000001"

    initial = lesson_document_validator.validate_lesson_document(
        fixture["initial_document"]
    )
    updated = lesson_document_validator.validate_lesson_document(
        fixture["updated_document"]
    )
    stale_attempt = lesson_document_validator.validate_lesson_document(
        fixture["stale_attempt_document"]
    )

    initial_etag = courses_service.build_lesson_content_etag(lesson_id, initial)
    same_initial_etag = courses_service.build_lesson_content_etag(
        lesson_id,
        {"blocks": initial["blocks"], "schema_version": initial["schema_version"]},
    )
    updated_etag = courses_service.build_lesson_content_etag(lesson_id, updated)
    stale_attempt_etag = courses_service.build_lesson_content_etag(
        lesson_id,
        stale_attempt,
    )

    assert initial_etag == same_initial_etag
    assert updated_etag != initial_etag
    assert stale_attempt_etag != initial_etag
    assert stale_attempt_etag != updated_etag


def test_corpus_binding_groups_point_to_real_runtime_and_test_files() -> None:
    corpus = _load_corpus()
    fixtures = _fixtures(corpus)
    groups = corpus["binding_groups"]
    assert isinstance(groups, Mapping)

    declared_fixtures: set[str] = set()
    for group_id, group in groups.items():
        assert isinstance(group, Mapping), group_id
        for list_key in ("runtime_paths", "test_paths", "fixture_ids"):
            assert isinstance(group[list_key], list), f"{group_id}.{list_key}"
            assert group[list_key], f"{group_id}.{list_key}"

        for relative_path in [*group["runtime_paths"], *group["test_paths"]]:
            path = ROOT / str(relative_path)
            assert path.exists(), f"{group_id}: {relative_path}"

        for fixture_id in group["fixture_ids"]:
            assert fixture_id in fixtures, f"{group_id}: {fixture_id}"
            declared_fixtures.add(str(fixture_id))

    assert set(fixtures).issubset(declared_fixtures)
