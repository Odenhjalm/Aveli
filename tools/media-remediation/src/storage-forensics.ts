import path from "node:path";

import {
  decodeUrlComponentSafe,
  hasCompatibleExtension,
  hasCompatibleMime,
  mimeFamily,
  normalizeFilenameLabelForMatch,
  normalizeFilenameForMatch,
} from "./repair-utils.js";
import type {
  FixStrategy,
  MediaRepairPlanRow,
  StorageCatalogEntry,
  StorageRecoveryClassification,
  StorageRecoveryReportRow,
  StorageRecoverySummary,
} from "./types.js";

const SAFE_AUTO_RECOVER_THRESHOLD = 85;
const PROBABLE_MATCH_THRESHOLD = 65;
const AMBIGUOUS_MATCH_THRESHOLD = 50;
const AMBIGUITY_DELTA = 10;

interface MatchSignals {
  exactPathMatch: boolean;
  filenameMatch: boolean;
  normalizedFilenameMatch: boolean;
  filenameLabelMatch: boolean;
  sameLessonFolder: boolean;
  sameCourseFolder: boolean;
  sameExtension: boolean;
  sameFileSize: boolean;
  sameMimeFamily: boolean;
  compatibleExtension: boolean;
  compatibleMime: boolean;
}

interface StorageRecoveryCandidate {
  entry: StorageCatalogEntry;
  score: number;
  matchReason: string;
  signals: MatchSignals;
}

interface StorageCatalogIndexes {
  byExactPath: Map<string, StorageCatalogEntry[]>;
  byFilename: Map<string, StorageCatalogEntry[]>;
  byNormalizedFilename: Map<string, StorageCatalogEntry[]>;
  byFilenameLabel: Map<string, StorageCatalogEntry[]>;
  byLessonId: Map<string, StorageCatalogEntry[]>;
  byCourseId: Map<string, StorageCatalogEntry[]>;
  bySize: Map<string, StorageCatalogEntry[]>;
}

function lower(value: string | null | undefined): string {
  return (value ?? "").trim().toLowerCase();
}

function normalizedText(value: string | null | undefined): string | null {
  const trimmed = (value ?? "").trim();
  return trimmed === "" ? null : trimmed;
}

function exactPathKey(bucket: string | null | undefined, storagePath: string | null | undefined): string | null {
  const normalizedBucket = normalizedText(bucket);
  const normalizedPath = normalizedText(storagePath);
  if (!normalizedBucket || !normalizedPath) {
    return null;
  }
  return `${normalizedBucket}:${normalizedPath}`;
}

function hasPathSegment(storagePath: string, expected: string): boolean {
  return storagePath.split("/").some((segment) => segment === expected);
}

function buildCatalogIndexes(entries: StorageCatalogEntry[]): StorageCatalogIndexes {
  const indexes: StorageCatalogIndexes = {
    byExactPath: new Map<string, StorageCatalogEntry[]>(),
    byFilename: new Map<string, StorageCatalogEntry[]>(),
    byNormalizedFilename: new Map<string, StorageCatalogEntry[]>(),
    byFilenameLabel: new Map<string, StorageCatalogEntry[]>(),
    byLessonId: new Map<string, StorageCatalogEntry[]>(),
    byCourseId: new Map<string, StorageCatalogEntry[]>(),
    bySize: new Map<string, StorageCatalogEntry[]>(),
  };

  const push = (map: Map<string, StorageCatalogEntry[]>, key: string | null, value: StorageCatalogEntry): void => {
    if (!key) {
      return;
    }
    const current = map.get(key) ?? [];
    current.push(value);
    map.set(key, current);
  };

  for (const entry of entries) {
    push(indexes.byExactPath, exactPathKey(entry.bucket, entry.storage_path), entry);
    push(indexes.byFilename, lower(entry.filename), entry);
    push(indexes.byNormalizedFilename, entry.normalized_filename, entry);
    push(indexes.byFilenameLabel, normalizeFilenameLabelForMatch(entry.filename), entry);
    push(indexes.byLessonId, entry.lesson_id_hint, entry);
    push(indexes.byCourseId, entry.course_id_hint, entry);
    push(indexes.bySize, entry.size === null ? null : `${entry.size}`, entry);
  }

  return indexes;
}

function expectedFilename(row: MediaRepairPlanRow): string | null {
  const storagePath = normalizedText(row.storage_path);
  if (!storagePath) {
    return null;
  }
  return decodeUrlComponentSafe(path.posix.basename(storagePath));
}

