import { NextRequest, NextResponse } from "next/server";
import type { TokenPair } from "@/types/api";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080";
const ACCESS_TOKEN_MAX_AGE = 900;
const REFRESH_TOKEN_MAX_AGE = 30 * 86400;
const SECURE = process.env.NODE_ENV === "production";

export async function POST(req: NextRequest) {
  const refreshToken = req.cookies.get("mopro_rt")?.value;
  if (!refreshToken) {
    return NextResponse.json(
      { error: { code: "unauthorized", message: "No refresh token" } },
      { status: 401 },
    );
  }

  try {
    const upstream = await fetch(`${API_BASE}/auth/refresh`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Idempotency-Key": crypto.randomUUID(),
      },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });

    const data = await upstream.json() as TokenPair | { error: { code: string; message: string } };

    if (!upstream.ok) {
      // Refresh token is invalid/expired — clear all session cookies
      const res = NextResponse.json(data, { status: upstream.status });
      res.cookies.delete("mopro_at");
      res.cookies.delete("mopro_rt");
      res.cookies.delete("mopro_s");
      return res;
    }

    const tokens = data as TokenPair;
    const res = NextResponse.json({ ok: true }, { status: 200 });

    res.cookies.set("mopro_at", tokens.access_token, {
      httpOnly: true,
      secure: SECURE,
      sameSite: "lax",
      maxAge: ACCESS_TOKEN_MAX_AGE,
      path: "/",
    });

    res.cookies.set("mopro_rt", tokens.refresh_token, {
      httpOnly: true,
      secure: SECURE,
      sameSite: "lax",
      maxAge: REFRESH_TOKEN_MAX_AGE,
      path: "/",
    });

    res.cookies.set("mopro_s", "1", {
      httpOnly: false,
      secure: SECURE,
      sameSite: "lax",
      maxAge: REFRESH_TOKEN_MAX_AGE,
      path: "/",
    });

    return res;
  } catch (e) {
    console.error("[refresh] upstream error:", e);
    return NextResponse.json(
      { error: { code: "network_error", message: "Backend unreachable" } },
      { status: 503 },
    );
  }
}
