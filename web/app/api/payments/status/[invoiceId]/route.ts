import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ invoiceId: string }> },
) {
  const { invoiceId } = await params;

  const cookieStore = await cookies();
  const accessToken = cookieStore.get("mopro_at")?.value;

  const internalBase =
    process.env.API_BASE_URL_INTERNAL ??
    process.env.API_BASE_URL ??
    "http://localhost:8080";

  const headers: Record<string, string> = {
    Accept: "application/json",
    "User-Agent": "mopro-web/L3b",
  };
  if (accessToken) {
    headers["Authorization"] = `Bearer ${accessToken}`;
  }

  let upstream: Response;
  try {
    upstream = await fetch(
      `${internalBase}/payments/${invoiceId}/intent-status`,
      { headers, cache: "no-store" },
    );
  } catch {
    return NextResponse.json({ status: "pending" }, { status: 200 });
  }

  const data = await upstream.json().catch(() => ({ status: "pending" }));
  return NextResponse.json(data, { status: upstream.ok ? 200 : upstream.status });
}
