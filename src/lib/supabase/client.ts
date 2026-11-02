import { createBrowserClient } from "@supabase/ssr";
import { env } from "@/lib/env";
import { DB_SCHEMA } from "./schema";

export function createClient() {
  return createBrowserClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    db: { schema: DB_SCHEMA },
  });
}
