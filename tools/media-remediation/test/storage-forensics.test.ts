import test from "node:test";
import assert from "node:assert/strict";

import { analyzeStorageRecovery } from "../src/storage-forensics.js";
import type { MediaRepairPlanRow, StorageCatalogEntry } from "../src/types.js";

function makePlanRow(overrides: Partial<MediaRepairPlanRow> = {}): MediaRepairPlanRow {
  return {
    course_id: "course-1",
    lesson_id: "lesson-1",
    lesson_media_id: "lesson-media-1",
    media_object_id: "media-object-1",
    media_asset_id: null,
    bucket: "course-media",
    storage_path: "course-1/lesson-1/audio/Example Audio.mp3",
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
    lesson_storage_path: "course-1/lesson-1/audio/Example Audio.mp3",
    media_object_bucket: "course-media",
    media_object_path: "course-1/lesson-1/audio/Example Audio.mp3",
    media_object_content_type: "audio/mpeg",
    media_object_byte_size: 1234,
    media_object_original_name: "Example Audio.mp3",
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
    normalized_storage_path: "course-1/lesson-1/audio/Example Audio.mp3",
    canonical_object_exists: false,
    normalized_object_exists: false,
    source_object_exists: false,
    streaming_object_exists: false,
    safe_matching_media_asset_id: null,
    safe_matching_media_asset_count: 0,
    issue_type: "MISSING_IN_STORAGE",
    fix_strategy: "MANUAL_REUPLOAD_REQUIRED",
    repair_priority: 25,
    ...overrides,
  };
}

function makeCatalogEntry(overrides: Partial<StorageCatalogEntry> = {}): StorageCatalogEntry {
  return {
    bucket: "course-media",
    storage_path: "archive/course-1/lesson-1/audio/Example Audio.mp3",
    filename: "Example Audio.mp3",
    extension: ".mp3",
    size: 1234,
    content_type: "audio/mpeg",
    mime_family: "audio",
    etag: "etag-1",
    created_at: "2026-03-12T00:00:00.000Z",
    normalized_filename: "example-audio.mp3",
    course_id_hint: "course-1",
    lesson_id_hint: "lesson-1",
    ...overrides,
  };
}

test("analyzeStorageRecovery promotes unique strong media_object matches to RECOVER_FROM_STORAGE_MATCH", () => {
  const analysis = analyzeStorageRecovery(
    [makePlanRow()],
    [makeCatalogEntry()],
  );

  assert.equal(analysis.rows[0]?.fix_strategy, "RECOVER_FROM_STORAGE_MATCH");
  assert.equal(analysis.rows[0]?.storage_recovery_classification, "SAFE_AUTO_RECOVER");
  assert.equal(analysis.reportRows[0]?.classification, "SAFE_AUTO_RECOVER");
  assert.equal(analysis.summary.safe_auto_recover_count, 1);
});

test("analyzeStorageRecovery keeps uploaded media_asset rows as probable matches even with strong signals", () => {
  const analysis = analyzeStorageRecovery(
    [makePlanRow({
      reference_type: "media_asset",
      media_object_id: null,
      media_asset_id: "asset-1",
      media_state: "uploaded",
      media_asset_type: "audio",
      media_asset_source_bucket: "course-media",
      media_asset_source_path: "course-1/lesson-1/audio/Example Audio.mp3",
    })],
    [makeCatalogEntry({ storage_path: "course-1/lesson-1/audio/Example Audio.mp3" })],
  );

  assert.equal(analysis.rows[0]?.fix_strategy, "MANUAL_REUPLOAD_REQUIRED");
  assert.equal(analysis.rows[0]?.storage_recovery_classification, "PROBABLE_MATCH");
  assert.equal(analysis.summary.safe_auto_recover_count, 0);
  assert.equal(analysis.summary.probable_match_count, 1);
});

test("analyzeStorageRecovery marks close competing matches as ambiguous", () => {
  const analysis = analyzeStorageRecovery(
    [makePlanRow()],
    [
      makeCatalogEntry({ storage_path: "archive/course-1/lesson-1/audio/Example Audio.mp3" }),
      makeCatalogEntry({ storage_path: "recovered/course-1/lesson-1/audio/Example Audio.mp3", etag: "etag-2" }),
    ],
  );

  assert.equal(analysis.rows[0]?.fix_strategy, "MANUAL_REUPLOAD_REQUIRED");
  assert.equal(analysis.rows[0]?.storage_recovery_classification, "AMBIGUOUS_MATCH");
  assert.equal(analysis.summary.ambiguous_match_count, 1);
});

test("analyzeStorageRecovery reports no match when no candidate is compatible", () => {
  const analysis = analyzeStorageRecovery(
    [makePlanRow({ lesson_media_kind: "document", content_type: "application/pdf", storage_path: "course-1/lesson-1/document/guide.pdf" })],
    [makeCatalogEntry({ filename: "image.png", extension: ".png", content_type: "image/png", mime_family: "image" })],
  );

  assert.equal(analysis.rows[0]?.storage_recovery_classification, "NO_MATCH");
  assert.equal(analysis.summary.no_match_count, 1);
});

test("analyzeStorageRecovery promotes unique same-lesson image matches when size and mime agree", () => {
  const analysis = analyzeStorageRecovery(
    [makePlanRow({
      lesson_media_kind: "image",
      content_type: "image/png",
      storage_path: "course-1/lesson-1/image/legacy-reference.png",
      bucket: "public-media",
      byte_size: 4321,
      media_object_bucket: "public-media",
      media_object_path: "course-1/lesson-1/image/legacy-reference.png",
      media_object_content_type: "image/png",
      media_object_byte_size: 4321,
      media_object_original_name: "legacy-reference.png",
    })],
    [makeCatalogEntry({
      bucket: "public-media",
      storage_path: "lessons/lesson-1/images/recovered-reference.png",
      filename: "recovered-reference.png",
      extension: ".png",
      size: 4321,
      content_type: "image/png",
      mime_family: "image",
      normalized_filename: "recovered-reference.png",
    })],
  );

  assert.equal(analysis.rows[0]?.fix_strategy, "RECOVER_FROM_STORAGE_MATCH");
  assert.equal(analysis.rows[0]?.storage_recovery_classification, "SAFE_AUTO_RECOVER");
  assert.match(analysis.rows[0]?.storage_recovery_match_reason ?? "", /same_lesson_folder/);
});
