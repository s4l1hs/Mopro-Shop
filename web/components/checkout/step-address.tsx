"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import type { Resolver } from "react-hook-form";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { TR_PROVINCES } from "@/lib/tr-provinces";
import { cn } from "@/lib/utils";

const addressSchema = z.object({
  fullName: z.string().min(3, "Ad soyad en az 3 karakter olmalıdır"),
  phone: z
    .string()
    .regex(/^(\+90|0)?5\d{9}$/, "Geçerli bir Türkiye cep telefonu giriniz"),
  city: z.string().min(1, "Şehir seçiniz"),
  district: z.string().min(2, "İlçe en az 2 karakter olmalıdır"),
  addressLine: z.string().min(10, "Adres en az 10 karakter olmalıdır"),
  postalCode: z
    .string()
    .refine((v) => v === "" || /^\d{5}$/.test(v), "Posta kodu 5 haneli olmalıdır"),
});

export type AddressFormValues = z.infer<typeof addressSchema>;

interface StepAddressProps {
  defaultValues?: Partial<AddressFormValues> | undefined;
  onNext: (values: AddressFormValues) => void;
  submitLabel?: string | undefined;
  onCancel?: (() => void) | undefined;
}

export function StepAddress({ defaultValues, onNext, submitLabel, onCancel }: StepAddressProps) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<AddressFormValues>({
    resolver: zodResolver(addressSchema) as Resolver<AddressFormValues>,
    defaultValues: {
      fullName: defaultValues?.fullName ?? "",
      phone: defaultValues?.phone ?? "",
      city: defaultValues?.city ?? "",
      district: defaultValues?.district ?? "",
      addressLine: defaultValues?.addressLine ?? "",
      postalCode: defaultValues?.postalCode ?? "",
    },
  });

  return (
    <form onSubmit={handleSubmit(onNext)} className="space-y-4" noValidate>
      <div className="grid sm:grid-cols-2 gap-4">
        <Field label="Ad Soyad" error={errors.fullName?.message}>
          <Input
            {...register("fullName")}
            placeholder="Mehmet Yılmaz"
            autoComplete="name"
            className={cn(errors.fullName && "border-destructive")}
          />
        </Field>
        <Field label="Cep Telefonu" error={errors.phone?.message}>
          <Input
            {...register("phone")}
            placeholder="0532 000 00 00"
            type="tel"
            autoComplete="tel"
            inputMode="tel"
            className={cn(errors.phone && "border-destructive")}
          />
        </Field>
      </div>

      <div className="grid sm:grid-cols-2 gap-4">
        <Field label="Şehir" error={errors.city?.message}>
          <select
            {...register("city")}
            className={cn(
              "flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50",
              errors.city && "border-destructive",
            )}
          >
            <option value="">Şehir seçiniz</option>
            {TR_PROVINCES.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </select>
        </Field>
        <Field label="İlçe" error={errors.district?.message}>
          <Input
            {...register("district")}
            placeholder="Kadıköy"
            className={cn(errors.district && "border-destructive")}
          />
        </Field>
      </div>

      <Field label="Adres" error={errors.addressLine?.message}>
        <textarea
          {...register("addressLine")}
          placeholder="Mahalle, sokak, kapı no, daire no…"
          rows={3}
          className={cn(
            "flex w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50 resize-none",
            errors.addressLine && "border-destructive",
          )}
        />
      </Field>

      <Field label="Posta Kodu (isteğe bağlı)" error={errors.postalCode?.message}>
        <Input
          {...register("postalCode")}
          placeholder="34700"
          inputMode="numeric"
          maxLength={5}
          className={cn("max-w-[140px]", errors.postalCode && "border-destructive")}
        />
      </Field>

      <div className="pt-2 flex gap-2">
        {onCancel && (
          <Button type="button" variant="outline" onClick={onCancel}>
            İptal
          </Button>
        )}
        <Button type="submit" disabled={isSubmitting} className="w-full sm:w-auto">
          {submitLabel ?? "Devam et — Ödeme"}
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
