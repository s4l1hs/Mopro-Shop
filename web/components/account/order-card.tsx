"use client";

import Image from "next/image";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { formatPrice } from "@/lib/money";
import type { Order } from "@/lib/types/account";
import { OrderStatusPill } from "./order-status-pill";

interface OrderCardProps {
  order: Order;
}

export function OrderCard({ order }: OrderCardProps) {
  const date = new Date(order.created_at).toLocaleDateString("tr-TR", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });

  const visibleItems = order.items.slice(0, 4);
  const extraCount = order.items.length - visibleItems.length;

  const secondaryAction = () => {
    if (order.status === "delivered") return { label: "İade et", href: `/account/orders/${order.id}/return` };
    if (order.status === "shipped") return { label: "Kargoyu takip et", href: order.tracking_number ? `https://tracking.mopro.com/${order.tracking_number}` : "#" };
    if (order.status === "cancelled") return { label: "Tekrar sipariş ver", href: `/account/orders/${order.id}/reorder` };
    return null;
  };

  const secondary = secondaryAction();

  return (
    <div className="rounded-lg border border-border overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 bg-muted/40 border-b border-border">
        <span className="text-xs font-mono text-muted-foreground">
          Sipariş No: #{order.order_number}
        </span>
        <OrderStatusPill status={order.status} />
      </div>

      <div className="px-4 py-3 space-y-3">
        {/* Date */}
        <p className="text-xs text-muted-foreground">{date}</p>

        {/* Item thumbnails */}
        <div className="flex items-center gap-2">
          {visibleItems.map((item) => (
            <div
              key={item.id}
              className="relative h-12 w-12 rounded-md overflow-hidden bg-muted shrink-0"
            >
              <Image
                src={item.cover_image_url}
                alt={item.title}
                fill
                className="object-cover"
              />
            </div>
          ))}
          {extraCount > 0 && (
            <div className="h-12 w-12 rounded-md bg-muted flex items-center justify-center shrink-0">
              <span className="text-xs text-muted-foreground font-medium">+{extraCount}</span>
            </div>
          )}
        </div>

        {/* Totals */}
        <div className="flex items-center justify-between text-sm">
          <span className="font-semibold text-foreground">
            {formatPrice(order.total_minor, order.currency)}
          </span>
          {order.monthly_cashback_minor > 0 && (
            <span className="text-xs text-primary">
              Aylık {formatPrice(order.monthly_cashback_minor, "TRY_COIN")} cashback
            </span>
          )}
        </div>

        {/* Actions */}
        <div className="flex gap-2 pt-1">
          <Button size="sm" variant="outline" asChild>
            <Link href={`/account/orders/${order.id}`}>Detayları gör</Link>
          </Button>
          {secondary && (
            <Button size="sm" variant="ghost" asChild>
              <Link href={secondary.href}>{secondary.label}</Link>
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
