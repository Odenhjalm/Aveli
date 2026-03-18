import test from "node:test";
import assert from "node:assert/strict";

import { buildRecoveryMutationPlan, filterSafeAutoRecoverRows } from "../src/storage-recovery-pilot.js";
import type { MediaRepairPlanRow, StorageRecoveryReportRow } from "../src/types.js";

function makePlanRow(overrides: Partial<MediaRepairPlanRow> = {}): MediaRepairPlanRow {
  return {
    course_id: "course-1",
    lesson_id: "lesson-1",
    lesson_media_id: "lesson-media-1",
    media_object_id: "media-object-1",
    media_asset_id: null,
    bucket: "public-media",
    storage_path: "legacy/path.png",
    content_type: "image/png",
    byte_size: 1234,
    media_state: "legacy",
    created_at: "2026-03-12T00:00:00.000Z",
    reference_type: "media_object",
    is_inventory_in_scope: true,
    is_active: true,
    course_is_published: true,
    lesson_is_intro: false,
    lesson_media_kind: "image",
    lesson_storage_bucket: null,
    lesson_storage_path: null,
    media_object_bucket: "public-media",
    media_object_path: "legacy/path.png",
    media_object_content_type: "image/png",
    media_object_byte_size: 1234,
    media_object_original_name: "legacy.png",
    media_asset_type: null,
    media_asset_purpose: null,
    media_asset_source_bucket: null,
    media_asset_source_path: null,
    media_asset_original_content_type: null,
    media_asset_original_size_bytes: null,
    media_asset_stream_bucket: null,
    media_asset_stream_path: null,
    media_asset_ingest_format: null,
    media_asset_streaming_format: null,
    media_asset_codec: null,
    media_asset_error_message: null,
    storage_created_at: null,
    storage_updated_at: null,
    normalized_bucket: "public-media",
    normalized_storage_path: "legacy/path.png",
    canonical_object_exists: false,
    normalized_object_exists: false,
    source_object_exists: false,
    streaming_object_exists: false,
    safe_matching_media_asset_id: null,
    safe_matching_media_asset_count: 0,
    issue_type: "MISSING_IN_STORAGE",
    fix_strategy: "RECOVER_FROM_STORAGE_MATCH",
    repair_priority: 25,
    storage_recovery_classification: "SAFE_AUTO_RECOVER",
    storage_recovery_bucket: "public-media",
    storage_recovery_path: "lessons/lesson-1/images/recovered.png",
    storage_recovery_content_type: "image/png",
    storage_recovery_size_bytes: 1234,
    storage_recovery_confidence_score: 100,
    storage_recovery_match_reason: "same_lesson_folder",
    storage_recovery_candidate_count: 1,
    ...overrides,
  };
}

test("filterSafeAutoRecoverRows keeps only SAFE_AUTO_RECOVER rows", () => {
  const rows: StorageRecoveryReportRow[] = [
    {
      course_id: "course-1",
      lesson_id: "lesson-1",
      lesson_media_id: "safe-1",
      reference_type: "media_object",
      original_db_bucket: "public-media",
      original_db_path: "legacy/path.png",
      matched_storage_bucket: "public-media",
      matched_storage_path: "lessons/lesson-1/images/recovered.png",
      confidence_score: 100,
      classification: "SAFE_AUTO_RECOVER",
      match_reason: "same_lesson_folder",
      fix_strategy_before: "MANUAL_REUPLOAD_REQUIRED",
      fix_strategy_after: "RECOVER_FROM_STORAGE_MATCH",
    },
    {
      course_id: "course-1",
      lesson_id: "lesson-1",
      lesson_media_id: "ambiguous-1",
      reference_type: "media_object",
      original_db_bucket: "public-media",
      original_db_path: "legacy/path.png",
      matched_storage_bucket: "public-media",
      matched_storage_path: "lessons/lesson-1/images/recovered.png",
      confidence_score: 74,
      classification: "AMBIGUOUS_MATCH",
      match_reason: "same_filename",
      fix_strategy_before: "MANUAL_REUPLOAD_REQUIRED",
      fix_strategy_after: "MANUAL_REUPLOAD_REQUIRED",
    },
  ];

  const safe = filterSafeAutoRecoverRows(rows);
  assert.deepEqual(safe.map((row) => row.lesson_media_id), ["safe-1"]);
});

test("buildRecoveryMutationPlan targets media_objects for media_object references", () => {
  const mutation = buildRecoveryMutationPlan(makePlanRow());
  assert.equal(mutation.resource, "media_objects");
  assert.equal(mutation.target_id, "media-object-1");
  assert.deepEqual(mutation.patch, {
    storage_bucket: "public-media",
    storage_path: "lessons/lesson-1/images/recovered.png",
  });
  assert.match(mutation.sql, /^update app\.media_objects set /);
});

test("buildRecoveryMutationPlan targets lesson_media for direct references", () => {
  const mutation = buildRecoveryMutationPlan(makePlanRow({
    reference_type: "direct_storage_path",
    media_object_id: null,
    lesson_storage_bucket: "public-media",
    lesson_storage_path: "legacy/path.png",
  }));
  assert.equal(mutation.resource, "lesson_media");
  assert.equal(mutation.target_id, "lesson-media-1");
  assert.deepEqual(mutation.patch, {
    storage_bucket: "public-media",
    storage_path: "lessons/lesson-1/images/recovered.png",
  });
  assert.match(mutation.sql, /^update app\.lesson_media set /);
});

test("buildRecoveryMutationPlan targets streaming path for ready media_asset references", () => {
  const mutation = buildRecoveryMutationPlan(makePlanRow({
    reference_type: "media_asset",
    media_object_id: null,
    media_asset_id: "asset-1",
    media_state: "ready",
    media_asset_type: "image",
  }));
  assert.equal(mutation.resource, "media_assets");
  assert.equal(mutation.target_id, "asset-1");
  assert.deepEqual(mutation.patch, {
    streaming_storage_bucket: "public-media",
    streaming_object_path: "lessons/lesson-1/images/recovered.png",
  });
  assert.match(mutation.sql, /^update app\.media_assets set /);
});
