# Round Island ERP – project guide for Claude Code

Web accounts / invoicing app for **Round Island (Pvt) Ltd, Colombo, Sri Lanka** (currency LKR).
We are rebuilding a working single-file browser app as a proper multi-user web app.

- **Reference implementation (source of truth for behaviour):** `reference/ERP_Accounts_Module_v5.html` – one HTML file, vanilla JS, data in localStorage. Read it before building any feature; match its calculations exactly.
- **Invoice print format:** `reference/invoice_format_SCAN1209.pdf` (scanned invoice). **Product list + rates:** `reference/product_list.xlsx`.
- **Full feature list and accounting rules:** `docs/SPEC.md`. **Order of work:** `docs/BUILD_PLAN.md`. **Deploy steps:** `docs/DEPLOY.md`.

## Stack (do not change without asking)
- Next.js (App Router) + TypeScript (strict) + Tailwind CSS (shadcn/ui for components)
- Supabase: Postgres, Auth, Storage, Row Level Security. Client via `@supabase/ssr`.
  - **Shared project** (`fkyttnebqkrmntjwddrc`, also used by other apps): everything lives in schema **`round_island`** (`src/lib/supabase/schema.ts`). Every migration starts with `set search_path = round_island, public;`. Storage buckets are `ri-deposit-slips` / `ri-company-assets` and storage policies are prefixed `ri_`.
  - `auth.users` is shared with the other apps: **never delete auth users** and never change project-wide auth settings (sign-up etc.). A login without a `company_members` row simply gets the "No access" screen.
  - The user applies SQL and runs git themselves – Claude writes the files and gives step-by-step directions.
- Hosting: Vercel. Package manager: npm.
- Validation: zod. Tests: Vitest for accounting logic, Playwright for key flows.
- File import: `exceljs` (xlsx) and `papaparse` (csv).

## Commands
- `npm run dev` – local dev server · `npm run build` · `npm run lint` · `npm run typecheck` · `npm test`
- Types: `npx supabase gen types typescript --project-id fkyttnebqkrmntjwddrc --schema round_island > src/lib/database.types.ts` (needs `npx supabase login`)
- Next.js 16: middleware is `src/proxy.ts`; Cache Components is on, so anything reading the session sits inside `<Suspense>`. Read `node_modules/next/dist/docs/` before using an unfamiliar API.
- Run lint, typecheck and tests before saying a task is finished.

## Layout
```
src/app/(auth)/login            sign in
src/app/(app)/…                 dashboard, sales, purchases, payments, receipts, supplier-payments,
                                customers, suppliers, statement, outstanding, sales-reports, pl, notes, settings, data
src/app/(sales)/invoicing       restricted screen for the "sales" role (replaces the old standalone sales sheet)
src/lib/accounting/             PURE functions (no I/O): pl.ts, notes.ts, setoff.ts, invoice.ts, tax.ts  + *.test.ts
src/lib/supabase/               server.ts, client.ts, middleware helper
src/lib/import/                 csv/xlsx importers (sales, purchases, receipts, payments, set-off, products)
src/components/                 UI;  src/components/invoice/InvoicePrint.tsx = printable invoice (A4)
supabase/migrations/            SQL, applied in order. Never edit an applied migration – add a new one.
                                0003_hardening.sql: sales-role RLS, set-off/credit-note checks (deferred to commit),
                                reconcile_document(), next_invoice_no(), audit_log, party_totals / party_credits views
```

## Non-negotiable rules
1. **All accounting maths lives in `src/lib/accounting/` as pure, tested functions.** Port each formula from the reference HTML (`compute`, `plColumns`, `openItems`, `settledMap`, `allOpenInvoices`, `autoAllocate`) and write a Vitest test using numbers taken from the reference app. The UI never recomputes totals itself.
2. **Money is `numeric(14,2)` in the DB and is rounded to 2 dp with half-up rounding in one helper (`money.ts`).** Never use floating-point sums for stored totals; round each line, then sum.
3. **Security is enforced by RLS, not by the UI.** Every table has `company_id` and a policy. Never use the service-role key in browser code or in a `NEXT_PUBLIC_` variable. Roles: `owner`, `accountant`, `sales` (sales may only create/edit their own *sale* invoices).
4. **One invoice = one `trade_documents` header + 1..6 `trade_lines`.** The old app stored one row per line; do not copy that shape.
5. **Every list that the old app showed must tie out:** Customers page balance = Customer Receipts outstanding = Outstanding Report. All three read from the same view/function (`open_documents` / `allOpenInvoices`). Add a test that proves it.
6. **Never delete accounting data silently.** Deletes ask for confirmation, show what will go (incl. set-offs), and are logged (add an `audit_log` table in the first phase that touches deletes).
7. Dates are stored as `date` (no time zone). Display `dd/mm/yyyy`; the invoice print uses `dd.mm.yyyy`. Importers read **day-first** by default with a switch for month-first (see `guessMDY` in the reference).
8. Keep the existing wording of labels/notes/report titles – staff are used to them (including the spelling **"Ingridients"** category).
9. Mobile-friendly layouts; every report has Print / Save-as-PDF (print CSS) and CSV export.
10. Small, reviewable commits. Ask before adding dependencies not listed above.

## Domain glossary
- **Sale / Sales Return / Purchase / Purchase Return** – the four `doc_kind`s. Returns are credit notes that may point at an original document (`against_id`).
- **Customer Receipt / Supplier Payment** – money that is *set off* against invoices/bills via `payment_allocations`; any unallocated part is "on account".
- **VAT & SSCL** – tax charged on sales. Sale line amounts are stored **excluding** this tax; tax is separate.
- **Turnover tax / Income tax** – calculated at the rates in company settings, but **replaced by the actual amounts** when payments of kind `turnover_tax` / `income_tax` exist (per month column).
- **Invoice type** – Cash, Credit, Card, Sample, FOC (label on each sale invoice; drives the Sales Reports).
- **Asset purchase** – capital item; excluded from P&L, shown in Note 9.
