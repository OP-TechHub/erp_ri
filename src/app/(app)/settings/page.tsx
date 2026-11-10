import Link from "next/link";
import { PagePlaceholder } from "@/components/shell/PagePlaceholder";

export default function Page() {
  return (
    <div className="space-y-4">
      <PagePlaceholder title="Settings" phase={2} />
      <Link href="/settings/members" className="text-sm underline">
        Members (owner only)
      </Link>
    </div>
  );
}
