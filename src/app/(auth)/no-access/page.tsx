import { Suspense } from "react";
import { redirect } from "next/navigation";
import { UserBox } from "@/components/shell/UserBox";
import { getAppContext } from "@/lib/auth/session";

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
  if (membership) redirect("/");
  return (
    <>
      <p className="text-sm">
        You are signed in, but this login has not been added to Round Island. Ask the owner to add you under
        Settings → Members.
      </p>
      <UserBox email={email} />
    </>
  );
}
