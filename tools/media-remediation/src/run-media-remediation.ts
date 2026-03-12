import path from "node:path";

import { loadServiceEnvironment, printUsage } from "./config.js";
import {
  loadActiveMediaInventory,
  loadLessonMedia,
  loadMediaAssets,
  loadMediaObjects,
  loadMediaRepairPlanAnalysis,
  loadStorageObjects,
} from "./data.js";
import { buildRunDirectory, ensureDir, resolveWorkspaceReportPath, writeJsonFile, writeTextFile } from "./fs-utils.js";
import { StructuredLogger } from "./logger.js";
import { SupabaseAdminClient } from "./postgrest.js";
import { summarizeVerificationAsMarkdown, PostRepairVerifier } from "./post-repair-verifier.js";
import { buildPlannedManifest, MediaRepairExecutor } from "./repair-executor.js";
import { isExecutedAsMain } from "./runtime.js";
import { SafetyReportGenerator } from "./safety-report.js";
import { SupabaseStorageAdmin } from "./storage.js";
import { summarizeStorageRecoveryAsMarkdown } from "./storage-forensics.js";
import type { ActiveMediaInventoryRow, MediaRepairPlanRow, StorageCatalogEntry } from "./types.js";

function nowIso(): string {
  return new Date().toISOString();
}

function summarizeInventoryAsMarkdown(rows: ActiveMediaInventoryRow[]): string {
  const byReferenceType = rows.reduce<Record<string, number>>((counts, row) => {
    counts[row.reference_type] = (counts[row.reference_type] ?? 0) + 1;
    return counts;
  }, {});

  return [
    "# Media Inventory",
    "",
    `Generated at: ${nowIso()}`,
    "",
    `- inventory rows: ${rows.length}`,
    `- media_asset references: ${byReferenceType.media_asset ?? 0}`,
    `- media_object references: ${byReferenceType.media_object ?? 0}`,
    `- direct_storage_path references: ${byReferenceType.direct_storage_path ?? 0}`,
    "",
    "| course_id | lesson_id | lesson_media_id | reference_type | bucket | storage_path | media_state |",
    "| --- | --- | --- | --- | --- | --- | --- |",
    ...rows.map((row) => {
      const storagePath = (row.storage_path ?? "").replaceAll("|", "\\|");
      return `| ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${row.reference_type} | ${row.bucket ?? ""} | ${storagePath} | ${row.media_state ?? ""} |`;
    }),
    "",
  ].join("\n");
}

function summarizeRepairPlanAsMarkdown(rows: MediaRepairPlanRow[]): string {
  const issueCounts = rows.reduce<Record<string, number>>((counts, row) => {
    const issueType = row.issue_type ?? "NO_ISSUE";
    counts[issueType] = (counts[issueType] ?? 0) + 1;
    return counts;
  }, {});

  const lines = [
    "# Media Repair Plan",
    "",
    `Generated at: ${nowIso()}`,
    "",
    `- rows in repair scope: ${rows.length}`,
    ...Object.entries(issueCounts)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([issueType, count]) => `- ${issueType}: ${count}`),
    "",
    "| repair_priority | issue_type | fix_strategy | course_id | lesson_id | lesson_media_id | bucket | storage_path |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
  ];

  for (const row of rows) {
    const storagePath = (row.storage_path ?? "").replaceAll("|", "\\|");
    lines.push(
      `| ${row.repair_priority} | ${row.issue_type ?? ""} | ${row.fix_strategy} | ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${row.bucket ?? ""} | ${storagePath} |`,
    );
  }

  lines.push("");
  return lines.join("\n");
}

function summarizeStorageCatalogAsMarkdown(rows: StorageCatalogEntry[]): string {
  const byBucket = rows.reduce<Record<string, number>>((counts, row) => {
    counts[row.bucket] = (counts[row.bucket] ?? 0) + 1;
    return counts;
  }, {});

  return [
    "# Storage Catalog",
    "",
    `Generated at: ${nowIso()}`,
    "",
    `- storage objects catalogued: ${rows.length}`,
    ...Object.entries(byBucket)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([bucket, count]) => `- ${bucket}: ${count}`),
    "",
    "| bucket | storage_path | filename | extension | size | content_type | etag | created_at |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ...rows.map((row) =>
      `| ${row.bucket} | ${row.storage_path.replaceAll("|", "\\|")} | ${row.filename.replaceAll("|", "\\|")} | ${row.extension ?? ""} | ${row.size ?? ""} | ${row.content_type ?? ""} | ${row.etag ?? ""} | ${row.created_at ?? ""} |`,
    ),
    "",
  ].join("\n");
}

