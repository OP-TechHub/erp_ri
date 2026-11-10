"use server";

import { z } from "zod";
import { requireOwner } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export type ActionResult = { error?: string };

const role = z.enum(["owner", "accountant", "sales"]);

/** Adds an existing login (Supabase → Authentication → Users) to the company, or changes its role. */
export async function addMember(_prev: ActionResult, form: FormData): Promise<ActionResult> {
  const parsed = z.object({ email: z.email(), role }).safeParse({ email: form.get("email"), role: form.get("role") });
  if (!parsed.success) return { error: "Enter a valid e-mail and choose a role." };
  const { membership } = await requireOwner();
  const supabase = await createClient();
  const { error } = await supabase.rpc("add_member_by_email", {
    cid: membership.companyId,
    p_email: parsed.data.email,
    p_role: parsed.data.role,
  });
  return error ? { error: error.message } : {};
}

export async function setMemberRole(userId: string, newRole: string): Promise<ActionResult> {
  const parsed = z.object({ userId: z.uuid(), role }).safeParse({ userId, role: newRole });
  if (!parsed.success) return { error: "Invalid role." };
  const { membership } = await requireOwner();
  const supabase = await createClient();
  const { error } = await supabase
    .from("company_members")
    .update({ role: parsed.data.role })
    .eq("company_id", membership.companyId)
    .eq("user_id", parsed.data.userId);
  return error ? { error: error.message } : {};
}

/** Removes access to this company only. The login itself is never deleted (it is shared with other apps). */
export async function removeMember(userId: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(userId);
  if (!parsed.success) return { error: "Invalid user." };
  const { membership } = await requireOwner();
  const supabase = await createClient();
  const { error } = await supabase
    .from("company_members")
    .delete()
    .eq("company_id", membership.companyId)
    .eq("user_id", parsed.data);
  return error ? { error: error.message } : {};
}
