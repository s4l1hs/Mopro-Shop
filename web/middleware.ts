import createMiddleware from "next-intl/middleware";
import { type NextRequest, NextResponse } from "next/server";
import { routing } from "./i18n/routing";

const intlMiddleware = createMiddleware(routing);

// Routes that require authentication (matched after stripping locale prefix)
const PROTECTED_PREFIXES = ["/account", "/checkout"];
// Routes that are only for unauthenticated users
const AUTH_ONLY_PREFIXES = ["/login"];

function stripLocale(pathname: string): string {
  return pathname.replace(/^\/(tr|en)(\/|$)/, "/");
}

export default function middleware(request: NextRequest): NextResponse {
  const { pathname } = request.nextUrl;

  // API routes bypass all middleware
  if (pathname.startsWith("/api/")) {
    return NextResponse.next();
  }

  const stripped = stripLocale(pathname);
  const hasSession = request.cookies.has("mopro_s");

  // Redirect authenticated users away from /login
  if (AUTH_ONLY_PREFIXES.some((p) => stripped.startsWith(p)) && hasSession) {
    const locale = pathname.startsWith("/en") ? "en" : "tr";
    const next = request.nextUrl.searchParams.get("next");
    const dest = next ? decodeURIComponent(next) : (locale === "tr" ? "/" : "/en");
    return NextResponse.redirect(new URL(dest, request.url));
  }

  // Redirect unauthenticated users away from protected routes
  if (PROTECTED_PREFIXES.some((p) => stripped.startsWith(p)) && !hasSession) {
    const locale = pathname.startsWith("/en") ? "en" : "tr";
    const next = encodeURIComponent(pathname);
    const base = locale === "tr" ? "/login" : "/en/login";
    return NextResponse.redirect(new URL(`${base}?next=${next}`, request.url));
  }

  return intlMiddleware(request);
}

export const config = {
  matcher: [
    // Match all paths except static files and Next.js internals
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|txt)$).*)",
  ],
};
