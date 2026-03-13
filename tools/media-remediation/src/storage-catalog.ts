import type { SupabaseAdminClient } from "./postgrest.js";
import type { StorageObjectRecord } from "./types.js";

const KNOWN_BUCKETS = ["course-media", "public-media", "lesson-media", "seminar-media"];
const PAGE_SIZE = 1000;
const REQUEST_TIMEOUT_MS = 30_000;
const MAX_RETRIES = 4;
const STORAGE_REQUEST_CONCURRENCY = 4;

let activeStorageRequests = 0;
const storageWaiters: Array<() => void> = [];

interface StorageListEntry {
  name: string;
  id: string | null;
  created_at: string | null;
  updated_at: string | null;
  last_accessed_at: string | null;
  metadata: Record<string, unknown> | null;
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
