import { Suspense } from "react";
import { redirect } from "next/navigation";
import { UserBox } from "@/components/shell/UserBox";
import { getAppContext } from "@/lib/auth/session";

export default function SalesLayout({ children }: LayoutProps<"/">) {
  return (
    <Suspense fallback={<p className="p-6 text-sm text-muted-foreground">Loading…</p>}>
      <SalesShell>{children}</SalesShell>
    </Suspense>
  );
}

/** Restricted screen for the "sales" role; accounts staff may open it too. */
async function SalesShell({ children }: { children: React.ReactNode }) {
  const { email, membership } = await getAppContext();
  if (!membership) redirect("/no-access");
  return (
    <div className="flex min-h-full flex-1 flex-col">
      <header className="flex items-center justify-between border-b px-4 py-2 print:hidden">
        <span className="font-semibold">{membership.companyName}</span>
        <UserBox email={email} role={membership.role} />
      </header>
      <main className="flex-1 p-4 md:p-6">{children}</main>
    </div>
  );
}
