import { Suspense } from "react";
import { redirect } from "next/navigation";
import { UserBox } from "@/components/shell/UserBox";
import { ACCOUNTS_ROLES, getAppContext } from "@/lib/auth/session";

export default function NoAccessPage() {
  return (
    <main className="flex flex-1 items-center justify-center p-4">
      <div className="w-full max-w-sm space-y-3 rounded-xl border p-6">
        <h1 className="text-lg font-semibold">No access</h1>
        <Suspense>
          <Body />
        </Suspense>
      </div>
    </main>
  );
}

async function Body() {
  const { email, membership } = await getAppContext();
  if (membership && ACCOUNTS_ROLES.includes(membership.role)) redirect("/");
  return (
    <>
      {membership ? (
        <p className="text-sm">
          Your ERP role is <span className="font-medium capitalize">{membership.role}</span>. The screens for this role
          are not ready yet.
        </p>
      ) : (
        <p className="text-sm">
          You are signed in, but this login has no access to Round Island. Access follows Cloud Kitchen → Staff: ask an
          admin there to approve you with the Cloud Kitchen workspace.
        </p>
      )}
      <UserBox email={email} role={membership?.role} />
    </>
  );
}
