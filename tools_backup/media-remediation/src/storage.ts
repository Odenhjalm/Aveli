import { createReadStream, createWriteStream } from "node:fs";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { Readable } from "node:stream";
import type { ReadableStream as WebReadableStream } from "node:stream/web";

import type { StructuredLogger } from "./logger.js";
import type { StorageProbe } from "./types.js";

function encodeObjectPath(storagePath: string): string {
  return storagePath
    .split("/")
    .map((part) => encodeURIComponent(part))
    .join("/");
}

async function readResponseBody(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return "<unreadable>";
  }
}

function isConfirmedMissingResponse(statusCode: number, responseBody: string): boolean {
  if (statusCode === 404) {
    return true;
  }
  if (statusCode !== 400) {
    return false;
  }

  const normalized = responseBody.trim().toLowerCase();
  return (
    normalized.includes('"statuscode":"404"')
    || normalized.includes('"statuscode":404')
    || normalized.includes('"error":"not_found"')
    || normalized.includes("object not found")
  );
}

function buildStorageFailureMessage(input: {
  phase: "HEAD" | "GET";
  bucket: string;
  storagePath: string;
  statusCode: number;
  responseBody: string;
}): string {
  if ([401, 403].includes(input.statusCode)) {
    return `Storage ${input.phase} auth failed for ${input.bucket}/${input.storagePath}: ${input.statusCode} ${input.responseBody}`;
  }
  return `Storage ${input.phase} failed for ${input.bucket}/${input.storagePath}: ${input.statusCode} ${input.responseBody}`;
}

export interface SignedUpload {
  url: string;
  headers: Record<string, string>;
  path: string;
  expiresIn: number;
}

export class SupabaseStorageAdmin {
  public constructor(
    private readonly supabaseUrl: string,
    private readonly serviceRoleKey: string,
    private readonly logger: StructuredLogger,
    private readonly retryCount: number,
    private readonly retryDelayMs: number,
  ) {}

  public async probeObject(bucket: string, storagePath: string): Promise<StorageProbe> {
    const objectUrl = new URL(
      `/storage/v1/object/${bucket}/${encodeObjectPath(storagePath)}`,
      this.supabaseUrl,
    );

    const headResponse = await this.request(objectUrl, {
      method: "HEAD",
      headers: this.authHeaders(),
    });

    if (headResponse.ok) {
      return {
        bucket,
        path: storagePath,
        exists: true,
        statusCode: headResponse.status,
        contentType: headResponse.headers.get("content-type"),
        contentLength: Number.parseInt(headResponse.headers.get("content-length") ?? "", 10) || null,
      };
    }

    if ([400, 404].includes(headResponse.status)) {
      const getResponse = await this.request(objectUrl, {
        method: "GET",
        headers: {
          ...this.authHeaders(),
          Range: "bytes=0-0",
        },
      });
      if ([200, 206].includes(getResponse.status)) {
        return {
          bucket,
          path: storagePath,
          exists: true,
          statusCode: getResponse.status,
          contentType: getResponse.headers.get("content-type"),
          contentLength: Number.parseInt(getResponse.headers.get("content-length") ?? "", 10) || null,
        };
      }
      const getResponseBody = await readResponseBody(getResponse);
      if (isConfirmedMissingResponse(getResponse.status, getResponseBody)) {
        return {
          bucket,
          path: storagePath,
          exists: false,
          statusCode: getResponse.status,
          contentType: null,
          contentLength: null,
        };
      }
      throw new Error(buildStorageFailureMessage({
        phase: "GET",
        bucket,
        storagePath,
        statusCode: getResponse.status,
        responseBody: getResponseBody,
      }));
    }

    throw new Error(buildStorageFailureMessage({
      phase: "HEAD",
      bucket,
      storagePath,
      statusCode: headResponse.status,
      responseBody: await readResponseBody(headResponse),
    }));
  }

  public async downloadObject(bucket: string, storagePath: string, destination: string): Promise<void> {
    const url = new URL(
      `/storage/v1/object/${bucket}/${encodeObjectPath(storagePath)}`,
      this.supabaseUrl,
    );
    const response = await this.request(url, {
      method: "GET",
      headers: this.authHeaders(),
    });
    if (!response.ok || response.body === null) {
      throw new Error(`Download failed for ${bucket}/${storagePath}: ${response.status} ${await readResponseBody(response)}`);
    }

    await mkdir(path.dirname(destination), {
      recursive: true,
    });

    const body = Readable.fromWeb(response.body as unknown as WebReadableStream);
    const sink = createWriteStream(destination);
    await new Promise<void>((resolve, reject) => {
      body.pipe(sink);
      body.on("error", reject);
      sink.on("error", reject);
      sink.on("finish", () => resolve());
    });
  }

  public async createUploadUrl(
    bucket: string,
    storagePath: string,
    contentType: string,
    upsert = true,
    cacheSeconds = 3600,
  ): Promise<SignedUpload> {
    const url = new URL(
      `/storage/v1/object/upload/sign/${bucket}/${encodeObjectPath(storagePath)}`,
      this.supabaseUrl,
    );
    const response = await this.request(url, {
      method: "POST",
      headers: {
        ...this.authHeaders(),
        "Content-Type": "application/json",
        ...(upsert ? { "x-upsert": "true" } : {}),
      },
      body: JSON.stringify({}),
    });
    if (!response.ok) {
      throw new Error(`Upload signing failed: ${response.status} ${await readResponseBody(response)}`);
    }

    const payload = (await response.json()) as { url?: string; signedUrl?: string };
    const relativeUrl = payload.url ?? payload.signedUrl;
    if (!relativeUrl) {
      throw new Error("Upload signing response missing url");
    }

    const absoluteUrl = new URL(relativeUrl, this.supabaseUrl).toString();
    return {
      url: absoluteUrl,
      path: storagePath,
      expiresIn: 7200,
      headers: {
        "content-type": contentType,
        "cache-control": `max-age=${cacheSeconds}`,
        "x-upsert": upsert ? "true" : "false",
      },
    };
  }

  public async uploadFile(upload: SignedUpload, localPath: string): Promise<void> {
    const response = await this.request(new URL(upload.url), {
      method: "PUT",
      headers: upload.headers,
      body: createReadStream(localPath) as unknown as BodyInit,
      duplex: "half",
    } as RequestInit);
    if (!response.ok) {
      throw new Error(`Signed upload failed: ${response.status} ${await readResponseBody(response)}`);
    }
  }

  private authHeaders(): Record<string, string> {
    return {
      apikey: this.serviceRoleKey,
      Authorization: `Bearer ${this.serviceRoleKey}`,
    };
  }

  private async request(url: URL, init: RequestInit): Promise<Response> {
    let attempt = 0;
    while (true) {
      attempt += 1;
      try {
        return await fetch(url, init);
      } catch (error) {
        if (attempt >= this.retryCount) {
          throw error;
        }
        this.logger.warn("storage.retry", {
          url: url.toString(),
          attempt,
          error: error instanceof Error ? error.message : String(error),
        });
        await new Promise((resolve) => setTimeout(resolve, this.retryDelayMs * attempt));
      }
    }
  }
}
