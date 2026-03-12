import path from "node:path";

import { loadServiceEnvironment, printUsage } from "./config.js";
import {
  loadActiveMediaInventory,
  loadLessonMedia,
  loadMediaAssets,
  loadMediaObjects,
  loadMediaRepairPlan,
  loadStorageObjects,
} from "./data.js";
import { buildRunDirectory, ensureDir, writeJsonFile, writeTextFile } from "./fs-utils.js";
import { StructuredLogger } from "./logger.js";
import { SupabaseAdminClient } from "./postgrest.js";
import { summarizeVerificationAsMarkdown, PostRepairVerifier } from "./post-repair-verifier.js";
import { buildPlannedManifest, MediaRepairExecutor } from "./repair-executor.js";
import { isExecutedAsMain } from "./runtime.js";
import { SafetyReportGenerator } from "./safety-report.js";
import { SupabaseStorageAdmin } from "./storage.js";
import type { ActiveMediaInventoryRow, MediaRepairPlanRow } from "./types.js";

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
    const allPlanRows = await loadMediaRepairPlan(client, {
      activeOnly: false,
      courseIds: env.options.courseIds,
    });
    const inScopePlanRows = allPlanRows.filter(
      (row) => row.is_inventory_in_scope && row.issue_type !== null && row.fix_strategy !== "NO_ACTION",
    );
    await writeJsonFile(path.join(runDir, "02-media-repair-plan.json"), inScopePlanRows);
    await writeTextFile(path.join(runDir, "02-media-repair-plan.md"), summarizeRepairPlanAsMarkdown(inScopePlanRows));
    logger.info("pipeline.phase.complete", {
      phase: "media_issue_classification",
      allRowCount: allPlanRows.length,
      repairScopeRowCount: inScopePlanRows.length,
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
    const refreshedPlanRows = await loadMediaRepairPlan(client, {
      activeOnly: true,
      courseIds: env.options.courseIds,
    });
    const verifier = new PostRepairVerifier(storage, logger, env.options.minByteSize);
    const verificationResults = await verifier.verify(
      refreshedInventoryRows,
      new Map(refreshedPlanRows.map((row) => [row.lesson_media_id, row])),
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
