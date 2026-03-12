import type { StructuredLogger } from "./logger.js";

type FilterOperator = "eq" | "neq" | "lt" | "lte" | "gt" | "gte" | "is" | "like" | "in";

export interface Filter {
  column: string;
  operator: FilterOperator;
  value: boolean | number | string | null | Array<boolean | number | string>;
}

export interface SelectOptions {
  schema?: string;
  select?: string;
  filters?: Filter[];
  order?: string;
  limit?: number;
  offset?: number;
}

function encodeFilterValue(
  operator: FilterOperator,
  value: Filter["value"],
): string {
  if (operator === "in") {
    const values = Array.isArray(value) ? value : [value];
    const serialized = values
      .map((item) => {
        if (typeof item === "number" || typeof item === "boolean") {
          return `${item}`;
        }
        return `"${String(item).replaceAll('"', '\\"')}"`;
      })
      .join(",");
    return `(${serialized})`;
  }
  if (value === null) {
    return "null";
  }
  return `${value}`;
}

async function readResponseBody(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return "<unreadable>";
  }
}

export class SupabaseAdminClient {
  public constructor(
    private readonly supabaseUrl: string,
    private readonly serviceRoleKey: string,
    private readonly logger: StructuredLogger,
    private readonly retryCount: number,
    private readonly retryDelayMs: number,
  ) {}

  public async listAll<T>(resource: string, options: SelectOptions = {}): Promise<T[]> {
    const allRows: T[] = [];
    let offset = options.offset ?? 0;
    const limit = options.limit ?? 500;

    while (true) {
      const rows = await this.select<T>(resource, { ...options, limit, offset });
      allRows.push(...rows);
      if (rows.length < limit) {
        return allRows;
      }
      offset += limit;
    }
  }

  public async select<T>(resource: string, options: SelectOptions = {}): Promise<T[]> {
    const url = this.buildUrl(resource, options);
    const response = await this.request("GET", url, {
      headers: this.profileHeaders(options.schema ?? "app"),
    });
    if (!response.ok) {
      throw new Error(`Select failed for ${resource}: ${response.status} ${await readResponseBody(response)}`);
    }
    return (await response.json()) as T[];
  }

  public async patch<T>(
    resource: string,
    values: Record<string, unknown>,
    options: Omit<SelectOptions, "limit" | "offset"> = {},
  ): Promise<T[]> {
    const url = this.buildUrl(resource, { ...options, select: options.select ?? "*" });
    const response = await this.request("PATCH", url, {
      headers: {
        ...this.profileHeaders(options.schema ?? "app", true),
        Prefer: "return=representation",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(values),
    });
    if (!response.ok) {
      throw new Error(`Patch failed for ${resource}: ${response.status} ${await readResponseBody(response)}`);
    }
    return (await response.json()) as T[];
  }

  public async insert<T>(
    resource: string,
    values: Record<string, unknown> | Array<Record<string, unknown>>,
    options: {
      schema?: string;
      select?: string;
      onConflict?: string;
      upsert?: boolean;
    } = {},
  ): Promise<T[]> {
    const params = new URLSearchParams();
    params.set("select", options.select ?? "*");
    if (options.onConflict) {
      params.set("on_conflict", options.onConflict);
    }
    const url = new URL(`/rest/v1/${resource}`, this.supabaseUrl);
    url.search = params.toString();
    const prefer = options.upsert
      ? "resolution=merge-duplicates,return=representation"
      : "return=representation";
    const response = await this.request("POST", url, {
      headers: {
        ...this.profileHeaders(options.schema ?? "app", true),
        Prefer: prefer,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(values),
    });
    if (!response.ok) {
      throw new Error(`Insert failed for ${resource}: ${response.status} ${await readResponseBody(response)}`);
    }
    return (await response.json()) as T[];
  }

  public getSupabaseUrl(): string {
    return this.supabaseUrl;
  }

  public getServiceRoleKey(): string {
    return this.serviceRoleKey;
  }

  public getRetryConfig(): { retryCount: number; retryDelayMs: number } {
    return {
      retryCount: this.retryCount,
      retryDelayMs: this.retryDelayMs,
    };
  }

  private buildUrl(resource: string, options: SelectOptions): URL {
    const url = new URL(`/rest/v1/${resource}`, this.supabaseUrl);
    const params = new URLSearchParams();
    params.set("select", options.select ?? "*");
    if (options.order) {
      params.set("order", options.order);
    }
    if (options.limit !== undefined) {
      params.set("limit", `${options.limit}`);
    }
    if (options.offset !== undefined) {
      params.set("offset", `${options.offset}`);
    }
    for (const filter of options.filters ?? []) {
      params.set(filter.column, `${filter.operator}.${encodeFilterValue(filter.operator, filter.value)}`);
    }
    url.search = params.toString();
    return url;
  }

  private profileHeaders(schema: string, isWrite = false): Record<string, string> {
    return {
      apikey: this.serviceRoleKey,
      Authorization: `Bearer ${this.serviceRoleKey}`,
      [isWrite ? "Content-Profile" : "Accept-Profile"]: schema,
      ...(isWrite ? { "Accept-Profile": schema } : {}),
    };
  }

  private async request(urlMethod: string, url: URL, init: RequestInit): Promise<Response> {
    let attempt = 0;
    while (true) {
      attempt += 1;
      try {
        return await fetch(url, { method: urlMethod, ...init });
      } catch (error) {
        if (attempt >= this.retryCount) {
          throw error;
        }
        this.logger.warn("postgrest.retry", {
          method: urlMethod,
          url: url.toString(),
          attempt,
          error: error instanceof Error ? error.message : String(error),
        });
        await new Promise((resolve) => setTimeout(resolve, this.retryDelayMs * attempt));
      }
    }
  }
}
