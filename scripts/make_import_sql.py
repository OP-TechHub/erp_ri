#!/usr/bin/env python3
"""Turn a backup file from the OLD single-file app (Backup & Export -> Download backup .json)
into one SQL file you can run in the Supabase SQL editor.

    python3 scripts/make_import_sql.py accounts_backup_live_2026-11-02.json supabase/data/import_data.sql

Before running the SQL: create your login in Supabase (Authentication -> Users -> Add user) and put that
e-mail on the line marked  EDIT  in the generated file.  Run it once, on an EMPTY database.
Only the Python standard library is needed.
"""
import json, sys, uuid, collections, datetime

NS = uuid.UUID("6f1d2c3a-0000-4000-8000-52494552502e")
def U(*a): return str(uuid.uuid5(NS, "|".join(map(str, a))))
def r2(x): return round(float(x) + (1e-9 if x >= 0 else -1e-9), 2)
def q(s): return "'" + str(s if s is not None else "").replace("'", "''") + "'"
def n(x): return f"{x:.2f}"
def d(s): return q(s) + "::date"

src, out = sys.argv[1], sys.argv[2]
J = json.load(open(src, encoding="utf-8"))
st, cats, sp, py = J["settings"], J["cats"], J["sp"], J["py"]
notes = []                                           # everything that was changed, for the report
CID = U("company", st["company"])

# ---------- categories ----------
GROUP = {"sales": "sales", "purchase": "purchase", "admin": "admin", "selling": "selling", "finance": "finance", "otherIncome": "other_income", "assets": "assets"}
catrows, catid = [], {}
for g, names in cats.items():
    for i, name in enumerate(names):
        k = (GROUP[g], name.strip().lower())
        if k in catid: continue
        catid[k] = U("cat", *k); catrows.append((catid[k], GROUP[g], name, i))
def find_cat(name, groups):
    for g in groups:
        k = (g, (name or "").strip().lower())
        if k in catid: return catid[k], next(r[2] for r in catrows if r[0] == catid[k])
    return None, name or ""

# ---------- parties ----------
parties, pid = [], {}
for kind, key in (("customer", "customers"), ("supplier", "suppliers")):
    for c in J[key]:
        k = (kind, c["name"].strip().lower()); pid[k] = U("party", *k)
        parties.append((pid[k], kind, c["name"], c.get("phone", ""), c.get("email", ""), c.get("address", ""), c.get("notes", "")))
def party(kind, name):
    k = (kind, (name or "").strip().lower())
    if k not in pid and name and name.strip():
        pid[k] = U("party", *k); parties.append((pid[k], kind, name.strip(), "", "", "", "")); notes.append(f"party '{name}' was not in the {kind} list - created")
    return pid.get(k)

# ---------- documents ----------
KIND = {"Sale": "sale", "Sales Return": "sales_return", "Purchase": "purchase", "Purchase Return": "purchase_return"}
groups = collections.OrderedDict()
for i, r in enumerate(sp):
    ref = (r.get("ref") or "").strip()
    key = (r["type"], ref.lower(), r["party"], r["date"]) if ref else (r["type"], "", r["party"], r["date"], i)   # blank refs: one document per row
    groups.setdefault(key, []).append(r)
seen_ref, docs, rowdoc = {}, [], {}
for key, rows in groups.items():
    t, refl = key[0], key[1]; ref = (rows[0].get("ref") or "").strip(); newref = ref
    if ref:
        c = seen_ref.setdefault((t, refl), 0); seen_ref[(t, refl)] = c + 1
        if c:
            newref = f"{ref}-{c + 1}"; notes.append(f"{t} ref '{ref}' was used again ({rows[0]['party']}, {rows[0]['date']}) - renamed '{newref}'")
    did = U("doc", *key)
    docs.append({"id": did, "t": t, "date": rows[0]["date"], "ref": newref, "party": rows[0]["party"], "rows": rows, "against": rows[0].get("against")})
    for r in rows: rowdoc[r["id"]] = did
for dd in docs:
    if len(dd["rows"]) > 6: raise SystemExit(f"document {dd['ref']} has {len(dd['rows'])} lines (max 6)")

# ---------- payments / allocations ----------
PK = {"Customer Receipt": "customer_receipt", "Supplier Payment": "supplier_payment", "Expense": "expense", "Other Income": "other_income",
      "Asset Purchase": "asset_purchase", "Income Tax": "income_tax", "Turnover Tax": "turnover_tax"}
CATG = {"expense": ["admin", "selling", "finance", "purchase"], "other_income": ["other_income"], "asset_purchase": ["assets"]}
alloc = collections.defaultdict(float); alloc_rows = []
for p in py:
    per = collections.defaultdict(float)
    for a in p.get("alloc", []):
        if a["id"] not in rowdoc: raise SystemExit("allocation points to an unknown invoice: " + a["id"])
        per[rowdoc[a["id"]]] += a["amt"]
    for did, amt in per.items():
        alloc_rows.append([U("payment", p["id"]), did, r2(amt)]); alloc[did] += r2(amt)

