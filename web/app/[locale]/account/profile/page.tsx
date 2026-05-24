"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import type { Resolver } from "react-hook-form";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { useProfileQuery, useUpdateProfileMutation } from "@/lib/account/queries";
import { cn } from "@/lib/utils";

function validateTCNo(tc: string): boolean {
  if (!/^\d{11}$/.test(tc)) return false;
  if (tc.charAt(0) === "0") return false;
  const digits = Array.from(tc).map((c) => parseInt(c, 10));
  const oddSum = ((digits[0] ?? 0) + (digits[2] ?? 0) + (digits[4] ?? 0) + (digits[6] ?? 0) + (digits[8] ?? 0)) * 7;
  const evenSum = (digits[1] ?? 0) + (digits[3] ?? 0) + (digits[5] ?? 0) + (digits[7] ?? 0);
  if ((oddSum - evenSum + 1000) % 10 !== (digits[9] ?? 0)) return false;
  const first10Sum = digits.slice(0, 10).reduce((a, b) => a + b, 0);
  return first10Sum % 10 === (digits[10] ?? 0);
}

const profileSchema = z.object({
  first_name: z.string().min(1, "Ad gereklidir"),
  last_name: z.string().min(1, "Soyad gereklidir"),
  birth_date: z.string().optional(),
  gender: z
    .enum(["female", "male", "other", "prefer_not_to_say"])
    .optional(),
  tax_id: z
    .string()
    .refine((v) => v === "" || validateTCNo(v), "Geçerli bir TC kimlik numarası giriniz")
    .optional(),
});

type ProfileFormValues = z.infer<typeof profileSchema>;

const GENDER_OPTIONS = [
  { value: "female", label: "Kadın" },
  { value: "male", label: "Erkek" },
  { value: "other", label: "Diğer" },
  { value: "prefer_not_to_say", label: "Belirtmek istemiyorum" },
] as const;

function FieldLabel({ label, note }: { label: string; note?: string | undefined }) {
  return (
    <div>
      <label className="text-sm font-medium text-foreground">{label}</label>
      {note && <p className="text-xs text-muted-foreground mt-0.5">{note}</p>}
    </div>
  );
}

function Field({
  label,
  note,
  error,
  children,
}: {
  label: string;
  note?: string | undefined;
  error: string | undefined;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <FieldLabel label={label} {...(note !== undefined && { note })} />
      {children}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}

function ProfileForm() {
  const { data: profile, isLoading } = useProfileQuery();
  const updateMutation = useUpdateProfileMutation();

  const {
    register,
    handleSubmit,
    formState: { errors, isDirty, isSubmitting },
  } = useForm<ProfileFormValues>({
    resolver: zodResolver(profileSchema) as Resolver<ProfileFormValues>,
    ...(profile
      ? {
          values: {
            first_name: profile.first_name,
            last_name: profile.last_name,
            birth_date: profile.birth_date ?? "",
            gender: profile.gender,
            tax_id: profile.tax_id ?? "",
          },
        }
      : {}),
  });

  const onSubmit = async (values: ProfileFormValues) => {
    try {
      await updateMutation.mutateAsync({
        first_name: values.first_name,
        last_name: values.last_name,
        ...(values.birth_date ? { birth_date: values.birth_date } : {}),
        ...(values.gender ? { gender: values.gender } : {}),
        ...(values.tax_id ? { tax_id: values.tax_id } : {}),
      });
      toast.success("Profil güncellendi");
    } catch {
      toast.error("Güncelleme başarısız");
    }
  };

  if (isLoading) {
    return (
      <div className="space-y-4">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-10 rounded-md" />
        ))}
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit(onSubmit as unknown as Parameters<typeof handleSubmit>[0])} className="space-y-5" noValidate>
      <div className="grid sm:grid-cols-2 gap-4">
        <Field label="Ad" error={errors.first_name?.message}>
          <Input
            {...register("first_name")}
            placeholder="Mehmet"
            autoComplete="given-name"
            className={cn(errors.first_name && "border-destructive")}
          />
        </Field>
        <Field label="Soyad" error={errors.last_name?.message}>
          <Input
            {...register("last_name")}
            placeholder="Yılmaz"
            autoComplete="family-name"
            className={cn(errors.last_name && "border-destructive")}
          />
        </Field>
      </div>

      <Field
        label="E-posta"
        note="E-posta değiştirmek için destek ile iletişime geç"
        error={undefined}
      >
        <Input
          value={profile?.email ?? ""}
          readOnly
          disabled
          className="bg-muted/50 cursor-not-allowed"
        />
      </Field>

      <Field
        label="Telefon"
        note="Telefon değiştirmek için yeni hesap doğrulaması gerekir — destek ile iletişime geç"
        error={undefined}
      >
        <Input
          value={profile?.phone ?? ""}
          readOnly
          disabled
          className="bg-muted/50 cursor-not-allowed"
        />
      </Field>

      <Field label="Doğum Tarihi (isteğe bağlı)" error={errors.birth_date?.message}>
        <Input
          {...register("birth_date")}
          type="date"
          className={cn("max-w-[200px]", errors.birth_date && "border-destructive")}
        />
      </Field>

      <div className="space-y-1.5">
        <label className="text-sm font-medium text-foreground">
          Cinsiyet (isteğe bağlı)
        </label>
        <div className="flex flex-wrap gap-3">
          {GENDER_OPTIONS.map(({ value, label }) => (
            <label key={value} className="flex items-center gap-2 cursor-pointer">
              <input
                {...register("gender")}
                type="radio"
                value={value}
                className="accent-primary"
              />
              <span className="text-sm text-foreground">{label}</span>
            </label>
          ))}
        </div>
      </div>

      <Field
        label="TC Kimlik No (isteğe bağlı)"
        note="Fatura için gereklidir"
        error={errors.tax_id?.message}
      >
        <Input
          {...register("tax_id")}
          placeholder="12345678901"
          inputMode="numeric"
          maxLength={11}
          className={cn("max-w-[200px]", errors.tax_id && "border-destructive")}
        />
      </Field>

      <Button
        type="submit"
        disabled={!isDirty || isSubmitting}
        className="w-full sm:w-auto"
      >
        {isSubmitting ? "Kaydediliyor…" : "Kaydet"}
      </Button>
    </form>
  );
}

export default function ProfilePage() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-foreground">Profil Bilgilerim</h1>

      {/* Avatar */}
      <div className="flex items-center gap-4">
        <div className="h-16 w-16 rounded-full bg-primary/15 flex items-center justify-center text-2xl font-bold text-primary select-none">
          M
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => toast("Fotoğraf yükleme yakında aktif olacak.")}
        >
          Fotoğraf yükle
        </Button>
      </div>

      <ProfileForm />
    </div>
  );
}
