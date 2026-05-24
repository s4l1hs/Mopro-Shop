"use client";

import { useState } from "react";
import { toast } from "sonner";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { OrderSummary } from "./order-summary";
import { apiFetch } from "@/lib/api-client";
import { useCartItems, useCartStore } from "@/store/cart";
import type { AddressFormValues } from "./step-address";
import type { PaymentFormValues } from "./step-payment";

interface StepReviewProps {
  address: AddressFormValues;
  payment: PaymentFormValues;
  onBack: () => void;
}

export function StepReview({ address, payment, onBack }: StepReviewProps) {
  const [consent1, setConsent1] = useState(false);
  const [consent2, setConsent2] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const items = useCartItems();
  const clearCart = useCartStore((s) => s.clearCart);
  const router = useRouter();

  const canSubmit = consent1 && consent2 && !submitting && items.length > 0;

  const handlePlaceOrder = async () => {
    if (!canSubmit) return;
    setSubmitting(true);
    try {
      type OrderResponse = { id: string };
      const res = await apiFetch<OrderResponse>("/orders", {
        method: "POST",
        body: {
          items: items.map((it) => ({
            productId: it.productId,
            quantity: it.quantity,
            priceMinor: it.priceMinor,
          })),
          address: {
            fullName: address.fullName,
            phone: address.phone,
            city: address.city,
            district: address.district,
            addressLine: address.addressLine,
            postalCode: address.postalCode ?? "",
          },
          payment: {
            // Sipay mock: send masked card data only
            lastFour: payment.cardNumber.replace(/\s/g, "").slice(-4),
            holderName: payment.holderName,
            expiry: payment.expiry,
          },
        },
      });
      clearCart();
      router.push(`/orders/${res.id}?status=success`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Sipariş gönderilemedi";
      toast.error(msg);
      setSubmitting(false);
    }
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

      {/* Payment summary */}
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
          {submitting ? "Sipariş veriliyor…" : "Siparişi onayla"}
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
