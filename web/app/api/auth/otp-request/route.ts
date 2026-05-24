import { NextRequest, NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080";

// Defense-in-depth: TR mobile E.164 only; client must already enforce this.
const TR_PHONE_RE = /^\+905\d{9}$/;

export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch (e) {
    console.error("[otp-request] upstream error:", e);
    return NextResponse.json({ error: { code: "bad_request", message: "Invalid JSON" } }, { status: 400 });
  }

  const phone = (body as { phone?: unknown }).phone;
  if (typeof phone !== "string" || !TR_PHONE_RE.test(phone)) {
    return NextResponse.json(
      { error: { code: "invalid_phone", message: "Telefon numarası geçersiz" } },
      { status: 422 },
    );
  }

  try {
    const upstream = await fetch(`${API_BASE}/auth/otp/request`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Idempotency-Key": crypto.randomUUID(),
      },
      body: JSON.stringify(body),
    });

    // 204 No Content has empty body — don't try to parse JSON
    if (upstream.status === 204 || upstream.headers.get("content-length") === "0") {
      return new NextResponse(null, { status: upstream.status });
    }
    const text = await upstream.text();
    const data = text ? JSON.parse(text) : null;
    return NextResponse.json(data, { status: upstream.status });
  } catch (e) {
    console.error("[otp-request] upstream error:", e);
    return NextResponse.json(
      { error: { code: "network_error", message: "Backend unreachable" } },
      { status: 503 },
    );
  }
}
