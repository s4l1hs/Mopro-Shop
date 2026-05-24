"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import type { Resolver } from "react-hook-form";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

function luhn(n: string): boolean {
  let sum = 0;
  let alternate = false;
  for (let i = n.length - 1; i >= 0; i--) {
    let digit = parseInt(n[i] ?? "0", 10);
    if (alternate) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
    alternate = !alternate;
  }
  return sum % 10 === 0;
}

function detectBrand(n: string): "visa" | "mastercard" | "troy" | null {
  const d = n.replace(/\s/g, "");
  if (/^9792/.test(d)) return "troy";
  if (/^4/.test(d)) return "visa";
  if (/^5[1-5]|^2[2-7]/.test(d)) return "mastercard";
  return null;
}

function formatCardNumber(raw: string): string {
  return raw
    .replace(/\D/g, "")
    .slice(0, 16)
    .replace(/(\d{4})(?=\d)/g, "$1 ");
}

function formatExpiry(raw: string): string {
  const digits = raw.replace(/\D/g, "").slice(0, 4);
  return digits.length > 2 ? `${digits.slice(0, 2)}/${digits.slice(2)}` : digits;
}

const paymentSchema = z.object({
  cardNumber: z.string().refine((v) => {
    const d = v.replace(/\s/g, "");
    return d.length >= 13 && d.length <= 19 && luhn(d);
  }, "Kart numarası geçersiz"),
  expiry: z
    .string()
    .regex(/^(0[1-9]|1[0-2])\/\d{2}$/, "AA/YY formatında giriniz")
    .refine((v) => {
      const [mm, yy] = v.split("/");
      const exp = new Date(2000 + parseInt(yy ?? "0", 10), parseInt(mm ?? "0", 10) - 1, 1);
      return exp > new Date();
    }, "Kart süresi dolmuş"),
  cvv: z.string().regex(/^\d{3,4}$/, "CVV 3 veya 4 haneli olmalıdır"),
  holderName: z.string().min(3, "Kart üzerindeki isim giriniz"),
});

export type PaymentFormValues = z.infer<typeof paymentSchema>;

interface StepPaymentProps {
  onNext: (values: PaymentFormValues) => void;
  onBack: () => void;
}

export function StepPayment({ onNext, onBack }: StepPaymentProps) {
  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<PaymentFormValues>({
    resolver: zodResolver(paymentSchema) as Resolver<PaymentFormValues>,
    defaultValues: { cardNumber: "", expiry: "", cvv: "", holderName: "" },
  });

  const cardNumber = watch("cardNumber");
  const brand = detectBrand(cardNumber);

  return (
    <form onSubmit={handleSubmit(onNext)} className="space-y-4" noValidate>
      {/* Card number */}
      <Field label="Kart Numarası" error={errors.cardNumber?.message}>
        <div className="relative">
          <Input
            {...register("cardNumber")}
            placeholder="0000 0000 0000 0000"
            inputMode="numeric"
            autoComplete="cc-number"
            maxLength={19}
            className={cn("pr-16", errors.cardNumber && "border-destructive")}
            onChange={(e) => {
              setValue("cardNumber", formatCardNumber(e.target.value), {
                shouldValidate: false,
              });
            }}
          />
          {brand && (
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-semibold text-muted-foreground uppercase tracking-wide">
              {brand}
            </span>
          )}
        </div>
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Son Kullanma" error={errors.expiry?.message}>
          <Input
            {...register("expiry")}
            placeholder="AA/YY"
            inputMode="numeric"
            autoComplete="cc-exp"
            maxLength={5}
            className={cn(errors.expiry && "border-destructive")}
            onChange={(e) => {
              setValue("expiry", formatExpiry(e.target.value), {
                shouldValidate: false,
              });
            }}
          />
        </Field>
        <Field label="CVV" error={errors.cvv?.message}>
          <Input
            {...register("cvv")}
            placeholder="000"
            type="password"
            inputMode="numeric"
            autoComplete="cc-csc"
            maxLength={4}
            className={cn(errors.cvv && "border-destructive")}
          />
        </Field>
      </div>

      <Field label="Kart Üzerindeki İsim" error={errors.holderName?.message}>
        <Input
          {...register("holderName")}
          placeholder="MEHMET YILMAZ"
          autoComplete="cc-name"
          className={cn(errors.holderName && "border-destructive")}
          onChange={(e) => {
            setValue("holderName", e.target.value.toUpperCase(), {
              shouldValidate: false,
            });
          }}
        />
      </Field>

      <div className="flex gap-3 pt-2">
        <Button type="button" variant="outline" onClick={onBack}>
          Geri
        </Button>
        <Button type="submit" disabled={isSubmitting}>
          Devam et — Sipariş özeti
        </Button>
      </div>
    </form>
  );
}

function Field({
  label,
  error,
  children,
}: {
  label: string;
  error: string | undefined;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <label className="text-sm font-medium text-foreground">{label}</label>
      {children}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
