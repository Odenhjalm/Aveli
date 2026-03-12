import test from "node:test";
import assert from "node:assert/strict";

import { PostRepairVerifier } from "../src/post-repair-verifier.js";
import type { ActiveMediaInventoryRow, MediaRepairPlanRow } from "../src/types.js";

function makeInventoryRow(overrides: Partial<ActiveMediaInventoryRow> = {}): ActiveMediaInventoryRow {
  return {
    course_id: "course-1",
    lesson_id: "lesson-1",
    lesson_media_id: "lesson-media-1",
    media_object_id: "media-object-1",
    media_asset_id: null,
    bucket: "public-media",
    storage_path: "course-1/lesson-1/image/legacy-reference.png",
    content_type: "image/png",
    byte_size: 4321,
    media_state: "legacy",
    created_at: "2026-03-12T00:00:00.000Z",
    reference_type: "media_object",
    is_inventory_in_scope: true,
    is_active: true,
    course_is_published: true,
    lesson_is_intro: false,
    lesson_media_kind: "image",
    lesson_storage_bucket: "public-media",
    lesson_storage_path: "course-1/lesson-1/image/legacy-reference.png",
    media_object_bucket: "public-media",
    media_object_path: "course-1/lesson-1/image/legacy-reference.png",
    media_object_content_type: "image/png",
    media_object_byte_size: 4321,
    media_object_original_name: "legacy-reference.png",
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
    ...overrides,
  };
}

function makePlanRow(overrides: Partial<MediaRepairPlanRow> = {}): MediaRepairPlanRow {
  return {
    ...makeInventoryRow(),
    normalized_bucket: "public-media",
    normalized_storage_path: "course-1/lesson-1/image/legacy-reference.png",
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
    storage_recovery_path: "lessons/lesson-1/images/recovered-reference.png",
    storage_recovery_content_type: "image/png",
    storage_recovery_size_bytes: 4321,
    storage_recovery_confidence_score: 100,
    storage_recovery_match_reason: "same_lesson_folder,same_file_size",
    storage_recovery_candidate_count: 1,
    ...overrides,
  };
}

test("PostRepairVerifier can verify dry-run recovery targets using simulated plan state", async () => {
  const verifier = new PostRepairVerifier(
    {
      probeObject: async (bucket: string, path: string) => ({
        bucket,
        path,
        exists: bucket === "public-media" && path === "lessons/lesson-1/images/recovered-reference.png",
        statusCode: 200,
        contentType: "image/png",
        contentLength: 4321,
      }),
    } as never,
    { info() {} } as never,
    1,
  );

  const [result] = await verifier.verify(
    [makeInventoryRow()],
    new Map([["lesson-media-1", makePlanRow()]]),
    { simulatePlannedRepairs: true },
  );

  assert.equal(result?.status, "PASS");
  assert.equal(result?.details.storagePath, "lessons/lesson-1/images/recovered-reference.png");
  assert.equal(result?.details.simulatedReferenceApplied, true);
});
