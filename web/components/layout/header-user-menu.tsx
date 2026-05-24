"use client";

import { LogOut, MapPin, Package, User, Wallet } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useSession } from "@/lib/auth/use-session";
import { cn } from "@/lib/utils";

interface HeaderUserMenuProps {
  className?: string;
}

export function HeaderUserMenu({ className }: HeaderUserMenuProps) {
  const { isAuthenticated } = useSession();
  const router = useRouter();

  if (!isAuthenticated) {
    return (
      <Button variant="ghost" size="sm" asChild className={cn("gap-1.5", className)}>
        <Link href="/login">
          <User className="h-4 w-4" />
          <span className="hidden xl:inline">Giriş Yap</span>
        </Link>
      </Button>
    );
  }

  const handleLogout = async () => {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push("/login");
    router.refresh();
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="sm" className={cn("gap-1.5", className)}>
          <User className="h-4 w-4" />
          <span className="hidden xl:inline">Hesabım</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48">
        <DropdownMenuItem asChild>
          <Link href="/account" className="flex items-center gap-2 cursor-pointer">
            <User className="h-4 w-4" />
            Hesabım
          </Link>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <Link href="/account/orders" className="flex items-center gap-2 cursor-pointer">
            <Package className="h-4 w-4" />
            Siparişlerim
          </Link>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <Link href="/account/addresses" className="flex items-center gap-2 cursor-pointer">
            <MapPin className="h-4 w-4" />
            Adreslerim
          </Link>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <Link href="/account/wallet" className="flex items-center gap-2 cursor-pointer">
            <Wallet className="h-4 w-4" />
            Cüzdanım
          </Link>
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onClick={handleLogout}
          className="text-destructive focus:text-destructive cursor-pointer"
        >
          <LogOut className="h-4 w-4 mr-2" />
          Çıkış Yap
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
