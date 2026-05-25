"use client";

import { Check } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useRef } from "react";
import { OrderSummary } from "@/components/checkout/order-summary";
import { StepAddress, type AddressFormValues } from "@/components/checkout/step-address";
import { StepPayment, type PaymentFormValues } from "@/components/checkout/step-payment";
import { StepReview } from "@/components/checkout/step-review";
import { getSipayErrorMessage } from "@/lib/payments/error-map";
import { useCartItems } from "@/store/cart";
import { cn } from "@/lib/utils";

const STEPS = [
  { n: 1, label: "Adres" },
  { n: 2, label: "Ödeme" },
  { n: 3, label: "Özet" },
] as const;

function CheckoutStepper({ current }: { current: number }) {
  return (
    <ol className="flex items-center gap-0">
      {STEPS.map(({ n, label }, i) => {
        const done = n < current;
        const active = n === current;
        return (
          <li key={n} className="flex items-center">
            <div className="flex flex-col items-center">
              <span
                className={cn(
                  "flex h-8 w-8 items-center justify-center rounded-full text-sm font-semibold border-2 transition-colors",
                  done
                    ? "bg-primary border-primary text-primary-foreground"
                    : active
                      ? "border-primary text-primary bg-background"
                      : "border-border text-muted-foreground bg-background",
                )}
              >
                {done ? <Check className="h-4 w-4" /> : n}
              </span>
              <span
                className={cn(
                  "text-xs mt-1",
                  active ? "text-primary font-medium" : "text-muted-foreground",
                )}
              >
                {label}
              </span>
            </div>
            {i < STEPS.length - 1 && (
              <div
                className={cn(
                  "h-0.5 w-16 mx-2 mb-4 transition-colors",
                  done ? "bg-primary" : "bg-border",
                )}
              />
            )}
          </li>
        );
      })}
    </ol>
  );
}

function CheckoutFlow() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const items = useCartItems();

  const step = Math.max(1, Math.min(3, parseInt(searchParams.get("step") ?? "1", 10)));

  const addressRef = useRef<AddressFormValues | undefined>(undefined);
  const paymentRef = useRef<PaymentFormValues | undefined>(undefined);

  useEffect(() => {
    if (items.length === 0) {
      router.replace("/cart");
    }
  }, [items.length, router]);

  const goToStep = (n: number) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("step", String(n));
    router.push(`?${params.toString()}`);
  };

  const handleAddressNext = (values: AddressFormValues) => {
    addressRef.current = values;
    goToStep(2);
  };

  const handlePaymentNext = (values: PaymentFormValues) => {
    paymentRef.current = values;
    goToStep(3);
  };

  if (items.length === 0) {
    return null;
  }

  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6 md:py-8">
      <div className="mb-8 flex justify-center">
        <CheckoutStepper current={step} />
      </div>

      <div className="grid lg:grid-cols-[1fr_360px] gap-6 lg:gap-10 items-start">
        {/* Left: active step form */}
        <div className="rounded-lg border border-border p-5">
          {step === 1 && (
            <>
              <h2 className="text-lg font-semibold mb-5">Teslimat Adresi</h2>
              <StepAddress
                {...(addressRef.current !== undefined && {
                  defaultValues: addressRef.current,
                })}
                onNext={handleAddressNext}
              />
            </>
          )}
          {step === 2 && (
            <>
              <h2 className="text-lg font-semibold mb-5">Ödeme Bilgileri</h2>
              <StepPayment
                onNext={handlePaymentNext}
                onBack={() => goToStep(1)}
              />
            </>
          )}
          {step === 3 && addressRef.current && paymentRef.current && (
            <>
              <h2 className="text-lg font-semibold mb-5">Sipariş Özeti</h2>
              <StepReview
                address={addressRef.current}
                payment={paymentRef.current}
                onBack={() => goToStep(2)}
                initialError={
                  searchParams.get("error")
                    ? getSipayErrorMessage(searchParams.get("error"))
                    : undefined
                }
              />
            </>
          )}
          {step === 3 && (!addressRef.current || !paymentRef.current) && (
            <p className="text-sm text-muted-foreground">
              Lütfen önceki adımları tamamlayın.{" "}
              <button
                type="button"
                onClick={() => goToStep(1)}
                className="text-primary underline underline-offset-2"
              >
                Başa dön
              </button>
            </p>
          )}
        </div>

        {/* Right: order summary sidebar */}
        <div className="rounded-lg border border-border p-4 lg:sticky lg:top-20">
          <h3 className="font-semibold text-foreground mb-3">Sipariş Özeti</h3>
          <OrderSummary compact />
        </div>
      </div>
    </div>
  );
}

export default function CheckoutPage() {
  return (
    <Suspense fallback={null}>
      <CheckoutFlow />
    </Suspense>
  );
}
