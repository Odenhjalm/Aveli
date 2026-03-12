import path from "node:path";

import { FIX_STRATEGIES } from "./types.js";
import type { FixStrategy, RuntimeOptions } from "./types.js";

function parseInteger(value: string | undefined, fallback: number): number {
  if (value === undefined || value.trim() === "") {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseBoolean(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value.trim() === "") {
    return fallback;
  }
  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "n", "off"].includes(normalized)) {
    return false;
  }
  return fallback;
}

function parseMultiValue(argv: string[], flag: string): string[] {
  const values: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === flag && argv[index + 1]) {
      values.push(argv[index + 1] ?? "");
    }
  }
  return values.filter(Boolean);
}

function parseValue(argv: string[], flag: string, fallback: string): string {
  const index = argv.findIndex((item) => item === flag);
  if (index === -1) {
    return fallback;
  }
  return argv[index + 1] ?? fallback;
}

function hasFlag(argv: string[], flag: string): boolean {
  return argv.includes(flag);
}

function parseFixStrategies(argv: string[]): FixStrategy[] {
  const requested = parseMultiValue(argv, "--fix-strategy");
  const allowed = new Set<string>(FIX_STRATEGIES);
  const invalid = requested.filter((value) => !allowed.has(value));
  if (invalid.length > 0) {
    throw new Error(
      `Invalid --fix-strategy value(s): ${invalid.join(", ")}. Allowed values: ${FIX_STRATEGIES.join(", ")}`,
    );
  }
  return requested as FixStrategy[];
}

export interface ServiceEnvironment {
  supabaseUrl: string;
  serviceRoleKey: string;
  options: RuntimeOptions;
}

export function loadServiceEnvironment(argv: string[], serviceName: string): ServiceEnvironment {
  const supabaseUrl = process.env.SUPABASE_URL?.trim() ?? "";
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() ?? "";

  if (!supabaseUrl) {
    throw new Error("SUPABASE_URL is required");
  }
  if (!serviceRoleKey) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is required");
  }

  const outputDir = path.resolve(
    parseValue(argv, "--output-dir", process.env.MEDIA_REMEDIATION_OUTPUT_DIR ?? "reports/media-remediation"),
  );

  const options: RuntimeOptions = {
    dryRun:
      hasFlag(argv, "--dry-run")
      || parseBoolean(process.env.MEDIA_REMEDIATION_DRY_RUN, true),
    activeOnly:
      !hasFlag(argv, "--include-inactive")
      && parseBoolean(process.env.MEDIA_REMEDIATION_ACTIVE_ONLY, true),
    outputDir,
    courseIds: parseMultiValue(argv, "--course-id"),
    fixStrategies: parseFixStrategies(argv),
    batchSize: parseInteger(
      parseValue(argv, "--batch-size", process.env.MEDIA_REMEDIATION_BATCH_SIZE ?? "50"),
      50,
    ),
    minByteSize: parseInteger(
      parseValue(argv, "--min-byte-size", process.env.MEDIA_REMEDIATION_MIN_BYTE_SIZE ?? "100"),
      100,
    ),
    retryCount: parseInteger(
      parseValue(argv, "--retry-count", process.env.MEDIA_REMEDIATION_RETRY_COUNT ?? "3"),
      3,
    ),
    retryDelayMs: parseInteger(
      parseValue(argv, "--retry-delay-ms", process.env.MEDIA_REMEDIATION_RETRY_DELAY_MS ?? "500"),
      500,
    ),
    ffmpegBin: parseValue(argv, "--ffmpeg-bin", process.env.MEDIA_REMEDIATION_FFMPEG ?? "ffmpeg"),
    ffprobeBin: parseValue(argv, "--ffprobe-bin", process.env.MEDIA_REMEDIATION_FFPROBE ?? "ffprobe"),
  };

  return { supabaseUrl, serviceRoleKey, options };
}

export function printUsage(serviceName: string): void {
  process.stdout.write(
    [
      `Usage: ${serviceName} [--dry-run] [--course-id <uuid>] [--fix-strategy <name>] [--output-dir <dir>]`,
      "",
      "Environment:",
      "  SUPABASE_URL",
      "  SUPABASE_SERVICE_ROLE_KEY",
      "  MEDIA_REMEDIATION_DRY_RUN=true|false",
      "  MEDIA_REMEDIATION_ACTIVE_ONLY=true|false  (legacy compatibility flag; inventory scope now covers all real lesson media rows)",
      `Fix strategies: ${FIX_STRATEGIES.join(", ")}`,
    ].join("\n"),
  );
  process.stdout.write("\n");
}
