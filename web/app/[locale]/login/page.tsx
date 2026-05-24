"use client";

import { useTranslations } from "next-intl";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ApiError } from "@/lib/api-client";
import { formatTrPhoneForDisplay, normalizeTrPhone } from "@/lib/phone";

type Step = "phone" | "otp";

const OTP_RESEND_SECONDS = 60;
const PHONE_PREFIX = "+90";

// Digits must match /^5\d{9}$/ before submit is enabled
const VALID_DIGITS_RE = /^5\d{9}$/;

export default function GirisPage() {
  const t = useTranslations("auth");
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get("next") ?? "/";

  const [step, setStep] = useState<Step>("phone");
  // phoneDigits: raw 10-digit string used for validation and E.164 construction
  const [phoneDigits, setPhoneDigits] = useState("");
  // phoneDisplay: formatted "555 123 45 67" shown in the input
  const [phoneDisplay, setPhoneDisplay] = useState("");
  const [otp, setOtp] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [countdown, setCountdown] = useState(0);

  const countdownRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const otpInputRef = useRef<HTMLInputElement>(null);

  const startCountdown = useCallback(() => {
    setCountdown(OTP_RESEND_SECONDS);
    countdownRef.current = setInterval(() => {
      setCountdown((c) => {
        if (c <= 1) {
          clearInterval(countdownRef.current!);
          return 0;
        }
        return c - 1;
      });
    }, 1000);
  }, []);

  useEffect(() => {
    return () => {
      if (countdownRef.current) clearInterval(countdownRef.current);
    };
  }, []);

  const applyDigits = (d: string) => {
    const truncated = d.replace(/\D/g, "").slice(0, 10);
    setPhoneDigits(truncated);
    setPhoneDisplay(formatTrPhoneForDisplay(truncated));
  };

  const handlePhoneChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setError(null);
    applyDigits(e.currentTarget.value);
  };

  const handlePhonePaste = (e: React.ClipboardEvent<HTMLInputElement>) => {
    e.preventDefault();
    setError(null);
    const text = e.clipboardData.getData("text");
    // Attempt full normalization first (strips country code, validates length)
    const e164 = normalizeTrPhone(text);
    if (e164) {
      applyDigits(e164.slice(3)); // "+905551234567" → "5551234567"
    } else {
      // Fall back: strip non-digits and truncate to 10
      applyDigits(text.replace(/\D/g, "").slice(0, 10));
    }
  };

  const handleSendOtp = async (e: React.FormEvent) => {
    e.preventDefault();
    const e164 = normalizeTrPhone(phoneDigits);
    if (!e164) return;
    setError(null);
    setLoading(true);

    try {
      const res = await fetch("/api/auth/otp-request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phone: e164, market: "TR" }),
      });

      if (!res.ok) {
        const data = (await res.json()) as { error?: { code?: string; message?: string } };
        const code = data.error?.code ?? "unknown";
        if (code === "rate_limit") {
          setError(t("rate_limit"));
        } else if (code === "phone_locked") {
          setError(t("phone_locked"));
        } else {
          setError(data.error?.message ?? t("unknown_error"));
        }
        return;
      }

      setStep("otp");
      startCountdown();
      setTimeout(() => otpInputRef.current?.focus(), 100);
    } catch {
      setError(t("network_error"));
    } finally {
      setLoading(false);
    }
  };

  const handleVerifyOtp = async (e: React.FormEvent) => {
    e.preventDefault();
    if (otp.length !== 6) return;
    const e164 = normalizeTrPhone(phoneDigits);
    if (!e164) return;
    setError(null);
    setLoading(true);

    try {
      const res = await fetch("/api/auth/otp-verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phone: e164, code: otp }),
      });

      if (!res.ok) {
        const data = (await res.json()) as { error?: { code?: string; message?: string } };
        const code = data.error?.code ?? "unknown";
        if (code === "otp_expired") {
          setError(t("otp_expired"));
        } else if (code === "otp_invalid") {
          setError(t("otp_invalid"));
        } else {
          setError(data.error?.message ?? t("unknown_error"));
        }
        return;
      }

      const data = (await res.json()) as { profile_complete: boolean };
      toast.success("Giriş başarılı");

      if (!data.profile_complete) {
        router.replace("/account/complete-profile");
      } else {
        router.replace(next);
      }
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError(t("network_error"));
      }
    } finally {
      setLoading(false);
    }
  };

  const handleResend = async () => {
    if (countdown > 0 || loading) return;
    const e164 = normalizeTrPhone(phoneDigits);
    if (!e164) return;
    setError(null);
    setLoading(true);
    try {
      const res = await fetch("/api/auth/otp-request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phone: e164, market: "TR" }),
      });
      if (res.ok) {
        startCountdown();
        setOtp("");
        toast.info("Doğrulama kodu tekrar gönderildi");
      }
    } catch {
      // silent — user will see the resend button is still available
    } finally {
      setLoading(false);
    }
  };

  // Show inline error when first digit is typed but is not 5
  const showFirstDigitError = phoneDigits.length > 0 && !phoneDigits.startsWith("5");
  const phoneValid = VALID_DIGITS_RE.test(phoneDigits);

  return (
    <div className="mx-auto flex min-h-[calc(100vh-8rem)] max-w-sm flex-col items-center justify-center px-4 py-12">
      <div className="w-full rounded-xl border border-border bg-card p-6 shadow-sm">
        {step === "phone" ? (
          <form onSubmit={handleSendOtp} className="flex flex-col gap-5" noValidate>
            <div>
              <h1 className="text-2xl font-bold text-foreground">{t("login_title")}</h1>
              <p className="mt-1 text-sm text-muted-foreground">{t("phone_subtitle")}</p>
            </div>

            <div className="flex flex-col gap-1.5">
              <label htmlFor="phone" className="text-sm font-medium text-foreground">
                {t("phone_title")}
              </label>
              <div className="flex items-center gap-2 rounded-md border border-input bg-background px-3 py-2 focus-within:ring-2 focus-within:ring-ring">
                <span className="select-none text-sm font-medium text-muted-foreground">
                  {PHONE_PREFIX}
                </span>
                <input
                  id="phone"
                  type="tel"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  autoComplete="tel"
                  placeholder={t("phone_hint")}
                  value={phoneDisplay}
                  onChange={handlePhoneChange}
                  onPaste={handlePhonePaste}
                  className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
                  maxLength={13}
                  required
                  autoFocus
                />
              </div>
              {showFirstDigitError && (
                <p role="alert" className="text-xs text-destructive">
                  TR mobil numarası 5 ile başlamalı
                </p>
              )}
            </div>

            {error && (
              <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
                {error}
              </p>
            )}

            <Button type="submit" disabled={loading || !phoneValid} className="w-full">
              {loading ? "…" : t("send_otp")}
            </Button>
          </form>
        ) : (
          <form onSubmit={handleVerifyOtp} className="flex flex-col gap-5" noValidate>
            <div>
              <h1 className="text-2xl font-bold text-foreground">{t("otp_title")}</h1>
              <p className="mt-1 text-sm text-muted-foreground">
                {t("otp_subtitle", { phone: `${PHONE_PREFIX} ${phoneDisplay}` })}
              </p>
            </div>

            <div className="flex flex-col gap-1.5">
              <label htmlFor="otp" className="text-sm font-medium text-foreground">
                {t("otp_hint")}
              </label>
              <Input
                ref={otpInputRef}
                id="otp"
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                placeholder="000000"
                value={otp}
                onChange={(e) => {
                  setError(null);
                  setOtp(e.target.value.replace(/\D/g, "").slice(0, 6));
                }}
                className="text-center text-2xl tracking-[0.5em]"
                maxLength={6}
                required
              />
            </div>

            {error && (
              <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
                {error}
              </p>
            )}

            <Button type="submit" disabled={loading || otp.length !== 6} className="w-full">
              {loading ? "…" : t("verify")}
            </Button>

            <div className="text-center">
              {countdown > 0 ? (
                <p className="text-sm text-muted-foreground">
                  {t("resend_countdown", { seconds: countdown })}
                </p>
              ) : (
                <button
                  type="button"
                  onClick={handleResend}
                  disabled={loading}
                  className="text-sm font-medium text-primary underline-offset-4 hover:underline disabled:opacity-50"
                >
                  {t("resend")}
                </button>
              )}
            </div>

            <button
              type="button"
              onClick={() => {
                setStep("phone");
                setOtp("");
                setError(null);
                if (countdownRef.current) clearInterval(countdownRef.current);
                setCountdown(0);
              }}
              className="text-center text-sm text-muted-foreground underline-offset-4 hover:underline"
            >
              Numarayı değiştir
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
