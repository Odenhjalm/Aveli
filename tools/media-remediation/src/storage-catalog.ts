import path from "node:path";

import type { SupabaseAdminClient } from "./postgrest.js";
import { mimeFamily, normalizeFilenameForMatch } from "./repair-utils.js";
import type { StorageCatalogEntry, StorageObjectRecord } from "./types.js";

const KNOWN_BUCKETS = ["course-media", "public-media", "lesson-media", "seminar-media"];
export const STORAGE_CATALOG_BUCKETS = ["course-media", "public-media", "lesson-media"] as const;
const PAGE_SIZE = 1000;
const REQUEST_TIMEOUT_MS = 30_000;
const MAX_RETRIES = 4;
const STORAGE_REQUEST_CONCURRENCY = 4;

let activeStorageRequests = 0;
const storageWaiters: Array<() => void> = [];
const UUID_SEGMENT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const storageCatalogCache = new Map<string, Promise<StorageCatalogEntry[]>>();

interface StorageListEntry {
  name: string;
  id: string | null;
  created_at: string | null;
  updated_at: string | null;
  last_accessed_at: string | null;
  metadata: Record<string, unknown> | null;
}

function firstString(...values: Array<unknown>): string | null {
  for (const value of values) {
    if (typeof value === "string" && value.trim() !== "") {
      return value.trim();
    }
  }
  return null;
}

function firstNumber(...values: Array<unknown>): number | null {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === "string" && value.trim() !== "") {
      const parsed = Number.parseInt(value, 10);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  }
  return null;
}

function extractUuidAfterKeyword(storagePath: string, keyword: string): string | null {
  const parts = storagePath.split("/");
  const keywordIndex = parts.findIndex((part) => part.toLowerCase() === keyword);
  const candidate = keywordIndex >= 0 ? (parts[keywordIndex + 1] ?? "") : "";
  return UUID_SEGMENT.test(candidate) ? candidate : null;
}

function extractCourseIdHint(storagePath: string): string | null {
  const direct = storagePath.split("/").find((part) => UUID_SEGMENT.test(part)) ?? null;
  const named = extractUuidAfterKeyword(storagePath, "courses");
  return named ?? direct;
}

function extractLessonIdHint(storagePath: string): string | null {
  const named = extractUuidAfterKeyword(storagePath, "lessons");
  if (named) {
    return named;
  }
  const parts = storagePath.split("/");
  for (let index = 0; index < parts.length; index += 1) {
    if (UUID_SEGMENT.test(parts[index] ?? "") && UUID_SEGMENT.test(parts[index + 1] ?? "")) {
      return parts[index + 1] ?? null;
    }
  }
  return null;
}

async function readResponseBody(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return "<unreadable>";
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function acquireStorageSlot(): Promise<void> {
  if (activeStorageRequests < STORAGE_REQUEST_CONCURRENCY) {
    activeStorageRequests += 1;
    return;
  }
  await new Promise<void>((resolve) => {
    storageWaiters.push(() => {
      activeStorageRequests += 1;
      resolve();
    });
  });
}

function releaseStorageSlot(): void {
  activeStorageRequests = Math.max(0, activeStorageRequests - 1);
  const next = storageWaiters.shift();
  next?.();
}

async function requestStorageList(
  client: SupabaseAdminClient,
  bucket: string,
  prefix: string,
  offset: number,
): Promise<StorageListEntry[]> {
  const url = new URL(`/storage/v1/object/list/${bucket}`, client.getSupabaseUrl());
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt += 1) {
    await acquireStorageSlot();
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          apikey: client.getServiceRoleKey(),
          Authorization: `Bearer ${client.getServiceRoleKey()}`,
          "Content-Type": "application/json",
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        body: JSON.stringify({
          prefix,
          limit: PAGE_SIZE,
          offset,
        }),
      });
      if (response.ok) {
        return (await response.json()) as StorageListEntry[];
      }
      const body = await readResponseBody(response);
      if (response.status === 429 && attempt < MAX_RETRIES) {
        await sleep(250 * attempt);
        continue;
      }
      throw new Error(`Storage list failed for ${bucket}/${prefix || ""}: ${response.status} ${body}`);
    } finally {
      releaseStorageSlot();
    }
  }
  throw new Error(`Storage list failed for ${bucket}/${prefix || ""}: retries exhausted`);
}

