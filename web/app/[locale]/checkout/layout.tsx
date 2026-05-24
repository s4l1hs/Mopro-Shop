import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import type { ReactNode } from "react";

interface Props {
  children: ReactNode;
}

export default async function CheckoutLayout({ children }: Props) {
  const cookieStore = await cookies();
  const session = cookieStore.get("mopro_s");

  if (!session?.value) {
    redirect("/login?next=/checkout");
  }

  return <>{children}</>;
}
