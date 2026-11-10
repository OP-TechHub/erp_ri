"use client";

import { useActionState, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { addMember, removeMember, setMemberRole, type ActionResult } from "./actions";

const ROLES = [
  { value: "owner", label: "Owner" },
  { value: "accountant", label: "Accountant" },
  { value: "sales", label: "Sales" },
] as const;
const field = "rounded-md border bg-background px-2 py-1.5 text-sm";

export function AddMemberForm() {
  const router = useRouter();
  const [state, action, pending] = useActionState<ActionResult, FormData>(async (prev, form) => {
    const res = await addMember(prev, form);
    if (!res.error) router.refresh();
    return res;
  }, {});
  return (
    <form action={action} className="flex flex-wrap items-end gap-2">
      <label className="space-y-1 text-sm">
        <span className="block">E-mail of an existing login</span>
        <input name="email" type="email" required className={field + " w-72"} />
      </label>
      <label className="space-y-1 text-sm">
        <span className="block">Role</span>
        <select name="role" defaultValue="sales" className={field}>
          {ROLES.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}
            </option>
          ))}
        </select>
      </label>
      <Button type="submit" disabled={pending}>
        {pending ? "Adding…" : "Add member"}
      </Button>
      {state.error && <p className="w-full text-sm text-destructive">{state.error}</p>}
    </form>
  );
}

export function MemberRow({ userId, email, role, isSelf }: { userId: string; email: string; role: string; isSelf: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [value, setValue] = useState(role);

  const run = (fn: () => Promise<ActionResult>) =>
    start(async () => {
      const res = await fn();
      setError(res.error ?? null);
      if (res.error) setValue(role);
      router.refresh();
    });

  return (
    <tr className="border-b align-top">
      <td className="py-2 pr-4">
        {email}
        {isSelf && <span className="ml-1 text-muted-foreground">(you)</span>}
        {error && <div className="text-xs text-destructive">{error}</div>}
      </td>
      <td className="py-2 pr-4">
        <select
          value={value}
          disabled={pending}
          className={field}
          onChange={(e) => {
            setValue(e.target.value);
            run(() => setMemberRole(userId, e.target.value));
          }}
        >
          {ROLES.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}
            </option>
          ))}
        </select>
      </td>
      <td className="py-2">
        <Button
          variant="destructive"
          size="sm"
          disabled={pending}
          onClick={() => {
            if (confirm(`Remove ${email} from this company? Their login is kept; they just lose access here.`))
              run(() => removeMember(userId));
          }}
        >
          Remove
        </Button>
      </td>
    </tr>
  );
}
