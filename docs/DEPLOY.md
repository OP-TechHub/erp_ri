# Setup & deployment (VS Code + Supabase + Vercel)

## 1. One-time tools
Install: Node.js 20+ LTS, Git, VS Code, the Claude Code extension (or `npm i -g @anthropic-ai/claude-code`), Supabase CLI (`npm i -D supabase` in the project), Vercel CLI optional (`npm i -g vercel`). Create free accounts: GitHub, Supabase, Vercel.

## 2. Project
1. Unzip this starter into a folder, open it in VS Code, run `git init` and make the first commit.
2. Start Claude Code in the folder and say: *"Read CLAUDE.md and docs/BUILD_PLAN.md and do Phase 0."* Continue phase by phase.
3. Create a GitHub repo and push (`git remote add origin …; git push -u origin main`).

## 3. Supabase
1. supabase.com → New project (choose a region near Sri Lanka, e.g. Singapore). Save the database password.
2. Project Settings → API: copy **Project URL**, **anon key** (public) and **service_role key** (SECRET – never in the browser).
3. Apply the schema: either paste `supabase/migrations/0001_init.sql` then `0002_seed_products.sql` into *SQL Editor → Run*, or `npx supabase login`, `npx supabase link --project-ref <ref>`, `npx supabase db push`.
4. Authentication → Providers: enable Email. For a private business app turn **off** "Allow new users to sign up" after you have created the owner and staff accounts (Authentication → Users → Add user).
5. Authentication → URL Configuration: Site URL = your Vercel URL; add `http://localhost:3000` as a redirect URL.
6. **Load your existing data:** create your login (Authentication → Users → Add user, tick auto-confirm), open `supabase/data/import_data.sql`, replace `YOUR_LOGIN_EMAIL` with that e-mail, paste the whole file into the SQL Editor and Run. Look at the check table at the end and compare it with the totals in the comments at the top. Do this *instead of* calling `create_company`; do not run it twice (it needs an empty database – to redo, delete the company row first: `delete from companies;`).
7. Storage buckets `deposit-slips` and `company-assets` are created by the migration (private).
8. Turn on daily backups (Pro plan) or schedule `pg_dump` – the free plan has no automatic backups, so export regularly.

## 4. Environment variables
Copy `.env.example` to `.env.local` and fill it in. On Vercel add the same names under *Project → Settings → Environment Variables* (Production + Preview).

## 5. Vercel
1. vercel.com → Add New → Project → import the GitHub repo (framework: Next.js, defaults are fine).
2. Add the env vars, Deploy. Every push to `main` redeploys; pull requests get preview URLs.
3. Optional: add your own domain under *Settings → Domains*.
4. After the first deploy: sign in, create the company (Phase 1 screen), add staff with the `sales` role.

## 6. Go-live checklist
- [ ] RLS test: log in as a `sales` user and confirm you cannot open payments, P&L or other users' invoices (try the Supabase API directly too).
- [ ] Old-app data imported and reconciled (SPEC §6).
- [ ] Invoice print compared with the scanned original on a real printer.
- [ ] Backup routine decided (who exports, how often).
- [ ] Service-role key exists only in Vercel server env and your local `.env.local`.

**Privacy:** `supabase/data/*.sql` and any backup `.json` contain real customer and financial data. They are in `.gitignore`; keep the GitHub repo **private** anyway.
