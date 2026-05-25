"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { OrderSummary } from "./order-summary";
import { useCartItems } from "@/store/cart";
import { useCheckoutStore } from "@/lib/checkout/checkout-store";
import { getSipayErrorMessage } from "@/lib/payments/error-map";
import type { AddressFormValues } from "./step-address";
import type { PaymentFormValues } from "./step-payment";

interface StepReviewProps {
  address: AddressFormValues;
  payment: PaymentFormValues;
  onBack: () => void;
  initialError?: string | undefined;
}

type SubmitState =
  | { kind: "idle" }
  | { kind: "submitting" }
  | { kind: "redirecting"; url: string }
  | { kind: "error"; message: string };

export function StepReview({ address, payment, onBack, initialError }: StepReviewProps) {
  const [consent1, setConsent1] = useState(false);
  const [consent2, setConsent2] = useState(false);
  const [state, setState] = useState<SubmitState>(
    initialError ? { kind: "error", message: initialError } : { kind: "idle" },
  );
  const items = useCartItems();
  const { getOrCreateIdempotencyKey, clearCardData } = useCheckoutStore();

  const submitting = state.kind === "submitting" || state.kind === "redirecting";
  const canSubmit = consent1 && consent2 && !submitting && items.length > 0;

  const handlePlaceOrder = async () => {
    if (!canSubmit) return;

    setState({ kind: "submitting" });

    const idempotencyKey = getOrCreateIdempotencyKey();

    // returnURL: Sipay redirects here after 3DS; we parse invoice_id from query params.
    const returnURL = `${window.location.origin}/checkout/redirect`;

    let data: { sipay_3ds_url?: string; session_id?: string; invoice_id?: string; error?: string; message?: string };
    try {
      const res = await fetch("/api/payments/intent", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify({
          address: { fullName: address.fullName },
          return_url: returnURL,
          consent: {
            distance_sale: consent2,
            pre_info: consent1,
            ts: new Date().toISOString(),
          },
        }),
      });

      data = await res.json();

      if (!res.ok) {
        const code = data.error ?? "unknown";
        setState({ kind: "error", message: getSipayErrorMessage(code) });
        return;
      }
    } catch {
      setState({ kind: "error", message: getSipayErrorMessage(null) });
      return;
    }

    if (!data.sipay_3ds_url) {
      setState({
        kind: "error",
        message: "3D Secure adresi alınamadı. Lütfen tekrar deneyin.",
      });
      return;
    }

    // Clear sensitive display fields before leaving the page.
    clearCardData();
    setState({ kind: "redirecting", url: data.sipay_3ds_url });

    // Full-page nav — not router.push, not iframe — per Sipay 3DS integration spec.
    window.location.assign(data.sipay_3ds_url);
  };

  return (
    <div className="space-y-6">
      {/* Address summary */}
      <section className="space-y-2">
        <h3 className="text-sm font-semibold text-foreground">Teslimat Adresi</h3>
        <div className="rounded-md border border-border px-4 py-3 text-sm text-muted-foreground space-y-0.5">
          <p className="font-medium text-foreground">{address.fullName}</p>
          <p>{address.phone}</p>
          <p>
            {address.addressLine}, {address.district} / {address.city}
            {address.postalCode ? ` ${address.postalCode}` : ""}
          </p>
        </div>
      </section>

      {/* Payment summary — display only; card data not sent to our backend */}
      <section className="space-y-2">
        <h3 className="text-sm font-semibold text-foreground">Ödeme Yöntemi</h3>
        <div className="rounded-md border border-border px-4 py-3 text-sm text-muted-foreground">
          <p>
            {payment.holderName} — •••• {payment.cardNumber.replace(/\s/g, "").slice(-4)}
          </p>
          <p>Son kullanma: {payment.expiry}</p>
        </div>
      </section>

      <Separator />

      {/* Order summary */}
      <section>
        <h3 className="text-sm font-semibold text-foreground mb-3">Ürünler</h3>
        <OrderSummary compact />
      </section>

      <Separator />

      {/* Consent checkboxes */}
      <div className="space-y-3">
        <ConsentBox checked={consent1} onChange={setConsent1}>
          <strong>Ön Bilgilendirme Formu</strong>&apos;nu okudum ve kabul ediyorum.
        </ConsentBox>
        <ConsentBox checked={consent2} onChange={setConsent2}>
          <strong>Mesafeli Satış Sözleşmesi</strong>&apos;ni okudum ve kabul ediyorum.
        </ConsentBox>
      </div>

      {state.kind === "error" && (
        <p role="alert" className="text-sm text-destructive rounded-md border border-destructive/30 bg-destructive/5 px-3 py-2">
          {state.message}
        </p>
      )}

      {state.kind === "redirecting" && (
        <p className="text-sm text-muted-foreground text-center animate-pulse">
          Sipay güvenli ödeme sayfasına yönlendiriliyorsunuz…
        </p>
      )}

      <div className="flex gap-3 pt-1">
        <Button type="button" variant="outline" onClick={onBack} disabled={submitting}>
          Geri
        </Button>
        <Button
          type="button"
          disabled={!canSubmit}
          onClick={handlePlaceOrder}
          className="flex-1"
        >
          {state.kind === "submitting"
            ? "İşleniyor…"
            : state.kind === "redirecting"
              ? "Yönlendiriliyor…"
              : "Siparişi Onayla ve Öde"}
        </Button>
      </div>
    </div>
  );
}

function ConsentBox({
  checked,
  onChange,
  children,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  children: React.ReactNode;
}) {
  return (
    <label className="flex items-start gap-2.5 cursor-pointer">
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="mt-0.5 h-4 w-4 rounded border-border accent-primary"
      />
      <span className="text-sm text-muted-foreground">{children}</span>
    </label>
  );
}

