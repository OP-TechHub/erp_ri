# Build plan – Round Island ERP as the back office of Cloud Kitchen
Start each session with: *"Read CLAUDE.md, docs/SPEC.md and docs/BUILD_PLAN.md. We are on Stage X, step N."*
Finish a step = lint + typecheck + tests green; Claude gives the commit and SQL steps, the owner runs them.

**Decided 2026-11-10:** Round Island and Cloud Kitchen are one business. The money side moves to this ERP; Cloud Kitchen
(`C:/Users/yjoff/cloud_kitchen`) keeps orders, kitchen, dispatch, invoices, items (LO_RI selling codes), customers, stock,
production, ingredients, recipes and purchasing up to **PO approved**. CK's own accounts module is retired at the switch-over.
HORECA and Retail are never touched.

## Done
- **Phase 0 – Scaffold**: Next.js 16, Supabase clients, proxy, app shell, login.
- **Phase 1 – Database**: 0001–0006 (schema `round_island`, RLS, set-off and credit-note checks, `reconcile_document`, audit log,
  order source, line units, fixed/free price mode), company (`supabase/seed/create_company.sql`).
- **Items in Cloud Kitchen**: `cloud_kitchen/supabase/items_import.sql` – LO_RI-00001…00016 with recipes; old LOC/EXPORT/TEMP removed.

## Stage A – Link the two databases (nothing changes for CK staff)
1. ✔ `0007_ck_roles.sql` + `0008_ck_link.sql`: staff → ERP access, customers → parties, items → products,
   invoices → sale documents (+ receipt when paid at once). Errors go to `ck_sync_errors`; `ck_backfill()` copies what exists.
2. Parallel run: CK keeps its own books; check `round_island.ck_sync_check` daily (every CK invoice copied, same totals).

## Stage B – Build the back office (CK staff keep working in CK meanwhile)
1. **Master data** – Settings (company, tax rates, invoice texts, logo), categories, suppliers; customers and items read-only (from CK).
2. **Accounting core (no UI)** – `src/lib/accounting/*`: open items / settled map / oldest-first credits, auto set-off, P&L columns,
   notes 1-10, tax overrides; tests with numbers from the reference app; tie-out test (CLAUDE.md rule 5). `costing.ts` exists.
3. **Money in** – Customer Receipts with set-off grid, credit notes against CK invoices; **cashier** screen (receipts + daily cash-up,
   same rules as CK `finance.sql`); cheques in hand → deposited → cleared / bounced; card settlements (bank fee → expense).
4. **Money out** – purchasing after PO approved: funded (cash / credit) → bought (actual qty, price, bill ref, receipt files) →
   handover → [CK: received, raises stock] → checked = ERP purchase bill with ingredient lines (feeds recipe costing);
   supplier payments, issued cheques; Payments Entry (expenses, other income, assets, taxes); other payables.
5. **Reports** – Dashboard, Outstanding Statement / Report, Sales Reports (type, order source, deposit slips), P&L (3 columns +
   month ZIP), Notes, recipe costing report (SPEC §8); CSV and print for all.
6. **Read functions for CK** – `erp_overview(from, to)`, `erp_customer_balance(customer)`: the numbers CK's Overview and invoice
   dialog show today, now from the ERP.
7. **Importers & bulk tools** – SPEC §5 importers with preview; delete by party & amount, delete receipts by date, cancel set-offs.

## Stage C – Switch-over (one evening, planned with the owner)
1. Freeze finance entries in CK.
2. One-time SQL: delete the ERP's shadow invoice copies, then migrate CK's books (documents, payments, set-offs, suppliers,
   categories, expenses, cheques, cash-ups, card settlements, other payables, deposit slips, open purchase requests) with a check table.
3. Cloud Kitchen: drop `invoices_to_ledger`; remove its Finance / accounts tabs, Expenses, Receive, cheques, cash-up, card
   settlements, other payables, manual "New sale" and the purchasing steps after PO approved; Overview and invoice dialog call
   the ERP functions; `executive_summary` reads ERP expenses.
4. Reconcile balances, P&L month-to-date and cash position before / after; smoke-test HORECA / Retail (unchanged).
5. Mark CK's accounts module retired (tables kept read-only, never silently deleted). Deploy per `docs/DEPLOY.md`.

## Dropped from the first plan
ERP sales invoice form and `/invoicing` sales screen (invoicing stays in CK), ERP `next_invoice_no()` series, ERP member management
(follows CK staff), ERP-owned item / ingredient / recipe tables, the old-app data import (`supabase/data/import_data.sql`, no longer
used: the old data was cleared on 2026-11-10).

## Prompt snippets that work well
- "Port `plColumns` from the reference to `src/lib/accounting/pl.ts` as a pure function with types, and write Vitest cases for: a month with no tax payments, a month with an actual income-tax payment, and the year-end month with opening/closing stock."
- "Review this step against the reference app and the Cloud Kitchen feature it replaces, and list any behaviour I missed."
