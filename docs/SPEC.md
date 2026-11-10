# Functional specification (derived from `reference/ERP_Accounts_Module_v5.html`)

When this document and the reference app disagree, **the reference app wins** – tell the user and update this file.

## 1. Modules / screens
| Screen | What it does |
|---|---|
| Dashboard | Period tiles (revenue, cost, profit), monthly revenue-vs-cost bars, quick "+ Sale / + Purchase / + Receipt / + Payment" buttons. |
| Sales Entry | List/search/filter sales + returns; **+ New sale = invoice form** (see §3); Print invoice per row; Upload file (xlsx/csv); Template; Export CSV; "Delete by party & amount". |
| Purchase Entry | Same list for purchases + purchase returns (bill no, supplier, single line + category + tax). |
| Payments Entry | Expense, Other Income, Asset Purchase, Income Tax, Turnover Tax. Category list depends on type. |
| Customer Receipts | Receipt entry with set-off to invoices; outstanding invoices table; upload invoice-wise receipts; set-off from file; cancel all set-offs; delete receipts by date. |
| Supplier Payments | Mirror of receipts for suppliers; supplier summary + outstanding bills; payments to "Ingridients" etc. flow to purchases/cost of sales. |
| Customers / Suppliers | Master list with phone/email/address/notes and live balance (must equal the outstanding report). |
| Outstanding Statement | Per-party statement. |
| Outstanding Report | Open invoices/bills: date, invoice no, amount; filter party, "as at" date; Print/PDF + CSV. Customers and Suppliers. |
| **Sales Reports** | Filter by invoice type (All, Cash, Credit, Card, Sample, FOC, Not set), **order source** (All, Walk-in, Call, WhatsApp, Website, Other, Not set) and date range; summary by source as well as by type. Day-by-day sections with totals, summary by type, per-invoice print icon, Export CSV. **Cash** view: per-day **Attach PDF** (deposit slip, PDF or photo; view / replace / remove). Non-cash views: per-day "PDF slip" (daily sales slip with Prepared by / Checked by lines). |
| Profit & Loss | Columns **This month / Last month / Accumulated** (financial-year start → end of selected month). Month-wise files (one P&L per month, ZIP of CSVs). |
| Notes to Accounts | Same three columns. Notes 1-10 (see §2). |
| Settings | Company name, currency, period, opening/closing stock, turnover-tax rate, income-tax rate (default 30 %), invoice address/bank/terms/logo, categories (7 groups), products (code, name, category group, **rate**; upload file). |
| Backup & Export | JSON backup/restore + CSV exports (replace with server-side export/import). |

## 2. Accounting rules
**P&L order:** Sales incl. VAT & SSCL → less VAT & SSCL → **Revenue (Note 1, net of returns)** → Cost of sales (Note 2) → Gross profit → Other income (3) → Administrative (4) → Selling & distribution (5) → Finance costs (6) → Turnover tax (10) → Profit before tax → Income tax (7) → Net profit.

- **Cost of sales (Note 2):** opening stock + net purchases (purchases − purchase returns) − closing stock. For a single month the figure is just net purchases; opening/closing stock (Settings) are brought in **only in the year-end month, Accumulated column**.
- **Income tax:** `rate × profit before tax` per column, unless actual `income_tax` payments exist in that column → use the actual amount. **Turnover tax:** `rate × revenue`, same override with `turnover_tax` payments (per month).
- **Asset purchases** are not in the P&L (Note 9). **Supplier payments** only settle bills; they never hit the P&L directly.
- **Note 8a/8b (receivables / payables):** movements inside each column – invoices incl. tax less receipts/payments; no opening balances. "Last month" before the financial-year start is blank.
- Entries dated outside the period are ignored by the P&L (tagged "outside period" in lists).

**Set-off rules**
- A receipt/payment stores `alloc: [{invoice, amount}]`; `unallocated = amount − Σalloc` is "on account".
- Balance of an invoice = total − allocations − credit notes pointing at it.
- Unlinked credit notes and on-account receipts are applied **oldest invoice first** when computing party balances (`allOpenInvoices(side, apply=true)`), so party balance, receipts screen and outstanding report agree.
- Auto set-off = oldest first. "Cancel all set-offs" clears allocations only (keeps receipts). A credit note cannot exceed the balance of the document it is against.

