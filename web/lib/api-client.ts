import type { ErrorEnvelope } from "@/types/api";

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly traceId?: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

type FetchOptions = Omit<RequestInit, "body"> & {
  body?: unknown;
  // Pass the Bearer token when calling from route handlers that have it
  accessToken?: string;
};

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080";

// Core fetch wrapper used by both server and client code.
// - Adds Accept-Language from navigator (client) or a fixed fallback (server).
// - Adds X-Idempotency-Key for all state-mutating methods.
// - Serialises body as JSON.
// - Throws ApiError on non-2xx responses.
export async function apiFetch<T>(
  path: string,
  { body, accessToken, ...init }: FetchOptions = {},
): Promise<T> {
  const method = init.method?.toUpperCase() ?? (body !== undefined ? "POST" : "GET");
  const isMutating = ["POST", "PUT", "PATCH", "DELETE"].includes(method);

  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  headers.set("Accept", "application/json");

  if (accessToken) {
    headers.set("Authorization", `Bearer ${accessToken}`);
  }

  // Add idempotency key on mutating requests if not already provided
  if (isMutating && !headers.has("Idempotency-Key")) {
    headers.set(
      "Idempotency-Key",
      typeof crypto !== "undefined" ? crypto.randomUUID() : `${Date.now()}`,
    );
  }

  const url = path.startsWith("http") ? path : `${API_BASE}${path}`;

  const fetchInit: RequestInit = { ...init, method, headers };
  if (body !== undefined) {
    fetchInit.body = JSON.stringify(body);
  }

  const res = await fetch(url, fetchInit);

  if (!res.ok) {
    let envelope: ErrorEnvelope | undefined;
    try {
      envelope = (await res.json()) as ErrorEnvelope;
    } catch {
      // ignore parse errors
    }
    throw new ApiError(
      res.status,
      envelope?.error.code ?? "unknown",
      envelope?.error.message ?? `HTTP ${res.status}`,
      envelope?.error.trace_id,
    );
  }

  if (res.status === 204) {
    return undefined as T;
  }

  return res.json() as Promise<T>;
}