function expectedExtension(row: MediaRepairPlanRow): string | null {
  const filename = expectedFilename(row);
  const extension = path.posix.extname(filename ?? "").toLowerCase();
  return extension === "" ? null : extension;
}

function expectedFilenameLabel(row: MediaRepairPlanRow): string | null {
  return normalizeFilenameLabelForMatch(expectedFilename(row));
}

function isSafeReferenceTarget(row: MediaRepairPlanRow): boolean {
  if (row.reference_type === "media_object") {
    return row.media_object_id !== null;
  }
  if (row.reference_type === "direct_storage_path") {
    return row.media_object_id === null && row.media_asset_id === null;
  }
  return row.media_asset_id !== null && lower(row.media_state) === "ready";
}

function collectCandidatePool(row: MediaRepairPlanRow, indexes: StorageCatalogIndexes): StorageCatalogEntry[] {
  const pool = new Map<string, StorageCatalogEntry>();
  const add = (entries: StorageCatalogEntry[] | undefined): void => {
    for (const entry of entries ?? []) {
      pool.set(`${entry.bucket}:${entry.storage_path}`, entry);
    }
  };

  add(indexes.byExactPath.get(exactPathKey(row.bucket, row.storage_path) ?? ""));
  add(indexes.byFilename.get(lower(expectedFilename(row))));
  add(indexes.byNormalizedFilename.get(normalizeFilenameForMatch(expectedFilename(row)) ?? ""));
  add(indexes.byFilenameLabel.get(expectedFilenameLabel(row) ?? ""));
  add(indexes.byLessonId.get(row.lesson_id));
  add(indexes.byCourseId.get(row.course_id));
  if (row.byte_size !== null) {
    add(indexes.bySize.get(`${row.byte_size}`));
  }

  return [...pool.values()];
}

function computeSignals(row: MediaRepairPlanRow, entry: StorageCatalogEntry): MatchSignals {
  const rowFilename = expectedFilename(row);
  const rowNormalizedFilename = normalizeFilenameForMatch(rowFilename);
  const rowFilenameLabel = expectedFilenameLabel(row);
  const rowExtension = expectedExtension(row);
  const rowMimeFamily = mimeFamily(row.content_type);
  const candidateMimeFamily = mimeFamily(entry.content_type);

  return {
    exactPathMatch: exactPathKey(row.bucket, row.storage_path) === exactPathKey(entry.bucket, entry.storage_path),
    filenameMatch: lower(entry.filename) === lower(rowFilename),
    normalizedFilenameMatch: rowNormalizedFilename !== null && entry.normalized_filename === rowNormalizedFilename,
    filenameLabelMatch:
      rowFilenameLabel !== null
      && normalizeFilenameLabelForMatch(entry.filename) === rowFilenameLabel,
    sameLessonFolder:
      entry.lesson_id_hint === row.lesson_id
      || hasPathSegment(entry.storage_path, row.lesson_id),
    sameCourseFolder:
      entry.course_id_hint === row.course_id
      || hasPathSegment(entry.storage_path, row.course_id),
    sameExtension: rowExtension !== null && entry.extension === rowExtension,
    sameFileSize:
      row.byte_size !== null
      && entry.size !== null
      && row.byte_size === entry.size,
    sameMimeFamily:
      rowMimeFamily !== null
      && candidateMimeFamily !== null
      && rowMimeFamily === candidateMimeFamily,
    compatibleExtension: hasCompatibleExtension({
      lessonMediaKind: row.lesson_media_kind,
      storagePath: entry.storage_path,
    }),
    compatibleMime:
      entry.content_type === null
        ? false
        : hasCompatibleMime({
            lessonMediaKind: row.lesson_media_kind,
            contentType: entry.content_type,
          }),
  };
}

function computeConfidenceScore(signals: MatchSignals): number {
  if (signals.exactPathMatch) {
    return 100;
  }

  if (!signals.compatibleExtension && !signals.compatibleMime) {
    return 0;
  }

  let score = 0;
  if (signals.filenameMatch) {
    score += 30;
  }
  if (signals.normalizedFilenameMatch) {
    score += 20;
  }
  if (signals.filenameLabelMatch) {
    score += 15;
  }
  if (signals.sameLessonFolder) {
    score += 40;
  }
  if (signals.sameCourseFolder) {
    score += 15;
  }
  if (signals.sameExtension) {
    score += 10;
  }
  if (signals.sameFileSize) {
    score += 20;
  }
  if (signals.sameMimeFamily) {
    score += 5;
  }
  if (signals.compatibleExtension) {
    score += 5;
  }
  if (signals.compatibleMime) {
    score += 5;
  }

  return Math.min(score, 100);
}