# ---------- line amounts (rounded) + fix cents so fully-settled invoices stay settled ----------
for dd in docs:
    dd["lines"] = [{"amount": r2(r["amount"]), "tax": r2(r.get("tax", 0)), "raw": r["amount"] + r.get("tax", 0), "r": r} for r in dd["rows"]]
settled_old = collections.defaultdict(float)
for p in py:
    for a in p.get("alloc", []): settled_old[rowdoc[a["id"]]] += a["amt"]
for dd in docs:
    if dd["t"] not in ("Sale", "Purchase") or dd["id"] not in settled_old: continue
    old_bal = sum(l["raw"] for l in dd["lines"]) - settled_old[dd["id"]]
    new_total = sum(l["amount"] + l["tax"] for l in dd["lines"])
    new_bal = round(new_total - alloc[dd["id"]], 2)
    if abs(old_bal) < 0.005 and new_bal != 0 and abs(new_bal) <= 0.05:
        last = dd["lines"][-1]; last["amount"] = round(last["amount"] - new_bal, 2)
        notes.append(f"{dd['t']} {dd['ref'] or '(no ref)'}: last line adjusted by {-new_bal:+.2f} so the settled invoice stays at zero balance")

# ---------- write SQL ----------
L = []
w = L.append
tot = lambda t: (sum(r["amount"] for r in sp if r["type"] == t), sum(r.get("tax", 0) for r in sp if r["type"] == t))
exp = {}
for t in ("Sale", "Purchase"): exp[t] = tot(t)
for t in PK:
    exp[t] = sum(p["amount"] for p in py if p["type"] == t)
w("-- Generated by scripts/make_import_sql.py from " + src.split("/")[-1])
w("-- Company: %s | period %s to %s" % (st["company"], st["start"], st["end"]))
w("-- Run ONCE on an empty database, in the Supabase SQL editor.   Step 1: edit the e-mail on the line marked EDIT.")
w("--")
w("-- Expected totals in the OLD app (exact):")
w("--   documents: %d (from %d rows)   payments: %d   set-off rows: %d   parties: %d   products: %d" % (len(docs), len(sp), len(py), len(alloc_rows), len(parties), len(J["products"])))
for t in ("Sale", "Purchase"): w("--   %-17s amount %.4f   tax %.4f" % (t, *exp[t]))
for t in PK:
    if exp[t]: w("--   %-17s %.2f" % (t, exp[t]))
w("-- The imported figures are rounded to 2 decimals per line, so totals may differ by a few cents.")
w("-- Entries dated before the financial-year start stay in the database; reports ignore them just like the old app did.")
if notes:
    w("-- Changes made while converting:")
    for x in notes: w("--   * " + x)
w("")
w("begin;")
w("create temp table _cfg as select 'YOUR_LOGIN_EMAIL'::text as email;   -- EDIT: the e-mail you created under Authentication -> Users")
w("do $$ begin if not exists (select 1 from auth.users u join _cfg c on lower(u.email) = lower(c.email)) then raise exception 'No Supabase user with that e-mail. Create the user first and edit the EDIT line.'; end if; end $$;")
w("")
w("insert into companies (id, name, currency, period_start, period_end, opening_stock, closing_stock, income_tax_rate, turnover_tax_rate) values (%s, %s, %s, %s, %s, %s, %s, %s, %s);" % (
  q(CID), q(st["company"]), q(st.get("currency", "LKR")), d(st["start"]), d(st["end"]), n(st.get("openingStock", 0)), n(st.get("closingStock", 0)), st.get("taxRate", 0.3), st.get("turnoverTaxRate", 0)))
w("insert into company_members (company_id, user_id, role) select %s, u.id, 'owner' from auth.users u join _cfg c on lower(u.email) = lower(c.email);" % q(CID))
for k, v in (("invoice_address", "invAddress"), ("invoice_bank", "invBank"), ("invoice_terms", "invTerms")):
    if st.get(v): w("update companies set %s = %s where id = %s;" % (k, q(st[v]), q(CID)))
w("")
w("insert into categories (id, company_id, grp, name, sort_order) values")
w(",\n".join("(%s, %s, %s, %s, %d)" % (q(i), q(CID), q(g), q(nm), so) for i, g, nm, so in catrows) + ";")
w("insert into parties (id, company_id, kind, name, phone, email, address, notes) values")
w(",\n".join("(%s, %s, %s, %s, %s, %s, %s, %s)" % (q(i), q(CID), q(k), q(nm), q(ph), q(em), q(ad), q(no)) for i, k, nm, ph, em, ad, no in parties) + ";")
prod = []
for p in J["products"]:
    cid_, _ = find_cat((p.get("code") + " – " if p.get("code") else "") + p["name"], ["sales"]) if p.get("code") else find_cat(p["name"], ["sales"])
    prod.append("(%s, %s, %s, %s, %s, %s, %s)" % (q(U("product", p["name"], p.get("code", ""))), q(CID), q(p.get("code", "")), q(p["name"]), q(p.get("category", "")), n(p.get("rate", 0) or 0), q(cid_) if cid_ else "null"))
