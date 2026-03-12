import test from "node:test";
import assert from "node:assert/strict";

import {
  buildBackfillPilotCandidates,
  renderBackfillMutationSql,
  resolveBackfillTargetReference,
} from "../src/backfill-media-asset-pilot.js";
import type { MediaAssetRecord, MediaRepairPlanRow } from "../src/types.js";

function makePlanRow(overrides: Partial<MediaRepairPlanRow> = {}): MediaRepairPlanRow {
  return {
    course_id: "course-1",
    lesson_id: "lesson-1",
    lesson_media_id: "lesson-media-1",
    media_object_id: "media-object-1",
    media_asset_id: null,
    bucket: "course-media",
    storage_path: "course-1/lesson-1/audio/example.mp3",
    content_type: "audio/mpeg",
    byte_size: 1234,
    media_state: "legacy",
    created_at: "2026-03-12T00:00:00.000Z",
    reference_type: "media_object",
    is_inventory_in_scope: true,
    is_active: true,
    course_is_published: true,
    lesson_is_intro: false,
    lesson_media_kind: "audio",
    lesson_storage_bucket: "course-media",
    lesson_storage_path: "course-1/lesson-1/audio/example.mp3",
    media_object_bucket: "course-media",
    media_object_path: "course-1/lesson-1/audio/example.mp3",
    media_object_content_type: "audio/mpeg",
    media_object_byte_size: 1234,
    media_object_original_name: "example.mp3",
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
    normalized_bucket: "course-media",
    normalized_storage_path: "course-1/lesson-1/audio/example.mp3",
    canonical_object_exists: false,
    normalized_object_exists: false,
    source_object_exists: false,
    streaming_object_exists: false,
    safe_matching_media_asset_id: "asset-1",
    safe_matching_media_asset_count: 1,
    issue_type: "MISSING_IN_STORAGE",
    fix_strategy: "BACKFILL_MEDIA_ASSET",
    repair_priority: 25,
    ...overrides,
  };
}

function makeMediaAsset(overrides: Partial<MediaAssetRecord> = {}): MediaAssetRecord {
  return {
    id: "asset-1",
    course_id: "course-1",
    lesson_id: "lesson-1",
    media_type: "audio",
    purpose: "lesson_audio",
    state: "ready",
    storage_bucket: "course-media",
    original_object_path: "media/source/audio/course-1/example.wav",
    original_content_type: "audio/wav",
    original_size_bytes: 4321,
    streaming_storage_bucket: "course-media",
    streaming_object_path: "media/derived/audio/course-1/example.mp3",
    ingest_format: "wav",
    streaming_format: "mp3",
    codec: "mp3",
    error_message: null,
    created_at: "2026-03-12T00:00:00.000Z",
    updated_at: "2026-03-12T00:00:00.000Z",
    ...overrides,
  };
}

test("resolveBackfillTargetReference prefers streaming path for ready assets", () => {
  assert.deepEqual(
    resolveBackfillTargetReference(makeMediaAsset(), "audio"),
    {
      bucket: "course-media",
      path: "media/derived/audio/course-1/example.mp3",
      contentType: "audio/mpeg",
    },
  );
});

test("buildBackfillPilotCandidates excludes incompatible media kinds", () => {
  const candidates = buildBackfillPilotCandidates(
    [makePlanRow({ lesson_media_kind: "image" })],
    [makeMediaAsset({ media_type: "audio" })],
  );
  assert.equal(candidates.length, 0);
});

test("renderBackfillMutationSql matches the expected mutation pattern", () => {
  assert.equal(
    renderBackfillMutationSql(makePlanRow({
      lesson_media_id: "lesson-media-99",
      safe_matching_media_asset_id: "asset-99",
    })),
    "update app.lesson_media set media_asset_id = 'asset-99' where id = 'lesson-media-99' and media_asset_id is null;",
  );
});
