import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin("./i18n/request.ts");

const cspDirectives = [
  "default-src 'self'",
  // unsafe-inline required for Next.js inline scripts; nonce-based CSP is a W5 hardening task
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https://img.moproshop.com",
  "font-src 'self'",
  "connect-src 'self' https://api.moproshop.com https://moproshop.com",
  "frame-src 'self' https://3ds.sipay.com.tr",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join("; ");

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "img.moproshop.com" },
    ],
    formats: ["image/avif", "image/webp"],
  },

  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "Content-Security-Policy", value: cspDirectives },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
        ],
      },
    ];
  },

  experimental: {
    // Turbopack is stable in Next.js 15; no flag needed
  },
};

export default withNextIntl(nextConfig);
