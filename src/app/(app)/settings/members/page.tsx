import { requireOwner } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

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
          Access is managed in Cloud Kitchen → Staff and follows it automatically: admin → owner, accountant →
          accountant, supply chain → purchasing, sales → cashier, manager / executive → viewer. Kitchen and dispatch
          staff have no ERP access.
        </p>
      </div>
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b text-left text-muted-foreground">
            <th className="py-2 pr-4 font-medium">E-mail</th>
            <th className="py-2 font-medium">ERP role</th>
          </tr>
        </thead>
        <tbody>
          {members.map((m) => (
            <tr key={m.user_id} className="border-b">
              <td className="py-2 pr-4">
                {m.email}
                {m.user_id === userId && <span className="ml-1 text-muted-foreground">(you)</span>}
              </td>
              <td className="py-2 capitalize">{m.role}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
