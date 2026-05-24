import type { ReactNode } from "react";

// Root layout: minimal shell. The [locale] layout provides <html> + <body>.
// API route handlers render without any layout.
export default function RootLayout({ children }: { children: ReactNode }) {
  return children;
}
