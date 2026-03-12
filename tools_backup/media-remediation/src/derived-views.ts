import path from "node:path";

import {
  areMediaKindsCompatible,
  canonicalizeStoredReference,
  hasCompatibleExtension,
  hasCompatibleMime,
} from "./repair-utils.js";
import type { SupabaseAdminClient } from "./postgrest.js";
import { loadStorageObjectsViaApi } from "./storage-catalog.js";
import type {
  ActiveMediaInventoryRow,
  CourseRecord,
  LessonMediaRecord,
  LessonRecord,
  MediaAssetRecord,
  MediaObjectRecord,
  MediaRepairPlanRow,
  StorageObjectRecord,
} from "./types.js";

interface StorageMetaRecord {
  storage_created_at: string | null;
  storage_updated_at: string | null;
  storage_content_type: string | null;
  storage_size: number | null;
}

interface FallbackSnapshot {
  courses: CourseRecord[];
  lessons: LessonRecord[];
  lessonMediaRows: LessonMediaRecord[];
  mediaObjects: MediaObjectRecord[];
  mediaAssets: MediaAssetRecord[];
  storageObjects: StorageObjectRecord[];
}

const KNOWN_BUCKETS = new Set(["course-media", "public-media", "lesson-media", "seminar-media"]);

const snapshotCache = new Map<string, Promise<FallbackSnapshot>>();
const inventoryCache = new Map<string, Promise<ActiveMediaInventoryRow[]>>();
const repairPlanCache = new Map<string, Promise<MediaRepairPlanRow[]>>();

function cacheKey(courseIds: string[]): string {
  return courseIds.length === 0 ? "*" : [...courseIds].sort().join(",");
}

function lower(value: string | null | undefined): string {
  return (value ?? "").trim().toLowerCase();
}

function normalizedText(value: string | null | undefined): string | null {
  const trimmed = (value ?? "").trim();
  return trimmed === "" ? null : trimmed;
}

function firstDefined<T>(...values: Array<T | null | undefined>): T | null {
  for (const value of values) {
    if (value !== null && value !== undefined && value !== "") {
      return value;
    }
  }
  return null;
}

function storageKey(bucket: string | null | undefined, storagePath: string | null | undefined): string | null {
  const normalizedBucket = normalizedText(bucket);
  const normalizedPath = normalizedText(storagePath);
  if (!normalizedBucket || !normalizedPath) {
    return null;
  }
  return `${normalizedBucket}:${normalizedPath}`;
}

function extractStorageMeta(storageObject: StorageObjectRecord): StorageMetaRecord {
  const metadata = storageObject.metadata ?? {};
  const rawContentType = metadata.mimetype;
  const rawSize = metadata.size;
  const storage_content_type =
    typeof rawContentType === "string" && rawContentType.trim() !== "" ? rawContentType.trim() : null;
  let storage_size: number | null = null;
  if (typeof rawSize === "number" && Number.isFinite(rawSize)) {
    storage_size = rawSize;
  } else if (typeof rawSize === "string" && rawSize.trim() !== "") {
    const parsed = Number.parseInt(rawSize, 10);
    storage_size = Number.isFinite(parsed) ? parsed : null;
  }
  return {
    storage_created_at: storageObject.created_at,
    storage_updated_at: storageObject.updated_at,
    storage_content_type,
    storage_size,
  };
}

