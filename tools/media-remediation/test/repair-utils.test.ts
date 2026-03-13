import test from "node:test";
import assert from "node:assert/strict";

import {
  canonicalizeStoredReference,
  classifySafetyGroup,
  inferTranscodeTarget,
  isSupportedPlaybackFormat,
  normalizeStoragePath,
} from "../src/repair-utils.js";

test("canonicalizeStoredReference strips duplicate bucket prefixes", () => {
  assert.deepEqual(
    canonicalizeStoredReference({
      bucket: "course-media",
      path: "course-media/path/to/file.mp3",
    }),
    {
      bucket: "course-media",
      path: "path/to/file.mp3",
      changed: true,
      reasons: ["bucket_prefix_stripped"],
    },
  );
});

test("normalizeStoragePath trims, decodes, collapses slashes, and lowercases the extension", () => {
  assert.equal(
    normalizeStoragePath(" /storage/v1/object/public/course-media/courses/demo%20file//lesson%20one/Track.M4A "),
    "courses/demo file/lesson one/Track.m4a",
  );
});

test("normalizeStoragePath canonicalizes legacy course and lesson layouts", () => {
  assert.equal(
    normalizeStoragePath(
      "fa8f3753-cf21-4144-bf90-f25eaefc5c47/c5480dac-c2cd-4c4b-8124-46177c9435ff/audio/4eb2f0a238e345afb7eb0a8e2dcb9aea_symboliska-farger.M4A",
    ),
    "courses/fa8f3753-cf21-4144-bf90-f25eaefc5c47/lessons/c5480dac-c2cd-4c4b-8124-46177c9435ff/4eb2f0a238e345afb7eb0a8e2dcb9aea_symboliska-farger.m4a",
  );
});

test("canonicalizeStoredReference can reassign bucket from storage path", () => {
  assert.deepEqual(
    canonicalizeStoredReference({
      bucket: "course-media",
      path: "public-media/lesson/image.png",
    }),
    {
      bucket: "public-media",
      path: "lesson/image.png",
      changed: true,
      reasons: ["bucket_prefix_reassigned_bucket", "bucket_prefix_stripped"],
    },
  );
});

test("inferTranscodeTarget generates deterministic repaired image target", () => {
  assert.deepEqual(
    inferTranscodeTarget({
      bucket: "public-media",
      path: "lessons/demo.webp",
      contentType: "image/webp",
      kind: "image",
    }),
    {
      bucket: "public-media",
      sourcePath: "lessons/demo.webp",
      targetPath: "lessons/demo.repaired.jpg",
      targetContentType: "image/jpeg",
      targetExtension: ".jpg",
    },
  );
});

test("isSupportedPlaybackFormat rejects webp", () => {
  assert.equal(
    isSupportedPlaybackFormat({
      kind: "image",
      contentType: "image/webp",
      storagePath: "lessons/demo.webp",
    }),
    false,
  );
});

test("classifySafetyGroup blocks active references before anything else", () => {
  assert.equal(
    classifySafetyGroup({
      detectedReason: "orphaned_storage_object",
      referencedByActiveMedia: true,
      referencedByAnyMedia: true,
    }),
    "BLOCKED_BY_ACTIVE_REFERENCE",
  );
});
