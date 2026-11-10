import { Suspense } from "react";
import { Sidebar } from "@/components/shell/Sidebar";
import { UserBox } from "@/components/shell/UserBox";
import { requireAccounts } from "@/lib/auth/session";

export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <Suspense fallback={<p className="p-6 text-sm text-muted-foreground">Loading…</p>}>
      <AccountsShell>{children}</AccountsShell>
    </Suspense>
  );
}

/** The session is read per request, so the shell streams in behind the Suspense boundary. */
async function AccountsShell({ children }: { children: React.ReactNode }) {
  const { email, membership } = await requireAccounts();
  return (
    <div className="flex min-h-full flex-1 flex-col md:flex-row">
      <Sidebar companyName={membership.companyName} footer={<UserBox email={email} role={membership.role} />} />
      <main className="min-w-0 flex-1 p-4 md:p-6">{children}</main>
    </div>
  );
}
