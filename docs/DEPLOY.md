# Setup & deployment (VS Code + Supabase + Vercel)

## 1. One-time tools
Install: Node.js 20+ LTS, Git, VS Code, the Claude Code extension (or `npm i -g @anthropic-ai/claude-code`), Supabase CLI (`npm i -D supabase` in the project), Vercel CLI optional (`npm i -g vercel`). Create free accounts: GitHub, Supabase, Vercel.

## 2. Project
1. Unzip this starter into a folder, open it in VS Code, run `git init` and make the first commit.
2. Start Claude Code in the folder and say: *"Read CLAUDE.md and docs/BUILD_PLAN.md and do Phase 0."* Continue phase by phase.
3. Create a GitHub repo and push (`git remote add origin …; git push -u origin main`).

## 3. Supabase
The app uses the **shared Oceanpick project** (`fkyttnebqkrmntjwddrc`), in its own schema `round_island`. Other apps use the same project, so:
never delete users under Authentication → Users, and leave project-wide auth settings (sign-up, providers, URL list entries of other apps) alone.

1. Project Settings → API: copy the **Project URL** and the **anon key** (public). The app does not use the service-role key.
2. **Apply the schema:** SQL Editor → New query → paste `supabase/migrations/0001_init.sql` → Run. Then the same with `0002_seed_products.sql` and `0003_hardening.sql`, in that order. Each must finish with "Success".
3. Project Settings → API → **Exposed schemas** (Data API settings): add `round_island` and save. Without this the app gets "schema must be one of …" errors.
4. Authentication → URL Configuration: **add** your Vercel URL and `http://localhost:3000` as redirect URLs (keep the existing entries of the other apps).
5. **Load your existing data:** use an existing login or create one (Authentication → Users → Add user, tick auto-confirm). Open `supabase/data/import_data.sql`, replace `YOUR_LOGIN_EMAIL` with that e-mail, paste the whole file into the SQL Editor and Run. Compare the check table at the end with the totals in the comments at the top. Run it only once – to redo, first `delete from round_island.companies;` (this also logs every removed row in `round_island.audit_log`).
6. Staff: create their logins under Authentication → Users, then add them in the app under Settings → Members.
7. Storage buckets `ri-deposit-slips` and `ri-company-assets` are created by the migration (private).
8. Backups: the project is shared, so a restore would affect all apps. Export this app's data regularly (Backup & Export screen, or `pg_dump --schema=round_island`).

## 4. Environment variables
Copy `.env.example` to `.env.local` and fill it in. On Vercel add the same names under *Project → Settings → Environment Variables* (Production + Preview).

## 5. Vercel
1. vercel.com → Add New → Project → import the GitHub repo (framework: Next.js, defaults are fine).
2. Add the env vars, Deploy. Every push to `main` redeploys; pull requests get preview URLs.
3. Optional: add your own domain under *Settings → Domains*.
4. After the first deploy: sign in (the company already exists from the data import) and add staff under Settings → Members.

## 6. Go-live checklist
- [ ] RLS test: log in as a `sales` user and confirm you cannot open payments, P&L or other users' invoices (try the Supabase API directly too).
- [ ] Old-app data imported and reconciled (SPEC §6).
- [ ] Invoice print compared with the scanned original on a real printer.
- [ ] Backup routine decided (who exports, how often).
- [ ] No service-role key in Vercel or `.env.local` (the app does not need it; it must never be a `NEXT_PUBLIC_` variable).

**Privacy:** `supabase/data/*.sql` and any backup `.json` contain real customer and financial data. They are in `.gitignore`; keep the GitHub repo **private** anyway.