async function listBucketRecursively(
  client: SupabaseAdminClient,
  bucket: string,
  prefix: string,
  objects: StorageObjectRecord[],
): Promise<void> {
  let offset = 0;
  while (true) {
    const entries = await requestStorageList(client, bucket, prefix, offset);
    const folders: string[] = [];

    for (const entry of entries) {
      if (entry.id === null && entry.metadata === null) {
        const folderPrefix = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
        folders.push(folderPrefix);
        continue;
      }
      objects.push({
        id: entry.id ?? `${bucket}:${prefix}:${entry.name}`,
        bucket_id: bucket,
        name: prefix === "" ? entry.name : `${prefix}/${entry.name}`,
        created_at: entry.created_at,
        updated_at: entry.updated_at,
        metadata: entry.metadata,
      });
    }

    await Promise.all(
      folders.map(async (folderPrefix) => {
        await listBucketRecursively(client, bucket, folderPrefix, objects);
      }),
    );

    if (entries.length < PAGE_SIZE) {
      return;
    }
    offset += PAGE_SIZE;
  }
}

export async function loadStorageObjectsViaApi(client: SupabaseAdminClient): Promise<StorageObjectRecord[]> {
  const objects: StorageObjectRecord[] = [];
  await Promise.all(
    KNOWN_BUCKETS.map(async (bucket) => {
      await listBucketRecursively(client, bucket, "", objects);
    }),
  );
  return objects.sort((left, right) => {
    const byBucket = left.bucket_id.localeCompare(right.bucket_id);
    if (byBucket !== 0) {
      return byBucket;
    }
    return left.name.localeCompare(right.name);
  });
}

export function buildStorageCatalog(storageObjects: StorageObjectRecord[]): StorageCatalogEntry[] {
  return storageObjects
    .filter((storageObject) => STORAGE_CATALOG_BUCKETS.includes(storageObject.bucket_id as (typeof STORAGE_CATALOG_BUCKETS)[number]))
    .map((storageObject) => {
      const metadata = storageObject.metadata ?? {};
      const filename = path.posix.basename(storageObject.name);
      const extension = path.posix.extname(filename).toLowerCase() || null;
      const contentType = firstString(
        metadata.mimetype,
        metadata.contentType,
        metadata.content_type,
      );
      return {
        bucket: storageObject.bucket_id,
        storage_path: storageObject.name,
        filename,
        extension,
        size: firstNumber(metadata.size, metadata.length, metadata.contentLength),
        content_type: contentType,
        mime_family: mimeFamily(contentType),
        etag: firstString(metadata.eTag, metadata.etag, metadata.httpEtag),
        created_at: storageObject.created_at,
        normalized_filename: normalizeFilenameForMatch(filename),
        course_id_hint: extractCourseIdHint(storageObject.name),
        lesson_id_hint: extractLessonIdHint(storageObject.name),
      };
    })
    .sort((left, right) => {
      const byBucket = left.bucket.localeCompare(right.bucket);
      if (byBucket !== 0) {
        return byBucket;
      }
      return left.storage_path.localeCompare(right.storage_path);
    });
}

export async function loadStorageCatalog(client: SupabaseAdminClient): Promise<StorageCatalogEntry[]> {
  const key = client.getSupabaseUrl();
  const existing = storageCatalogCache.get(key);
  if (existing) {
    return existing;
  }
  const promise = (async (): Promise<StorageCatalogEntry[]> => {
    const storageObjects = await loadStorageObjectsViaApi(client);
    return buildStorageCatalog(storageObjects);
  })();
  storageCatalogCache.set(key, promise);
  return promise;
}

export function clearStorageCatalogCache(): void {
  storageCatalogCache.clear();
}
