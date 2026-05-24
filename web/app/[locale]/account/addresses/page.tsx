"use client";

import { MoreVertical, Plus } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import {
  StepAddress,
  type AddressFormValues,
} from "@/components/checkout/step-address";
import {
  useAddressesQuery,
  useCreateAddressMutation,
  useDeleteAddressMutation,
  useSetDefaultAddressMutation,
  useUpdateAddressMutation,
} from "@/lib/account/queries";
import type { Address } from "@/lib/types/account";
import { cn } from "@/lib/utils";

type DialogMode = "create" | "edit";

interface DialogState {
  mode: DialogMode;
  address?: Address;
}

function addressToFormValues(a: Address): AddressFormValues {
  return {
    fullName: a.full_name,
    phone: a.phone,
    city: a.city,
    district: a.district,
    addressLine: a.address_line,
    postalCode: a.postal_code ?? "",
  };
}

function AddressCard({
  address,
  onEdit,
  onDelete,
  onSetDefault,
}: {
  address: Address;
  onEdit: (a: Address) => void;
  onDelete: (id: string) => void;
  onSetDefault: (id: string) => void;
}) {
  return (
    <div
      className={cn(
        "rounded-lg border p-4 space-y-2 relative",
        address.is_default ? "border-primary bg-primary/5" : "border-border",
      )}
    >
      {/* Badges */}
      <div className="flex items-center gap-2 flex-wrap">
        {address.label && (
          <span className="text-xs px-2 py-0.5 rounded-full bg-muted text-muted-foreground font-medium">
            {address.label}
          </span>
        )}
        {address.is_default && (
          <span className="text-xs px-2 py-0.5 rounded-full bg-primary/15 text-primary font-medium">
            Varsayılan
          </span>
        )}
      </div>

      {/* Address content */}
      <div className="text-sm space-y-0.5">
        <p className="font-medium text-foreground">{address.full_name}</p>
        <p className="text-muted-foreground">
          {address.address_line}, {address.district} / {address.city}
          {address.postal_code ? ` ${address.postal_code}` : ""}
        </p>
        <p className="text-muted-foreground">
          •••• {address.phone.slice(-4)}
        </p>
      </div>

      {/* 3-dot menu */}
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label="Adres işlemleri"
            className="absolute top-3 right-3 p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
          >
            <MoreVertical className="h-4 w-4" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={() => onEdit(address)}>Düzenle</DropdownMenuItem>
          {!address.is_default && (
            <DropdownMenuItem onClick={() => onSetDefault(address.id)}>
              Varsayılan yap
            </DropdownMenuItem>
          )}
          <DropdownMenuItem
            className="text-destructive focus:text-destructive"
            onClick={() => onDelete(address.id)}
          >
            Sil
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

export default function AddressesPage() {
  const { data: addresses, isLoading } = useAddressesQuery();
  const createMutation = useCreateAddressMutation();
  const updateMutation = useUpdateAddressMutation();
  const deleteMutation = useDeleteAddressMutation();
  const defaultMutation = useSetDefaultAddressMutation();

  const [dialog, setDialog] = useState<DialogState | null>(null);
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null);

  const handleSave = async (values: AddressFormValues) => {
    const payload = {
      full_name: values.fullName,
      phone: values.phone,
      city: values.city,
      district: values.district,
      address_line: values.addressLine,
      ...(values.postalCode ? { postal_code: values.postalCode } : {}),
    };

    try {
      if (dialog?.mode === "edit" && dialog.address) {
        await updateMutation.mutateAsync({ id: dialog.address.id, ...payload });
        toast.success("Adres güncellendi");
      } else {
        await createMutation.mutateAsync({
          ...payload,
          is_default: (addresses?.length ?? 0) === 0,
        } as Parameters<typeof createMutation.mutateAsync>[0]);
        toast.success("Adres eklendi");
      }
      setDialog(null);
    } catch {
      toast.error("İşlem başarısız oldu");
    }
  };

  const handleDelete = async (id: string) => {
    try {
      await deleteMutation.mutateAsync(id);
      toast.success("Adres silindi");
      setDeleteConfirmId(null);
    } catch {
      toast.error("Silinemedi");
    }
  };

  const handleSetDefault = async (id: string) => {
    try {
      await defaultMutation.mutateAsync(id);
      toast.success("Varsayılan adres güncellendi");
    } catch {
      toast.error("İşlem başarısız");
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-foreground">Adreslerim</h1>
        <Button onClick={() => setDialog({ mode: "create" })}>
          <Plus className="h-4 w-4 mr-1.5" />
          Yeni adres ekle
        </Button>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-32 rounded-lg" />
          ))}
        </div>
      ) : !addresses || addresses.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-muted-foreground mb-4">Henüz adres eklenmemiş.</p>
          <Button onClick={() => setDialog({ mode: "create" })}>
            <Plus className="h-4 w-4 mr-1.5" />
            İlk adresini ekle
          </Button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {addresses.map((address) => (
            <AddressCard
              key={address.id}
              address={address}
              onEdit={(a) => setDialog({ mode: "edit", address: a })}
              onDelete={(id) => setDeleteConfirmId(id)}
              onSetDefault={handleSetDefault}
            />
          ))}
        </div>
      )}

      {/* Add/Edit dialog */}
      <Dialog open={dialog !== null} onOpenChange={(open) => !open && setDialog(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>
              {dialog?.mode === "edit" ? "Adresi düzenle" : "Yeni adres ekle"}
            </DialogTitle>
          </DialogHeader>
          {dialog !== null && (
            <StepAddress
              {...(dialog.address !== undefined && {
                defaultValues: addressToFormValues(dialog.address),
              })}
              onNext={handleSave}
              submitLabel="Kaydet"
              onCancel={() => setDialog(null)}
            />
          )}
        </DialogContent>
      </Dialog>

      {/* Delete confirm dialog */}
      <Dialog
        open={deleteConfirmId !== null}
        onOpenChange={(open) => !open && setDeleteConfirmId(null)}
      >
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Adresi sil</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            Bu adresi silmek istediğinize emin misiniz? Bu işlem geri alınamaz.
          </p>
          <div className="flex gap-2 justify-end pt-2">
            <Button variant="outline" onClick={() => setDeleteConfirmId(null)}>
              İptal
            </Button>
            <Button
              variant="destructive"
              disabled={deleteMutation.isPending}
              onClick={() => deleteConfirmId && handleDelete(deleteConfirmId)}
            >
              Sil
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
