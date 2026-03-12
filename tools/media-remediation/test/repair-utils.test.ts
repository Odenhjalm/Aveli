import test from "node:test";
import assert from "node:assert/strict";

import {
  canonicalizeStoredReference,
  classifySafetyGroup,
  inferTranscodeTarget,
  isSupportedPlaybackFormat,
  normalizeFilenameLabelForMatch,
  normalizeFilenameForMatch,
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

test("normalizeFilenameForMatch lowercases, strips diacritics, decodes url encoding, and collapses separators", () => {
  assert.equal(
    normalizeFilenameForMatch("Änglar%20%20-%20övning__vind.wav"),
    "anglar-ovning-vind.wav",
  );
});

test("normalizeFilenameLabelForMatch strips generated prefixes before normalizing", () => {
  assert.equal(
    normalizeFilenameLabelForMatch("a0c26c36f0b44ad3818e2905b7119403_Änglar - övning.wav"),
    "anglar-ovning",
  );
});
