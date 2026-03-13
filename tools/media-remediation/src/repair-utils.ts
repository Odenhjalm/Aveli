import path from "node:path";

import type { CanonicalStorageReference, SafetyGroup, TranscodeTarget } from "./types.js";

const KNOWN_BUCKETS = new Set(["course-media", "public-media", "lesson-media", "seminar-media"]);
const UUID_PATTERN = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const LEGACY_KIND_SEGMENTS = "(?:audio|video|image|images|files|documents|document|pdf|other)";
const STORAGE_API_PREFIX_PATTERNS = [
  /^api\/files\//i,
  /^storage\/v1\/object\/public\//i,
  /^storage\/v1\/object\/sign\//i,
  /^storage\/v1\/object\/authenticated\//i,
  /^storage\/v1\/object\//i,
  /^object\/public\//i,
  /^object\/sign\//i,
  /^object\/authenticated\//i,
  /^object\//i,
];
const MEDIA_PIPELINE_PREFIX_PATTERN =
  /^media\/(?:source|derived)\/(?:audio|video|image|images|files|documents|document|pdf|other)\//i;
const LEGACY_LESSON_PATH_PATTERN = new RegExp(
  `^(?<course>${UUID_PATTERN})/(?<lesson>${UUID_PATTERN})/${LEGACY_KIND_SEGMENTS}/(?<filename>.+)$`,
  "i",
);
const CANONICAL_LESSON_PATH_PATTERN = new RegExp(
  `^courses/(?<course>${UUID_PATTERN})/lessons/(?<lesson>${UUID_PATTERN})/${LEGACY_KIND_SEGMENTS}/(?<filename>.+)$`,
  "i",
);
const LESSON_ONLY_PATH_PATTERN = new RegExp(
  `^lessons/(?<lesson>${UUID_PATTERN})/${LEGACY_KIND_SEGMENTS}/(?<filename>.+)$`,
  "i",
);

