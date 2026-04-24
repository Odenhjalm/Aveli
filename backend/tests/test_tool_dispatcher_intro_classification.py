from __future__ import annotations

import inspect
from pathlib import Path

from app import schemas
from app.services import tool_dispatcher


def test_list_intro_courses_filters_by_required_enrollment_source_not_group_position(
    monkeypatch,
) -> None:
    captured: dict[str, object] = {}
    expected = {
        "stub": False,
        "row_count": 0,
        "truncated": False,
        "rows": [],
    }

    def _fake_fetch_rows(sql: str, params, *, limit_cap: int):
        captured["sql"] = sql
        captured["params"] = params
        captured["limit_cap"] = limit_cap
        return expected

    monkeypatch.setattr(
        tool_dispatcher,
        "_fetch_rows",
        _fake_fetch_rows,
        raising=True,
    )

    result = tool_dispatcher._list_intro_courses({"limit": 7})

    assert result is expected
    assert (
        "required_enrollment_source = 'intro_enrollment'::app.course_enrollment_source"
        in str(captured["sql"])
    )
    assert "visibility = 'public'::app.course_visibility" in str(captured["sql"])
    assert "ORDER BY updated_at DESC" in str(captured["sql"])
    assert "group_position = 0" not in str(captured["sql"])
    assert captured["params"] == (7,)
    assert captured["limit_cap"] == 7


def test_list_intro_courses_does_not_classify_intro_by_group_position() -> None:
    source = inspect.getsource(tool_dispatcher._list_intro_courses)

    assert "required_enrollment_source" in source
    assert "group_position = 0" not in source


def test_course_schema_still_includes_group_position_and_enrollable() -> None:
    assert "group_position" in schemas.Course.model_fields
    assert "enrollable" in schemas.Course.model_fields


def test_existing_course_access_regression_still_documents_noncanonical_group_position_case() -> None:
    authority_test = (
        Path(__file__).resolve().parent / "test_course_access_authority.py"
    ).read_text(encoding="utf-8")

    assert (
        "test_required_source_purchase_ignores_group_position_and_sellable"
        in authority_test
    )
