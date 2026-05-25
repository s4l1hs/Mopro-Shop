import { Suspense } from "react";
import { CheckoutRedirectClient } from "./redirect-client";

export const dynamic = "force-dynamic";

interface Props {
  searchParams: Promise<Record<string, string>>;
}

// Sipay redirects here after 3DS with: invoice_id, sipay_status, hash_key, transaction_id, error_code
// We treat query params as hints only — the webhook is the source of truth.
// This page polls the backend DB until a terminal state appears (max 30s).
export default async function CheckoutRedirectPage({ searchParams }: Props) {
  const params = await searchParams;
  return (
    <Suspense fallback={null}>
      <CheckoutRedirectClient searchParams={params} />
    </Suspense>
  );
}