function safelyDecodeURIComponent(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function lowercaseExtension(storagePath: string): string {
  const parsed = path.posix.parse(storagePath);
  if (parsed.ext === "") {
    return storagePath;
  }
  const prefix = parsed.dir === "" ? "" : `${parsed.dir}/`;
  return `${prefix}${parsed.name}${parsed.ext.toLowerCase()}`;
}

function normalizeBucket(value: string | null | undefined): string | null {
  const normalized = (value ?? "").trim().replace(/^\/+|\/+$/g, "");
  return normalized === "" ? null : normalized;
}

function normalizePath(value: string | null | undefined): string | null {
  const raw = (value ?? "").trim();
  if (raw === "") {
    return null;
  }
  let candidate = raw.replaceAll("\\", "/");
  try {
    if (/^https?:\/\//i.test(candidate)) {
      const parsed = new URL(candidate);
      candidate = parsed.pathname;
    }
  } catch {
    // Keep the raw string when URL parsing fails.
  }
  candidate = safelyDecodeURIComponent(candidate);
  candidate = candidate.replace(/^\/+/, "");
  candidate = candidate.replace(/\/{2,}/g, "/");
  for (const prefix of [
    "api/files/",
    "storage/v1/object/public/",
    "storage/v1/object/sign/",
    "object/public/",
    "object/sign/",
  ]) {
    if (candidate.startsWith(prefix)) {
      candidate = candidate.slice(prefix.length);
      break;
    }
  }
  return lowercaseExtension(candidate.replace(/^\/+/, "").replace(/\/{2,}/g, "/"));
}

export function normalizeStoragePath(value: string | null | undefined): string | null {
  const raw = (value ?? "").trim();
  if (raw === "") {
    return null;
  }

  let candidate = raw.replaceAll("\\", "/");
  try {
    if (/^https?:\/\//i.test(candidate)) {
      const parsed = new URL(candidate);
      candidate = parsed.pathname;
    }
  } catch {
    // Keep the raw string when URL parsing fails.
  }

  candidate = safelyDecodeURIComponent(candidate).trim();
  candidate = candidate.replace(/^\/+/, "");
  candidate = candidate.replace(/\/{2,}/g, "/");

  for (const pattern of STORAGE_API_PREFIX_PATTERNS) {
    if (pattern.test(candidate)) {
      candidate = candidate.replace(pattern, "");
      break;
    }
  }

  const pathSegments = candidate.split("/");
  if (pathSegments.length > 1 && KNOWN_BUCKETS.has(pathSegments[0] ?? "")) {
    candidate = pathSegments.slice(1).join("/");
  }

  candidate = candidate.replace(MEDIA_PIPELINE_PREFIX_PATTERN, "");

  const canonicalMatch = candidate.match(CANONICAL_LESSON_PATH_PATTERN);
  if (canonicalMatch?.groups) {
    candidate = `courses/${canonicalMatch.groups["course"]}/lessons/${canonicalMatch.groups["lesson"]}/${canonicalMatch.groups["filename"]}`;
  } else {
    const legacyMatch = candidate.match(LEGACY_LESSON_PATH_PATTERN);
    if (legacyMatch?.groups) {
      candidate = `courses/${legacyMatch.groups["course"]}/lessons/${legacyMatch.groups["lesson"]}/${legacyMatch.groups["filename"]}`;
    } else {
      const lessonOnlyMatch = candidate.match(LESSON_ONLY_PATH_PATTERN);
      if (lessonOnlyMatch?.groups) {
        candidate = `lessons/${lessonOnlyMatch.groups["lesson"]}/${lessonOnlyMatch.groups["filename"]}`;
      }
    }
  }

  candidate = candidate.replace(/\/{2,}/g, "/").replace(/^\/+/, "");
  if (candidate === "") {
    return null;
  }
  return lowercaseExtension(candidate);
}

export function normalizeMediaKind(value: string | null | undefined): string | null {
  const normalized = (value ?? "").trim().toLowerCase();
  if (normalized === "") {
    return null;
  }
  if (normalized === "pdf") {
    return "document";
  }
  return normalized;
}

export function areMediaKindsCompatible(input: {
  lessonMediaKind: string | null | undefined;
  mediaAssetType: string | null | undefined;
}): boolean {
  const lessonMediaKind = normalizeMediaKind(input.lessonMediaKind);
  const mediaAssetType = normalizeMediaKind(input.mediaAssetType);
  if (lessonMediaKind === null || mediaAssetType === null) {
    return true;
  }
  return lessonMediaKind === mediaAssetType;
}

export function hasCompatibleExtension(input: {
  lessonMediaKind: string | null | undefined;
  storagePath: string | null | undefined;
}): boolean {
  const lessonMediaKind = normalizeMediaKind(input.lessonMediaKind);
  const extension = path.posix.extname(normalizePath(input.storagePath) ?? "").toLowerCase();
  if (lessonMediaKind === null || extension === "") {
    return false;
  }
  if (lessonMediaKind === "image") {
    return [".jpg", ".jpeg", ".png", ".gif", ".bmp"].includes(extension);
  }
  if (lessonMediaKind === "audio") {
    return [".mp3", ".m4a", ".aac", ".ogg", ".oga", ".opus", ".flac", ".wav", ".wave", ".weba", ".webm"].includes(extension);
  }
  if (lessonMediaKind === "video") {
    return [".mp4", ".mov", ".m4v", ".webm"].includes(extension);
  }
  if (lessonMediaKind === "document") {
    return extension === ".pdf";
  }
  return false;
}

export function hasCompatibleMime(input: {
  lessonMediaKind: string | null | undefined;
  contentType: string | null | undefined;
}): boolean {
  const lessonMediaKind = normalizeMediaKind(input.lessonMediaKind);
  const contentType = (input.contentType ?? "").trim().toLowerCase();
  if (lessonMediaKind === null || contentType === "") {
    return false;
  }
  if (lessonMediaKind === "image") {
    return ["image/jpeg", "image/png", "image/gif", "image/bmp"].includes(contentType);
  }
  if (lessonMediaKind === "audio") {
    return [
      "audio/mpeg",
      "audio/mp3",
      "audio/mp4",
      "audio/aac",
      "audio/ogg",
      "audio/flac",
      "audio/wav",
      "audio/x-wav",
      "audio/wave",
      "audio/vnd.wave",
      "audio/webm",
    ].includes(contentType);
  }
  if (lessonMediaKind === "video") {
    return ["video/mp4", "video/quicktime", "video/webm"].includes(contentType);
  }
  if (lessonMediaKind === "document") {
    return contentType === "application/pdf";
  }
  return false;
}

export function canonicalizeStoredReference(input: {
  bucket: string | null | undefined;
  path: string | null | undefined;
}): CanonicalStorageReference {
  let bucket = normalizeBucket(input.bucket);
  let storagePath = normalizePath(input.path);
  const reasons: string[] = [];
  let changed = false;

  if (storagePath === null) {
    return { bucket, path: null, changed, reasons };
  }

  const parts = storagePath.split("/");
  if (parts.length > 1 && KNOWN_BUCKETS.has(parts[0] ?? "")) {
    const prefixBucket = parts[0] ?? null;
    const remainder = parts.slice(1).join("/");
    if (prefixBucket !== bucket) {
      bucket = prefixBucket;
      reasons.push("bucket_prefix_reassigned_bucket");
      changed = true;
    }
    if (remainder !== storagePath) {
      storagePath = remainder;
      reasons.push("bucket_prefix_stripped");
      changed = true;
    }
  } else if (bucket !== null && storagePath.startsWith(`${bucket}/`)) {
    storagePath = storagePath.slice(bucket.length + 1);
    reasons.push("duplicate_bucket_prefix_stripped");
    changed = true;
  }

  return { bucket, path: storagePath, changed, reasons };
}

export function inferTranscodeTarget(input: {
  bucket: string | null | undefined;
  path: string | null | undefined;
  contentType: string | null | undefined;
  kind: string | null | undefined;
}): TranscodeTarget | null {
  const bucket = normalizeBucket(input.bucket);
  const sourcePath = normalizePath(input.path);
  const contentType = (input.contentType ?? "").trim().toLowerCase();
  const kind = (input.kind ?? "").trim().toLowerCase();

  if (bucket === null || sourcePath === null) {
    return null;
  }

  const parsed = path.posix.parse(sourcePath);
  if (contentType === "image/webp" || parsed.ext.toLowerCase() === ".webp") {
    return {
      bucket,
      sourcePath,
      targetPath: path.posix.join(parsed.dir, `${parsed.name}.repaired.jpg`),
      targetContentType: "image/jpeg",
      targetExtension: ".jpg",
    };
  }

  if (
    kind === "audio"
    && ![".mp3", ".m4a", ".aac", ".ogg", ".oga", ".opus", ".flac", ".wav", ".wave", ".weba", ".webm"].includes(parsed.ext.toLowerCase())
  ) {
    return {
      bucket,
      sourcePath,
      targetPath: path.posix.join(parsed.dir, `${parsed.name}.repaired.mp3`),
      targetContentType: "audio/mpeg",
      targetExtension: ".mp3",
    };
  }

  return null;
}

export function isSupportedPlaybackFormat(input: {
  kind: string | null | undefined;
  contentType: string | null | undefined;
  storagePath: string | null | undefined;
}): boolean {
  const kind = normalizeMediaKind(input.kind) ?? "";
  const contentType = (input.contentType ?? "").trim().toLowerCase();
  const extension = path.posix.extname(normalizePath(input.storagePath) ?? "").toLowerCase();

  if (kind === "image") {
    return !["image/webp", ".webp"].includes(contentType) && extension !== ".webp";
  }

  if (kind === "audio") {
    return (
      [
        "audio/mpeg",
        "audio/mp3",
        "audio/mp4",
        "audio/aac",
        "audio/ogg",
        "audio/flac",
        "audio/wav",
        "audio/x-wav",
        "audio/wave",
        "audio/vnd.wave",
        "audio/webm",
      ].includes(contentType)
      || [
        ".mp3",
        ".m4a",
        ".aac",
        ".ogg",
        ".oga",
        ".opus",
        ".flac",
        ".wav",
        ".wave",
        ".weba",
        ".webm",
      ].includes(extension)
    );
  }

  if (kind === "video") {
    return (
      ["video/mp4", "video/quicktime", "video/webm"].includes(contentType)
      || [".mp4", ".mov", ".m4v", ".webm"].includes(extension)
    );
  }

  if (kind === "document" || kind === "pdf") {
    return contentType === "application/pdf" || extension === ".pdf";
  }

  return true;
}

export function classifySafetyGroup(input: {
  detectedReason: string;
  referencedByActiveMedia: boolean;
  referencedByAnyMedia: boolean;
}): SafetyGroup {
  if (input.referencedByActiveMedia) {
    return "BLOCKED_BY_ACTIVE_REFERENCE";
  }
  if (
    !input.referencedByAnyMedia
    && ["orphaned_storage_object", "duplicate_or_obsolete_object"].includes(input.detectedReason)
  ) {
    return "SAFE_TO_QUARANTINE";
  }
  return "NEEDS_MANUAL_REVIEW";
}
