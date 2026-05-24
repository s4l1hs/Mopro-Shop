import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import {
  AccountMobileTabStrip,
  AccountSidebar,
} from "@/components/account/sidebar";

interface Props {
  children: ReactNode;
}

export default async function AccountLayout({ children }: Props) {
  const cookieStore = await cookies();
  const session = cookieStore.get("mopro_s");

  if (!session?.value) {
    redirect("/login?next=/account");
  }

  return (
    <>
      {/* Mobile tab strip — sticky just below the main header (h-14) */}
      <div className="lg:hidden sticky top-14 z-30 bg-background/95 backdrop-blur-sm border-b border-border">
        <AccountMobileTabStrip />
      </div>

      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6 md:py-8">
        <div className="lg:grid lg:grid-cols-[240px_1fr] gap-6">
          {/* Desktop sidebar */}
          <aside className="hidden lg:block">
            <div className="sticky top-32">
              <AccountSidebar />
            </div>
          </aside>

          {/* Main content */}
          <main className="min-w-0">{children}</main>
        </div>
      </div>
    </>
  );
}
