import { z } from "zod";

/**
 * Public Supabase settings, validated once. NEXT_PUBLIC_ values must be read with literal
 * `process.env.NAME` expressions so Next.js can inline them into the browser bundle.
 * The service-role key is never read here: it must not reach browser code (CLAUDE.md rule 3).
 */
const publicSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(20),
});

export const env = publicSchema.parse({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
});