w("insert into products (id, company_id, code, name, group_name, rate, category_id) values")
w(",\n".join(prod) + ";")
w("")
dv, lv, itype_n = [], [], 0
for dd in docs:
    kind = KIND[dd["t"]]; side = "customer" if kind.startswith("sale") or kind == "sales_return" else "supplier"
    pi = party(side, dd["party"]); it = "null"
    if kind == "sale" and all((r.get("itype") or r.get("desc", "")).strip().lower() == "cash" for r in dd["rows"]): it = "'cash'"; itype_n += 1
    elif kind == "sale" and dd["rows"][0].get("itype"): it = q(dd["rows"][0]["itype"].lower())
    f = dd["rows"][0]
    dv.append("(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % (q(dd["id"]), q(CID), q(kind), d(dd["date"]), q(dd["ref"]), q(pi) if pi else "null", q(dd["party"]), it,
              f.get("disc") or 0, 0, q(f.get("cdet", ""))))
    for i, l in enumerate(dd["lines"], 1):
        r = l["r"]; cid_, cname = find_cat(r.get("cat"), ["sales"] if kind.startswith("sale") or kind == "sales_return" else ["purchase"])
        lv.append("(%s, %s, %s, %d, %s, %s, %s, %s, %s, %s, %s)" % (q(U("line", dd["id"], i)), q(dd["id"]), q(CID), i, q(cid_) if cid_ else "null", q(cname), q(r.get("desc", "")),
                  r.get("qty") or "null", r.get("price") or "null", n(l["amount"]), n(l["tax"])))
# parties created on the fly must be inserted too -> re-emit party insert for the extras
extra = [p for p in parties if p[0] not in {x[0] for x in parties[:len(J["customers"]) + len(J["suppliers"])]}]
if extra:
    w("insert into parties (id, company_id, kind, name, phone, email, address, notes) values")
    w(",\n".join("(%s, %s, %s, %s, '', '', '', '')" % (q(i), q(CID), q(k), q(nm)) for i, k, nm, *_ in extra) + ";")
w("insert into trade_documents (id, company_id, kind, doc_date, ref, party_id, party_name, invoice_type, discount_pct, tax_pct, customer_details) values")
w(",\n".join(dv) + ";")
w("insert into trade_lines (id, document_id, company_id, line_no, category_id, category, description, qty, unit_price, amount, tax) values")
w(",\n".join(lv) + ";")
w("")
pv = []
for p in py:
    kind = PK[p["type"]]; side = "supplier" if kind == "supplier_payment" else "customer"
    pi = party(side, p.get("party")) if kind in ("customer_receipt", "supplier_payment") else None
    cid_, cname = (find_cat(p.get("cat"), CATG[kind]) if kind in CATG else (None, ""))
    pv.append("(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % (q(U("payment", p["id"])), q(CID), q(kind), d(p["date"]), q(p.get("ref", "")), q(pi) if pi else "null", q(p.get("party", "")),
              q(p.get("desc", "")), q(cid_) if cid_ else "null", q(cname), q(p.get("mode", "Bank")), q(p.get("reference", "")), n(r2(p["amount"]))))
w("insert into payments (id, company_id, kind, pay_date, ref, party_id, party_name, description, category_id, category, mode, reference, amount) values")
w(",\n".join(pv) + ";")
w("insert into payment_allocations (payment_id, document_id, company_id, amount) values")
w(",\n".join("(%s, %s, %s, %s)" % (q(a), q(b), q(CID), n(c)) for a, b, c in alloc_rows) + ";")
w("")
w("-- Check: compare with the expected totals at the top of this file")
w("select 'documents' as item, count(*)::numeric as value from trade_documents union all select 'lines', count(*) from trade_lines")
w(" union all select 'sales amount', coalesce(sum(l.amount),0) from trade_lines l join trade_documents d on d.id=l.document_id where d.kind='sale'")
w(" union all select 'sales tax', coalesce(sum(l.tax),0) from trade_lines l join trade_documents d on d.id=l.document_id where d.kind='sale'")
w(" union all select 'purchases amount', coalesce(sum(l.amount),0) from trade_lines l join trade_documents d on d.id=l.document_id where d.kind='purchase'")
w(" union all select 'receipts', coalesce(sum(amount),0) from payments where kind='customer_receipt' union all select 'supplier payments', coalesce(sum(amount),0) from payments where kind='supplier_payment'")
w(" union all select 'expenses', coalesce(sum(amount),0) from payments where kind='expense' union all select 'set-offs', coalesce(sum(amount),0) from payment_allocations")
w(" union all select 'open sales invoices (balance)', coalesce(sum(balance),0) from open_documents where kind='sale';")
w("commit;")
open(out, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("written", out, "| documents", len(docs), "| cash-typed invoices", itype_n, "| notes", len(notes))
for x in notes: print(" -", x)
print("expected:", {k: (v if not isinstance(v, tuple) else tuple(round(a, 2) for a in v)) for k, v in exp.items()})