function buildMatchReason(signals: MatchSignals): string {
  const reasons: string[] = [];
  if (signals.exactPathMatch) {
    reasons.push("exact_path");
  }
  if (signals.filenameMatch) {
    reasons.push("filename_match");
  }
  if (signals.normalizedFilenameMatch) {
    reasons.push("normalized_filename_match");
  }
  if (signals.filenameLabelMatch) {
    reasons.push("filename_label_match");
  }
  if (signals.sameLessonFolder) {
    reasons.push("same_lesson_folder");
  }
  if (signals.sameCourseFolder) {
    reasons.push("same_course_folder");
  }
  if (signals.sameExtension) {
    reasons.push("same_extension");
  }
  if (signals.sameFileSize) {
    reasons.push("same_file_size");
  }
  if (signals.sameMimeFamily) {
    reasons.push("same_mime_family");
  }
  if (signals.compatibleExtension && !signals.sameExtension) {
    reasons.push("compatible_extension");
  }
  if (signals.compatibleMime && !signals.sameMimeFamily) {
    reasons.push("compatible_mime");
  }
  return reasons.join(",");
}

function classifyTopCandidate(
  row: MediaRepairPlanRow,
  candidates: StorageRecoveryCandidate[],
): StorageRecoveryClassification {
  const [topCandidate, secondCandidate] = candidates;
  if (!topCandidate || topCandidate.score < AMBIGUOUS_MATCH_THRESHOLD) {
    return "NO_MATCH";
  }

  const ambiguous =
    secondCandidate !== undefined
    && secondCandidate.score >= PROBABLE_MATCH_THRESHOLD
    && Math.abs(topCandidate.score - secondCandidate.score) < AMBIGUITY_DELTA;

  const hasIdentitySignal =
    topCandidate.signals.exactPathMatch
    || topCandidate.signals.filenameMatch
    || topCandidate.signals.normalizedFilenameMatch
    || topCandidate.signals.filenameLabelMatch
    || topCandidate.signals.sameLessonFolder;

  const hasLocationSignal =
    topCandidate.signals.exactPathMatch
    || topCandidate.signals.sameLessonFolder
    || topCandidate.signals.sameCourseFolder;

  const strictSignals =
    hasIdentitySignal
    && hasLocationSignal
    && topCandidate.signals.sameExtension
    && topCandidate.signals.sameMimeFamily
    && (topCandidate.signals.sameFileSize || topCandidate.signals.exactPathMatch)
    && topCandidate.signals.compatibleExtension
    && topCandidate.signals.compatibleMime;

  if (
    !ambiguous
    && topCandidate.score >= SAFE_AUTO_RECOVER_THRESHOLD
    && strictSignals
    && isSafeReferenceTarget(row)
  ) {
    return "SAFE_AUTO_RECOVER";
  }
  if (ambiguous) {
    return "AMBIGUOUS_MATCH";
  }
  if (topCandidate.score >= PROBABLE_MATCH_THRESHOLD) {
    return "PROBABLE_MATCH";
  }
  return "AMBIGUOUS_MATCH";
}

function scoreCandidates(row: MediaRepairPlanRow, entries: StorageCatalogEntry[]): StorageRecoveryCandidate[] {
  return entries
    .map((entry) => {
      const signals = computeSignals(row, entry);
      return {
        entry,
        score: computeConfidenceScore(signals),
        matchReason: buildMatchReason(signals),
        signals,
      };
    })
    .filter((candidate) => candidate.score > 0)
    .sort((left, right) => {
      const byScore = right.score - left.score;
      if (byScore !== 0) {
        return byScore;
      }
      return `${left.entry.bucket}/${left.entry.storage_path}`.localeCompare(`${right.entry.bucket}/${right.entry.storage_path}`);
    });
}

function recoveryFixStrategy(classification: StorageRecoveryClassification, current: FixStrategy): FixStrategy {
  return classification === "SAFE_AUTO_RECOVER" ? "RECOVER_FROM_STORAGE_MATCH" : current;
}

