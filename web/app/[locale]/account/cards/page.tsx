"use client";

import { MoreVertical, Plus } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import {
  useDeleteCardMutation,
  useSavedCardsQuery,
  useSetDefaultCardMutation,
} from "@/lib/account/queries";
import type { SavedCard } from "@/lib/types/account";
import { cn } from "@/lib/utils";

const BRAND_LABELS: Record<SavedCard["brand"], string> = {
  visa: "VISA",
  mastercard: "MC",
  troy: "TROY",
  unknown: "",
};

function SavedCardItem({ card }: { card: SavedCard }) {
  const deleteMutation = useDeleteCardMutation();
  const defaultMutation = useSetDefaultCardMutation();

  return (
    <div
      className={cn(
        "relative rounded-xl p-5 space-y-4 transition-colors",
        card.is_default
          ? "bg-primary text-primary-foreground"
          : "bg-card border border-border",
      )}
    >
      {/* Brand */}
      <div className="flex justify-between items-start">
        <span
          className={cn(
            "text-xs font-bold tracking-widest",
            card.is_default ? "text-primary-foreground/80" : "text-muted-foreground",
          )}
        >
          {BRAND_LABELS[card.brand]}
        </span>
        {card.is_default && (
          <span className="text-xs px-2 py-0.5 rounded-full bg-white/20 text-white font-medium">
            Varsayılan
          </span>
        )}
      </div>

      {/* PAN */}
      <p
        className={cn(
          "text-xl font-mono tracking-widest",
          card.is_default ? "text-white" : "text-foreground",
        )}
      >
        •••• •••• •••• {card.last_four}
      </p>

      {/* Footer */}
      <div className="flex justify-between items-end">
        <div>
          <p
            className={cn(
              "text-xs",
              card.is_default ? "text-white/70" : "text-muted-foreground",
            )}
          >
            Kart sahibi
          </p>
          <p
            className={cn(
              "text-sm font-medium",
              card.is_default ? "text-white" : "text-foreground",
            )}
          >
            {card.holder_name}
          </p>
        </div>
        <div className="text-right">
          <p
            className={cn(
              "text-xs",
              card.is_default ? "text-white/70" : "text-muted-foreground",
            )}
          >
            Son kullanma
          </p>
          <p
            className={cn(
              "text-sm font-medium",
              card.is_default ? "text-white" : "text-foreground",
            )}
          >
            {card.expiry}
          </p>
        </div>
      </div>

      {/* 3-dot menu */}
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label="Kart işlemleri"
            className={cn(
              "absolute top-3 right-3 p-1.5 rounded-md transition-colors",
              card.is_default
                ? "text-white/70 hover:text-white hover:bg-white/10"
                : "text-muted-foreground hover:text-foreground hover:bg-accent",
            )}
          >
            <MoreVertical className="h-4 w-4" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {!card.is_default && (
            <DropdownMenuItem
              onClick={() =>
                defaultMutation
                  .mutateAsync(card.id)
                  .then(() => toast.success("Varsayılan kart güncellendi"))
                  .catch(() => toast.error("İşlem başarısız"))
              }
            >
              Varsayılan yap
            </DropdownMenuItem>
          )}
          <DropdownMenuItem
            className="text-destructive focus:text-destructive"
            onClick={() =>
              deleteMutation
                .mutateAsync(card.id)
                .then(() => toast.success("Kart silindi"))
                .catch(() => toast.error("Silinemedi"))
            }
          >
            Sil
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

export default function CardsPage() {
  const { data: cards, isLoading } = useSavedCardsQuery();

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-foreground">Kayıtlı Kartlarım</h1>
        <Button
          onClick={() =>
            toast("Yeni kart eklemek için ödeme sırasında 'Kartımı kaydet' seçeneğini işaretle.")
          }
        >
          <Plus className="h-4 w-4 mr-1.5" />
          Yeni kart ekle
        </Button>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {Array.from({ length: 2 }).map((_, i) => (
            <Skeleton key={i} className="h-44 rounded-xl" />
          ))}
        </div>
      ) : !cards || cards.length === 0 ? (
        <div className="py-16 text-center space-y-3">
          <p className="text-muted-foreground">Kayıtlı kart yok.</p>
          <p className="text-sm text-muted-foreground">
            Ödeme sırasında &ldquo;Kartımı kaydet&rdquo; seçeneğini işaretleyerek
            kartını ekleyebilirsin.
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {cards.map((card) => (
            <SavedCardItem key={card.id} card={card} />
          ))}
        </div>
      )}
    </div>
  );
}
