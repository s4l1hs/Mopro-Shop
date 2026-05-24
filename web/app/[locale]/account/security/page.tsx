"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  useDeleteAccountMutation,
  useLoginEventsQuery,
  useRevokeAllSessionsMutation,
  useRevokeSessionMutation,
  useSessionsQuery,
} from "@/lib/account/queries";

function relativeTime(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins} dakika önce`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs} saat önce`;
  return `${Math.floor(hrs / 24)} gün önce`;
}

export default function SecurityPage() {
  const router = useRouter();
  const { data: sessions, isLoading: sessionsLoading } = useSessionsQuery();
  const { data: events, isLoading: eventsLoading } = useLoginEventsQuery();
  const revokeOne = useRevokeSessionMutation();
  const revokeAll = useRevokeAllSessionsMutation();
  const deleteAccount = useDeleteAccountMutation();

  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [confirmText, setConfirmText] = useState("");

  const handleRevokeAll = async () => {
    try {
      await revokeAll.mutateAsync();
      toast.success("Tüm diğer oturumlar kapatıldı");
    } catch {
      toast.error("İşlem başarısız");
    }
  };

  const handleDeleteAccount = async () => {
    if (confirmText !== "MOPRO") return;
    try {
      await deleteAccount.mutateAsync();
      toast.success("Hesabınız silindi");
      router.push("/");
    } catch {
      toast.error("Hesap silinemedi");
    }
  };

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-bold text-foreground">Güvenlik</h1>

      {/* Active sessions */}
      <section className="space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-foreground">Aktif Oturumlar</h2>
          <Button
            size="sm"
            variant="destructive"
            disabled={revokeAll.isPending}
            onClick={handleRevokeAll}
          >
            Tümünü kapat
          </Button>
        </div>

        {sessionsLoading ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-14 rounded-lg" />
            ))}
          </div>
        ) : !sessions || sessions.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aktif oturum bulunamadı.</p>
        ) : (
          <div className="divide-y divide-border rounded-lg border border-border overflow-hidden">
            {sessions.map((session) => (
              <div
                key={session.id}
                className="flex items-center justify-between px-4 py-3"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium text-foreground">
                      {session.device}
                    </p>
                    {session.is_current && (
                      <span className="text-xs px-2 py-0.5 rounded-full bg-primary/10 text-primary font-medium">
                        Bu cihaz
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {session.location} — {relativeTime(session.last_active_at)}
                  </p>
                </div>
                {!session.is_current && (
                  <button
                    type="button"
                    disabled={revokeOne.isPending}
                    onClick={() =>
                      revokeOne
                        .mutateAsync(session.id)
                        .then(() => toast.success("Oturum kapatıldı"))
                        .catch(() => toast.error("İşlem başarısız"))
                    }
                    className="text-xs text-destructive hover:underline underline-offset-2"
                  >
                    Oturumu kapat
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Login activity */}
      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-foreground">Giriş Geçmişi</h2>

        {eventsLoading ? (
          <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-12 rounded-lg" />
            ))}
          </div>
        ) : !events || events.length === 0 ? (
          <p className="text-sm text-muted-foreground">Giriş geçmişi bulunamadı.</p>
        ) : (
          <div className="divide-y divide-border rounded-lg border border-border overflow-hidden">
            {events.slice(0, 10).map((event) => (
              <div key={event.id} className="flex items-center justify-between px-4 py-3">
                <div>
                  <p className="text-sm text-foreground">{event.device}</p>
                  <p className="text-xs text-muted-foreground">
                    {event.location} — {event.ip}
                  </p>
                </div>
                <p className="text-xs text-muted-foreground">
                  {new Date(event.created_at).toLocaleDateString("tr-TR", {
                    day: "numeric",
                    month: "short",
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </p>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Account deletion */}
      <section className="rounded-lg border border-destructive bg-destructive/5 p-5 space-y-3">
        <h2 className="text-lg font-semibold text-destructive">Hesap Silme</h2>
        <p className="text-sm text-muted-foreground">
          Hesabınızı sildiğinizde tüm verileriniz, siparişleriniz ve cashback planlarınız
          kalıcı olarak silinir. Bu işlem geri alınamaz.
        </p>
        <Button
          variant="destructive"
          onClick={() => setDeleteDialogOpen(true)}
          className="bg-transparent border-destructive text-destructive hover:bg-destructive hover:text-destructive-foreground"
          style={{ border: "1px solid" }}
        >
          Hesabımı sil
        </Button>
      </section>

      {/* Delete confirm dialog */}
      <Dialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-destructive">Hesabı kalıcı sil</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Bu işlem geri alınamaz. Onaylamak için aşağıya{" "}
              <strong className="text-foreground">MOPRO</strong> yazın.
            </p>
            <Input
              value={confirmText}
              onChange={(e) => setConfirmText(e.target.value)}
              placeholder="MOPRO"
            />
            <div className="flex gap-2 justify-end">
              <Button variant="outline" onClick={() => setDeleteDialogOpen(false)}>
                İptal
              </Button>
              <Button
                variant="destructive"
                disabled={confirmText !== "MOPRO" || deleteAccount.isPending}
                onClick={handleDeleteAccount}
              >
                Hesabı sil
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
