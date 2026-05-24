"use client";

import { CheckCircle2, XCircle } from "lucide-react";
import Link from "next/link";
import { Suspense } from "react";
import { useParams, useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";

function OrderConfirmationContent() {
  const params = useParams();
  const searchParams = useSearchParams();
  const orderId = params["id"] as string;
  const status = searchParams.get("status");
  const success = status === "success";

  return (
    <div className="mx-auto max-w-lg px-4 sm:px-6 py-16 text-center">
      {success ? (
        <>
          <CheckCircle2 className="mx-auto h-16 w-16 text-success mb-6" />
          <h1 className="text-2xl font-bold text-foreground mb-2">
            Siparişiniz alındı!
          </h1>
          <p className="text-muted-foreground mb-1">
            Sipariş numaranız:{" "}
            <span className="font-mono font-medium text-foreground">{orderId}</span>
          </p>
          <p className="text-sm text-muted-foreground mb-8">
            Kargoya verildikten 3 iş günü sonra cashback planınız aktif olur ve
            aylık Mopro Coin hesabınıza yansır.
          </p>
          <div className="flex flex-col sm:flex-row gap-3 justify-center">
            <Button asChild>
              <Link href="/">Ana sayfaya dön</Link>
            </Button>
            <Button variant="outline" asChild>
              <Link href="/account">Siparişlerim</Link>
            </Button>
          </div>
        </>
      ) : (
        <>
          <XCircle className="mx-auto h-16 w-16 text-destructive mb-6" />
          <h1 className="text-2xl font-bold text-foreground mb-2">
            Ödeme başarısız
          </h1>
          <p className="text-muted-foreground mb-8">
            Siparişiniz tamamlanamadı. Lütfen kart bilgilerinizi kontrol edip
            tekrar deneyin.
          </p>
          <div className="flex flex-col sm:flex-row gap-3 justify-center">
            <Button asChild>
              <Link href="/checkout">Tekrar dene</Link>
            </Button>
            <Button variant="outline" asChild>
              <Link href="/cart">Sepete dön</Link>
            </Button>
          </div>
        </>
      )}
    </div>
  );
}

export default function OrderConfirmationPage() {
  return (
    <Suspense fallback={null}>
      <OrderConfirmationContent />
    </Suspense>
  );
}
