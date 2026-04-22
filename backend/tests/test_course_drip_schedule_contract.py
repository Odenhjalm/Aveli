from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_course_drip_schedule_contract_exists_and_is_cross_referenced() -> None:
    drip_contract = (
        ROOT / "actual_truth" / "contracts" / "course_drip_schedule_contract.md"
    ).read_text(encoding="utf-8")
    domain_spec = (
        ROOT / "actual_truth" / "contracts" / "AVELI_COURSE_DOMAIN_SPEC.md"
    ).read_text(encoding="utf-8")
    editor_contract = (
        ROOT / "actual_truth" / "contracts" / "course_lesson_editor_contract.md"
    ).read_text(encoding="utf-8")

    assert "# COURSE DRIP SCHEDULE CONTRACT" in drip_contract
    assert "legacy uniform drip semantics" in drip_contract
    assert "custom lesson-offset drip semantics" in drip_contract
    assert "mode resolution" in drip_contract
    assert "post-enrollment schedule lock semantics" in drip_contract

    assert "course_drip_schedule_contract.md" in domain_spec
    assert "course_drip_schedule_contract.md" in editor_contract
    assert "This contract owns editor structure read/write shapes only." in editor_contract
