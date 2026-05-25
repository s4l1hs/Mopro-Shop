import { CheckCircle2, XCircle, Clock } from "lucide-react";
import Link from "next/link";
import { cookies } from "next/headers";
import { Button } from "@/components/ui/button";

const API_BASE =
  process.env.API_BASE_URL_INTERNAL ??
  process.env.API_BASE_URL ??
  "http://localhost:8080";

interface OrderRecord {
  id: number;
  status: string;
}

async function fetchOrder(
  orderId: string,
  accessToken: string,
): Promise<OrderRecord | null> {
  try {
    const res = await fetch(`${API_BASE}/orders/${orderId}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
      cache: "no-store",
    });
    if (!res.ok) return null;
    return (await res.json()) as OrderRecord;
  } catch {
    return null;
  }
}

interface Props {
  params: Promise<{ id: string; locale: string }>;
  searchParams: Promise<Record<string, string>>;
}

export default async function OrderConfirmationPage({ params, searchParams }: Props) {
  const { id } = await params;
  const sp = await searchParams;
  const urlStatus = sp["status"];

  // Verify actual order status from DB — do not trust URL claim alone.
  const cookieStore = await cookies();
  const accessToken = cookieStore.get("mopro_at")?.value ?? "";
  const order = accessToken ? await fetchOrder(id, accessToken) : null;

  // Determine truth: DB wins over URL claim in both directions.
  const dbStatus = order?.status;
  const isSuccess =
    dbStatus === "paid" ||
    dbStatus === "shipped" ||
    dbStatus === "delivered" ||
    (dbStatus == null && urlStatus === "success");
  const isPending = dbStatus === "pending_payment";

  return (
    <div className="mx-auto max-w-lg px-4 sm:px-6 py-16 text-center">
      {isSuccess ? (
        <>
          <CheckCircle2 className="mx-auto h-16 w-16 text-green-500 mb-6" />
          <h1 className="text-2xl font-bold text-foreground mb-2">
            Siparişiniz alındı!
          </h1>
          <p className="text-muted-foreground mb-1">
            Sipariş numaranız:{" "}
            <span className="font-mono font-medium text-foreground">{id}</span>
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
              <Link href="/account/orders">Siparişlerim</Link>
            </Button>
          </div>
        </>
      ) : isPending ? (
        <>
          <Clock className="mx-auto h-16 w-16 text-yellow-500 mb-6" />
          <h1 className="text-2xl font-bold text-foreground mb-2">
            Ödeme bekleniyor
          </h1>
          <p className="text-muted-foreground mb-8">
            Siparişiniz oluşturuldu ancak ödeme henüz onaylanmadı. Birkaç dakika
            içinde durum güncellenecektir.
          </p>
          <Button asChild>
            <Link href="/account/orders">Siparişlerime Dön</Link>
          </Button>
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
