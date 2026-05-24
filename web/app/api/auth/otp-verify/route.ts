import { NextRequest, NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080";

// Defense-in-depth: TR mobile E.164 only; client must already enforce this.
const TR_PHONE_RE = /^\+905\d{9}$/;
const OTP_CODE_RE = /^\d{6}$/;

// Cookie lifetimes must match token lifetimes from the API
const ACCESS_TOKEN_MAX_AGE = 900;          // 15 min  (matches expires_in)
const REFRESH_TOKEN_MAX_AGE = 30 * 86400;  // 30 days

const SECURE = process.env.NODE_ENV === "production";

// Backend response shape (verified against production Phase 4.2a smoke tests)
interface VerifyResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  refresh_expires_at: string;
  token_type: string;
}

export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch (e) {
    console.error("[otp-verify] bad json:", e);
    return NextResponse.json({ error: { code: "bad_request", message: "Invalid JSON" } }, { status: 400 });
  }

  const { phone, code } = body as { phone?: unknown; code?: unknown };
  if (typeof phone !== "string" || !TR_PHONE_RE.test(phone)) {
    return NextResponse.json(
      { error: { code: "invalid_phone", message: "Telefon numarası geçersiz" } },
      { status: 422 },
    );
  }
  if (typeof code !== "string" || !OTP_CODE_RE.test(code)) {
    return NextResponse.json(
      { error: { code: "invalid_code", message: "Doğrulama kodu 6 haneli olmalı" } },
      { status: 422 },
    );
  }

  try {
    const upstream = await fetch(`${API_BASE}/auth/otp/verify`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Idempotency-Key": crypto.randomUUID(),
      },
      body: JSON.stringify(body),
    });

    const text = await upstream.text();
    const data = text ? JSON.parse(text) : null;

    if (!upstream.ok) {
      return NextResponse.json(data, { status: upstream.status });
    }

    const verified = data as VerifyResponse;
    if (!verified?.access_token || !verified?.refresh_token) {
      console.error("[otp-verify] backend OK but tokens missing:", data);
      return NextResponse.json(
        { error: { code: "invalid_response", message: "Backend returned 200 but tokens are missing" } },
        { status: 502 },
      );
    }

    // TODO(profile-complete): call /me with the new access token to check
    // if name/surname are set. For W1, assume profile is complete and let
    // the UI surface "complete your profile" prompts where needed.
    const res = NextResponse.json({ profile_complete: true }, { status: 200 });

    // Access token — HTTP-only, short-lived
    res.cookies.set("mopro_at", verified.access_token, {
      httpOnly: true,
      secure: SECURE,
      sameSite: "lax",
      maxAge: ACCESS_TOKEN_MAX_AGE,
      path: "/",
    });

    // Refresh token — HTTP-only, long-lived
    res.cookies.set("mopro_rt", verified.refresh_token, {
      httpOnly: true,
      secure: SECURE,
      sameSite: "lax",
      maxAge: REFRESH_TOKEN_MAX_AGE,
      path: "/",
    });

    // Session indicator — NOT httponly, client reads this to know "are we logged in"
    res.cookies.set("mopro_s", "1", {
      httpOnly: false,
      secure: SECURE,
      sameSite: "lax",
      maxAge: REFRESH_TOKEN_MAX_AGE,
      path: "/",
    });

    return res;
  } catch (e) {
    console.error("[otp-verify] upstream error:", e);
    return NextResponse.json(
      { error: { code: "network_error", message: "Backend unreachable" } },
      { status: 503 },
    );
  }
}
