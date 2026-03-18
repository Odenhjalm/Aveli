import { readFile } from "node:fs/promises";
import path from "node:path";

import { loadServiceEnvironment, printUsage } from "./config.js";
import { loadActiveMediaInventory, loadMediaRepairPlan } from "./data.js";
import { clearDerivedViewCaches } from "./derived-views.js";
import { buildRunDirectory, ensureDir, writeJsonFile, writeTextFile } from "./fs-utils.js";
import { StructuredLogger } from "./logger.js";
import { summarizeVerificationAsMarkdown, PostRepairVerifier } from "./post-repair-verifier.js";
import { SupabaseAdminClient } from "./postgrest.js";
import type { Filter } from "./postgrest.js";
import {
  areMediaKindsCompatible,
  hasCompatibleExtension,
  hasCompatibleMime,
} from "./repair-utils.js";
import { isExecutedAsMain } from "./runtime.js";
import { SupabaseStorageAdmin } from "./storage.js";
import type {
  ActiveMediaInventoryRow,
  MediaRepairPlanRow,
  StorageProbe,
  StorageRecoveryReportRow,
  VerificationResult,
} from "./types.js";

type RecoveryResource = "lesson_media" | "media_assets" | "media_objects";
type UpdateStatus = "pending" | "applied" | "failed" | "not_run";
type RowStatus = "PASS" | "FAIL" | "NOT_RUN";
type SafeAutoRecoverReportRow = StorageRecoveryReportRow & { classification: "SAFE_AUTO_RECOVER" };

interface StorageRecoveryReportDocument {
  generatedAt?: string;
  summary?: unknown;
  rows: StorageRecoveryReportRow[];
}

interface RecoveryMutationPlan {
  resource: RecoveryResource;
  target_id: string;
  patch: Record<string, number | string | null | undefined>;
  sql: string;
}

interface RecoveryExecution {
  lesson_media_id: string;
  course_id: string;
  lesson_id: string;
  reference_type: ActiveMediaInventoryRow["reference_type"];
  target_table: RecoveryResource;
  target_id: string | null;
  matched_storage_bucket: string | null;
  matched_storage_path: string | null;
  sql: string | null;
  preflight_probe: StorageProbe | null;
  preflight_probe_error: string | null;
  update_status: UpdateStatus;
  update_row_count: number;
  verification_status: RowStatus;
  verification_result: VerificationResult | null;
  verification_summary: {
    storage_head_check: boolean;
    mime_compatible: boolean;
    lesson_media_kind_compatible: boolean;
    playback_path_resolves: boolean;
    verification_pass: boolean;
  } | null;
  stop_reason: string | null;
}

interface ControlledRecoveryReport {
  generated_at: string;
  apply: boolean;
  report_path: string;
  selected_rows: Array<{
    course_id: string;
    lesson_id: string;
    lesson_media_id: string;
    reference_type: ActiveMediaInventoryRow["reference_type"];
    matched_storage_bucket: string | null;
    matched_storage_path: string | null;
    confidence_score: number;
    match_reason: string;
    fix_strategy_before: string;
    fix_strategy_after: string;
  }>;
  exact_sql_mutations_executed: string[];
  verification_results_per_row: RecoveryExecution[];
  updated_inventory_snapshot: ActiveMediaInventoryRow[];
  remaining_manual_reupload_required_count: number;
  aborted: boolean;
  abort_reason: string | null;
}

function nowIso(): string {
  return new Date().toISOString();
}

function parseValue(argv: string[], flag: string): string | null {
  const index = argv.findIndex((item) => item === flag);
  if (index === -1) {
    return null;
  }
  return argv[index + 1] ?? null;
}

