import { NextRequest, NextResponse } from "next/server";

const API_BASE = process.env.API_BASE_URL ?? "http://localhost:8080";

export async function POST(req: NextRequest) {
  const accessToken = req.cookies.get("mopro_at")?.value;

  // Best-effort: tell the backend to revoke the session
  if (accessToken) {
    try {
      await fetch(`${API_BASE}/v1/auth/session`, {
        method: "DELETE",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Accept": "application/json",
        },
      });
    } catch {
      // ignore — we clear cookies regardless
    }
  }

  const res = NextResponse.json({ ok: true }, { status: 200 });
  res.cookies.delete("mopro_at");
  res.cookies.delete("mopro_rt");
  res.cookies.delete("mopro_s");
  return res;
}
