import type { SupabaseAdminClient } from "./postgrest.js";
import type { StorageObjectRecord } from "./types.js";

const KNOWN_BUCKETS = ["course-media", "public-media", "lesson-media", "seminar-media"];
const PAGE_SIZE = 1000;

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

async function requestStorageList(
  client: SupabaseAdminClient,
  bucket: string,
  prefix: string,
  offset: number,
): Promise<StorageListEntry[]> {
  const url = new URL(`/storage/v1/object/list/${bucket}`, client.getSupabaseUrl());
  const response = await fetch(url, {
    method: "POST",
    headers: {
      apikey: client.getServiceRoleKey(),
      Authorization: `Bearer ${client.getServiceRoleKey()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      prefix,
      limit: PAGE_SIZE,
      offset,
    }),
  });
  if (!response.ok) {
    throw new Error(`Storage list failed for ${bucket}/${prefix || ""}: ${response.status} ${await readResponseBody(response)}`);
  }
  return (await response.json()) as StorageListEntry[];
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

    for (const folderPrefix of folders) {
      await listBucketRecursively(client, bucket, folderPrefix, objects);
    }

    if (entries.length < PAGE_SIZE) {
      return;
    }
    offset += PAGE_SIZE;
  }
}

export async function loadStorageObjectsViaApi(client: SupabaseAdminClient): Promise<StorageObjectRecord[]> {
  const objects: StorageObjectRecord[] = [];
  for (const bucket of KNOWN_BUCKETS) {
    await listBucketRecursively(client, bucket, "", objects);
  }
  return objects.sort((left, right) => {
    const byBucket = left.bucket_id.localeCompare(right.bucket_id);
    if (byBucket !== 0) {
      return byBucket;
    }
    return left.name.localeCompare(right.name);
  });
}
