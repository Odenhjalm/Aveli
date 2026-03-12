import { stat } from "node:fs/promises";
import path from "node:path";

import { loadServiceEnvironment, printUsage } from "./config.js";
import { loadMediaRepairPlan } from "./data.js";
import { transcodeWithFfmpeg, verifyFfmpegAvailable, withTempDir } from "./ffmpeg.js";
import { buildRunDirectory, ensureDir, writeJsonFile } from "./fs-utils.js";
import { StructuredLogger } from "./logger.js";
import { SupabaseAdminClient } from "./postgrest.js";
import {
  canonicalizeStoredReference,
  inferTranscodeTarget,
} from "./repair-utils.js";
import { isExecutedAsMain } from "./runtime.js";
import { SupabaseStorageAdmin } from "./storage.js";
import type { ChangeManifestEntry, MediaRepairPlanRow } from "./types.js";

type ManifestPartial = Omit<
  ChangeManifestEntry,
  "phase" | "courseId" | "lessonId" | "lessonMediaId" | "mediaObjectId" | "mediaAssetId" | "issueType" | "fixStrategy" | "timestamp"
>;

function nowIso(): string {
  return new Date().toISOString();
}

function toManifestEntry(
  row: MediaRepairPlanRow,
  partial: ManifestPartial,
): ChangeManifestEntry {
  return {
    phase: "repair",
    courseId: row.course_id,
    lessonId: row.lesson_id,
    lessonMediaId: row.lesson_media_id,
    mediaObjectId: row.media_object_id,
    mediaAssetId: row.media_asset_id,
    issueType: row.issue_type,
    fixStrategy: row.fix_strategy,
    timestamp: nowIso(),
    ...partial,
  };
}

function rewriteNameWithExtension(originalName: string | null | undefined, extension: string, storagePath: string): string {
  const basis = originalName?.trim() || path.posix.basename(storagePath);
  const parsed = path.posix.parse(basis);
  return `${parsed.name}${extension}`;
}

function groupByCourse(rows: MediaRepairPlanRow[]): Map<string, MediaRepairPlanRow[]> {
  const grouped = new Map<string, MediaRepairPlanRow[]>();
  for (const row of rows) {
    const current = grouped.get(row.course_id) ?? [];
    current.push(row);
    grouped.set(row.course_id, current);
  }
  return grouped;
}

function filterRepairScope(rows: MediaRepairPlanRow[], fixStrategies: string[]): MediaRepairPlanRow[] {
  return rows.filter((row) => {
    if (row.issue_type === null || row.fix_strategy === "NO_ACTION") {
      return false;
    }
    if (fixStrategies.length > 0 && !fixStrategies.includes(row.fix_strategy)) {
      return false;
    }
    return true;
  });
}

function requiresLocalFfmpeg(row: MediaRepairPlanRow): boolean {
  return (
    row.fix_strategy === "TRANSCODE_FORMAT"
    && (row.media_object_id !== null || (row.media_object_id === null && row.media_asset_id === null))
  );
}

export function buildPlannedManifest(rows: MediaRepairPlanRow[]): ChangeManifestEntry[] {
  return rows
    .filter((row) => row.issue_type !== null)
    .map((row) =>
      toManifestEntry(row, {
        action: row.fix_strategy,
        status: "planned",
        details: {
          repairPriority: row.repair_priority,
          isInventoryInScope: row.is_inventory_in_scope,
          isPublishedScope: row.course_is_published,
          isIntroLesson: row.lesson_is_intro,
          bucket: row.bucket,
          storagePath: row.storage_path,
          normalizedBucket: row.normalized_bucket,
          normalizedStoragePath: row.normalized_storage_path,
          storageRecoveryClassification: row.storage_recovery_classification ?? null,
          storageRecoveryBucket: row.storage_recovery_bucket ?? null,
          storageRecoveryPath: row.storage_recovery_path ?? null,
          storageRecoveryConfidenceScore: row.storage_recovery_confidence_score ?? null,
          storageRecoveryMatchReason: row.storage_recovery_match_reason ?? null,
        },
      }),
    );
}

export class MediaRepairExecutor {
  public constructor(
    private readonly client: SupabaseAdminClient,
    private readonly storage: SupabaseStorageAdmin,
    private readonly logger: StructuredLogger,
    private readonly options: {
      dryRun: boolean;
      minByteSize: number;
      ffmpegBin: string;
    },
  ) {}

