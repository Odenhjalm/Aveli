import path from "node:path";

import { loadServiceEnvironment, printUsage } from "./config.js";
import { loadActiveMediaInventory, loadMediaRepairPlan } from "./data.js";
import { buildRunDirectory, ensureDir, writeJsonFile, writeTextFile } from "./fs-utils.js";
import { StructuredLogger } from "./logger.js";
import { SupabaseAdminClient } from "./postgrest.js";
import { areMediaKindsCompatible, isSupportedPlaybackFormat } from "./repair-utils.js";
import { isExecutedAsMain } from "./runtime.js";
import { SupabaseStorageAdmin } from "./storage.js";
import type {
  ActiveMediaInventoryRow,
  MediaRepairPlanRow,
  StorageProbe,
  VerificationResult,
  VerificationStatus,
} from "./types.js";

function nowIso(): string {
  return new Date().toISOString();
}

function isAuthFailure(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("auth failed") || message.includes(": 401 ") || message.includes(": 403 ");
}

function computeReferenceCanonicality(row: ActiveMediaInventoryRow): boolean {
  if (row.reference_type === "media_asset") {
    if (row.media_state?.toLowerCase() !== "ready") {
      return false;
    }
    return row.storage_path === row.media_asset_stream_path;
  }
  if (row.reference_type === "media_object") {
    return row.storage_path === row.media_object_path;
  }
  return row.storage_path === row.lesson_storage_path;
}

export function summarizeVerificationAsMarkdown(results: VerificationResult[]): string {
  const summary = {
    PASS: results.filter((item) => item.status === "PASS").length,
    WARNING: results.filter((item) => item.status === "WARNING").length,
    FAIL: results.filter((item) => item.status === "FAIL").length,
  };

  const header = [
    "# Post-Repair Verification",
    "",
    `Generated at: ${nowIso()}`,
    "",
    `- PASS: ${summary.PASS}`,
    `- WARNING: ${summary.WARNING}`,
    `- FAIL: ${summary.FAIL}`,
    "",
    "| status | course_id | lesson_id | lesson_media_id | message |",
    "| --- | --- | --- | --- | --- |",
  ];

  const body = results.map((result) => {
    const message = result.message.replaceAll("\n", " ").replaceAll("|", "\\|");
    return `| ${result.status} | ${result.courseId} | ${result.lessonId} | ${result.lessonMediaId} | ${message} |`;
  });

  return [...header, ...body, ""].join("\n");
}

export class PostRepairVerifier {
  public constructor(
    private readonly storage: SupabaseStorageAdmin,
    private readonly logger: StructuredLogger,
    private readonly minByteSize: number,
  ) {}

  public async verify(
    inventory: ActiveMediaInventoryRow[],
    planRows: Map<string, MediaRepairPlanRow>,
  ): Promise<VerificationResult[]> {
    const results: VerificationResult[] = [];

    for (const row of inventory) {
      const plan = planRows.get(row.lesson_media_id) ?? null;
      let probe: StorageProbe = {
        bucket: row.bucket ?? "",
        path: row.storage_path ?? "",
        exists: false,
        statusCode: 0,
        contentType: null,
        contentLength: null,
      };
      let probeError: string | null = null;
      let probeAuthFailure = false;
      if (row.bucket && row.storage_path) {
        try {
          probe = await this.storage.probeObject(row.bucket, row.storage_path);
        } catch (error) {
          probeError = error instanceof Error ? error.message : String(error);
          probeAuthFailure = isAuthFailure(error);
        }
      }

      const supported = isSupportedPlaybackFormat({
        kind: row.lesson_media_kind,
        contentType: probe.contentType ?? row.content_type,
        storagePath: row.storage_path,
      });
      const byteSize = probe.contentLength ?? row.byte_size ?? 0;
      const assetReady = row.media_asset_id === null || row.media_state?.toLowerCase() === "ready";
      const canonicalReference = computeReferenceCanonicality(row);
      const mediaKindCompatible = areMediaKindsCompatible({
        lessonMediaKind: row.lesson_media_kind,
        mediaAssetType: row.media_asset_type,
      });

      let status: VerificationStatus = "PASS";
      const messages: string[] = [];
      if (probeError !== null) {
        status = "FAIL";
        messages.push(probeAuthFailure ? "storage probe auth failure" : "storage probe failed");
      }
      if (probeError === null && !probe.exists) {
        status = "FAIL";
        messages.push("storage object missing");
      }
      if (!assetReady) {
        status = "FAIL";
        messages.push(`media asset state is ${row.media_state ?? "unknown"}`);
      }
      if (!canonicalReference) {
        status = "FAIL";
        messages.push("lesson_media does not point at the canonical object");
      }
      if (!mediaKindCompatible) {
        status = "FAIL";
        messages.push(
          `lesson_media kind ${row.lesson_media_kind ?? "unknown"} conflicts with media asset type ${row.media_asset_type ?? "unknown"}`,
        );
      }
      if (status !== "FAIL" && !supported) {
        status = "WARNING";
        messages.push("playback format remains unsupported");
      }
      if (status !== "FAIL" && byteSize > 0 && byteSize < this.minByteSize) {
        status = "WARNING";
        messages.push(`byte size below threshold (${byteSize} < ${this.minByteSize})`);
      }
      if (messages.length === 0) {
        messages.push("verification checks passed");
      }

      const result: VerificationResult = {
        status,
        courseId: row.course_id,
        lessonId: row.lesson_id,
        lessonMediaId: row.lesson_media_id,
        issueType: plan?.issue_type ?? null,
        message: messages.join("; "),
        details: {
          bucket: row.bucket,
          storagePath: row.storage_path,
          probe,
          probeError,
          probeAuthFailure,
          supported,
          byteSize,
          assetReady,
          canonicalReference,
          mediaKindCompatible,
        },
      };
      results.push(result);
      this.logger.info("verification.row", {
        lessonMediaId: result.lessonMediaId,
        status: result.status,
        message: result.message,
        ...result.details,
      });
    }

    return results;
  }
}

export async function runPostRepairVerifier(argv: string[] = process.argv.slice(2)): Promise<void> {
  if (argv.includes("--help")) {
    printUsage("post-repair-verifier");
    return;
  }

  const env = loadServiceEnvironment(argv, "post-repair-verifier");
  const runDir = buildRunDirectory(env.options.outputDir, "verification");
  await ensureDir(runDir);
  const logger = new StructuredLogger({ service: "post-repair-verifier" }, path.join(runDir, "audit.log"));
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
    const [inventoryRows, repairPlanRows] = await Promise.all([
      loadActiveMediaInventory(client, {
        activeOnly: env.options.activeOnly,
        courseIds: env.options.courseIds,
      }),
      loadMediaRepairPlan(client, {
        activeOnly: env.options.activeOnly,
        courseIds: env.options.courseIds,
      }),
    ]);
    const planMap = new Map(repairPlanRows.map((row) => [row.lesson_media_id, row]));
    const verifier = new PostRepairVerifier(storage, logger, env.options.minByteSize);
    const results = await verifier.verify(inventoryRows, planMap);

    await writeJsonFile(path.join(runDir, "verification-results.json"), results);
    await writeTextFile(path.join(runDir, "verification-results.md"), summarizeVerificationAsMarkdown(results));
    logger.info("verification.complete", {
      runDir,
      rowCount: results.length,
      failCount: results.filter((result) => result.status === "FAIL").length,
    });
  } finally {
    await logger.close();
  }
}

if (isExecutedAsMain(import.meta.url)) {
  runPostRepairVerifier().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