function normalizePathFromUrl(storagePath: string | null): {
  urlNormalizedPath: string | null;
  apiNormalizedPath: string | null;
} {
  if (storagePath === null) {
    return { urlNormalizedPath: null, apiNormalizedPath: null };
  }
  const trimmed = storagePath.trim();
  if (trimmed === "") {
    return { urlNormalizedPath: null, apiNormalizedPath: null };
  }

  let urlNormalizedPath: string | null;
  if (/^https?:\/\//i.test(trimmed)) {
    urlNormalizedPath = trimmed.replace(/^https?:\/\/[^/]+\//i, "");
  } else {
    urlNormalizedPath = trimmed.replace(/^\/+/, "");
  }

  let apiNormalizedPath: string | null = null;
  const candidate = urlNormalizedPath.replace(/^\/+/, "");
  if (candidate.startsWith("storage/v1/object/public/")) {
    apiNormalizedPath = candidate.replace(/^storage\/v1\/object\/public\/[^/]+\//, "");
  } else if (candidate.startsWith("storage/v1/object/sign/")) {
    apiNormalizedPath = candidate.replace(/^storage\/v1\/object\/sign\/[^/]+\//, "");
  } else if (candidate.startsWith("object/public/")) {
    apiNormalizedPath = candidate.replace(/^object\/public\/[^/]+\//, "");
  } else if (candidate.startsWith("object/sign/")) {
    apiNormalizedPath = candidate.replace(/^object\/sign\/[^/]+\//, "");
  }

  return { urlNormalizedPath, apiNormalizedPath };
}

function sortInventoryRows<T extends { course_id: string; lesson_id: string; created_at: string }>(rows: T[]): T[] {
  return [...rows].sort((left, right) => {
    const byCourse = left.course_id.localeCompare(right.course_id);
    if (byCourse !== 0) {
      return byCourse;
    }
    const byLesson = left.lesson_id.localeCompare(right.lesson_id);
    if (byLesson !== 0) {
      return byLesson;
    }
    return left.created_at.localeCompare(right.created_at);
  });
}

function isMissingViewError(error: unknown, resource: string): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("PGRST205") && message.includes(resource);
}

async function loadFallbackSnapshot(
  client: SupabaseAdminClient,
  courseIds: string[],
): Promise<FallbackSnapshot> {
  const key = cacheKey(courseIds);
  const existing = snapshotCache.get(key);
  if (existing) {
    return existing;
  }

  const promise = (async (): Promise<FallbackSnapshot> => {
    const courseFilters = courseIds.length === 0 ? [] : [{ column: "id", operator: "in" as const, value: courseIds }];
    const lessonFilters = courseIds.length === 0 ? [] : [{ column: "course_id", operator: "in" as const, value: courseIds }];

    const [courses, lessons, lessonMediaRows, mediaObjects, mediaAssets, storageObjects] = await Promise.all([
      client.listAll<CourseRecord>("courses", {
        select: "id,is_published",
        filters: courseFilters,
        order: "id.asc",
      }),
      client.listAll<LessonRecord>("lessons", {
        select: "id,course_id,is_intro",
        filters: lessonFilters,
        order: "id.asc",
      }),
      client.listAll<LessonMediaRecord>("lesson_media", {
        select: "id,lesson_id,kind,storage_bucket,storage_path,media_id,media_asset_id,created_at",
        order: "created_at.asc",
      }),
      client.listAll<MediaObjectRecord>("media_objects", {
        select: "id,storage_bucket,storage_path,content_type,byte_size,original_name,created_at",
        order: "created_at.asc",
      }),
      client.listAll<MediaAssetRecord>("media_assets", {
        select: [
          "id",
          "course_id",
          "lesson_id",
          "media_type",
          "purpose",
          "state",
          "storage_bucket",
          "original_object_path",
          "original_content_type",
          "original_size_bytes",
          "streaming_storage_bucket",
          "streaming_object_path",
          "ingest_format",
          "streaming_format",
          "codec",
          "error_message",
          "created_at",
          "updated_at",
        ].join(","),
        order: "created_at.asc",
      }),
      loadStorageObjectsViaApi(client),
    ]);

    return {
      courses,
      lessons,
      lessonMediaRows,
      mediaObjects,
      mediaAssets,
      storageObjects,
    };
  })();

  snapshotCache.set(key, promise);
  return promise;
}

export async function buildDerivedActiveMediaInventory(
  client: SupabaseAdminClient,
  options: { activeOnly: boolean; courseIds: string[] },
): Promise<ActiveMediaInventoryRow[]> {
  const key = cacheKey(options.courseIds);
  const cached = inventoryCache.get(key);
  const promise = cached ?? (async (): Promise<ActiveMediaInventoryRow[]> => {
    const snapshot = await loadFallbackSnapshot(client, options.courseIds);
    const courseMap = new Map(snapshot.courses.map((course) => [course.id, course]));
    const lessonMap = new Map(snapshot.lessons.map((lesson) => [lesson.id, lesson]));
    const mediaObjectMap = new Map(snapshot.mediaObjects.map((mediaObject) => [mediaObject.id, mediaObject]));
    const mediaAssetMap = new Map(snapshot.mediaAssets.map((mediaAsset) => [mediaAsset.id, mediaAsset]));
    const storageMetaMap = new Map(
      snapshot.storageObjects
        .map((storageObject) => {
          const key = storageKey(storageObject.bucket_id, storageObject.name);
          return key ? [key, extractStorageMeta(storageObject)] as const : null;
        })
        .filter((entry): entry is readonly [string, StorageMetaRecord] => entry !== null),
    );

    const rows: ActiveMediaInventoryRow[] = [];

    for (const lessonMediaRow of snapshot.lessonMediaRows) {
      const lesson = lessonMap.get(lessonMediaRow.lesson_id);
      if (!lesson) {
        continue;
      }
      const course = courseMap.get(lesson.course_id);
      if (!course) {
        continue;
      }

      const mediaObject =
        lessonMediaRow.media_id !== null ? (mediaObjectMap.get(lessonMediaRow.media_id) ?? null) : null;
      const mediaAsset =
        lessonMediaRow.media_asset_id !== null ? (mediaAssetMap.get(lessonMediaRow.media_asset_id) ?? null) : null;

      const mediaAssetState = lower(mediaAsset?.state);
      const lessonMediaKind = lower(lessonMediaRow.kind);
      const reference_type =
        lessonMediaRow.media_asset_id !== null
          ? "media_asset"
          : lessonMediaRow.media_id !== null
            ? "media_object"
            : "direct_storage_path";

      const bucket =
        lessonMediaRow.media_asset_id !== null && mediaAssetState === "ready"
          ? firstDefined(
              normalizedText(mediaAsset?.streaming_storage_bucket),
              normalizedText(mediaAsset?.storage_bucket),
              normalizedText(mediaObject?.storage_bucket),
              normalizedText(lessonMediaRow.storage_bucket),
              "lesson-media",
            )
          : lessonMediaRow.media_asset_id !== null
            ? firstDefined(
                normalizedText(mediaAsset?.storage_bucket),
                normalizedText(mediaObject?.storage_bucket),
                normalizedText(lessonMediaRow.storage_bucket),
                "lesson-media",
              )
            : firstDefined(
                normalizedText(mediaObject?.storage_bucket),
                normalizedText(lessonMediaRow.storage_bucket),
                "lesson-media",
              );

      const storage_path =
        lessonMediaRow.media_asset_id !== null && mediaAssetState === "ready"
          ? firstDefined(
              normalizedText(mediaAsset?.streaming_object_path),
              normalizedText(mediaAsset?.original_object_path),
              normalizedText(mediaObject?.storage_path),
              normalizedText(lessonMediaRow.storage_path),
            )
          : lessonMediaRow.media_asset_id !== null
            ? firstDefined(
                normalizedText(mediaAsset?.original_object_path),
                normalizedText(mediaObject?.storage_path),
                normalizedText(lessonMediaRow.storage_path),
              )
            : firstDefined(
                normalizedText(mediaObject?.storage_path),
                normalizedText(lessonMediaRow.storage_path),
              );

      const storageMeta = storageMetaMap.get(storageKey(bucket, storage_path) ?? "") ?? null;
      const content_type = firstDefined(
        lessonMediaRow.media_asset_id !== null && mediaAssetState === "ready" && lower(mediaAsset?.media_type) === "audio"
          ? "audio/mpeg"
          : null,
        lessonMediaRow.media_asset_id !== null && mediaAssetState === "ready" && lower(mediaAsset?.media_type) === "image"
          ? "image/jpeg"
          : null,
        normalizedText(mediaAsset?.original_content_type),
        normalizedText(mediaObject?.content_type),
        storageMeta?.storage_content_type,
        ["document", "pdf"].includes(lessonMediaKind) ? "application/pdf" : null,
      );
      const byte_size = firstDefined(
        mediaObject?.byte_size ?? null,
        mediaAsset?.original_size_bytes ?? null,
        storageMeta?.storage_size ?? null,
      );

      rows.push({
        course_id: course.id,
        lesson_id: lesson.id,
        lesson_media_id: lessonMediaRow.id,
        media_object_id: lessonMediaRow.media_id,
        media_asset_id: lessonMediaRow.media_asset_id,
        bucket,
        storage_path,
        content_type,
        byte_size,
        media_state:
          lessonMediaRow.media_asset_id !== null && mediaAssetState !== ""
            ? mediaAssetState
            : lessonMediaRow.media_asset_id === null
              ? "legacy"
              : "unknown",
        created_at: lessonMediaRow.created_at,
        reference_type,
        is_inventory_in_scope: true,
        is_active: true,
        course_is_published: Boolean(course.is_published),
        lesson_is_intro: Boolean(lesson.is_intro),
        lesson_media_kind: lessonMediaKind === "" ? null : lessonMediaKind,
        lesson_storage_bucket: normalizedText(lessonMediaRow.storage_bucket),
        lesson_storage_path: normalizedText(lessonMediaRow.storage_path),
        media_object_bucket: normalizedText(mediaObject?.storage_bucket),
        media_object_path: normalizedText(mediaObject?.storage_path),
        media_object_content_type: normalizedText(mediaObject?.content_type),
        media_object_byte_size: mediaObject?.byte_size ?? null,
        media_object_original_name: normalizedText(mediaObject?.original_name),
        media_asset_type: lower(mediaAsset?.media_type) || null,
        media_asset_purpose: lower(mediaAsset?.purpose) || null,
        media_asset_source_bucket: normalizedText(mediaAsset?.storage_bucket),
        media_asset_source_path: normalizedText(mediaAsset?.original_object_path),
        media_asset_original_content_type: normalizedText(mediaAsset?.original_content_type),
        media_asset_original_size_bytes: mediaAsset?.original_size_bytes ?? null,
        media_asset_stream_bucket: normalizedText(mediaAsset?.streaming_storage_bucket),
        media_asset_stream_path: normalizedText(mediaAsset?.streaming_object_path),
        media_asset_ingest_format: lower(mediaAsset?.ingest_format) || null,
        media_asset_streaming_format: lower(mediaAsset?.streaming_format) || null,
        media_asset_codec: normalizedText(mediaAsset?.codec),
        media_asset_error_message: normalizedText(mediaAsset?.error_message),
        storage_created_at: storageMeta?.storage_created_at ?? null,
        storage_updated_at: storageMeta?.storage_updated_at ?? null,
      });
    }

    return sortInventoryRows(rows);
  })();

  if (!cached) {
    inventoryCache.set(key, promise);
  }
  const rows = await promise;
  return options.activeOnly ? rows.filter((row) => row.is_inventory_in_scope) : rows;
}

export async function buildDerivedMediaRepairPlan(
  client: SupabaseAdminClient,
  options: { activeOnly: boolean; courseIds: string[] },
): Promise<MediaRepairPlanRow[]> {
  const key = cacheKey(options.courseIds);
  const cached = repairPlanCache.get(key);
  const promise = cached ?? (async (): Promise<MediaRepairPlanRow[]> => {
    const [inventoryRows, snapshot] = await Promise.all([
      buildDerivedActiveMediaInventory(client, { activeOnly: false, courseIds: options.courseIds }),
      loadFallbackSnapshot(client, options.courseIds),
    ]);

    const storageMetaMap = new Map(
      snapshot.storageObjects
        .map((storageObject) => {
          const key = storageKey(storageObject.bucket_id, storageObject.name);
          return key ? [key, extractStorageMeta(storageObject)] as const : null;
        })
        .filter((entry): entry is readonly [string, StorageMetaRecord] => entry !== null),
    );
    const mediaAssetsByLesson = new Map<string, MediaAssetRecord[]>();
    for (const mediaAsset of snapshot.mediaAssets) {
      if (!mediaAsset.lesson_id) {
        continue;
      }
      const rows = mediaAssetsByLesson.get(mediaAsset.lesson_id) ?? [];
      rows.push(mediaAsset);
      mediaAssetsByLesson.set(mediaAsset.lesson_id, rows);
    }

    const planRows: MediaRepairPlanRow[] = inventoryRows.map((inventoryRow) => {
      const { urlNormalizedPath, apiNormalizedPath } = normalizePathFromUrl(inventoryRow.storage_path);
      const normalizedStoragePath = firstDefined(apiNormalizedPath, urlNormalizedPath, inventoryRow.storage_path);
      let normalizedBucket = inventoryRow.bucket;
      if (normalizedStoragePath) {
        const firstSegment = normalizedStoragePath.split("/")[0] ?? "";
        if (KNOWN_BUCKETS.has(firstSegment) && firstSegment !== (inventoryRow.bucket ?? "")) {
          normalizedBucket = firstSegment;
        }
      }
      let normalizedStorageKey: string | null = null;
      if (normalizedStoragePath) {
        if (normalizedBucket && normalizedStoragePath.startsWith(`${normalizedBucket}/`)) {
          normalizedStorageKey = normalizedStoragePath.slice(normalizedBucket.length + 1);
        } else {
          const firstSegment = normalizedStoragePath.split("/")[0] ?? "";
          normalizedStorageKey = KNOWN_BUCKETS.has(firstSegment)
            ? normalizedStoragePath.replace(/^[^/]+\//, "")
            : normalizedStoragePath;
        }
      }

      const canonicalObject = storageMetaMap.get(storageKey(inventoryRow.bucket, inventoryRow.storage_path) ?? "") ?? null;
      const normalizedObject = storageMetaMap.get(storageKey(normalizedBucket, normalizedStorageKey) ?? "") ?? null;
      const sourceObject =
        storageMetaMap.get(
          storageKey(inventoryRow.media_asset_source_bucket, inventoryRow.media_asset_source_path) ?? "",
        ) ?? null;
      const streamingObject =
        storageMetaMap.get(
          storageKey(
            inventoryRow.media_asset_stream_bucket ?? inventoryRow.media_asset_source_bucket,
            inventoryRow.media_asset_stream_path,
          ) ?? "",
        ) ?? null;

      const resolvedByteSize = firstDefined(
        canonicalObject?.storage_size,
        normalizedObject?.storage_size,
        sourceObject?.storage_size,
        streamingObject?.storage_size,
        inventoryRow.byte_size,
      );

      const safeMatches = (mediaAssetsByLesson.get(inventoryRow.lesson_id) ?? []).filter((mediaAsset) => {
        if (inventoryRow.media_asset_id !== null) {
          return false;
        }
        if (mediaAsset.lesson_id !== inventoryRow.lesson_id) {
          return false;
        }
        if (!mediaAsset.course_id || mediaAsset.course_id !== inventoryRow.course_id) {
          return false;
        }
        if (lower(mediaAsset.state) !== "ready") {
          return false;
        }
        if (
          !areMediaKindsCompatible({
            lessonMediaKind: inventoryRow.lesson_media_kind,
            mediaAssetType: mediaAsset.media_type,
          })
        ) {
          return false;
        }
        const candidateStoragePath =
          normalizedText(mediaAsset.streaming_object_path) ?? normalizedText(mediaAsset.original_object_path);
        const candidateContentType = firstDefined(
          normalizedText(mediaAsset.original_content_type),
          lower(mediaAsset.media_type) === "audio" && normalizedText(mediaAsset.streaming_object_path)
            ? "audio/mpeg"
            : null,
          lower(mediaAsset.media_type) === "image"
            ? "image/jpeg"
            : null,
          ["document", "pdf"].includes(lower(mediaAsset.media_type))
            ? "application/pdf"
            : null,
        );
        if (
          !hasCompatibleExtension({
            lessonMediaKind: inventoryRow.lesson_media_kind,
            storagePath: candidateStoragePath,
          })
        ) {
          return false;
        }
        if (
          !hasCompatibleMime({
            lessonMediaKind: inventoryRow.lesson_media_kind,
            contentType: candidateContentType,
          })
        ) {
          return false;
        }
        return [
          storageKey(mediaAsset.streaming_storage_bucket ?? mediaAsset.storage_bucket, mediaAsset.streaming_object_path),
          storageKey(mediaAsset.storage_bucket, mediaAsset.original_object_path),
          storageKey(mediaAsset.streaming_storage_bucket ?? mediaAsset.storage_bucket, normalizedStorageKey),
          storageKey(mediaAsset.storage_bucket, normalizedStorageKey),
        ].includes(storageKey(inventoryRow.bucket, inventoryRow.storage_path))
          || [
            storageKey(mediaAsset.streaming_storage_bucket ?? mediaAsset.storage_bucket, mediaAsset.streaming_object_path),
            storageKey(mediaAsset.storage_bucket, mediaAsset.original_object_path),
          ].includes(storageKey(normalizedBucket, normalizedStorageKey));
      });

      const hasInvalidKey = (() => {
        const storagePath = inventoryRow.storage_path ?? "";
        const trimmed = storagePath.replace(/^\/+/, "");
        return (
          storagePath !== ""
          && (
            /^https?:\/\//i.test(storagePath)
            || trimmed.startsWith("storage/v1/object/")
            || trimmed.startsWith("object/")
            || (inventoryRow.bucket !== null && trimmed.startsWith(`${inventoryRow.bucket}/`))
            || KNOWN_BUCKETS.has(trimmed.split("/")[0] ?? "")
          )
        );
      })();

      const hasUnsupportedFormat =
        lower(inventoryRow.content_type) === "image/webp"
        || path.posix.extname(inventoryRow.storage_path ?? "").toLowerCase() === ".webp";
      const hasTinyFile = (resolvedByteSize ?? 0) > 0 && (resolvedByteSize ?? 0) < 100;

      const canonical_object_exists = canonicalObject !== null;
      const normalized_object_exists = normalizedObject !== null;
      const source_object_exists = sourceObject !== null;
      const streaming_object_exists = streamingObject !== null;
      const safe_matching_media_asset_count = safeMatches.length;
      const safe_matching_media_asset_id = safeMatches.length === 1 ? safeMatches[0]?.id ?? null : null;

      const issue_type =
        hasInvalidKey
          ? "INVALID_KEY"
          : !canonical_object_exists && !normalized_object_exists
            ? "MISSING_IN_STORAGE"
            : inventoryRow.media_asset_id !== null && lower(inventoryRow.media_state) !== "ready"
              ? "NOT_READY_ASSET"
              : hasUnsupportedFormat
                ? "UNSUPPORTED_FORMAT"
                : hasTinyFile
                  ? "TINY_FILE"
                  : inventoryRow.media_asset_id === null
                    ? "LEGACY_DIRECT_REFERENCE"
                    : null;

      const fix_strategy =
        hasInvalidKey
          ? "REKEY_STORAGE_PATH"
          : !canonical_object_exists && !normalized_object_exists
            ? inventoryRow.media_asset_id !== null && source_object_exists
              ? "RESTORE_FROM_SOURCE"
              : inventoryRow.media_asset_id === null && safe_matching_media_asset_count === 1
                ? "BACKFILL_MEDIA_ASSET"
                : "MANUAL_REUPLOAD_REQUIRED"
            : inventoryRow.media_asset_id !== null && lower(inventoryRow.media_state) !== "ready"
              ? source_object_exists
                ? "RESTORE_FROM_SOURCE"
                : "MANUAL_REUPLOAD_REQUIRED"
              : hasUnsupportedFormat
                ? inventoryRow.media_asset_id === null && safe_matching_media_asset_count === 1
                  ? "BACKFILL_MEDIA_ASSET"
                  : canonical_object_exists || normalized_object_exists || source_object_exists
                    ? "TRANSCODE_FORMAT"
                    : "MANUAL_REUPLOAD_REQUIRED"
                : hasTinyFile
                  ? inventoryRow.media_asset_id !== null && source_object_exists
                    ? "RESTORE_FROM_SOURCE"
                    : inventoryRow.media_asset_id === null && safe_matching_media_asset_count === 1
                      ? "BACKFILL_MEDIA_ASSET"
                      : "MANUAL_REUPLOAD_REQUIRED"
                  : inventoryRow.media_asset_id === null
                    ? safe_matching_media_asset_count === 1
                      ? "BACKFILL_MEDIA_ASSET"
                      : "NO_ACTION"
                    : "NO_ACTION";

      const repair_priority =
        (inventoryRow.is_inventory_in_scope ? 0 : 500)
        + (
          hasInvalidKey
            ? 10
            : !canonical_object_exists && !normalized_object_exists
              ? 20
              : inventoryRow.media_asset_id !== null && lower(inventoryRow.media_state) !== "ready"
                ? 30
                : hasUnsupportedFormat
                  ? 40
                  : hasTinyFile
                    ? 50
                    : inventoryRow.media_asset_id === null
                      ? 60
                      : 900
        )
        + (
          inventoryRow.reference_type === "media_asset"
            ? 0
            : inventoryRow.reference_type === "media_object"
              ? 5
              : 10
        );

      return {
        ...inventoryRow,
        normalized_bucket: normalizedBucket,
        normalized_storage_path: normalizedStorageKey,
        canonical_object_exists,
        normalized_object_exists,
        source_object_exists,
        streaming_object_exists,
        safe_matching_media_asset_id,
        safe_matching_media_asset_count,
        byte_size: resolvedByteSize,
        issue_type,
        fix_strategy,
        repair_priority,
      };
    });

    return [...planRows].sort((left, right) => {
      const byPriority = left.repair_priority - right.repair_priority;
      if (byPriority !== 0) {
        return byPriority;
      }
      const byCourse = left.course_id.localeCompare(right.course_id);
      if (byCourse !== 0) {
        return byCourse;
      }
      const byLesson = left.lesson_id.localeCompare(right.lesson_id);
      if (byLesson !== 0) {
        return byLesson;
      }
      return left.created_at.localeCompare(right.created_at);
    });
  })();

  if (!cached) {
    repairPlanCache.set(key, promise);
  }
  const rows = await promise;
  return options.activeOnly ? rows.filter((row) => row.is_inventory_in_scope) : rows;
}

export async function loadActiveMediaInventoryWithFallback(
  client: SupabaseAdminClient,
  options: { activeOnly: boolean; courseIds: string[] },
): Promise<ActiveMediaInventoryRow[]> {
  const filters = [
    ...(options.courseIds.length > 0 ? [{ column: "course_id", operator: "in" as const, value: options.courseIds }] : []),
    ...(options.activeOnly ? [{ column: "is_inventory_in_scope", operator: "eq" as const, value: true }] : []),
  ];

  try {
    return await client.listAll<ActiveMediaInventoryRow>("active_media_inventory", {
      select: "*",
      filters,
      order: "course_id.asc,lesson_id.asc,created_at.asc",
    });
  } catch (error) {
    if (!isMissingViewError(error, "active_media_inventory")) {
      throw error;
    }
    return buildDerivedActiveMediaInventory(client, options);
  }
}

export async function loadMediaRepairPlanWithFallback(
  client: SupabaseAdminClient,
  options: { activeOnly: boolean; courseIds: string[] },
): Promise<MediaRepairPlanRow[]> {
  const filters = [
    ...(options.courseIds.length > 0 ? [{ column: "course_id", operator: "in" as const, value: options.courseIds }] : []),
    ...(options.activeOnly ? [{ column: "is_inventory_in_scope", operator: "eq" as const, value: true }] : []),
  ];

  try {
    return await client.listAll<MediaRepairPlanRow>("media_repair_plan", {
      select: "*",
      filters,
      order: "repair_priority.asc,course_id.asc,lesson_id.asc,created_at.asc",
    });
  } catch (error) {
    if (!isMissingViewError(error, "media_repair_plan")) {
      throw error;
    }
    return buildDerivedMediaRepairPlan(client, options);
  }
}
