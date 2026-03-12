import path from "node:path";
import { fileURLToPath } from "node:url";

export function isExecutedAsMain(importMetaUrl: string): boolean {
  const entrypoint = process.argv[1];
  if (!entrypoint) {
    return false;
  }
  return fileURLToPath(importMetaUrl) === path.resolve(entrypoint);
}