function quoteSqlLiteral(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

function renderSqlValue(value: number | string | null): string {
  if (value === null) {
    return "null";
  }
  if (typeof value === "number") {
    return `${value}`;
  }
  return quoteSqlLiteral(value);
}

export function filterSafeAutoRecoverRows(rows: StorageRecoveryReportRow[]): SafeAutoRecoverReportRow[] {
  return rows.filter(
    (row): row is SafeAutoRecoverReportRow => row.classification === "SAFE_AUTO_RECOVER",
  );
}

function selectOrderedPatchEntries(
  patch: Record<string, number | string | null | undefined>,
  preferredOrder: string[],
): Array<[string, number | string | null]> {
  const entries = preferredOrder
    .filter((key) => key in patch && patch[key] !== undefined)
    .map((key) => [key, patch[key] ?? null] as [string, number | string | null]);
  const remainder = Object.entries(patch)
    .filter(([key, value]) => !preferredOrder.includes(key) && value !== undefined)
    .sort(([left], [right]) => left.localeCompare(right)) as Array<[string, number | string | null]>;
  return [...entries, ...remainder];
}

function renderUpdateSql(
  resource: RecoveryResource,
  patch: Record<string, number | string | null | undefined>,
  targetId: string,
): string {
  const preferredOrderByResource: Record<RecoveryResource, string[]> = {
    lesson_media: ["storage_bucket", "storage_path"],
    media_assets: [
      "streaming_storage_bucket",
      "streaming_object_path",
      "storage_bucket",
      "original_object_path",
    ],
    media_objects: ["storage_bucket", "storage_path"],
  };
  const assignments = selectOrderedPatchEntries(patch, preferredOrderByResource[resource])
    .map(([key, value]) => `${key} = ${renderSqlValue(value)}`)
    .join(", ");
  return `update app.${resource} set ${assignments} where id = ${quoteSqlLiteral(targetId)};`;
}

export function buildRecoveryMutationPlan(row: MediaRepairPlanRow): RecoveryMutationPlan {
  if (!row.storage_recovery_bucket || !row.storage_recovery_path) {
    throw new Error(`Missing storage recovery target for lesson_media ${row.lesson_media_id}`);
  }

  if (row.reference_type === "media_object") {
    if (!row.media_object_id) {
      throw new Error(`Missing media_object_id for lesson_media ${row.lesson_media_id}`);
    }
    const patch = {
      storage_bucket: row.storage_recovery_bucket,
      storage_path: row.storage_recovery_path,
    };
    return {
      resource: "media_objects",
      target_id: row.media_object_id,
      patch,
      sql: renderUpdateSql("media_objects", patch, row.media_object_id),
    };
  }

  if (row.reference_type === "media_asset") {
    if (!row.media_asset_id) {
      throw new Error(`Missing media_asset_id for lesson_media ${row.lesson_media_id}`);
    }
    const ready = (row.media_state ?? "").trim().toLowerCase() === "ready";
    const patch = ready
      ? {
          streaming_storage_bucket: row.storage_recovery_bucket,
          streaming_object_path: row.storage_recovery_path,
        }
      : {
          storage_bucket: row.storage_recovery_bucket,
          original_object_path: row.storage_recovery_path,
        };
    return {
      resource: "media_assets",
      target_id: row.media_asset_id,
      patch,
      sql: renderUpdateSql("media_assets", patch, row.media_asset_id),
    };
  }

  const patch = {
    storage_bucket: row.storage_recovery_bucket,
    storage_path: row.storage_recovery_path,
  };
  return {
    resource: "lesson_media",
    target_id: row.lesson_media_id,
    patch,
    sql: renderUpdateSql("lesson_media", patch, row.lesson_media_id),
  };
}

function summarizeSelectedRows(rows: SafeAutoRecoverReportRow[]): ControlledRecoveryReport["selected_rows"] {
  return rows.map((row) => ({
    course_id: row.course_id,
    lesson_id: row.lesson_id,
    lesson_media_id: row.lesson_media_id,
    reference_type: row.reference_type,
    matched_storage_bucket: row.matched_storage_bucket,
    matched_storage_path: row.matched_storage_path,
    confidence_score: row.confidence_score,
    match_reason: row.match_reason,
    fix_strategy_before: row.fix_strategy_before,
    fix_strategy_after: row.fix_strategy_after,
  }));
}

function summarizeInventoryRows(rows: ActiveMediaInventoryRow[]): string[] {
  return rows.map((row) =>
    `| ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${row.reference_type} | ${row.bucket ?? ""} | ${(row.storage_path ?? "").replaceAll("|", "\\|")} | ${row.content_type ?? ""} |`,
  );
}

function renderMarkdownReport(report: ControlledRecoveryReport): string {
  const verificationRows = report.verification_results_per_row.map((row) => {
    const message = row.verification_result?.message ?? row.stop_reason ?? "";
    return `| ${row.verification_status} | ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${message.replaceAll("|", "\\|")} |`;
  });

  const selectedRows = report.selected_rows.map((row) =>
    `| ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${row.reference_type} | ${row.confidence_score} | ${(row.matched_storage_path ?? "").replaceAll("|", "\\|")} |`,
  );

  return [
    "# SAFE_AUTO_RECOVER Controlled Recovery",
    "",
    `Generated at: ${report.generated_at}`,
    "",
    `- apply: ${report.apply}`,
    `- report_path: ${report.report_path}`,
    `- selected_rows: ${report.selected_rows.length}`,
    `- executed_sql_mutations: ${report.exact_sql_mutations_executed.length}`,
    `- remaining_manual_reupload_required_count: ${report.remaining_manual_reupload_required_count}`,
    `- aborted: ${report.aborted}`,
    `- abort_reason: ${report.abort_reason ?? "none"}`,
    "",
    "## Rows Selected",
    "",
    "| course_id | lesson_id | lesson_media_id | reference_type | confidence_score | matched_storage_path |",
    "| --- | --- | --- | --- | --- | --- |",
    ...selectedRows,
    "",
    "## Exact SQL Mutations Executed",
    "",
    "```sql",
    ...(report.exact_sql_mutations_executed.length > 0
      ? report.exact_sql_mutations_executed
      : ["-- no SQL mutations executed"]),
    "```",
    "",
    "## Verification Results Per Row",
    "",
    "| status | course_id | lesson_id | lesson_media_id | message |",
    "| --- | --- | --- | --- | --- |",
    ...verificationRows,
    "",
    "## Updated Inventory Snapshot",
    "",
    "| course_id | lesson_id | lesson_media_id | reference_type | bucket | storage_path | content_type |",
    "| --- | --- | --- | --- | --- | --- | --- |",
    ...summarizeInventoryRows(report.updated_inventory_snapshot),
    "",
  ].join("\n");
}

async function loadRecoveryReport(filePath: string): Promise<StorageRecoveryReportDocument> {
  const raw = await readFile(filePath, "utf8");
  const parsed = JSON.parse(raw) as StorageRecoveryReportDocument;
  if (!parsed || !Array.isArray(parsed.rows)) {
    throw new Error(`Invalid storage recovery report at ${filePath}`);
  }
  return parsed;
}

async function loadCurrentLessonContext(
  client: SupabaseAdminClient,
  courseId: string,
  lessonMediaId: string,
): Promise<{
  inventoryRow: ActiveMediaInventoryRow | null;
  planRow: MediaRepairPlanRow | null;
}> {
  clearDerivedViewCaches();
  const [inventoryRows, planRows] = await Promise.all([
    loadActiveMediaInventory(client, {
      activeOnly: false,
      courseIds: [courseId],
    }),
    loadMediaRepairPlan(client, {
      activeOnly: false,
      courseIds: [courseId],
    }),
  ]);

  return {
    inventoryRow: inventoryRows.find((row) => row.lesson_media_id === lessonMediaId) ?? null,
    planRow: planRows.find((row) => row.lesson_media_id === lessonMediaId) ?? null,
  };
}

function currentRowMatchesTarget(
  row: ActiveMediaInventoryRow,
  target: SafeAutoRecoverReportRow,
): boolean {
  return row.bucket === target.matched_storage_bucket && row.storage_path === target.matched_storage_path;
}

function filtersForMutation(mutation: RecoveryMutationPlan): Filter[] {
  return [{ column: "id", operator: "eq", value: mutation.target_id }];
}

async function verifyRecoveredRow(
  client: SupabaseAdminClient,
  storage: SupabaseStorageAdmin,
  logger: StructuredLogger,
  minByteSize: number,
  courseId: string,
  lessonMediaId: string,
): Promise<{
  inventoryRow: ActiveMediaInventoryRow | null;
  verificationResult: VerificationResult;
  verificationSummary: NonNullable<RecoveryExecution["verification_summary"]>;
}> {
  clearDerivedViewCaches();
  const [inventoryRows, planRows] = await Promise.all([
    loadActiveMediaInventory(client, {
      activeOnly: false,
      courseIds: [courseId],
    }),
    loadMediaRepairPlan(client, {
      activeOnly: false,
      courseIds: [courseId],
    }),
  ]);
  const inventoryRow = inventoryRows.find((row) => row.lesson_media_id === lessonMediaId) ?? null;
  if (inventoryRow === null) {
    const verificationResult: VerificationResult = {
      status: "FAIL",
      courseId,
      lessonId: "",
      lessonMediaId,
      issueType: null,
      message: "failed to reload lesson_media row after update",
      details: {},
    };
    return {
      inventoryRow,
      verificationResult,
      verificationSummary: {
        storage_head_check: false,
        mime_compatible: false,
        lesson_media_kind_compatible: false,
        playback_path_resolves: false,
        verification_pass: false,
      },
    };
  }

  const verifier = new PostRepairVerifier(storage, logger, minByteSize);
  const [verificationResult] = await verifier.verify(
    [inventoryRow],
    new Map(planRows.map((row) => [row.lesson_media_id, row])),
  );

  const probe = (verificationResult?.details.probe ?? null) as StorageProbe | null;
  const probeError = typeof verificationResult?.details.probeError === "string"
    ? verificationResult.details.probeError
    : null;
  const resolvedContentType = probe?.contentType ?? inventoryRow.content_type;
  const mimeCompatible = hasCompatibleMime({
    lessonMediaKind: inventoryRow.lesson_media_kind,
    contentType: resolvedContentType,
  });
  const extensionCompatible = hasCompatibleExtension({
    lessonMediaKind: inventoryRow.lesson_media_kind,
    storagePath: inventoryRow.storage_path,
  });
  const lessonMediaKindCompatible = areMediaKindsCompatible({
    lessonMediaKind: inventoryRow.lesson_media_kind,
    mediaAssetType: inventoryRow.media_asset_type,
  }) && extensionCompatible;
  const storageHeadCheck = probeError === null && probe?.exists === true;
  const playbackPathResolves = storageHeadCheck;
  const verificationPass =
    verificationResult.status === "PASS"
    && storageHeadCheck
    && mimeCompatible
    && lessonMediaKindCompatible
    && playbackPathResolves;

  return {
    inventoryRow,
    verificationResult,
    verificationSummary: {
      storage_head_check: storageHeadCheck,
      mime_compatible: mimeCompatible,
      lesson_media_kind_compatible: lessonMediaKindCompatible,
      playback_path_resolves: playbackPathResolves,
      verification_pass: verificationPass,
    },
  };
}

function buildExecutionStub(row: SafeAutoRecoverReportRow): RecoveryExecution {
  return {
    lesson_media_id: row.lesson_media_id,
    course_id: row.course_id,
    lesson_id: row.lesson_id,
    reference_type: row.reference_type,
    target_table: row.reference_type === "media_object"
      ? "media_objects"
      : row.reference_type === "media_asset"
        ? "media_assets"
        : "lesson_media",
    target_id: null,
    matched_storage_bucket: row.matched_storage_bucket,
    matched_storage_path: row.matched_storage_path,
    sql: null,
    preflight_probe: null,
    preflight_probe_error: null,
    update_status: "pending",
    update_row_count: 0,
    verification_status: "NOT_RUN",
    verification_result: null,
    verification_summary: null,
    stop_reason: null,
  };
}

async function countRemainingManualReuploadRequired(client: SupabaseAdminClient, courseIds: string[]): Promise<number> {
  clearDerivedViewCaches();
  const planRows = await loadMediaRepairPlan(client, {
    activeOnly: false,
    courseIds,
  });
  return planRows.filter((row) => row.fix_strategy === "MANUAL_REUPLOAD_REQUIRED").length;
}

export async function runStorageRecoveryPilot(argv: string[] = process.argv.slice(2)): Promise<void> {
  if (argv.includes("--help")) {
    printUsage("storage-recovery-pilot");
    process.stdout.write("\n  Live apply requires --apply --report-path <path-to-02-storage-recovery-report.json>.\n");
    return;
  }

  const reportPath = parseValue(argv, "--report-path");
  if (!reportPath) {
    throw new Error("--report-path is required");
  }

  const env = loadServiceEnvironment(argv, "storage-recovery-pilot");
  const apply = argv.includes("--apply");
  const resolvedReportPath = path.resolve(reportPath);
  const runDir = buildRunDirectory(env.options.outputDir, "storage-recovery-pilot");
  await ensureDir(runDir);
  const logger = new StructuredLogger(
    { service: "storage-recovery-pilot" },
    path.join(runDir, "audit.log"),
  );
  await logger.open();

  try {
    const report = await loadRecoveryReport(resolvedReportPath);
    const selectedRows = filterSafeAutoRecoverRows(report.rows).filter((row) =>
      env.options.courseIds.length === 0 || env.options.courseIds.includes(row.course_id)
    );

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

    const rowExecutions: RecoveryExecution[] = [];
    const exactSqlMutationsExecuted: string[] = [];
    const affectedLessonIds = new Set(selectedRows.map((row) => row.lesson_id));
    const affectedCourseIds = new Set(selectedRows.map((row) => row.course_id));
    let aborted = false;
    let abortReason: string | null = null;

    for (const selected of selectedRows) {
      const execution = buildExecutionStub(selected);

      if (!selected.matched_storage_bucket || !selected.matched_storage_path) {
        execution.update_status = "failed";
        execution.verification_status = "FAIL";
        execution.stop_reason = "missing_recovery_target";
        rowExecutions.push(execution);
        aborted = true;
        abortReason = `Missing recovery target for lesson_media ${selected.lesson_media_id}`;
        break;
      }

      const current = await loadCurrentLessonContext(client, selected.course_id, selected.lesson_media_id);
      if (current.inventoryRow === null) {
        execution.update_status = "failed";
        execution.verification_status = "FAIL";
        execution.stop_reason = "missing_inventory_row";
        rowExecutions.push(execution);
        aborted = true;
        abortReason = `Missing current inventory row for lesson_media ${selected.lesson_media_id}`;
        break;
      }

      if (!currentRowMatchesTarget(current.inventoryRow, selected)) {
        if (current.planRow === null) {
          execution.update_status = "failed";
          execution.verification_status = "FAIL";
          execution.stop_reason = "missing_plan_row_for_unrecovered_target";
          rowExecutions.push(execution);
          aborted = true;
          abortReason = `Missing repair plan row for lesson_media ${selected.lesson_media_id}`;
          break;
        }
        if (current.planRow.storage_recovery_classification === "AMBIGUOUS_MATCH") {
          execution.update_status = "failed";
          execution.verification_status = "FAIL";
          execution.stop_reason = "ambiguous_match_detected";
          rowExecutions.push(execution);
          aborted = true;
          abortReason = `Ambiguous match detected for lesson_media ${selected.lesson_media_id}`;
          break;
        }
        if (
          current.planRow.storage_recovery_classification !== "SAFE_AUTO_RECOVER"
          || current.planRow.fix_strategy !== "RECOVER_FROM_STORAGE_MATCH"
          || current.planRow.storage_recovery_bucket !== selected.matched_storage_bucket
          || current.planRow.storage_recovery_path !== selected.matched_storage_path
        ) {
          execution.update_status = "failed";
          execution.verification_status = "FAIL";
          execution.stop_reason = "current_plan_mismatch";
          rowExecutions.push(execution);
          aborted = true;
          abortReason = `Current repair plan no longer matches SAFE_AUTO_RECOVER target for lesson_media ${selected.lesson_media_id}`;
          break;
        }

        let preflightProbe: StorageProbe | null = null;
        let preflightProbeError: string | null = null;
        try {
          preflightProbe = await storage.probeObject(selected.matched_storage_bucket, selected.matched_storage_path);
        } catch (error) {
          preflightProbeError = error instanceof Error ? error.message : String(error);
        }
        execution.preflight_probe = preflightProbe;
        execution.preflight_probe_error = preflightProbeError;
        if (preflightProbeError !== null || preflightProbe?.exists !== true) {
          execution.update_status = "failed";
          execution.verification_status = "FAIL";
          execution.stop_reason = preflightProbeError ?? "storage_probe_failed";
          rowExecutions.push(execution);
          aborted = true;
          abortReason = `Storage probe failed for lesson_media ${selected.lesson_media_id}`;
          break;
        }

        const mutation = buildRecoveryMutationPlan(current.planRow);
        execution.target_table = mutation.resource;
        execution.target_id = mutation.target_id;
        execution.sql = mutation.sql;

        if (!apply) {
          execution.update_status = "not_run";
          execution.stop_reason = "dry_run";
        } else {
          const updatedRows = await client.patch<{ id: string }>(
            mutation.resource,
            mutation.patch,
            {
              select: "id",
              filters: filtersForMutation(mutation),
            },
          );
          execution.update_row_count = updatedRows.length;
          if (updatedRows.length !== 1) {
            execution.update_status = "failed";
            execution.verification_status = "FAIL";
            execution.stop_reason = `expected 1 updated row, received ${updatedRows.length}`;
            rowExecutions.push(execution);
            aborted = true;
            abortReason = `Mutation failed for lesson_media ${selected.lesson_media_id}`;
            break;
          }
          execution.update_status = "applied";
          exactSqlMutationsExecuted.push(mutation.sql);
        }
      } else {
        execution.update_status = "not_run";
        execution.stop_reason = "already_recovered";
      }

      const verified = await verifyRecoveredRow(
        client,
        storage,
        logger,
        env.options.minByteSize,
        selected.course_id,
        selected.lesson_media_id,
      );
      execution.verification_result = verified.verificationResult;
      execution.verification_summary = verified.verificationSummary;
      execution.verification_status = verified.verificationSummary.verification_pass ? "PASS" : "FAIL";
      rowExecutions.push(execution);

      if (execution.verification_status !== "PASS") {
        aborted = true;
        abortReason = `Verification failed for lesson_media ${selected.lesson_media_id}`;
        execution.stop_reason = execution.verification_result?.message ?? "verification_failed";
        break;
      }
    }

    clearDerivedViewCaches();
    const updatedInventorySnapshot = affectedCourseIds.size === 0
      ? []
      : (await loadActiveMediaInventory(client, {
          activeOnly: false,
          courseIds: [...affectedCourseIds],
        })).filter((row) => affectedLessonIds.has(row.lesson_id));
    const remainingManualCount = await countRemainingManualReuploadRequired(
      client,
      env.options.courseIds,
    );

    const output: ControlledRecoveryReport = {
      generated_at: nowIso(),
      apply,
      report_path: resolvedReportPath,
      selected_rows: summarizeSelectedRows(selectedRows),
      exact_sql_mutations_executed: exactSqlMutationsExecuted,
      verification_results_per_row: rowExecutions,
      updated_inventory_snapshot: updatedInventorySnapshot,
      remaining_manual_reupload_required_count: remainingManualCount,
      aborted,
      abort_reason: abortReason,
    };

    await writeJsonFile(path.join(runDir, "controlled-storage-recovery-report.json"), output);
    await writeTextFile(path.join(runDir, "controlled-storage-recovery-report.md"), renderMarkdownReport(output));
    const verificationRows = rowExecutions
      .map((row) => row.verification_result)
      .filter((row): row is VerificationResult => row !== null);
    if (verificationRows.length > 0) {
      await writeTextFile(
        path.join(runDir, "verification-results.md"),
        summarizeVerificationAsMarkdown(verificationRows),
      );
    }

    logger.info("pilot.complete", {
      runDir,
      apply,
      selectedRowCount: selectedRows.length,
      executedMutationCount: exactSqlMutationsExecuted.length,
      remainingManualReuploadRequiredCount: remainingManualCount,
      aborted,
      abortReason,
    });

    if (aborted) {
      throw new Error(abortReason ?? "Storage recovery pilot aborted");
    }
  } finally {
    await logger.close();
  }
}

if (isExecutedAsMain(import.meta.url)) {
  runStorageRecoveryPilot().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
