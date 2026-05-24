"use client";

import { Download, HelpCircle } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { useParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { CashbackSchedule } from "@/components/account/cashback-schedule";
import { OrderStatusPill } from "@/components/account/order-status-pill";
import { OrderTimeline } from "@/components/account/order-timeline";
import { formatPrice } from "@/lib/money";
import { useOrderDetailQuery } from "@/lib/account/queries";
import { toast } from "sonner";

function OrderDetailContent() {
  const params = useParams();
  const orderId = params["id"] as string;
  const { data: order, isLoading, isError } = useOrderDetailQuery(orderId);

  if (isLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-20 rounded-lg" />
        <Skeleton className="h-48 rounded-lg" />
        <Skeleton className="h-64 rounded-lg" />
      </div>
    );
  }

  if (isError || !order) {
    return (
      <div className="py-16 text-center">
        <p className="text-muted-foreground">Sipariş bulunamadı.</p>
        <Link href="/account/orders" className="text-sm text-primary hover:underline mt-2 inline-block">
          ← Siparişlerime dön
        </Link>
      </div>
    );
  }

  const date = new Date(order.created_at).toLocaleDateString("tr-TR", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });

  const shippingMinor = order.shipping_minor ?? 0;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <Link
          href="/account/orders"
          className="text-sm text-muted-foreground hover:text-foreground inline-flex items-center gap-1 mb-4"
        >
          ← Siparişlerim
        </Link>
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-xl font-bold text-foreground">
              Sipariş #{order.order_number}
            </h1>
            <p className="text-sm text-muted-foreground mt-0.5">{date}</p>
          </div>
          <div className="flex items-center gap-2">
            <OrderStatusPill status={order.status} />
            <Button
              size="sm"
              variant="outline"
              onClick={() => toast("Fatura indirme yakında aktif olacak.")}
            >
              <Download className="h-4 w-4 mr-1.5" />
              Fatura
            </Button>
            <Button size="sm" variant="ghost" asChild>
              <Link href="/account/support">
                <HelpCircle className="h-4 w-4 mr-1.5" />
                Yardım
              </Link>
            </Button>
          </div>
        </div>
      </div>

      <div className="grid lg:grid-cols-[1fr_340px] gap-6">
        <div className="space-y-6">
          {/* Timeline */}
          <section className="rounded-lg border border-border p-5">
            <h2 className="text-sm font-semibold text-foreground mb-4">Sipariş Durumu</h2>
            <OrderTimeline status={order.status} />
          </section>

          {/* Items */}
          <section className="rounded-lg border border-border overflow-hidden">
            <h2 className="text-sm font-semibold text-foreground px-4 py-3 border-b border-border">
              Ürünler ({order.items.length})
            </h2>
            <div className="divide-y divide-border">
              {order.items.map((item) => {
                const itemHref = item.product_slug
                  ? `/products/${item.product_id}/${item.product_slug}`
                  : `/products/${item.product_id}`;
                return (
                  <div key={item.id} className="flex items-center gap-4 px-4 py-3">
                    <Link href={itemHref} className="shrink-0">
                      <div className="relative h-16 w-16 rounded-md overflow-hidden bg-muted">
                        <Image
                          src={item.cover_image_url}
                          alt={item.title}
                          fill
                          className="object-cover"
                        />
                      </div>
                    </Link>
                    <div className="flex-1 min-w-0">
                      {item.brand && (
                        <p className="text-xs text-muted-foreground">{item.brand}</p>
                      )}
                      <Link href={itemHref}>
                        <p className="text-sm font-medium text-foreground line-clamp-2">
                          {item.title}
                        </p>
                      </Link>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {item.quantity} adet ×{" "}
                        {formatPrice(item.unit_price_minor, item.currency)}
                      </p>
                    </div>
                    <div className="text-right shrink-0">
                      <p className="text-sm font-semibold text-foreground">
                        {formatPrice(item.unit_price_minor * item.quantity, item.currency)}
                      </p>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-xs h-7 mt-1"
                        asChild
                      >
                        <Link href={itemHref}>Tekrar al</Link>
                      </Button>
                    </div>
                  </div>
                );
              })}
            </div>
          </section>

          {/* Delivery address */}
          {order.delivery_address && (
            <section className="rounded-lg border border-border p-4">
              <h2 className="text-sm font-semibold text-foreground mb-3">
                Teslimat Adresi
              </h2>
              <div className="text-sm text-muted-foreground space-y-0.5">
                <p className="font-medium text-foreground">
                  {order.delivery_address.full_name}
                </p>
                <p>{order.delivery_address.phone}</p>
                <p>
                  {order.delivery_address.address_line},{" "}
                  {order.delivery_address.district} / {order.delivery_address.city}
                  {order.delivery_address.postal_code
                    ? ` ${order.delivery_address.postal_code}`
                    : ""}
                </p>
              </div>
            </section>
          )}
        </div>

        <div className="space-y-6">
          {/* Payment summary */}
          <section className="rounded-lg border border-border p-4 space-y-3">
            <h2 className="text-sm font-semibold text-foreground">Ödeme</h2>
            <div className="space-y-1.5 text-sm">
              <div className="flex justify-between text-muted-foreground">
                <span>Ara toplam</span>
                <span>
                  {formatPrice(order.total_minor - shippingMinor, order.currency)}
                </span>
              </div>
              <div className="flex justify-between text-muted-foreground">
                <span>Kargo</span>
                <span>{shippingMinor === 0 ? "Ücretsiz" : formatPrice(shippingMinor, order.currency)}</span>
              </div>
              <Separator />
              <div className="flex justify-between font-semibold text-foreground">
                <span>Toplam</span>
                <span>{formatPrice(order.total_minor, order.currency)}</span>
              </div>
            </div>
            {order.payment_last_four && (
              <p className="text-xs text-muted-foreground border-t border-border pt-2">
                {order.payment_holder_name} — •••• {order.payment_last_four}
              </p>
            )}
          </section>

          {/* Cashback schedule */}
          {order.cashback_schedule && order.cashback_schedule.length > 0 && (
            <section className="rounded-lg border border-border p-4">
              <CashbackSchedule
                schedule={order.cashback_schedule}
                monthlyAmountMinor={order.monthly_cashback_minor}
                planStatus={order.cashback_plan_status ?? "active"}
              />
            </section>
          )}
        </div>
      </div>
    </div>
  );
}

export default function OrderDetailPage() {
  return (
    <Suspense fallback={<div className="space-y-6"><Skeleton className="h-20 rounded-lg"/><Skeleton className="h-48 rounded-lg"/></div>}>
      <OrderDetailContent />
    </Suspense>
  );
}
