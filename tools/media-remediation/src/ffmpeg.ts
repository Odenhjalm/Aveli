import { access } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { mkdtemp, rm } from "node:fs/promises";
import { spawn } from "node:child_process";

async function ensureBinary(binary: string): Promise<void> {
  try {
    await access(binary);
  } catch {
    // Ignore direct-path access failures; spawn will surface PATH-based lookup failures.
  }
}

function runProcess(command: string, args: string[]): Promise<{ stdout: string; stderr: string }> {
  return new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stderr = "";
    let stdout = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }
      reject(new Error(stderr || stdout || `${command} exited with code ${code ?? "unknown"}`));
    });
  });
}

function extractVersionLine(stdout: string, stderr: string): string {
  return [...stdout.split(/\r?\n/), ...stderr.split(/\r?\n/)].find((line) => line.trim() !== "")?.trim() ?? "";
}

export async function withTempDir<T>(fn: (dir: string) => Promise<T>): Promise<T> {
  const dir = await mkdtemp(path.join(os.tmpdir(), "aveli-media-remediation-"));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

export async function transcodeWithFfmpeg(input: {
  ffmpegBin: string;
  inputPath: string;
  outputPath: string;
  targetContentType: string;
}): Promise<void> {
  await ensureBinary(input.ffmpegBin);
  const args =
    input.targetContentType === "image/jpeg"
      ? [
          "-hide_banner",
          "-nostdin",
          "-y",
          "-i",
          input.inputPath,
          "-map_metadata",
          "-1",
          "-q:v",
          "3",
          input.outputPath,
        ]
      : [
          "-hide_banner",
          "-nostdin",
          "-y",
          "-i",
          input.inputPath,
          "-map_metadata",
          "-1",
          "-vn",
          "-c:a",
          "libmp3lame",
          "-b:a",
          "192k",
          input.outputPath,
        ];
  await runProcess(input.ffmpegBin, args);
}

export async function verifyFfmpegAvailable(ffmpegBin: string): Promise<{ versionLine: string }> {
  await ensureBinary(ffmpegBin);
  try {
    const result = await runProcess(ffmpegBin, ["-version"]);
    return {
      versionLine: extractVersionLine(result.stdout, result.stderr),
    };
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    throw new Error(
      `FFmpeg preflight failed for "${ffmpegBin}". Install ffmpeg or set --ffmpeg-bin / MEDIA_REMEDIATION_FFMPEG before running non-dry-run transcode repairs. ${reason}`,
    );
  }
}
