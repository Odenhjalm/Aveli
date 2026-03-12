import { createWriteStream, type WriteStream } from "node:fs";
import path from "node:path";

import { ensureDir } from "./fs-utils.js";

type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR";

export class StructuredLogger {
  private sink: WriteStream | null = null;

  public constructor(
    private readonly context: Record<string, unknown>,
    private readonly logFilePath: string,
  ) {}

  public async open(): Promise<void> {
    await ensureDir(path.dirname(this.logFilePath));
    this.sink = createWriteStream(this.logFilePath, { flags: "a" });
  }

  public async close(): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      if (this.sink === null) {
        resolve();
        return;
      }
      this.sink.end(() => resolve());
      this.sink.on("error", reject);
    });
    this.sink = null;
  }

  public debug(event: string, details: Record<string, unknown> = {}): void {
    this.log("DEBUG", event, details);
  }

  public info(event: string, details: Record<string, unknown> = {}): void {
    this.log("INFO", event, details);
  }

  public warn(event: string, details: Record<string, unknown> = {}): void {
    this.log("WARN", event, details);
  }

  public error(event: string, details: Record<string, unknown> = {}): void {
    this.log("ERROR", event, details);
  }

  private log(level: LogLevel, event: string, details: Record<string, unknown>): void {
    const line = JSON.stringify({
      timestamp: new Date().toISOString(),
      level,
      event,
      ...this.context,
      ...details,
    });
    process.stdout.write(`${line}\n`);
    this.sink?.write(`${line}\n`);
  }
}
