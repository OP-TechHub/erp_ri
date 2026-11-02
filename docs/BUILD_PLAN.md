# Build plan – give these to Claude Code one phase at a time
Start each session with: *"Read CLAUDE.md, docs/SPEC.md and docs/BUILD_PLAN.md. We are on Phase N."*
Finish a phase = lint + typecheck + tests green, then commit.

**Phase 0 – Scaffold.** `npx create-next-app@latest . --ts --tailwind --eslint --app --src-dir --use-npm`; add `@supabase/supabase-js @supabase/ssr zod exceljs papaparse` and dev `vitest @playwright/test`; init shadcn/ui; Supabase clients, auth middleware (redirect to `/login`), env validation with zod; `typecheck`/`test` scripts. App shell with left menu matching the reference.

**Phase 1 – Database & auth.** Apply `supabase/migrations/*`. Login page (email + password), first-run "create company" (calls `create_company`, then `seed_products`). Members page (owner invites users and sets role). Generate DB types. Add `audit_log` table + trigger on delete for documents/payments.

**Phase 2 – Master data.** Settings (company, tax rates, invoice details, logo upload to Storage), categories (7 groups, rename updates history), products with rates + file upload, customers, suppliers.

**Phase 3 – Accounting core (no UI).** `src/lib/accounting/*`: money rounding, invoice maths, open items / settled map / oldest-first credits, auto set-off, P&L columns, notes 1-10, tax overrides. Port from the reference; tests with numbers from the reference app (export a small data set from it and assert identical outputs).

**Phase 4 – Sales invoicing.** Invoice form (6 lines, rates, discount, tax, type, next number), list/search, edit, delete (confirm), **print page A4 per the PDF format**, sales role screen `/invoicing`.

**Phase 5 – Purchases, payments, receipts, set-off.** Entries, receipt/payment forms with set-off grid, auto set-off, supplier payments, credit notes (`against_id`).

**Phase 6 – Reports.** Dashboard, Outstanding Statement, Outstanding Report, **Sales Reports** (type filter, day sections, Cash → deposit-slip attach via Storage bucket `deposit-slips`, daily slip print), P&L (3 columns + month-wise ZIP), Notes, CSV/print for all.

**Phase 7 – Importers & bulk tools.** All importers in SPEC §5 with preview; delete-by-party-and-amount, delete receipts by date, cancel set-offs.

**Phase 8 – Data migration + go-live.** The import SQL already exists (`scripts/make_import_sql.py`, `supabase/data/import_data.sql`, SPEC §6). Load it into Supabase early (right after Phase 1) so every later phase is built and tested on the real data; for go-live take a fresh backup, regenerate, reload on an empty database, reconcile against the old app, then deploy per `docs/DEPLOY.md`.

## Prompt snippets that work well
- "Port `plColumns` from the reference to `src/lib/accounting/pl.ts` as a pure function with types, and write Vitest cases for: a month with no tax payments, a month with an actual income-tax payment, and the year-end month with opening/closing stock."
- "Build the invoice form exactly as described in SPEC §3; the print page must match `reference/invoice_format_SCAN1209.pdf`; show me a Playwright screenshot of the printed invoice."
- "Review this phase against the reference app and list any behaviour I missed."
