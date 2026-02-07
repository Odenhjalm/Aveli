from scripts import media_doctor


def test_media_doctor_format_report_is_deterministic():
    summary = {"b": 2, "a": {"z": 1, "y": 2}}
    assert (
        media_doctor.format_report(summary)
        == '{\n  "a": {\n    "y": 2,\n    "z": 1\n  },\n  "b": 2\n}'
    )


def test_media_doctor_build_report_is_deterministic_and_has_required_fields():
    report = media_doctor.build_report(
        legacy_records=[],
        pipeline_records=[],
        orphan_records=[],
        buckets={"course-media", "public-media", "lesson-media"},
    )
    assert "summary" in report
    assert "records" in report
    assert "generated_at" not in report["summary"]
    assert report["summary"]["total_records"] == 0


def test_media_doctor_orphan_records_are_flagged():
    orphan_object_rows = [
        media_doctor.OrphanMediaObjectRow(
            media_object_id="obj-1",
            storage_bucket="course-media",
            storage_path="lesson-1/demo.mp4",
            content_type=None,
            original_name=None,
            byte_size=None,
        )
    ]
    orphan_asset_rows = [
        media_doctor.OrphanMediaAssetRow(
            media_asset_id="asset-1",
            media_state="ready",
            storage_bucket="course-media",
            original_object_path="lessons/lesson-1/source.wav",
            streaming_object_path="lessons/lesson-1/derived.mp3",
            original_filename="source.wav",
            error_message=None,
        )
    ]

    object_records = media_doctor.build_orphan_object_records(
        orphan_object_rows,
        existence={},
        buckets={"course-media", "public-media", "lesson-media"},
        storage_table_available=False,
    )
    asset_records = media_doctor.build_orphan_asset_records(
        orphan_asset_rows,
        existence={},
        storage_table_available=False,
    )

    assert object_records[0].category == "orphan"
    assert object_records[0].status == "orphaned"
    assert object_records[0].recommended_action == "safe_to_delete"

    assert asset_records[0].category == "orphan"
    assert asset_records[0].status == "orphaned"
    assert asset_records[0].recommended_action == "safe_to_delete"
