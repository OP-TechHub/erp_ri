import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type Role = "owner" | "accountant" | "sales";
export type Membership = { companyId: string; companyName: string; role: Role };
export type AppContext = { userId: string; email: string; membership: Membership | null };

/**
 * The signed-in user and their company, read once per request (Data Access Layer).
 * Logins are shared with other apps on the same Supabase project, so a valid login
 * without a company_members row is normal: membership is then null.
 * Access to data is enforced by RLS; this only decides what to show.
 */
export const getAppContext = cache(async (): Promise<AppContext> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data, error } = await supabase.rpc("my_companies");
  if (error) throw new Error("Could not load your company: " + error.message);
  const rows = (data ?? []) as { company_id: string; name: string; role: Role }[];
  const first = rows[0];
  return {
    userId: user.id,
    email: user.email ?? "",
    membership: first ? { companyId: first.company_id, companyName: first.name, role: first.role } : null,
  };
});

/** For pages only accounts staff may open; sales staff go to their invoicing screen. */
export async function requireAccounts(): Promise<AppContext & { membership: Membership }> {
  const ctx = await getAppContext();
  if (!ctx.membership) redirect("/no-access");
  if (ctx.membership.role === "sales") redirect("/invoicing");
  return ctx as AppContext & { membership: Membership };
}

export async function requireOwner(): Promise<AppContext & { membership: Membership }> {
  const ctx = await requireAccounts();
  if (ctx.membership.role !== "owner") redirect("/settings");
  return ctx;
}
