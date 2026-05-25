"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
const POLL_INTERVAL_MS = 1500;
const MAX_POLL_MS = 30_000;
const TERMINAL_STATUSES = new Set(["captured", "failed", "cancelled", "refunded"]);

const LOADING_MESSAGES = [
  "Ödemen onaylanıyor…",
  "Bankadan onay bekleniyor…",
  "Neredeyse hazır…",
];

type PollState =
  | { kind: "polling"; msgIdx: number }
  | { kind: "timeout" }
  | { kind: "error"; message: string };

interface IntentStatus {
  status: string;
  order_id?: number;
  failure_reason?: string;
}

export function CheckoutRedirectClient({
  searchParams,
}: {
  searchParams: Record<string, string>;
}) {
  const router = useRouter();
  const invoiceId = searchParams["invoice_id"] ?? searchParams["invoiceId"] ?? null;

  const [pollState, setPollState] = useState<PollState>({ kind: "polling", msgIdx: 0 });
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const startRef = useRef(Date.now());
  const msgIdxRef = useRef(0);

  useEffect(() => {
    if (!invoiceId) {
      setPollState({ kind: "error", message: "Fatura numarası bulunamadı." });
      return;
    }

    const poll = async () => {
      // Cycle loading message
      msgIdxRef.current = (msgIdxRef.current + 1) % LOADING_MESSAGES.length;
      setPollState({ kind: "polling", msgIdx: msgIdxRef.current });

      // Timeout guard
      if (Date.now() - startRef.current > MAX_POLL_MS) {
        if (timerRef.current) clearInterval(timerRef.current);
        setPollState({ kind: "timeout" });
        return;
      }

      let data: IntentStatus;
      try {
        const res = await fetch(`/api/payments/status/${invoiceId}`, {
          cache: "no-store",
        });
        data = (await res.json()) as IntentStatus;
      } catch {
        return; // network blip — keep polling
      }

      if (!TERMINAL_STATUSES.has(data.status)) return;

      if (timerRef.current) clearInterval(timerRef.current);

      if (data.status === "captured" && data.order_id) {
        router.replace(`/orders/${data.order_id}?status=success&i=${invoiceId}`);
      } else {
        const reason = data.failure_reason ?? "unknown";
        router.replace(`/checkout?step=3&error=${encodeURIComponent(reason)}`);
      }
    };

    timerRef.current = setInterval(poll, POLL_INTERVAL_MS);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [invoiceId, router]);

  if (pollState.kind === "timeout") {
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center space-y-4">
        <p className="text-base font-medium text-foreground">
          Onay biraz gecikiyor
        </p>
        <p className="text-sm text-muted-foreground">
          Ödemeniz bankada işleniyor olabilir. Siparişlerim sayfasından durumu
          takip edebilirsiniz.
        </p>
        <Link
          href="/account/orders"
          className="inline-block mt-2 text-sm font-medium text-primary underline underline-offset-2"
        >
          Siparişlerim
        </Link>
      </div>
    );
  }

  if (pollState.kind === "error") {
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center space-y-4">
        <p className="text-sm text-destructive">{pollState.message}</p>
        <Link
          href="/checkout"
          className="text-sm font-medium text-primary underline underline-offset-2"
        >
          Sipariş sayfasına dön
        </Link>
      </div>
    );
  }

  // Polling in progress
  return (
    <div className="mx-auto max-w-md px-4 py-16 text-center space-y-6">
      <div className="flex justify-center">
        <span className="h-10 w-10 rounded-full border-4 border-primary border-t-transparent animate-spin" />
      </div>
      <p className="text-base text-foreground animate-pulse">
        {LOADING_MESSAGES[pollState.msgIdx]}
      </p>
    </div>
  );
}

