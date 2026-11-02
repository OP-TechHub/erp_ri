import { Sidebar } from "@/components/shell/Sidebar";

export default function AppLayout({ children }: LayoutProps<"/">) {
  // Company name comes from the database once Phase 1 is wired up.
  return (
    <div className="flex min-h-full flex-1 flex-col md:flex-row">
      <Sidebar companyName="Round Island (Pvt) Ltd" />
      <main className="flex-1 p-4 md:p-6">{children}</main>
    </div>
  );
}
