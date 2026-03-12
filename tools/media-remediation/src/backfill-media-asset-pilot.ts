import path from "node:path";

import { loadServiceEnvironment, printUsage } from "./config.js";
import { loadActiveMediaInventory, loadMediaAssets, loadMediaRepairPlan } from "./data.js";
import { clearDerivedViewCaches } from "./derived-views.js";
import { buildRunDirectory, ensureDir, writeJsonFile, writeTextFile } from "./fs-utils.js";
import { StructuredLogger } from "./logger.js";
import { summarizeVerificationAsMarkdown, PostRepairVerifier } from "./post-repair-verifier.js";
import { SupabaseAdminClient } from "./postgrest.js";
import {
  areMediaKindsCompatible,
  hasCompatibleExtension,
  hasCompatibleMime,
  normalizeMediaKind,
} from "./repair-utils.js";
import { isExecutedAsMain } from "./runtime.js";
import { SupabaseStorageAdmin } from "./storage.js";
import type {
  ActiveMediaInventoryRow,
  LessonMediaRecord,
  MediaAssetRecord,
  MediaRepairPlanRow,
  StorageProbe,
  VerificationResult,
} from "./types.js";

const MAX_BATCH_SIZE = 5;

type UpdateStatus = "pending" | "applied" | "failed" | "not_run";
type RowStatus = "PASS" | "FAIL" | "NOT_RUN";

interface BackfillTargetReference {
  bucket: string | null;
  path: string | null;
  contentType: string | null;
}

export interface BackfillPilotCandidate {
  row: MediaRepairPlanRow;
  mediaAsset: MediaAssetRecord;
  target: BackfillTargetReference;
  sql: string;
}

interface CandidateProbeResult extends BackfillPilotCandidate {
  preflightProbe: StorageProbe | null;
  preflightProbeError: string | null;
}

interface ExecutedMutation {
  lesson_media_id: string;
  course_id: string;
  lesson_id: string;
  safe_matching_media_asset_id: string;
  sql: string;
  update_status: UpdateStatus;
  update_row_count: number;
  verification_status: RowStatus;
  verification_result: VerificationResult | null;
  verification_summary: {
    lesson_media_kind_equals_media_asset_type: boolean;
    storage_path_resolves: boolean;
    mime_compatible: boolean;
    verification_pass: boolean;
  } | null;
  stop_reason: string | null;
}

interface ControlledBatchReport {
  generated_at: string;
  apply: boolean;
  batch_size_limit: number;
  selected_rows: Array<{
    course_id: string;
    lesson_id: string;
    lesson_media_id: string;
    issue_type: string | null;
    repair_priority: number;
    safe_matching_media_asset_id: string;
    safe_matching_media_asset_count: number;
    lesson_media_kind: string | null;
    media_asset_type: string | null;
    preflight_probe: StorageProbe | null;
    preflight_probe_error: string | null;
    sql: string;
  }>;
  exact_sql_mutations_executed: string[];
  verification_results_per_row: ExecutedMutation[];
  updated_inventory_snapshot_for_affected_lessons: ActiveMediaInventoryRow[];
  remaining_backfill_media_asset_candidates: Array<{
    course_id: string;
    lesson_id: string;
    lesson_media_id: string;
    issue_type: string | null;
    repair_priority: number;
    safe_matching_media_asset_id: string | null;
    safe_matching_media_asset_count: number;
  }>;
  aborted: boolean;
  abort_reason: string | null;
}

