export const ISSUE_TYPES = [
  "MISSING_IN_STORAGE",
  "UNSUPPORTED_FORMAT",
  "NOT_READY_ASSET",
  "INVALID_KEY",
  "TINY_FILE",
  "LEGACY_DIRECT_REFERENCE",
] as const;

export const FIX_STRATEGIES = [
  "RESTORE_FROM_SOURCE",
  "TRANSCODE_FORMAT",
  "REKEY_STORAGE_PATH",
  "BACKFILL_MEDIA_ASSET",
  "MANUAL_REUPLOAD_REQUIRED",
  "NO_ACTION",
] as const;

export const VERIFICATION_STATUSES = ["PASS", "WARNING", "FAIL"] as const;

export const SAFETY_GROUPS = [
  "SAFE_TO_QUARANTINE",
  "NEEDS_MANUAL_REVIEW",
  "BLOCKED_BY_ACTIVE_REFERENCE",
] as const;

export type IssueType = (typeof ISSUE_TYPES)[number];
export type FixStrategy = (typeof FIX_STRATEGIES)[number];
export type VerificationStatus = (typeof VERIFICATION_STATUSES)[number];
export type SafetyGroup = (typeof SAFETY_GROUPS)[number];

export interface ActiveMediaInventoryRow {
  course_id: string;
  lesson_id: string;
  lesson_media_id: string;
  media_object_id: string | null;
  media_asset_id: string | null;
  bucket: string | null;
  storage_path: string | null;
  content_type: string | null;
  byte_size: number | null;
  media_state: string | null;
  created_at: string;
  reference_type: "media_asset" | "media_object" | "direct_storage_path";
  is_inventory_in_scope: boolean;
  is_active: boolean;
  course_is_published: boolean;
  lesson_is_intro: boolean;
  lesson_media_kind: string | null;
  lesson_storage_bucket: string | null;
  lesson_storage_path: string | null;
  media_object_bucket: string | null;
  media_object_path: string | null;
  media_object_content_type: string | null;
  media_object_byte_size: number | null;
  media_object_original_name: string | null;
  media_asset_type: string | null;
  media_asset_purpose: string | null;
  media_asset_source_bucket: string | null;
  media_asset_source_path: string | null;
  media_asset_original_content_type: string | null;
  media_asset_original_size_bytes: number | null;
  media_asset_stream_bucket: string | null;
  media_asset_stream_path: string | null;
  media_asset_ingest_format: string | null;
  media_asset_streaming_format: string | null;
  media_asset_codec: string | null;
  media_asset_error_message: string | null;
  storage_created_at: string | null;
  storage_updated_at: string | null;
}

export interface MediaRepairPlanRow extends ActiveMediaInventoryRow {
  normalized_bucket: string | null;
  normalized_storage_path: string | null;
  canonical_object_exists: boolean;
  normalized_object_exists: boolean;
  source_object_exists: boolean;
  streaming_object_exists: boolean;
  safe_matching_media_asset_id: string | null;
  safe_matching_media_asset_count: number;
  issue_type: IssueType | null;
  fix_strategy: FixStrategy;
  repair_priority: number;
}

export interface MediaObjectRecord {
  id: string;
  storage_bucket: string | null;
  storage_path: string | null;
  content_type: string | null;
  byte_size: number | null;
  original_name: string | null;
  created_at: string;
}

export interface MediaAssetRecord {
  id: string;
  course_id: string | null;
  lesson_id: string | null;
  media_type: string | null;
  purpose: string | null;
  state: string | null;
  storage_bucket: string | null;
  original_object_path: string | null;
  original_content_type: string | null;
  original_size_bytes: number | null;
  streaming_storage_bucket: string | null;
  streaming_object_path: string | null;
  ingest_format: string | null;
  streaming_format: string | null;
  codec: string | null;
  error_message: string | null;
  created_at: string;
  updated_at: string;
}

export interface CourseRecord {
  id: string;
  is_published: boolean;
}

export interface LessonRecord {
  id: string;
  course_id: string;
  is_intro: boolean;
}

export interface LessonMediaRecord {
  id: string;
  lesson_id: string;
  kind: string | null;
  storage_bucket: string | null;
  storage_path: string | null;
  media_id: string | null;
  media_asset_id: string | null;
  created_at: string;
}

export interface StorageObjectRecord {
  id: string;
  bucket_id: string;
  name: string;
  created_at: string | null;
  updated_at: string | null;
  metadata: Record<string, unknown> | null;
}

export interface StorageProbe {
  bucket: string;
  path: string;
  exists: boolean;
  statusCode: number;
  contentType: string | null;
  contentLength: number | null;
}

export interface ChangeManifestEntry {
  phase: "inventory" | "classification" | "repair" | "verification" | "safety_report";
  courseId: string | null;
  lessonId: string | null;
  lessonMediaId: string | null;
  mediaObjectId: string | null;
  mediaAssetId: string | null;
  issueType: IssueType | null;
  fixStrategy: FixStrategy | null;
  action: string;
  status: "planned" | "skipped" | "applied" | "failed";
  details: Record<string, unknown>;
  timestamp: string;
}

export interface VerificationResult {
  status: VerificationStatus;
  courseId: string;
  lessonId: string;
  lessonMediaId: string;
  issueType: IssueType | null;
  message: string;
  details: Record<string, unknown>;
}

export interface SafetyReportCandidate {
  group: SafetyGroup;
  bucket: string;
  storage_path: string;
  size: number | null;
  detected_reason: string;
  first_seen: string | null;
  last_verified: string;
  referenced_by_active_media: boolean;
  referenced_by_any_media: boolean;
  details: Record<string, unknown>;
}

export interface CanonicalStorageReference {
  bucket: string | null;
  path: string | null;
  changed: boolean;
  reasons: string[];
}

export interface TranscodeTarget {
  bucket: string;
  sourcePath: string;
  targetPath: string;
  targetContentType: string;
  targetExtension: string;
}

export interface RuntimeOptions {
  dryRun: boolean;
  activeOnly: boolean;
  outputDir: string;
  courseIds: string[];
  fixStrategies: FixStrategy[];
  batchSize: number;
  minByteSize: number;
  retryCount: number;
  retryDelayMs: number;
  ffmpegBin: string;
  ffprobeBin: string;
}
