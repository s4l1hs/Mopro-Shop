import { NextRequest, NextResponse } from "next/server";
import type { TokenPair, User } from "@/types/api";

const API_BASE = process.env.API_BASE_URL ?? "http://localhost:8080";

// Cookie lifetimes must match token lifetimes from the API
const ACCESS_TOKEN_MAX_AGE = 900;          // 15 min  (matches expires_in)
const REFRESH_TOKEN_MAX_AGE = 30 * 86400;  // 30 days

const SECURE = process.env.NODE_ENV === "production";

interface OtpVerifyResponse {
  tokens: TokenPair;
  user: User;
}

export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: { code: "bad_request", message: "Invalid JSON" } }, { status: 400 });
  }

  try {
    const upstream = await fetch(`${API_BASE}/v1/auth/otp-verify`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Idempotency-Key": crypto.randomUUID(),
      },
      body: JSON.stringify(body),
    });

    const data = await upstream.json() as OtpVerifyResponse | { error: { code: string; message: string } };

    if (!upstream.ok) {
      return NextResponse.json(data, { status: upstream.status });
    }

    const { tokens, user } = data as OtpVerifyResponse;
    const profileComplete = Boolean(user.name_first && user.name_last);

    const res = NextResponse.json({ profile_complete: profileComplete }, { status: 200 });

    // Access token — HTTP-only, short-lived
    res.cookies.set("mopro_at", tokens.access_token, {
      httpOnly: true,
      secure: SECURE,
      sameSite: "lax",
      maxAge: ACCESS_TOKEN_MAX_AGE,
      path: "/",
    });

    // Refresh token — HTTP-only, long-lived
    res.cookies.set("mopro_rt", tokens.refresh_token, {
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
  } catch {
    return NextResponse.json(
      { error: { code: "network_error", message: "Backend unreachable" } },
      { status: 503 },
    );
  }
}