## 3. Sales invoice (the format the user prints)
- Header: invoice date, **invoice no** (auto next `INV` + zero-padded number, e.g. INV01612; editable; unique per company), customer (type-ahead; unknown name offers to create), **invoice type** (Cash/Credit/Card/Sample/FOC), **order source** (Walk-in / Call / WhatsApp / Website / Other – required on new invoices), discount %, VAT & SSCL %, optional customer details lines (contacts/address).
- **Up to 6 lines:** item (product = sales category), description (defaults to product name), **Qty** with its **unit – packs or kg** (§8), **unit price** (**fixed** line: the pack price from the item master, not editable; **free** line: typed, the per-kg price is suggested for kg), line total = qty × unit price.
- Money: `net line = round2(qty × price × (1 − disc%))`, `tax = round2(net × tax%)`; invoice total = Σnet + Σtax. Sub total, discount amount and total bill are shown.
- Save, or **Save & print**. Reprint any invoice any time. Edit an invoice = edit header + lines (blocked/warned if it has set-offs that would exceed the new total).
- **Print layout (A4)** follows `reference/invoice_format_SCAN1209.pdf`: logo top-left; "SALE INVOICE" top-right; company name + address; right side "Invoice No:" and "INVOICE DATE: dd.mm.yyyy" (+ "INVOICE TYPE"); customer block; table DESCRIPTION | QTY | UNIT PRICE | TOTAL with at least 6 rows (QTY shows the unit, e.g. "10 packs" / "3.500 kg" – changed from the scan's QTY-KG on 2026-11-10); SUB TOTAL, DISCOUNT (with "x% OFF" in the qty column), VAT & SSCL (only if > 0), TOTAL BILL; **Bank details** block; **Terms & Instructions** block ("Cheque should be drawn in favour to "Round Island Pvt Ltd"", "No Credit"); logo again bottom-right. Company address / bank / terms / logo come from Settings.
- Sample and FOC are currently recorded at the entered price like any sale (open question for the owner: should they be zero-value?).

## 4. Roles and access
| Role | Can do |
|---|---|
| owner | everything, manage members, settings |
| accountant | all accounting screens, imports, reports |
| sales | only `/invoicing`: create/print/edit **their own** sale invoices (with the product list, customers, next number). No access to payments, P&L, balances or other users' data. |

## 5. Importers (keep all of them)
CSV or xlsx; heading row auto-detected within the first 25 rows; column aliases (see `ALIAS` in the reference); dates day-first by default with a month-first switch and an automatic guess; duplicate skip key = date+type+ref+party+amount; option to create unknown customers/suppliers/categories; preview with counts, errors per line, then import.
Files used so far: sales (`Date, Type, Invoice No, Customer, Description, Category, Amount, Tax, Qty, Unit Price, Discount %, Customer Details, Invoice Type`), purchases, receipts, **invoice-wise receipts** (set off while importing), **set-off from file** (`RI_Setoff.xlsx`), supplier payments (`RI_Payments.csv`; replaces earlier supplier payments, category "Ingridients"), products (`name, category, rate`). "Delete by party & amount" (match on total incl. tax, excl. tax or either) and "Delete receipts / payments by date" (receipt date or date entered, optional ref prefix) are bulk tools with a confirmation listing what will be removed.

## 6. Migrating the existing data
Done with a generator, already run for the 2026-11-02 backup:
`python3 scripts/make_import_sql.py <backup.json> supabase/data/import_data.sql` → run the generated file once in the Supabase SQL editor on an empty database (edit the `YOUR_LOGIN_EMAIL` line first). It creates the company, members, categories, parties, products, documents + lines, payments and set-offs, then prints a check table to compare with the totals written at the top of the file. Re-run the generator with a newer backup for a final cut-over (on a fresh database).

Conversion rules (all listed in the SQL header when they happen):
- Old rows are grouped into one document per (type, ref, party, date); rows with a blank ref stay one document each. Max 6 lines per document.
- A ref reused for a different party/date gets a `-2` suffix (old app allowed duplicates; the new database does not).
- Amounts and tax are rounded to 2 dp per line; if that would leave a fully settled invoice with a 1-cent balance, the last line is adjusted by the cent.
- Old sales had no invoice type; where the description is exactly "Cash" the invoice type is set to `cash` (452 of 498 documents in the 2026-11-02 backup).
- Backup contains no quantities/unit prices for old sales, so those lines carry amount only (qty/price null) and print with the total only.
- Cash deposit slips are stored in the browser (IndexedDB), **not** in the backup – re-attach them in the new app.
- Entries dated before the financial-year start (2025-07 → 2026-03 in this data) are imported but ignored by P&L, as before.
- The old app applies on-account receipts and unlinked credits oldest-first when it shows party balances; the new accounting module must do the same (Phase 3), so the open-invoice sum straight from `open_documents` is *before* that step.

**Acceptance check after import:** document/line counts, Σ sales, Σ tax, Σ purchases, Σ receipts, Σ supplier payments, Σ expenses match the header (cents of rounding aside); then compare the P&L accumulated column and customer / supplier balances with the old app for the same month.

## 7. Decisions for the web version (where it differs from, or adds to, the reference)
- **Invoice numbers:** next number = `INV` + (highest `INVnnnnn` sale number + 1), at least 5 digits – `next_invoice_no()`, exactly like `invNext`. The old plain numbers (…1531) are not counted, so the new series starts at INV00001 (owner's decision, 2026-11-02).
- **Order source** (added 2026-11-10, not in the reference): how the order came in – Walk-in, Call, WhatsApp, Website or Other (`order_source`, migration 0004). Required on new sale invoices; invoices imported from the old app show "Not set". Independent of the invoice type: a walk-in or WhatsApp order can be Cash, Credit, Card, Sample or FOC.
- **Edit / delete reconciliation** (`reconcileInvoice`): changing an invoice's party or type moves its set-offs back on account and unlinks its credit notes; lowering its total below what is set off cuts allocations from the newest receipt back, then unlinks the newest notes; a credit note that becomes larger than its invoice's balance is unlinked. Done in the database (`reconcile_document()`, trigger on party/type change); a check at commit refuses anything that would still over-settle a document.
- **Parties are required** on every sale/purchase document and on receipts/supplier payments; unknown names are created as customers/suppliers (invoice form offers it, importers do it). The reference allowed free-text names.
- **Renaming** a party or category renames it on all past entries (as in the reference) – done by database triggers.
- **Sales staff** see only their own sale invoices, the customer list, sales categories and products; they can create and edit (not delete) their own invoices.
- **Live / Demo mode is dropped**; Vercel preview deployments are used for trying things out.
- **Outstanding Statement** keeps the reference's own method (all credits pooled oldest-first, ignoring set-offs; ageing 0-30 / 31-60 / 61-90 / >90) – it can differ from the Outstanding Report, as before.
- Open question for the owner: should **Sample / FOC** invoices be zero-value? Until decided they are recorded at the entered price.

## 8. Items, units and recipe costing (added 2026-11-10 – not in the reference app)
Source: `Round_Island_Monthly_Tracker` (Round Island part only). Migration `0005_items_costing.sql`, data `supabase/seed/items_ingredients_2026-11.sql`.
- **Item master:** code `LO_RI-00001` … (16 items: the tracker's 14 in its order, then LO_RI-00015 Barra Slidder and LO_RI-00016 Salt and Pepper), name, category group (Marinated Fillets / Convenience Range), pack size as printed ("320g (8pc)"), pack weight in grams, **pack price** (`rate`) and an optional **per-kg price** (`kg_rate`). Starting pack prices and sizes = the tracker's Product Master, except the two Collagen Soups, which are served in a cup: **150g cup, Rs 450** each (recipe still the tracker's 500ml one for now); 00015/00016 keep their old rates; the owner corrects them in Settings. Each item is also a sales category named "code – name" (as `prodLabel` in the reference).
- **Fixed or free price (owner, 2026-11-10):** every sale line is either **fixed** – packs at the item master's pack price and pack size, price not editable on the line – or **free** – quantity and price typed in, in packs or kg (bulk orders at a negotiated price; the per-kg price, if set, is only a suggestion). `price_mode` + `unit` on the line (migration 0006); rule in `src/lib/accounting/invoice.ts`. The same item can be sold either way. The invoice print column is **QTY** showing the unit ("10 packs", "3.500 kg"); unit price is per that unit.
- **Ingredients** (raw materials and packaging, unit kg / unit / l) have **no price list and no price is shown on the ingredient screens** – prices change with every purchase. Finance costing uses the price entered on each purchase. A purchase line names the ingredient, the quantity in its unit and the amount paid (excl. tax).
- **Recipe (BOM):** quantity of each ingredient in ONE pack. The tracker's quantities were loaded as starting values (marked there as placeholders) – to be corrected in Settings.
- **Ingredient cost for a month = monthly weighted average** of that month's purchase lines: Σ amount ÷ Σ qty (purchase returns subtract). No purchase that month → the latest earlier month's average; never bought → shown as "no cost yet".
- **Recipe cost per pack** = Σ round2(qty × ingredient cost). **COGS of a sale line** = packs × recipe cost, where packs = qty for pack lines and kg × 1000 ÷ pack weight for kg lines (items without a pack weight can't be costed when sold by kg until a weight is set).
- **Recipe costing report** (monthly): per item – packs sold, revenue, recipe cost per pack, COGS, gross profit, margin %; month totals; warnings for ingredients with no cost and kg lines that couldn't be converted. This is a management view; the statutory P&L (§2) is unchanged (cost of sales there = purchases ± stock).
- All costing maths: `src/lib/accounting/costing.ts`, tested against the tracker's January 2026 figures (14 recipe costs; revenue 2,132,600, COGS 928,875, gross profit 1,203,725).
- Sales staff can see items and their prices, never ingredients, recipes or costs.
