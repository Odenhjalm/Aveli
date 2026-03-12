import type {
  ActiveMediaInventoryRow,
  LessonMediaRecord,
  MediaAssetRecord,
  MediaObjectRecord,
  MediaRepairPlanRow,
  StorageCatalogEntry,
  StorageRecoveryReportRow,
  StorageRecoverySummary,
  StorageObjectRecord,
} from "./types.js";
import {
  loadActiveMediaInventoryWithFallback,
  loadMediaRepairPlanWithFallback,
} from "./derived-views.js";
import type { SupabaseAdminClient } from "./postgrest.js";
import { loadStorageCatalog, loadStorageObjectsViaApi } from "./storage-catalog.js";
import { analyzeStorageRecovery } from "./storage-forensics.js";

export interface MediaRepairPlanAnalysis {
  rows: MediaRepairPlanRow[];
  storageCatalog: StorageCatalogEntry[];
  recoveryReportRows: StorageRecoveryReportRow[];
  recoverySummary: StorageRecoverySummary;
}

export async function loadActiveMediaInventory(
  client: SupabaseAdminClient,
  options: { activeOnly: boolean; courseIds: string[] },
): Promise<ActiveMediaInventoryRow[]> {
  return loadActiveMediaInventoryWithFallback(client, options);
}

export async function loadMediaRepairPlan(
  client: SupabaseAdminClient,
  options: { activeOnly: boolean; courseIds: string[] },
): Promise<MediaRepairPlanRow[]> {
  const analysis = await loadMediaRepairPlanAnalysis(client, options);
  return analysis.rows;
}

export async function loadMediaRepairPlanAnalysis(
  client: SupabaseAdminClient,
  options: { activeOnly: boolean; courseIds: string[] },
): Promise<MediaRepairPlanAnalysis> {
  const planRows = await loadMediaRepairPlanWithFallback(client, options);
  if (!planRows.some((row) => row.fix_strategy === "MANUAL_REUPLOAD_REQUIRED")) {
    return {
      rows: planRows,
      storageCatalog: await loadStorageCatalog(client),
      recoveryReportRows: [],
      recoverySummary: {
        rows_reduced_from_manual_reupload_required: 0,
        safe_auto_recover_count: 0,
        probable_match_count: 0,
        ambiguous_match_count: 0,
        no_match_count: 0,
      },
    };
  }

  const storageCatalog = await loadStorageCatalog(client);
  const analysis = analyzeStorageRecovery(planRows, storageCatalog);
  return {
    rows: analysis.rows,
    storageCatalog,
    recoveryReportRows: analysis.reportRows,
    recoverySummary: analysis.summary,
  };
}

export async function loadMediaObjects(client: SupabaseAdminClient): Promise<MediaObjectRecord[]> {
  return client.listAll<MediaObjectRecord>("media_objects", {
    select: "id,storage_bucket,storage_path,content_type,byte_size,original_name,created_at",
    order: "created_at.asc",
  });
}

export async function loadMediaAssets(client: SupabaseAdminClient): Promise<MediaAssetRecord[]> {
  return client.listAll<MediaAssetRecord>("media_assets", {
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
  });
}

export async function loadLessonMedia(client: SupabaseAdminClient): Promise<LessonMediaRecord[]> {
  return client.listAll<LessonMediaRecord>("lesson_media", {
    select: "id,lesson_id,kind,storage_bucket,storage_path,media_id,media_asset_id,created_at",
    order: "created_at.asc",
  });
}

export async function loadStorageObjects(client: SupabaseAdminClient): Promise<StorageObjectRecord[]> {
  return loadStorageObjectsViaApi(client);
}
