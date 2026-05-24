import { defineRouting } from "next-intl/routing";

export const routing = defineRouting({
  locales: ["tr", "en"] as const,
  defaultLocale: "tr",
  // Default locale has no prefix in URL (/tr → /)
  localePrefix: "as-needed",
});