function nowIso(): string {
  return new Date().toISOString();
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

function quoteSqlLiteral(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

export function renderBackfillMutationSql(row: MediaRepairPlanRow): string {
  if (!row.safe_matching_media_asset_id) {
    throw new Error(`Missing safe_matching_media_asset_id for lesson_media ${row.lesson_media_id}`);
  }
  return [
    "update app.lesson_media",
    `set media_asset_id = ${quoteSqlLiteral(row.safe_matching_media_asset_id)}`,
    `where id = ${quoteSqlLiteral(row.lesson_media_id)}`,
    "and media_asset_id is null;",
  ].join(" ");
}

export function resolveBackfillTargetReference(mediaAsset: MediaAssetRecord, lessonMediaKind: string | null): BackfillTargetReference {
  const mediaType = normalizeMediaKind(mediaAsset.media_type);
  return {
    bucket: firstDefined(
      normalizedText(mediaAsset.streaming_storage_bucket),
      normalizedText(mediaAsset.storage_bucket),
    ),
    path: firstDefined(
      normalizedText(mediaAsset.streaming_object_path),
      normalizedText(mediaAsset.original_object_path),
    ),
    contentType: firstDefined(
      mediaType === "audio" ? "audio/mpeg" : null,
      mediaType === "image" ? "image/jpeg" : null,
      normalizedText(mediaAsset.original_content_type),
      ["document", "pdf"].includes(mediaType ?? "") || normalizeMediaKind(lessonMediaKind) === "document"
        ? "application/pdf"
        : null,
    ),
  };
}

export function isEligibleBackfillCandidate(
  row: MediaRepairPlanRow,
  mediaAsset: MediaAssetRecord | null,
): mediaAsset is MediaAssetRecord {
  if (row.fix_strategy !== "BACKFILL_MEDIA_ASSET") {
    return false;
  }
  if (row.media_asset_id !== null) {
    return false;
  }
  if (row.safe_matching_media_asset_count !== 1 || !row.safe_matching_media_asset_id) {
    return false;
  }
  if (mediaAsset === null) {
    return false;
  }
  if (mediaAsset.id !== row.safe_matching_media_asset_id) {
    return false;
  }
  if (lower(mediaAsset.state) !== "ready") {
    return false;
  }

  const target = resolveBackfillTargetReference(mediaAsset, row.lesson_media_kind);
  return (
    areMediaKindsCompatible({
      lessonMediaKind: row.lesson_media_kind,
      mediaAssetType: mediaAsset.media_type,
    })
    && hasCompatibleExtension({
      lessonMediaKind: row.lesson_media_kind,
      storagePath: target.path,
    })
    && hasCompatibleMime({
      lessonMediaKind: row.lesson_media_kind,
      contentType: target.contentType,
    })
  );
}

export function buildBackfillPilotCandidates(
  planRows: MediaRepairPlanRow[],
  mediaAssets: MediaAssetRecord[],
): BackfillPilotCandidate[] {
  const mediaAssetById = new Map(mediaAssets.map((item) => [item.id, item]));
  return planRows
    .filter((row) => row.fix_strategy === "BACKFILL_MEDIA_ASSET")
    .flatMap((row) => {
      const mediaAsset = row.safe_matching_media_asset_id
        ? (mediaAssetById.get(row.safe_matching_media_asset_id) ?? null)
        : null;
      if (!isEligibleBackfillCandidate(row, mediaAsset)) {
        return [];
      }
      return [{
        row,
        mediaAsset,
        target: resolveBackfillTargetReference(mediaAsset, row.lesson_media_kind),
        sql: renderBackfillMutationSql(row),
      }];
    });
}

function summarizeSelectedRows(rows: CandidateProbeResult[]): ControlledBatchReport["selected_rows"] {
  return rows.map((candidate) => ({
    course_id: candidate.row.course_id,
    lesson_id: candidate.row.lesson_id,
    lesson_media_id: candidate.row.lesson_media_id,
    issue_type: candidate.row.issue_type,
    repair_priority: candidate.row.repair_priority,
    safe_matching_media_asset_id: candidate.row.safe_matching_media_asset_id!,
    safe_matching_media_asset_count: candidate.row.safe_matching_media_asset_count,
    lesson_media_kind: candidate.row.lesson_media_kind,
    media_asset_type: candidate.mediaAsset.media_type,
    preflight_probe: candidate.preflightProbe,
    preflight_probe_error: candidate.preflightProbeError,
    sql: candidate.sql,
  }));
}

function summarizeRemainingCandidates(rows: MediaRepairPlanRow[]): ControlledBatchReport["remaining_backfill_media_asset_candidates"] {
  return rows
    .filter((row) => row.fix_strategy === "BACKFILL_MEDIA_ASSET")
    .map((row) => ({
      course_id: row.course_id,
      lesson_id: row.lesson_id,
      lesson_media_id: row.lesson_media_id,
      issue_type: row.issue_type,
      repair_priority: row.repair_priority,
      safe_matching_media_asset_id: row.safe_matching_media_asset_id,
      safe_matching_media_asset_count: row.safe_matching_media_asset_count,
    }));
}

function summarizeInventoryRows(rows: ActiveMediaInventoryRow[]): string[] {
  return rows.map((row) =>
    `| ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${row.reference_type} | ${row.media_asset_id ?? ""} | ${row.media_asset_type ?? ""} | ${row.bucket ?? ""} | ${(row.storage_path ?? "").replaceAll("|", "\\|")} | ${row.content_type ?? ""} |`,
  );
}

function renderMarkdownReport(report: ControlledBatchReport): string {
  const verificationRows = report.verification_results_per_row.map((row) => {
    const message = row.verification_result?.message ?? row.stop_reason ?? "";
    return `| ${row.verification_status} | ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${message.replaceAll("|", "\\|")} |`;
  });

  const selectedRows = report.selected_rows.map((row) =>
    `| ${row.repair_priority} | ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${row.safe_matching_media_asset_id} | ${row.preflight_probe_error ?? (row.preflight_probe?.exists ? "PASS" : "missing")} |`,
  );

  const remainingRows = report.remaining_backfill_media_asset_candidates.map((row) =>
    `| ${row.repair_priority} | ${row.course_id} | ${row.lesson_id} | ${row.lesson_media_id} | ${row.safe_matching_media_asset_id ?? ""} | ${row.safe_matching_media_asset_count} |`,
  );

  return [
    "# BACKFILL_MEDIA_ASSET Controlled Batch Pilot",
    "",
    `Generated at: ${report.generated_at}`,
    "",
    `- apply: ${report.apply}`,
    `- batch_size_limit: ${report.batch_size_limit}`,
    `- selected_rows: ${report.selected_rows.length}`,
    `- executed_sql_mutations: ${report.exact_sql_mutations_executed.length}`,
    `- aborted: ${report.aborted}`,
    `- abort_reason: ${report.abort_reason ?? "none"}`,
    "",
    "## Rows Selected",
    "",
    "| repair_priority | course_id | lesson_id | lesson_media_id | safe_matching_media_asset_id | preflight_probe |",
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
    "## Updated Inventory Snapshot For Affected Lessons",
    "",
    "| course_id | lesson_id | lesson_media_id | reference_type | media_asset_id | media_asset_type | bucket | storage_path | content_type |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ...summarizeInventoryRows(report.updated_inventory_snapshot_for_affected_lessons),
    "",
    "## Remaining BACKFILL_MEDIA_ASSET Candidates",
    "",
    "| repair_priority | course_id | lesson_id | lesson_media_id | safe_matching_media_asset_id | safe_matching_media_asset_count |",
    "| --- | --- | --- | --- | --- | --- |",
    ...remainingRows,
    "",
  ].join("\n");
}

async function probeCandidates(
  candidates: BackfillPilotCandidate[],
  storage: SupabaseStorageAdmin,
  logger: StructuredLogger,
): Promise<CandidateProbeResult[]> {
  const results: CandidateProbeResult[] = [];
  for (const candidate of candidates) {
    let preflightProbe: StorageProbe | null = null;
    let preflightProbeError: string | null = null;
    if (candidate.target.bucket && candidate.target.path) {
      try {
        preflightProbe = await storage.probeObject(candidate.target.bucket, candidate.target.path);
      } catch (error) {
        preflightProbeError = error instanceof Error ? error.message : String(error);
      }
    } else {
      preflightProbeError = "missing_target_reference";
    }

    logger.info("pilot.candidate.preflight", {
      lessonMediaId: candidate.row.lesson_media_id,
      safeMatchingMediaAssetId: candidate.row.safe_matching_media_asset_id,
      preflightProbe,
      preflightProbeError,
    });

    results.push({
      ...candidate,
      preflightProbe,
      preflightProbeError,
    });
  }
  return results;
}

async function verifyUpdatedRow(
  client: SupabaseAdminClient,
  storage: SupabaseStorageAdmin,
  logger: StructuredLogger,
  row: MediaRepairPlanRow,
): Promise<{
  verificationResult: VerificationResult;
  verificationSummary: NonNullable<ExecutedMutation["verification_summary"]>;
}> {
  const [lessonMediaRows, mediaAssetRows] = await Promise.all([
    client.select<LessonMediaRecord>("lesson_media", {
      select: "id,lesson_id,kind,storage_bucket,storage_path,media_id,media_asset_id,created_at",
      filters: [{ column: "id", operator: "eq", value: row.lesson_media_id }],
    }),
    client.select<MediaAssetRecord>("media_assets", {
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
      filters: [{ column: "id", operator: "eq", value: row.safe_matching_media_asset_id! }],
    }),
  ]);

  const lessonMedia = lessonMediaRows[0] ?? null;
  const mediaAsset = mediaAssetRows[0] ?? null;
  if (lessonMedia === null || mediaAsset === null || lessonMedia.media_asset_id !== mediaAsset.id) {
    const verificationResult: VerificationResult = {
      status: "FAIL",
      courseId: row.course_id,
      lessonId: row.lesson_id,
      lessonMediaId: row.lesson_media_id,
      issueType: row.issue_type,
      message: "failed to reload lesson_media/media_asset linkage after update",
      details: {
        lessonMediaFound: lessonMedia !== null,
        mediaAssetFound: mediaAsset !== null,
        linkedMediaAssetId: lessonMedia?.media_asset_id ?? null,
      },
    };
    return {
      verificationResult,
      verificationSummary: {
        lesson_media_kind_equals_media_asset_type: false,
        storage_path_resolves: false,
        mime_compatible: false,
        verification_pass: false,
      },
    };
  }

  const target = resolveBackfillTargetReference(mediaAsset, lessonMedia.kind);
  let probe: StorageProbe | null = null;
  let probeError: string | null = null;
  if (target.bucket && target.path) {
    try {
      probe = await storage.probeObject(target.bucket, target.path);
    } catch (error) {
      probeError = error instanceof Error ? error.message : String(error);
    }
  } else {
    probeError = "missing_target_reference";
  }

  const lessonKind = normalizeMediaKind(lessonMedia.kind);
  const mediaAssetType = normalizeMediaKind(mediaAsset.media_type);
  const kindMatch =
    lessonKind !== null
    && mediaAssetType !== null
    && lessonKind === mediaAssetType;
  const assetReady = lower(mediaAsset.state) === "ready";
  const storagePathResolves = Boolean(probe !== null && probe.exists && probeError === null);
  const mimeCompatible = hasCompatibleMime({
    lessonMediaKind: lessonMedia.kind,
    contentType: firstDefined(probe?.contentType, target.contentType),
  });
  const extensionCompatible = hasCompatibleExtension({
    lessonMediaKind: lessonMedia.kind,
    storagePath: target.path,
  });

  const messages: string[] = [];
  if (!kindMatch) {
    messages.push(
      `lesson_media kind ${lessonMedia.kind ?? "unknown"} conflicts with media asset type ${mediaAsset.media_type ?? "unknown"}`,
    );
  }
  if (!assetReady) {
    messages.push(`media asset state is ${mediaAsset.state ?? "unknown"}`);
  }
  if (!storagePathResolves) {
    messages.push(probeError ?? "storage object missing");
  }
  if (!mimeCompatible) {
    messages.push("resolved media asset MIME is incompatible");
  }
  if (!extensionCompatible) {
    messages.push("resolved media asset extension is incompatible");
  }
  if (messages.length === 0) {
    messages.push("verification checks passed");
  }

  const verificationPass = kindMatch && assetReady && storagePathResolves && mimeCompatible && extensionCompatible;
  const verificationResult: VerificationResult = {
    status: verificationPass ? "PASS" : "FAIL",
    courseId: row.course_id,
    lessonId: row.lesson_id,
    lessonMediaId: row.lesson_media_id,
    issueType: row.issue_type,
    message: messages.join("; "),
    details: {
      bucket: target.bucket,
      storagePath: target.path,
      probe,
      probeError,
      lessonMediaKind: lessonMedia.kind,
      mediaAssetType: mediaAsset.media_type,
      resolvedContentType: firstDefined(probe?.contentType, target.contentType),
      assetReady,
      kindMatch,
      mimeCompatible,
      extensionCompatible,
    },
  };

  logger.info("pilot.row.verification", {
    lessonMediaId: row.lesson_media_id,
    verificationResult,
  });

  return {
    verificationResult,
    verificationSummary: {
      lesson_media_kind_equals_media_asset_type: kindMatch,
      storage_path_resolves: storagePathResolves,
      mime_compatible: mimeCompatible,
      verification_pass: verificationPass,
    },
  };
}

export async function runBackfillMediaAssetPilot(argv: string[] = process.argv.slice(2)): Promise<void> {
  if (argv.includes("--help")) {
    printUsage("backfill-media-asset-pilot");
    process.stdout.write("\n  Live apply requires --apply and enforces --batch-size <= 5.\n");
    return;
  }

  const env = loadServiceEnvironment(argv, "backfill-media-asset-pilot");
  const apply = argv.includes("--apply");
  if (env.options.batchSize > MAX_BATCH_SIZE) {
    throw new Error(`Batch size ${env.options.batchSize} exceeds max allowed ${MAX_BATCH_SIZE}`);
  }
  const runDir = buildRunDirectory(env.options.outputDir, "backfill-media-asset-pilot");
  await ensureDir(runDir);
  const logger = new StructuredLogger(
    { service: "backfill-media-asset-pilot" },
    path.join(runDir, "audit.log"),
  );
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

    clearDerivedViewCaches();
    const [planRows, mediaAssets] = await Promise.all([
      loadMediaRepairPlan(client, {
        activeOnly: env.options.activeOnly,
        courseIds: env.options.courseIds,
      }),
      loadMediaAssets(client),
    ]);

    const candidates = buildBackfillPilotCandidates(planRows, mediaAssets);
    const probedCandidates = await probeCandidates(candidates, storage, logger);
    const selectedRows = probedCandidates
      .filter((candidate) => candidate.preflightProbeError === null && candidate.preflightProbe?.exists)
      .slice(0, env.options.batchSize);

    if (selectedRows.length > MAX_BATCH_SIZE) {
      throw new Error(`Selected ${selectedRows.length} rows; refusing to exceed ${MAX_BATCH_SIZE}`);
    }

    const rowExecutions: ExecutedMutation[] = [];
    const exactSqlMutationsExecuted: string[] = [];
    const affectedLessonIds = new Set<string>();
    const affectedCourseIds = new Set<string>();
    let aborted = false;
    let abortReason: string | null = null;

    for (const candidate of selectedRows) {
      const executed: ExecutedMutation = {
        lesson_media_id: candidate.row.lesson_media_id,
        course_id: candidate.row.course_id,
        lesson_id: candidate.row.lesson_id,
        safe_matching_media_asset_id: candidate.row.safe_matching_media_asset_id!,
        sql: candidate.sql,
        update_status: "pending",
        update_row_count: 0,
        verification_status: "NOT_RUN",
        verification_result: null,
        verification_summary: null,
        stop_reason: null,
      };

      if (!apply) {
        executed.update_status = "not_run";
        executed.stop_reason = "dry_run";
        rowExecutions.push(executed);
        continue;
      }

      const updatedRows = await client.patch<{ id: string }>(
        "lesson_media",
        { media_asset_id: candidate.row.safe_matching_media_asset_id },
        {
          select: "id",
          filters: [
            { column: "id", operator: "eq", value: candidate.row.lesson_media_id },
            { column: "media_asset_id", operator: "is", value: null },
          ],
        },
      );

      executed.update_row_count = updatedRows.length;
      if (updatedRows.length !== 1) {
        executed.update_status = "failed";
        executed.verification_status = "FAIL";
        executed.stop_reason = `expected 1 updated row, received ${updatedRows.length}`;
        rowExecutions.push(executed);
        aborted = true;
        abortReason = `Mutation failed for lesson_media ${candidate.row.lesson_media_id}`;
        logger.error("pilot.row.update_failed", {
          lessonMediaId: candidate.row.lesson_media_id,
          updatedRowCount: updatedRows.length,
        });
        break;
      }

      executed.update_status = "applied";
      exactSqlMutationsExecuted.push(candidate.sql);
      affectedLessonIds.add(candidate.row.lesson_id);
      affectedCourseIds.add(candidate.row.course_id);
      rowExecutions.push(executed);

      const { verificationResult, verificationSummary } = await verifyUpdatedRow(
        client,
        storage,
        logger,
        candidate.row,
      );
      executed.verification_result = verificationResult;
      executed.verification_summary = verificationSummary;
      executed.verification_status = verificationSummary.verification_pass ? "PASS" : "FAIL";

      if (executed.verification_status !== "PASS") {
        executed.stop_reason = verificationResult?.message ?? "verification_failed";
        aborted = true;
        abortReason = `Verification failed for lesson_media ${candidate.row.lesson_media_id}`;
        logger.error("pilot.row.verification_failed", {
          lessonMediaId: candidate.row.lesson_media_id,
          verificationResult,
          verificationSummary: executed.verification_summary,
        });
        break;
      }
    }

    clearDerivedViewCaches();
    const updatedInventoryRows = affectedCourseIds.size > 0
      ? await loadActiveMediaInventory(client, {
          activeOnly: false,
          courseIds: [...affectedCourseIds],
        })
      : [];
    const remainingPlanRows =
      !apply || exactSqlMutationsExecuted.length === 0
        ? planRows
        : await loadMediaRepairPlan(client, {
            activeOnly: env.options.activeOnly,
            courseIds: env.options.courseIds,
          });

    const report: ControlledBatchReport = {
      generated_at: nowIso(),
      apply,
      batch_size_limit: env.options.batchSize,
      selected_rows: summarizeSelectedRows(selectedRows),
      exact_sql_mutations_executed: exactSqlMutationsExecuted,
      verification_results_per_row: rowExecutions,
      updated_inventory_snapshot_for_affected_lessons: updatedInventoryRows.filter((row) =>
        affectedLessonIds.has(row.lesson_id)
      ),
      remaining_backfill_media_asset_candidates: summarizeRemainingCandidates(remainingPlanRows),
      aborted,
      abort_reason: abortReason,
    };

    await writeJsonFile(path.join(runDir, "controlled-backfill-batch-report.json"), report);
    await writeTextFile(path.join(runDir, "controlled-backfill-batch-report.md"), renderMarkdownReport(report));
    if (rowExecutions.some((row) => row.verification_result !== null)) {
      await writeTextFile(
        path.join(runDir, "verification-results.md"),
        summarizeVerificationAsMarkdown(
          rowExecutions
            .map((row) => row.verification_result)
            .filter((row): row is VerificationResult => row !== null),
        ),
      );
    }

    logger.info("pilot.complete", {
      runDir,
      apply,
      selectedRowCount: selectedRows.length,
      executedMutationCount: exactSqlMutationsExecuted.length,
      aborted,
      abortReason,
    });

    if (aborted) {
      throw new Error(abortReason ?? "Pilot aborted");
    }
  } finally {
    await logger.close();
  }
}

if (isExecutedAsMain(import.meta.url)) {
  runBackfillMediaAssetPilot().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