export async function runMediaRemediation(argv: string[] = process.argv.slice(2)): Promise<void> {
  if (argv.includes("--help")) {
    printUsage("run-media-remediation");
    return;
  }

  const env = loadServiceEnvironment(argv, "run-media-remediation");
  const runDir = buildRunDirectory(env.options.outputDir, "pipeline");
  await ensureDir(runDir);
  const logger = new StructuredLogger({ service: "run-media-remediation" }, path.join(runDir, "audit.log"));
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

    logger.info("pipeline.phase.start", { phase: "storage_catalog" });
    const planAnalysisPromise = loadMediaRepairPlanAnalysis(client, {
      activeOnly: false,
      courseIds: env.options.courseIds,
    });
    const storageCatalog = (await planAnalysisPromise).storageCatalog;
    await writeJsonFile(resolveWorkspaceReportPath("storage-catalog.json"), storageCatalog);
    await writeJsonFile(path.join(runDir, "00-storage-catalog.json"), storageCatalog);
    await writeTextFile(path.join(runDir, "00-storage-catalog.md"), summarizeStorageCatalogAsMarkdown(storageCatalog));
    logger.info("pipeline.phase.complete", {
      phase: "storage_catalog",
      rowCount: storageCatalog.length,
      reportPath: resolveWorkspaceReportPath("storage-catalog.json"),
    });

    logger.info("pipeline.phase.start", { phase: "read_only_inventory" });
    const allInventoryRows = await loadActiveMediaInventory(client, {
      activeOnly: false,
      courseIds: env.options.courseIds,
    });
    const inScopeInventoryRows = allInventoryRows.filter((row) => row.is_inventory_in_scope);
    await writeJsonFile(path.join(runDir, "01-active-media-inventory.json"), inScopeInventoryRows);
    await writeTextFile(path.join(runDir, "01-active-media-inventory.md"), summarizeInventoryAsMarkdown(inScopeInventoryRows));
    logger.info("pipeline.phase.complete", {
      phase: "read_only_inventory",
      allRowCount: allInventoryRows.length,
      inventoryScopeRowCount: inScopeInventoryRows.length,
    });

    logger.info("pipeline.phase.start", { phase: "media_issue_classification" });
    const planAnalysis = await planAnalysisPromise;
    const allPlanRows = planAnalysis.rows;
    const inScopePlanRows = allPlanRows.filter(
      (row) => row.is_inventory_in_scope && row.issue_type !== null && row.fix_strategy !== "NO_ACTION",
    );
    await writeJsonFile(path.join(runDir, "02-storage-recovery-report.json"), {
      generatedAt: nowIso(),
      summary: planAnalysis.recoverySummary,
      rows: planAnalysis.recoveryReportRows,
    });
    await writeTextFile(
      path.join(runDir, "02-storage-recovery-report.md"),
      summarizeStorageRecoveryAsMarkdown(planAnalysis.recoveryReportRows, planAnalysis.recoverySummary),
    );
    await writeJsonFile(path.join(runDir, "02-media-repair-plan.json"), inScopePlanRows);
    await writeTextFile(path.join(runDir, "02-media-repair-plan.md"), summarizeRepairPlanAsMarkdown(inScopePlanRows));
    logger.info("pipeline.phase.complete", {
      phase: "media_issue_classification",
      allRowCount: allPlanRows.length,
      repairScopeRowCount: inScopePlanRows.length,
      storageRecoveryRowsReduced: planAnalysis.recoverySummary.rows_reduced_from_manual_reupload_required,
      storageRecoverySafeAutoRecoverCount: planAnalysis.recoverySummary.safe_auto_recover_count,
    });

    logger.info("pipeline.phase.start", { phase: "repair_execution", dryRun: env.options.dryRun });
    const plannedManifest = buildPlannedManifest(inScopePlanRows);
    await writeJsonFile(path.join(runDir, "03-planned-repair-manifest.json"), plannedManifest);
    const executor = new MediaRepairExecutor(client, storage, logger, {
      dryRun: env.options.dryRun,
      minByteSize: env.options.minByteSize,
      ffmpegBin: env.options.ffmpegBin,
    });
    const executedManifest = await executor.run(inScopePlanRows);
    await writeJsonFile(path.join(runDir, "03-executed-repair-manifest.json"), executedManifest);
    logger.info("pipeline.phase.complete", {
      phase: "repair_execution",
      plannedChangeCount: plannedManifest.length,
      executedChangeCount: executedManifest.length,
      dryRun: env.options.dryRun,
    });

    logger.info("pipeline.phase.start", { phase: "post_repair_verification" });
    const refreshedInventoryRows = await loadActiveMediaInventory(client, {
      activeOnly: true,
      courseIds: env.options.courseIds,
    });
    const refreshedPlanRows = (await loadMediaRepairPlanAnalysis(client, {
      activeOnly: true,
      courseIds: env.options.courseIds,
    })).rows;
    const verifier = new PostRepairVerifier(storage, logger, env.options.minByteSize);
    const verificationResults = await verifier.verify(
      refreshedInventoryRows,
      new Map(refreshedPlanRows.map((row) => [row.lesson_media_id, row])),
      { simulatePlannedRepairs: env.options.dryRun },
    );
    await writeJsonFile(path.join(runDir, "04-post-repair-verification.json"), verificationResults);
    await writeTextFile(
      path.join(runDir, "04-post-repair-verification.md"),
      summarizeVerificationAsMarkdown(verificationResults),
    );
    logger.info("pipeline.phase.complete", {
      phase: "post_repair_verification",
      rowCount: verificationResults.length,
      failCount: verificationResults.filter((row) => row.status === "FAIL").length,
    });

    logger.info("pipeline.phase.start", { phase: "safety_report" });
    const [lessonMediaRows, mediaObjectRows, mediaAssetRows, storageObjectRows] = await Promise.all([
      loadLessonMedia(client),
      loadMediaObjects(client),
      loadMediaAssets(client),
      loadStorageObjects(client),
    ]);
    const safetyGenerator = new SafetyReportGenerator(logger, env.options.minByteSize);
    const safetyReport = safetyGenerator.generate({
      inventoryRows: await loadActiveMediaInventory(client, {
        activeOnly: false,
        courseIds: env.options.courseIds,
      }),
      lessonMediaRows,
      mediaObjectRows,
      mediaAssetRows,
      storageObjectRows,
      courseIds: env.options.courseIds,
    });
    await writeJsonFile(path.join(runDir, "05-safety-report.json"), safetyReport);
    await writeTextFile(
      path.join(runDir, "05-safety-report.md"),
      [
        "# Safety Report",
        "",
        `Generated at: ${nowIso()}`,
        "",
        "- No deletion performed",
        `- SAFE_TO_QUARANTINE: ${safetyReport.filter((row) => row.group === "SAFE_TO_QUARANTINE").length}`,
        `- NEEDS_MANUAL_REVIEW: ${safetyReport.filter((row) => row.group === "NEEDS_MANUAL_REVIEW").length}`,
        `- BLOCKED_BY_ACTIVE_REFERENCE: ${safetyReport.filter((row) => row.group === "BLOCKED_BY_ACTIVE_REFERENCE").length}`,
        "",
        "| group | detected_reason | bucket | storage_path | referenced_by_active_media |",
        "| --- | --- | --- | --- | --- |",
        ...safetyReport.map((row) => {
          const storagePath = row.storage_path.replaceAll("|", "\\|");
          return `| ${row.group} | ${row.detected_reason} | ${row.bucket} | ${storagePath} | ${row.referenced_by_active_media} |`;
        }),
        "",
      ].join("\n"),
    );
    logger.info("pipeline.phase.complete", {
      phase: "safety_report",
      candidateCount: safetyReport.length,
    });

    await writeJsonFile(path.join(runDir, "pipeline-summary.json"), {
      generatedAt: nowIso(),
      dryRun: env.options.dryRun,
      courseIds: env.options.courseIds,
      counts: {
        inventoryScopeRows: inScopeInventoryRows.length,
        repairScopeRows: inScopePlanRows.length,
        plannedChanges: plannedManifest.length,
        executedChanges: executedManifest.length,
        verificationRows: verificationResults.length,
        verificationFailures: verificationResults.filter((row) => row.status === "FAIL").length,
        safetyCandidates: safetyReport.length,
        storageCatalogRows: storageCatalog.length,
        storageRecoveryRowsReduced: planAnalysis.recoverySummary.rows_reduced_from_manual_reupload_required,
        storageRecoverySafeAutoRecoverCount: planAnalysis.recoverySummary.safe_auto_recover_count,
        storageRecoveryProbableMatchCount: planAnalysis.recoverySummary.probable_match_count,
        storageRecoveryAmbiguousMatchCount: planAnalysis.recoverySummary.ambiguous_match_count,
        storageRecoveryNoMatchCount: planAnalysis.recoverySummary.no_match_count,
      },
    });
  } finally {
    await logger.close();
  }
}

if (isExecutedAsMain(import.meta.url)) {
  runMediaRemediation().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