  public async run(rows: MediaRepairPlanRow[]): Promise<ChangeManifestEntry[]> {
    const executed: ChangeManifestEntry[] = [];
    const grouped = groupByCourse(rows);

    if (!this.options.dryRun && rows.some(requiresLocalFfmpeg)) {
      const preflight = await verifyFfmpegAvailable(this.options.ffmpegBin);
      this.logger.info("repair.ffmpeg.preflight", {
        ffmpegBin: this.options.ffmpegBin,
        versionLine: preflight.versionLine,
      });
    }

    for (const [courseId, courseRows] of grouped.entries()) {
      this.logger.info("repair.course.start", {
        courseId,
        rowCount: courseRows.length,
        dryRun: this.options.dryRun,
      });
      executed.push(...(await this.executeObjectPhase(courseRows)));
      executed.push(...(await this.executeReferencePhase(courseRows)));
      executed.push(...this.recordManualOnlyRows(courseRows));
      this.logger.info("repair.course.complete", {
        courseId,
        rowCount: courseRows.length,
      });
    }

    return executed;
  }

  private async executeObjectPhase(rows: MediaRepairPlanRow[]): Promise<ChangeManifestEntry[]> {
    const results: ChangeManifestEntry[] = [];
    const seen = new Set<string>();

    for (const row of rows) {
      let key: string | null = null;
      if (row.fix_strategy === "RESTORE_FROM_SOURCE" && row.media_asset_id) {
        key = `restore:asset:${row.media_asset_id}`;
      } else if (row.fix_strategy === "REKEY_STORAGE_PATH" && row.media_object_id) {
        key = `rekey:object:${row.media_object_id}`;
      } else if (row.fix_strategy === "REKEY_STORAGE_PATH" && row.media_asset_id) {
        key = `rekey:asset:${row.media_asset_id}`;
      } else if (row.fix_strategy === "TRANSCODE_FORMAT" && row.media_asset_id) {
        key = `transcode:asset:${row.media_asset_id}`;
      } else if (row.fix_strategy === "TRANSCODE_FORMAT" && row.media_object_id) {
        key = `transcode:object:${row.media_object_id}`;
      } else if (row.fix_strategy === "RECOVER_FROM_STORAGE_MATCH" && row.media_object_id) {
        key = `recover:object:${row.media_object_id}`;
      } else if (row.fix_strategy === "RECOVER_FROM_STORAGE_MATCH" && row.media_asset_id) {
        key = `recover:asset:${row.media_asset_id}`;
      }
      if (key === null || seen.has(key)) {
        continue;
      }
      seen.add(key);

      if (row.fix_strategy === "RESTORE_FROM_SOURCE" && row.media_asset_id) {
        results.push(await this.requeueMediaAsset(row, "restore_from_source"));
        continue;
      }
      if (row.fix_strategy === "REKEY_STORAGE_PATH" && row.media_object_id) {
        results.push(await this.rekeyMediaObject(row));
        continue;
      }
      if (row.fix_strategy === "REKEY_STORAGE_PATH" && row.media_asset_id) {
        results.push(await this.rekeyMediaAsset(row));
        continue;
      }
      if (row.fix_strategy === "TRANSCODE_FORMAT" && row.media_asset_id) {
        results.push(await this.requeueMediaAsset(row, "transcode_via_pipeline"));
        continue;
      }
      if (row.fix_strategy === "TRANSCODE_FORMAT" && row.media_object_id) {
        results.push(await this.transcodeMediaObject(row));
        continue;
      }
      if (row.fix_strategy === "RECOVER_FROM_STORAGE_MATCH" && row.media_object_id) {
        results.push(await this.recoverMediaObjectReference(row));
        continue;
      }
      if (row.fix_strategy === "RECOVER_FROM_STORAGE_MATCH" && row.media_asset_id) {
        results.push(await this.recoverMediaAssetReference(row));
      }
    }
    return results;
  }

