import { requireOwner } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { AddMemberForm, MemberRow } from "./MemberForms";

type Member = { user_id: string; email: string; role: string };

export default async function MembersPage() {
  const { userId, membership } = await requireOwner();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("member_list", { cid: membership.companyId });
  if (error) throw new Error(error.message);
  const members = (data ?? []) as Member[];

  return (
    <div className="max-w-3xl space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Members</h1>
        <p className="text-sm text-muted-foreground">
          Owner: everything. Accountant: all accounting screens. Sales: only the invoicing screen, and only their
          own invoices. To add someone, first create their login in Supabase (Authentication → Users), then add the
          e-mail here.
        </p>
      </div>
      <AddMemberForm />
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b text-left text-muted-foreground">
            <th className="py-2 pr-4 font-medium">E-mail</th>
            <th className="py-2 pr-4 font-medium">Role</th>
            <th className="py-2 font-medium" />
          </tr>
        </thead>
        <tbody>
          {members.map((m) => (
            <MemberRow key={m.user_id + m.role} userId={m.user_id} email={m.email} role={m.role} isSelf={m.user_id === userId} />
          ))}
        </tbody>
      </table>
    </div>
  );
}
