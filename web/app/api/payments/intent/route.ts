import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// In-memory sliding-window rate limiter: 5 intent creations per token per minute.
// Single-VDS deployment — in-process state is sufficient. For multi-instance
// deployments this should be moved to the backend Redis layer.
const rlMap = new Map<string, number[]>();
const RL_WINDOW_MS = 60_000;
const RL_MAX = 5;

function checkRateLimit(key: string): boolean {
  const now = Date.now();
  const ts = (rlMap.get(key) ?? []).filter((t) => now - t < RL_WINDOW_MS);
  if (ts.length >= RL_MAX) {
    rlMap.set(key, ts);
    return false;
  }
  ts.push(now);
  rlMap.set(key, ts);
  return true;
}

// Card data NEVER appears in this route handler (SAQ-A compliance).
// The card entry form on the frontend is display-only UX.
// Actual card capture happens on Sipay's hosted 3DS page after redirect.
export async function POST(req: NextRequest) {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get("mopro_at")?.value;
  if (!accessToken) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  if (!checkRateLimit(accessToken)) {
    return NextResponse.json(
      { error: "rate_limit_exceeded", message: "Çok fazla deneme. 1 dakika sonra tekrar deneyin." },
      { status: 429, headers: { "Retry-After": "60" } },
    );
  }

  const idempotencyKey = req.headers.get("idempotency-key") ?? crypto.randomUUID();

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "bad_request" }, { status: 400 });
  }

  const {
    address,
    return_url,
  } = body as {
    address?: { fullName?: string };
    return_url?: string;
  };

  if (!return_url) {
    return NextResponse.json({ error: "return_url required" }, { status: 400 });
  }

  // Derive buyer name from address.fullName; backend uses it as the PSP display name.
  const fullName = (address?.fullName ?? "").trim();
  const parts = fullName.split(/\s+/);
  const buyerName = parts.length > 1 ? parts.slice(0, -1).join(" ") : fullName;
  const buyerSurname = parts.length > 1 ? (parts[parts.length - 1] ?? "") : "";

  const internalBase =
    process.env.API_BASE_URL_INTERNAL ??
    process.env.API_BASE_URL ??
    "http://localhost:8080";

  let upstream: Response;
  try {
    upstream = await fetch(`${internalBase}/checkout/initiate`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Idempotency-Key": idempotencyKey,
        "User-Agent": "mopro-web/L3b",
        Accept: "application/json",
      },
      body: JSON.stringify({
        buyer_name: buyerName,
        buyer_surname: buyerSurname,
        buyer_email: "",
        return_url,
      }),
      cache: "no-store",
    });
  } catch (e) {
    console.error("[payments/intent] upstream fetch failed:", e);
    return NextResponse.json({ error: "service_unavailable" }, { status: 503 });
  }

  const data = (await upstream.json().catch(() => ({}))) as Record<string, unknown>;

  if (!upstream.ok) {
    return NextResponse.json(data, { status: upstream.status });
  }

  // Return only web-relevant fields; never expose three_ds_html (mobile only).
  return NextResponse.json(
    {
      sipay_3ds_url: data["sipay_3ds_url"] ?? null,
      session_id: data["session_id"],
      invoice_id: idempotencyKey,
    },
    { status: 201 },
  );
}