  private async executeReferencePhase(rows: MediaRepairPlanRow[]): Promise<ChangeManifestEntry[]> {
    const results: ChangeManifestEntry[] = [];
    const seen = new Set<string>();

    for (const row of rows) {
      const key = `${row.fix_strategy}:${row.lesson_media_id}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);

      if (row.fix_strategy === "BACKFILL_MEDIA_ASSET") {
        results.push(await this.backfillMediaAssetReference(row));
        continue;
      }
      if (row.fix_strategy === "REKEY_STORAGE_PATH" && !row.media_object_id && !row.media_asset_id) {
        results.push(await this.rekeyDirectLessonReference(row));
        continue;
      }
      if (row.fix_strategy === "RECOVER_FROM_STORAGE_MATCH" && !row.media_object_id && !row.media_asset_id) {
        results.push(await this.recoverDirectLessonReference(row));
        continue;
      }
      if (row.fix_strategy === "TRANSCODE_FORMAT" && !row.media_object_id && !row.media_asset_id) {
        results.push(await this.transcodeDirectLessonReference(row));
      }
    }
    return results;
  }

  private recordManualOnlyRows(rows: MediaRepairPlanRow[]): ChangeManifestEntry[] {
    return rows
      .filter((row) => row.fix_strategy === "MANUAL_REUPLOAD_REQUIRED")
      .map((row) =>
        toManifestEntry(row, {
          action: "manual_reupload_required",
          status: "skipped",
          details: {
            reason: "repair_requires_manual_reupload",
            issueType: row.issue_type,
          },
        }),
      );
  }

  private async requeueMediaAsset(row: MediaRepairPlanRow, action: string): Promise<ChangeManifestEntry> {
    if (!row.media_asset_id) {
      return toManifestEntry(row, {
        action,
        status: "skipped",
        details: { reason: "missing_media_asset_id" },
      });
    }

    const patch = {
      state: "uploaded",
      processing_locked_at: null,
      next_retry_at: nowIso(),
      error_message: null,
      updated_at: nowIso(),
    };

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action,
        status: "planned",
        details: { patch },
      });
    }

    await this.client.patch("media_assets", patch, {
      filters: [{ column: "id", operator: "eq", value: row.media_asset_id }],
    });
    return toManifestEntry(row, {
      action,
      status: "applied",
      details: { patch },
    });
  }

  private async rekeyMediaObject(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    const target = canonicalizeStoredReference({
      bucket: row.bucket,
      path: row.storage_path,
    });
    if (!row.media_object_id || !target.changed || !target.bucket || !target.path) {
      return toManifestEntry(row, {
        action: "rekey_media_object",
        status: "skipped",
        details: { reason: "already_canonical_or_missing_target", target },
      });
    }

    let probe;
    try {
      probe = await this.storage.probeObject(target.bucket, target.path);
    } catch (error) {
      return toManifestEntry(row, {
        action: "rekey_media_object",
        status: "failed",
        details: {
          reason: "storage_probe_failed",
          target,
          error: error instanceof Error ? error.message : String(error),
        },
      });
    }
    if (!probe.exists) {
      return toManifestEntry(row, {
        action: "rekey_media_object",
        status: "failed",
        details: { reason: "canonical_target_missing_in_storage", target },
      });
    }

    const patch = {
      storage_bucket: target.bucket,
      storage_path: target.path,
      content_type: probe.contentType ?? row.content_type,
      byte_size: probe.contentLength ?? row.byte_size,
      updated_at: nowIso(),
    };

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "rekey_media_object",
        status: "planned",
        details: { patch, target },
      });
    }

    await this.client.patch("media_objects", patch, {
      filters: [{ column: "id", operator: "eq", value: row.media_object_id }],
    });
    return toManifestEntry(row, {
      action: "rekey_media_object",
      status: "applied",
      details: { patch, target },
    });
  }

  private async rekeyMediaAsset(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    const target = canonicalizeStoredReference({
      bucket: row.bucket,
      path: row.storage_path,
    });
    if (!row.media_asset_id || !target.changed || !target.bucket || !target.path) {
      return toManifestEntry(row, {
        action: "rekey_media_asset",
        status: "skipped",
        details: { reason: "already_canonical_or_missing_target", target },
      });
    }

    let probe;
    try {
      probe = await this.storage.probeObject(target.bucket, target.path);
    } catch (error) {
      return toManifestEntry(row, {
        action: "rekey_media_asset",
        status: "failed",
        details: {
          reason: "storage_probe_failed",
          target,
          error: error instanceof Error ? error.message : String(error),
        },
      });
    }
    if (!probe.exists) {
      return toManifestEntry(row, {
        action: "rekey_media_asset",
        status: "failed",
        details: { reason: "canonical_target_missing_in_storage", target },
      });
    }

    const patch =
      row.media_state?.toLowerCase() === "ready" && row.media_asset_stream_path
        ? {
            streaming_storage_bucket: target.bucket,
            streaming_object_path: target.path,
            updated_at: nowIso(),
          }
        : {
            storage_bucket: target.bucket,
            original_object_path: target.path,
            updated_at: nowIso(),
          };

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "rekey_media_asset",
        status: "planned",
        details: { patch, target },
      });
    }

    await this.client.patch("media_assets", patch, {
      filters: [{ column: "id", operator: "eq", value: row.media_asset_id }],
    });
    return toManifestEntry(row, {
      action: "rekey_media_asset",
      status: "applied",
      details: { patch, target },
    });
  }

  private async transcodeMediaObject(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    if (!row.media_object_id || !row.bucket || !row.storage_path) {
      return toManifestEntry(row, {
        action: "transcode_media_object",
        status: "skipped",
        details: { reason: "missing_media_object_reference" },
      });
    }

    const source = canonicalizeStoredReference({ bucket: row.bucket, path: row.storage_path });
    const target = inferTranscodeTarget({
      bucket: source.bucket,
      path: source.path,
      contentType: row.content_type,
      kind: row.lesson_media_kind,
    });
    if (!source.bucket || !source.path || target === null) {
      return toManifestEntry(row, {
        action: "transcode_media_object",
        status: "skipped",
        details: { reason: "unsupported_transcode_target", source, target },
      });
    }

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "transcode_media_object",
        status: "planned",
        details: { source, target },
      });
    }

    const sourcePath = source.path;
    const targetPath = target.targetPath;
    await withTempDir(async (tempDir) => {
      const inputPath = path.join(tempDir, path.posix.basename(sourcePath));
      const outputPath = path.join(tempDir, path.posix.basename(targetPath));
      await this.storage.downloadObject(source.bucket!, sourcePath, inputPath);
      await transcodeWithFfmpeg({
        ffmpegBin: this.options.ffmpegBin,
        inputPath,
        outputPath,
        targetContentType: target.targetContentType,
      });
      const upload = await this.storage.createUploadUrl(
        target.bucket,
        target.targetPath,
        target.targetContentType,
      );
      await this.storage.uploadFile(upload, outputPath);
      const outputStats = await stat(outputPath);
      const probe = await this.storage.probeObject(target.bucket, target.targetPath);
      if (!probe.exists) {
        throw new Error(`Transcoded target missing after upload: ${target.bucket}/${target.targetPath}`);
      }
      await this.client.patch("media_objects", {
        storage_bucket: target.bucket,
        storage_path: target.targetPath,
        content_type: target.targetContentType,
        byte_size: outputStats.size,
        original_name: rewriteNameWithExtension(
          row.media_object_original_name,
          target.targetExtension,
          target.targetPath,
        ),
        updated_at: nowIso(),
      }, {
        filters: [{ column: "id", operator: "eq", value: row.media_object_id! }],
      });
    });

    return toManifestEntry(row, {
      action: "transcode_media_object",
      status: "applied",
      details: { targetBucket: target.bucket, targetPath: target.targetPath },
    });
  }

  private async backfillMediaAssetReference(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    if (!row.safe_matching_media_asset_id) {
      return toManifestEntry(row, {
        action: "backfill_media_asset_reference",
        status: "skipped",
        details: { reason: "missing_safe_matching_media_asset_id" },
      });
    }

    const patch = { media_asset_id: row.safe_matching_media_asset_id };

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "backfill_media_asset_reference",
        status: "planned",
        details: { patch },
      });
    }

    await this.client.patch("lesson_media", patch, {
      filters: [
        { column: "id", operator: "eq", value: row.lesson_media_id },
        { column: "media_asset_id", operator: "is", value: null },
      ],
    });

    return toManifestEntry(row, {
      action: "backfill_media_asset_reference",
      status: "applied",
      details: { patch },
    });
  }

  private async recoverMediaObjectReference(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    if (!row.media_object_id || !row.storage_recovery_bucket || !row.storage_recovery_path) {
      return toManifestEntry(row, {
        action: "recover_media_object_reference",
        status: "skipped",
        details: { reason: "missing_media_object_or_storage_recovery_target" },
      });
    }

    const patch = {
      storage_bucket: row.storage_recovery_bucket,
      storage_path: row.storage_recovery_path,
      content_type: row.storage_recovery_content_type ?? row.content_type,
      byte_size: row.storage_recovery_size_bytes ?? row.byte_size,
      updated_at: nowIso(),
    };

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "recover_media_object_reference",
        status: "planned",
        details: { patch },
      });
    }

    await this.client.patch("media_objects", patch, {
      filters: [{ column: "id", operator: "eq", value: row.media_object_id }],
    });
    return toManifestEntry(row, {
      action: "recover_media_object_reference",
      status: "applied",
      details: { patch },
    });
  }

  private async recoverMediaAssetReference(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    if (!row.media_asset_id || !row.storage_recovery_bucket || !row.storage_recovery_path) {
      return toManifestEntry(row, {
        action: "recover_media_asset_reference",
        status: "skipped",
        details: { reason: "missing_media_asset_or_storage_recovery_target" },
      });
    }

    const patch =
      row.media_state?.toLowerCase() === "ready"
        ? {
            streaming_storage_bucket: row.storage_recovery_bucket,
            streaming_object_path: row.storage_recovery_path,
            updated_at: nowIso(),
          }
        : {
            storage_bucket: row.storage_recovery_bucket,
            original_object_path: row.storage_recovery_path,
            original_content_type: row.storage_recovery_content_type ?? row.media_asset_original_content_type ?? row.content_type,
            original_size_bytes: row.storage_recovery_size_bytes ?? row.media_asset_original_size_bytes ?? row.byte_size,
            updated_at: nowIso(),
          };

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "recover_media_asset_reference",
        status: "planned",
        details: { patch },
      });
    }

    await this.client.patch("media_assets", patch, {
      filters: [{ column: "id", operator: "eq", value: row.media_asset_id }],
    });
    return toManifestEntry(row, {
      action: "recover_media_asset_reference",
      status: "applied",
      details: { patch },
    });
  }

  private async recoverDirectLessonReference(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    if (!row.storage_recovery_bucket || !row.storage_recovery_path) {
      return toManifestEntry(row, {
        action: "recover_direct_lesson_reference",
        status: "skipped",
        details: { reason: "missing_storage_recovery_target" },
      });
    }

    const patch = {
      storage_bucket: row.storage_recovery_bucket,
      storage_path: row.storage_recovery_path,
    };

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "recover_direct_lesson_reference",
        status: "planned",
        details: { patch },
      });
    }

    await this.client.patch("lesson_media", patch, {
      filters: [{ column: "id", operator: "eq", value: row.lesson_media_id }],
    });
    return toManifestEntry(row, {
      action: "recover_direct_lesson_reference",
      status: "applied",
      details: { patch },
    });
  }

  private async rekeyDirectLessonReference(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    const target = canonicalizeStoredReference({
      bucket: row.bucket,
      path: row.storage_path,
    });
    if (!target.changed || !target.bucket || !target.path) {
      return toManifestEntry(row, {
        action: "rekey_direct_lesson_reference",
        status: "skipped",
        details: { reason: "already_canonical_or_missing_target", target },
      });
    }

    let probe;
    try {
      probe = await this.storage.probeObject(target.bucket, target.path);
    } catch (error) {
      return toManifestEntry(row, {
        action: "rekey_direct_lesson_reference",
        status: "failed",
        details: {
          reason: "storage_probe_failed",
          target,
          error: error instanceof Error ? error.message : String(error),
        },
      });
    }
    if (!probe.exists) {
      return toManifestEntry(row, {
        action: "rekey_direct_lesson_reference",
        status: "failed",
        details: { reason: "canonical_target_missing_in_storage", target },
      });
    }

    const patch = {
      storage_bucket: target.bucket,
      storage_path: target.path,
    };

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "rekey_direct_lesson_reference",
        status: "planned",
        details: { patch },
      });
    }

    await this.client.patch("lesson_media", patch, {
      filters: [{ column: "id", operator: "eq", value: row.lesson_media_id }],
    });
    return toManifestEntry(row, {
      action: "rekey_direct_lesson_reference",
      status: "applied",
      details: { patch },
    });
  }

  private async transcodeDirectLessonReference(row: MediaRepairPlanRow): Promise<ChangeManifestEntry> {
    if (!row.bucket || !row.storage_path) {
      return toManifestEntry(row, {
        action: "transcode_direct_lesson_reference",
        status: "skipped",
        details: { reason: "missing_direct_reference" },
      });
    }

    const source = canonicalizeStoredReference({ bucket: row.bucket, path: row.storage_path });
    const target = inferTranscodeTarget({
      bucket: source.bucket,
      path: source.path,
      contentType: row.content_type,
      kind: row.lesson_media_kind,
    });
    if (!source.bucket || !source.path || target === null) {
      return toManifestEntry(row, {
        action: "transcode_direct_lesson_reference",
        status: "skipped",
        details: { reason: "unsupported_transcode_target", source, target },
      });
    }

    if (this.options.dryRun) {
      return toManifestEntry(row, {
        action: "transcode_direct_lesson_reference",
        status: "planned",
        details: { source, target },
      });
    }

    const sourcePath = source.path;
    const targetPath = target.targetPath;
    await withTempDir(async (tempDir) => {
      const inputPath = path.join(tempDir, path.posix.basename(sourcePath));
      const outputPath = path.join(tempDir, path.posix.basename(targetPath));
      await this.storage.downloadObject(source.bucket!, sourcePath, inputPath);
      await transcodeWithFfmpeg({
        ffmpegBin: this.options.ffmpegBin,
        inputPath,
        outputPath,
        targetContentType: target.targetContentType,
      });
      const upload = await this.storage.createUploadUrl(
        target.bucket,
        target.targetPath,
        target.targetContentType,
      );
      await this.storage.uploadFile(upload, outputPath);
      const probe = await this.storage.probeObject(target.bucket, target.targetPath);
      if (!probe.exists) {
        throw new Error(`Transcoded target missing after upload: ${target.bucket}/${target.targetPath}`);
      }
      await this.client.patch("lesson_media", {
        storage_bucket: target.bucket,
        storage_path: target.targetPath,
      }, {
        filters: [{ column: "id", operator: "eq", value: row.lesson_media_id }],
      });
    });

    return toManifestEntry(row, {
      action: "transcode_direct_lesson_reference",
      status: "applied",
      details: { targetBucket: target.bucket, targetPath: target.targetPath },
    });
  }
}

export async function runRepairExecutor(argv: string[] = process.argv.slice(2)): Promise<void> {
  if (argv.includes("--help")) {
    printUsage("repair-executor");
    return;
  }

  const env = loadServiceEnvironment(argv, "repair-executor");
  const runDir = buildRunDirectory(env.options.outputDir, "repair");
  await ensureDir(runDir);
  const logger = new StructuredLogger({ service: "repair-executor" }, path.join(runDir, "audit.log"));
  await logger.open();

  try {
    const client = new SupabaseAdminClient(
      env.supabaseUrl,
      env.serviceRoleKey,
      logger,
      env.options.retryCount,
      env.options.retryDelayMs,
    );
    const storage = new SupabaseStorageAdmin(
      env.supabaseUrl,
      env.serviceRoleKey,
      logger,
      env.options.retryCount,
      env.options.retryDelayMs,
    );
    const planRows = await loadMediaRepairPlan(client, {
      activeOnly: env.options.activeOnly,
      courseIds: env.options.courseIds,
    });
    const scopedPlanRows = filterRepairScope(planRows, env.options.fixStrategies);
    logger.info("repair.executor.scope", {
      loadedRowCount: planRows.length,
      repairScopeRowCount: scopedPlanRows.length,
      courseIds: env.options.courseIds,
      fixStrategies: env.options.fixStrategies,
      dryRun: env.options.dryRun,
    });

    const planned = buildPlannedManifest(scopedPlanRows);
    await writeJsonFile(path.join(runDir, "planned-changes.json"), planned);

    const executor = new MediaRepairExecutor(client, storage, logger, {
      dryRun: env.options.dryRun,
      minByteSize: env.options.minByteSize,
      ffmpegBin: env.options.ffmpegBin,
    });
    const executed = await executor.run(scopedPlanRows);
    await writeJsonFile(path.join(runDir, "executed-changes.json"), executed);
    await writeJsonFile(path.join(runDir, "repair-plan.json"), scopedPlanRows);

    logger.info("repair.executor.complete", {
      runDir,
      plannedCount: planned.length,
      executedCount: executed.length,
      dryRun: env.options.dryRun,
    });
  } finally {
    await logger.close();
  }
}

if (isExecutedAsMain(import.meta.url)) {
  runRepairExecutor().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