export function analyzeStorageRecovery(
  planRows: MediaRepairPlanRow[],
  storageCatalog: StorageCatalogEntry[],
): {
  rows: MediaRepairPlanRow[];
  reportRows: StorageRecoveryReportRow[];
  summary: StorageRecoverySummary;
} {
  const indexes = buildCatalogIndexes(storageCatalog);
  const reportRows: StorageRecoveryReportRow[] = [];

  const rows = planRows.map((row) => {
    if (row.fix_strategy !== "MANUAL_REUPLOAD_REQUIRED") {
      return row;
    }

    const candidates = scoreCandidates(row, collectCandidatePool(row, indexes));
    const classification = classifyTopCandidate(row, candidates);
    const topCandidate = candidates[0] ?? null;
    const fixStrategyAfter = recoveryFixStrategy(classification, row.fix_strategy);

    reportRows.push({
      course_id: row.course_id,
      lesson_id: row.lesson_id,
      lesson_media_id: row.lesson_media_id,
      reference_type: row.reference_type,
      original_db_bucket: row.bucket,
      original_db_path: row.storage_path,
      matched_storage_bucket: topCandidate?.entry.bucket ?? null,
      matched_storage_path: topCandidate?.entry.storage_path ?? null,
      confidence_score: topCandidate?.score ?? 0,
      classification,
      match_reason:
        classification === "AMBIGUOUS_MATCH" && candidates[1]
          ? `${topCandidate?.matchReason ?? ""};ambiguous_with=${candidates[1].entry.bucket}/${candidates[1].entry.storage_path}`
          : topCandidate?.matchReason ?? "no_match",
      fix_strategy_before: row.fix_strategy,
      fix_strategy_after: fixStrategyAfter,
    });

    return {
      ...row,
      fix_strategy: fixStrategyAfter,
      storage_recovery_classification: classification,
      storage_recovery_bucket: topCandidate?.entry.bucket ?? null,
      storage_recovery_path: topCandidate?.entry.storage_path ?? null,
      storage_recovery_content_type: topCandidate?.entry.content_type ?? null,
      storage_recovery_size_bytes: topCandidate?.entry.size ?? null,
      storage_recovery_confidence_score: topCandidate?.score ?? 0,
      storage_recovery_match_reason:
        classification === "AMBIGUOUS_MATCH" && candidates[1]
          ? `${topCandidate?.matchReason ?? ""};ambiguous`
          : topCandidate?.matchReason ?? "no_match",
      storage_recovery_candidate_count: candidates.length,
    };
  });

  const summary: StorageRecoverySummary = {
    rows_reduced_from_manual_reupload_required: reportRows.filter((row) => row.classification === "SAFE_AUTO_RECOVER").length,
    safe_auto_recover_count: reportRows.filter((row) => row.classification === "SAFE_AUTO_RECOVER").length,
    probable_match_count: reportRows.filter((row) => row.classification === "PROBABLE_MATCH").length,
    ambiguous_match_count: reportRows.filter((row) => row.classification === "AMBIGUOUS_MATCH").length,
    no_match_count: reportRows.filter((row) => row.classification === "NO_MATCH").length,
  };

  return { rows, reportRows, summary };
}

export function summarizeStorageRecoveryAsMarkdown(
  reportRows: StorageRecoveryReportRow[],
  summary: StorageRecoverySummary,
): string {
  return [
    "# Storage Recovery Report",
    "",
    `- rows reduced from MANUAL_REUPLOAD_REQUIRED: ${summary.rows_reduced_from_manual_reupload_required}`,
    `- SAFE_AUTO_RECOVER: ${summary.safe_auto_recover_count}`,
    `- PROBABLE_MATCH: ${summary.probable_match_count}`,
    `- AMBIGUOUS_MATCH: ${summary.ambiguous_match_count}`,
    `- NO_MATCH: ${summary.no_match_count}`,
    "",
    "| classification | confidence_score | lesson_media_id | original_db_path | matched_storage_path | match_reason |",
    "| --- | --- | --- | --- | --- | --- |",
    ...reportRows.map((row) => {
      const originalPath = `${row.original_db_bucket ?? ""}/${row.original_db_path ?? ""}`.replaceAll("|", "\\|");
      const matchedPath = `${row.matched_storage_bucket ?? ""}/${row.matched_storage_path ?? ""}`.replaceAll("|", "\\|");
      return `| ${row.classification} | ${row.confidence_score} | ${row.lesson_media_id} | ${originalPath} | ${matchedPath} | ${row.match_reason.replaceAll("|", "\\|")} |`;
    }),
    "",
  ].join("\n");
}
