import { signOut } from "@/lib/auth/actions";
import { Button } from "@/components/ui/button";

export function UserBox({ email, role }: { email: string; role?: string }) {
  return (
    <form action={signOut} className="space-y-1 px-4 py-3 text-xs text-muted-foreground">
      <div className="truncate" title={email}>
        {email}
        {role && <span className="ml-1 capitalize">· {role}</span>}
      </div>
      <Button type="submit" variant="outline" size="sm">
        Sign out
      </Button>
    </form>
  );
}
