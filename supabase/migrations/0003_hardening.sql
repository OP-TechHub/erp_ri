-- Round Island ERP – hardening on top of 0001/0002 (run third, before loading data).
--  * sales staff see only their own sale invoices, customers and sales categories (SPEC §4)
--  * cross-company integrity (composite foreign keys)
--  * set-off / credit-note checks, checked at COMMIT so an invoice can be saved header-then-lines
--  * reconcile_document(): port of reconcileInvoice() from the reference app
--  * next_invoice_no(): port of invNext()
--  * audit_log for every delete, last-owner protection, rename propagation
--  * party_totals / party_credits views behind the Customers / Suppliers balances
set search_path = round_island, public;

-- =====================================================================================
-- 1. Column rules
-- =====================================================================================
-- 0.125 % turnover tax needs five decimals
alter table companies
  alter column income_tax_rate   type numeric(7,5),
  alter column turnover_tax_rate type numeric(7,5),
  add constraint companies_rates_range check (income_tax_rate between 0 and 1 and turnover_tax_rate between 0 and 1);

alter table trade_documents
  alter column party_id set not null,                 -- unknown names are created as parties (invoice form / importers)
  add constraint trade_documents_against_kind check (against_id is null or kind in ('sales_return', 'purchase_return')),
  add constraint trade_documents_itype_kind   check (invoice_type is null or kind = 'sale');

alter table payments
  add constraint payments_party_required check (kind not in ('customer_receipt', 'supplier_payment') or party_id is not null);

-- Sale numbers are unique per company. Bill numbers come from suppliers, so they are unique per supplier only.
drop index trade_documents_ref_unique;
create unique index trade_documents_sales_ref_unique on trade_documents (company_id, kind, lower(btrim(ref)))
  where btrim(ref) <> '' and kind in ('sale', 'sales_return');
create unique index trade_documents_purchase_ref_unique on trade_documents (company_id, kind, party_id, lower(btrim(ref)))
  where btrim(ref) <> '' and kind in ('purchase', 'purchase_return');

create index trade_documents_against on trade_documents (against_id) where against_id is not null;
create index trade_documents_party   on trade_documents (party_id);
create index trade_lines_document    on trade_lines (document_id);
create index payments_party          on payments (party_id);
create index payment_allocations_doc on payment_allocations (document_id);

-- =====================================================================================
-- 2. Cross-company integrity: every reference must stay inside the same company
-- =====================================================================================
alter table parties         add constraint parties_id_company         unique (id, company_id);
alter table categories      add constraint categories_id_company      unique (id, company_id);
alter table trade_documents add constraint trade_documents_id_company unique (id, company_id);
alter table payments        add constraint payments_id_company        unique (id, company_id);

alter table trade_documents     drop constraint trade_documents_party_id_fkey,
                                drop constraint trade_documents_against_id_fkey;
alter table trade_lines         drop constraint trade_lines_document_id_fkey,
                                drop constraint trade_lines_category_id_fkey;
alter table payments            drop constraint payments_party_id_fkey,
                                drop constraint payments_category_id_fkey;
alter table payment_allocations drop constraint payment_allocations_payment_id_fkey,
                                drop constraint payment_allocations_document_id_fkey;
alter table products            drop constraint products_category_id_fkey;

-- A party with entries can't be deleted (as in the reference). A deleted category leaves the snapshot name on
-- the entries ("not in category list"), so only category_id is cleared.
alter table trade_documents
  add constraint trade_documents_party_fk   foreign key (party_id, company_id)   references parties (id, company_id),
  add constraint trade_documents_against_fk foreign key (against_id, company_id) references trade_documents (id, company_id) on delete set null (against_id);
alter table trade_lines
  add constraint trade_lines_document_fk foreign key (document_id, company_id) references trade_documents (id, company_id) on delete cascade,
  add constraint trade_lines_category_fk foreign key (category_id, company_id) references categories (id, company_id) on delete set null (category_id);
alter table payments
  add constraint payments_party_fk    foreign key (party_id, company_id)    references parties (id, company_id),
  add constraint payments_category_fk foreign key (category_id, company_id) references categories (id, company_id) on delete set null (category_id);
alter table payment_allocations
  add constraint payment_allocations_payment_fk  foreign key (payment_id, company_id)  references payments (id, company_id) on delete cascade,
  add constraint payment_allocations_document_fk foreign key (document_id, company_id) references trade_documents (id, company_id) on delete cascade;
alter table products
  add constraint products_category_fk foreign key (category_id, company_id) references categories (id, company_id) on delete set null (category_id);

-- =====================================================================================
-- 3. Document money helpers (security definer: the checks must see rows the caller's RLS hides)
-- =====================================================================================
create or replace function doc_total(did uuid) returns numeric
language sql stable security definer set search_path = round_island, public as $$
  select coalesce(sum(amount + tax), 0) from trade_lines where document_id = did;
$$;

-- set off by receipts / payments + credit notes linked to it  (= settledMap in the reference)
create or replace function doc_settled(did uuid) returns numeric
language sql stable security definer set search_path = round_island, public as $$
  select coalesce((select sum(amount) from payment_allocations where document_id = did), 0)
       + coalesce((select sum(doc_total(n.id)) from trade_documents n where n.against_id = did), 0);
$$;

create or replace function original_kind(k doc_kind) returns doc_kind
language sql immutable as $$
  select case k when 'sales_return' then 'sale'::doc_kind when 'purchase_return' then 'purchase'::doc_kind end;
$$;

-- =====================================================================================
-- 4. Set-off and credit-note checks (deferred to COMMIT)
-- =====================================================================================
create or replace function assert_document_ok(did uuid) returns void
language plpgsql stable security definer set search_path = round_island, public as $$
declare d trade_documents; t trade_documents; s numeric; tot numeric;
begin
  select * into d from trade_documents where id = did;
  if not found then return; end if;                                   -- deleted in this transaction
  if d.kind in ('sale', 'purchase') then
    s := doc_settled(did); tot := doc_total(did);
    if s > tot + 0.005 then
      raise exception 'Set-offs and credit notes (%) exceed the total (%) of % %', s, tot, d.kind, nullif(d.ref, '')
        using hint = 'Reduce the set-offs first, or call reconcile_document().';
    end if;
  elsif d.against_id is not null then
    select * into t from trade_documents where id = d.against_id;
    if t.kind is distinct from original_kind(d.kind) then
      raise exception 'A % can only be linked to a %', d.kind, original_kind(d.kind);
    end if;
    if t.party_id is distinct from d.party_id then
      raise exception 'Credit note % and document % belong to different parties', nullif(d.ref, ''), nullif(t.ref, '');
    end if;
    perform assert_document_ok(t.id);
  end if;
end $$;

create or replace function assert_payment_ok(pid uuid) returns void
language plpgsql stable security definer set search_path = round_island, public as $$
declare p payments; a numeric; bad text;
begin
  select * into p from payments where id = pid;
  if not found then return; end if;
  select coalesce(sum(amount), 0) into a from payment_allocations where payment_id = pid;
  if a = 0 then return; end if;
  if p.kind not in ('customer_receipt', 'supplier_payment') then
    raise exception 'Only customer receipts and supplier payments can be set off against documents';
  end if;
  if a > p.amount + 0.005 then
    raise exception 'Set-offs (%) exceed the % amount (%)', a, p.kind, p.amount;
  end if;
  select coalesce(nullif(d.ref, ''), d.id::text) into bad
  from payment_allocations x join trade_documents d on d.id = x.document_id
  where x.payment_id = pid
    and (d.kind <> case p.kind when 'customer_receipt' then 'sale'::doc_kind else 'purchase'::doc_kind end
         or d.party_id is distinct from p.party_id)
  limit 1;
  if bad is not null then
    raise exception 'Document % is not an open % of this party', bad,
      case p.kind when 'customer_receipt' then 'sale invoice' else 'purchase bill' end;
  end if;
end $$;

create or replace function check_trade_integrity() returns trigger
language plpgsql security definer set search_path = round_island, public as $$
begin
  if tg_table_name = 'trade_lines' then
    perform assert_document_ok(coalesce(new.document_id, old.document_id));
    if tg_op = 'UPDATE' and new.document_id <> old.document_id then perform assert_document_ok(old.document_id); end if;
  elsif tg_table_name = 'trade_documents' then
    if tg_op <> 'DELETE' then perform assert_document_ok(new.id); end if;
    if tg_op = 'UPDATE' and old.against_id is not null then perform assert_document_ok(old.against_id); end if;
  elsif tg_table_name = 'payment_allocations' then
    perform assert_document_ok(coalesce(new.document_id, old.document_id));
    perform assert_payment_ok(coalesce(new.payment_id, old.payment_id));
  elsif tg_table_name = 'payments' then
    if tg_op <> 'DELETE' then perform assert_payment_ok(new.id); end if;
  end if;
  return null;
end $$;

create constraint trigger trade_lines_integrity after insert or update or delete on trade_lines
  deferrable initially deferred for each row execute function check_trade_integrity();
create constraint trigger trade_documents_integrity after insert or update on trade_documents
  deferrable initially deferred for each row execute function check_trade_integrity();
create constraint trigger payment_allocations_integrity after insert or update or delete on payment_allocations
  deferrable initially deferred for each row execute function check_trade_integrity();
create constraint trigger payments_integrity after update on payments
  deferrable initially deferred for each row execute function check_trade_integrity();

-- =====================================================================================
-- 5. Reconcile after an edit (reconcileInvoice in the reference)
-- =====================================================================================
-- Party or type changed on an invoice/bill -> its set-offs go back on account and linked notes are unlinked.
-- Party or type changed on a credit note -> unlinked if its document no longer matches.
create or replace function on_document_party_change() returns trigger
language plpgsql security definer set search_path = round_island, public as $$
declare t trade_documents;
begin
  if old.party_id is distinct from new.party_id or old.kind <> new.kind then
    if old.kind in ('sale', 'purchase') then
      delete from payment_allocations where document_id = old.id;
      update trade_documents set against_id = null where against_id = old.id;
    end if;
    if new.against_id is not null then
      select * into t from trade_documents where id = new.against_id;
      if t.kind is distinct from original_kind(new.kind) or t.party_id is distinct from new.party_id then
        new.against_id := null;
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger trade_documents_party_change before update of party_id, kind on trade_documents
  for each row execute function on_document_party_change();

-- Call after saving an edited document (same transaction). Returns what was changed, for the UI message.
--  invoice/bill: if set-offs now exceed the total, cut allocations from the newest receipt back, then unlink the newest notes
--  credit note : unlinked if it is now larger than the balance of its document
create or replace function reconcile_document(did uuid) returns text[]
language plpgsql security definer set search_path = round_island, public as $$
declare d trade_documents; t trade_documents; excess numeric; cut numeric; r record; msgs text[] := '{}';
begin
  select * into d from trade_documents where id = did;
  if not found then return msgs; end if;
  if not (has_role(d.company_id, array['owner', 'accountant']::member_role[])
          or (d.kind = 'sale' and d.created_by = auth.uid() and has_role(d.company_id, array['sales']::member_role[]))) then
    raise exception 'not allowed';
  end if;

  if d.kind in ('sale', 'purchase') then
    excess := round(doc_settled(did) - doc_total(did), 2);
    if excess > 0.005 then
      for r in select a.payment_id, a.amount from payment_allocations a join payments p on p.id = a.payment_id
               where a.document_id = did order by p.pay_date desc, p.created_at desc loop
        exit when excess <= 0.005;
        cut := least(r.amount, excess);
        if r.amount - cut <= 0.005 then
          delete from payment_allocations where payment_id = r.payment_id and document_id = did;
        else
          update payment_allocations set amount = round(r.amount - cut, 2) where payment_id = r.payment_id and document_id = did;
        end if;
        excess := round(excess - cut, 2);
      end loop;
      for r in select id from trade_documents where against_id = did order by doc_date desc, created_at desc loop
        exit when excess <= 0.005;
        excess := round(excess - doc_total(r.id), 2);
        update trade_documents set against_id = null where id = r.id;
      end loop;
      msgs := array_append(msgs, 'set-offs were reduced to fit the new invoice total');
    end if;
  elsif d.against_id is not null then
    select * into t from trade_documents where id = d.against_id;
    -- balance of the document without this note
    if doc_total(did) > doc_total(t.id) - (doc_settled(t.id) - doc_total(did)) + 0.005 then
      update trade_documents set against_id = null where id = did;
      msgs := array_append(msgs, 'note is larger than the invoice balance, so it was unlinked');
    end if;
  end if;
  return msgs;
end $$;

-- =====================================================================================
-- 6. Invoice numbers (invNext): "INV" + (highest INVnnnn among sale numbers + 1), at least 5 digits.
--    Plain numbers from the old app (e.g. 1531) don't count, exactly as in the reference.
--    Sales staff can't see other users' invoices, hence security definer.
-- =====================================================================================
create or replace function next_invoice_no(cid uuid) returns text
language plpgsql stable security definer set search_path = round_island, public as $$
declare mx numeric; w int; nxt text;
begin
  if not is_member(cid) then raise exception 'not allowed'; end if;
  select coalesce(max(m[1]::numeric), 0), greatest(5, coalesce(max(length(m[1])), 0)) into mx, w
  from (select regexp_match(btrim(ref), '^INV(\d+)$', 'i') as m from trade_documents where company_id = cid and kind = 'sale') x
  where m is not null;
  nxt := (mx + 1)::text;
  return 'INV' || lpad(nxt, greatest(w, length(nxt)), '0');
end $$;

-- =====================================================================================
-- 7. Sales-role visibility (SPEC §4: no access to other users' data, payments, balances, suppliers)
--    The *_write / *_acct policies from 0001 are FOR ALL, so they already give accounts staff read access.
-- =====================================================================================
drop policy companies_read on companies;
create policy companies_read on companies for select using (has_role(id, array['owner', 'accountant']::member_role[]));

drop policy parties_read on parties;
create policy parties_read_sales on parties for select using (kind = 'customer' and has_role(company_id, array['sales']::member_role[]));

drop policy categories_read on categories;
create policy categories_read_sales on categories for select using (grp = 'sales' and has_role(company_id, array['sales']::member_role[]));
-- products_read (all members) stays: every product is a sales item

drop policy docs_read on trade_documents;
create policy docs_read_sales on trade_documents for select
  using (kind = 'sale' and created_by = auth.uid() and has_role(company_id, array['sales']::member_role[]));
drop policy docs_sales_ins on trade_documents;
create policy docs_sales_ins on trade_documents for insert
  with check (kind = 'sale' and created_by = auth.uid() and has_role(company_id, array['sales']::member_role[]));
drop policy docs_sales_upd on trade_documents;
create policy docs_sales_upd on trade_documents for update
  using      (kind = 'sale' and created_by = auth.uid() and has_role(company_id, array['sales']::member_role[]))
  with check (kind = 'sale' and created_by = auth.uid() and has_role(company_id, array['sales']::member_role[]) and against_id is null);
-- no delete policy for sales staff: only accounts staff delete invoices

drop policy lines_read on trade_lines;   -- lines_acct and lines_sales (own sale invoices) remain

-- What any member (incl. sales) may know about their companies: the invoice letterhead, never stock or tax rates.
create or replace function my_companies() returns table (company_id uuid, name text, role member_role)
language sql stable security definer set search_path = round_island, public as $$
  select c.id, c.name, m.role from company_members m join companies c on c.id = m.company_id
  where m.user_id = auth.uid() order by c.name;
$$;

create or replace function company_print_info(cid uuid)
returns table (name text, currency text, invoice_address text, invoice_bank text, invoice_terms text, logo_path text)
language plpgsql stable security definer set search_path = round_island, public as $$
begin
  if not is_member(cid) then raise exception 'not allowed'; end if;
  return query select c.name, c.currency, c.invoice_address, c.invoice_bank, c.invoice_terms, c.logo_path from companies c where c.id = cid;
end $$;

-- =====================================================================================
-- 8. Members (no service-role key in the app: owners add an existing login by e-mail)
--    auth.users is shared with other apps on this Supabase project – never delete users from it.
-- =====================================================================================
create or replace function member_list(cid uuid)
returns table (user_id uuid, email text, role member_role, created_at timestamptz)
language plpgsql stable security definer set search_path = round_island, public as $$
begin
  if not has_role(cid, array['owner']::member_role[]) then raise exception 'not allowed'; end if;
  return query select m.user_id, u.email::text, m.role, m.created_at
    from company_members m join auth.users u on u.id = m.user_id where m.company_id = cid order by u.email;
end $$;

create or replace function add_member_by_email(cid uuid, p_email text, p_role member_role) returns uuid
language plpgsql security definer set search_path = round_island, public as $$
declare uid uuid;
begin
  if not has_role(cid, array['owner']::member_role[]) then raise exception 'not allowed'; end if;
  select id into uid from auth.users where lower(email) = lower(btrim(p_email));
  if uid is null then
    raise exception 'No login with the e-mail %', p_email using hint = 'Create the user in Supabase (Authentication -> Users) first.';
  end if;
  insert into company_members (company_id, user_id, role) values (cid, uid, p_role)
    on conflict (company_id, user_id) do update set role = excluded.role;
  return uid;
end $$;

-- A company must keep at least one owner (cascades from deleting the company itself are allowed).
create or replace function keep_last_owner() returns trigger
language plpgsql security definer set search_path = round_island, public as $$
begin
  if old.role = 'owner' and (tg_op = 'DELETE' or new.role <> 'owner')
     and exists (select 1 from companies where id = old.company_id)
     and not exists (select 1 from company_members where company_id = old.company_id and role = 'owner' and user_id <> old.user_id) then
    raise exception 'A company needs at least one owner';
  end if;
  return coalesce(new, old);
end $$;
create trigger company_members_last_owner before update or delete on company_members
  for each row execute function keep_last_owner();

-- Company bootstrap is an admin task: run from the SQL editor, where there is no signed-in user.
-- (Round Island itself is created by supabase/data/import_data.sql instead.)
drop function create_company(text, date, date);
create or replace function create_company(p_name text, p_start date, p_end date, p_owner_email text) returns uuid
language plpgsql security definer set search_path = round_island, public as $$
declare cid uuid; uid uuid;
begin
  select id into uid from auth.users where lower(email) = lower(btrim(p_owner_email));
  if uid is null then raise exception 'No login with the e-mail %', p_owner_email; end if;
  insert into companies (name, period_start, period_end) values (p_name, p_start, p_end) returning id into cid;
  insert into company_members (company_id, user_id, role) values (cid, uid, 'owner');
  insert into categories (company_id, grp, name, sort_order)
  select cid, g::cat_group, n, row_number() over ()::int
  from (values
    ('sales','Product Sales'),('sales','Service Income'),
    ('purchase','Goods for Resale'),('purchase','Raw Materials'),('purchase','Packing Materials'),('purchase','Ingridients'),
    ('admin','Salaries & Wages'),('admin','EPF / ETF'),('admin','Rent'),('admin','Electricity & Water'),('admin','Telephone & Internet'),
    ('admin','Stationery & Office'),('admin','Repairs & Maintenance'),('admin','Depreciation'),('admin','Professional Fees'),('admin','Insurance'),
    ('selling','Advertising'),('selling','Transport & Delivery'),('selling','Sales Commission'),
    ('finance','Bank Interest'),('finance','Bank Charges'),
    ('other_income','Interest Income'),('other_income','Rental Income'),
    ('assets','Land & Buildings'),('assets','Plant & Machinery'),('assets','Furniture & Fittings'),('assets','Computers & Office Equipment'),('assets','Motor Vehicles'),('assets','Other Assets')
  ) v(g, n);
  return cid;
end $$;
revoke execute on function create_company(text, date, date, text) from public, anon, authenticated;

-- =====================================================================================
-- 9. Renames flow to past entries (as in the reference)
-- =====================================================================================
create or replace function propagate_party_name() returns trigger language plpgsql as $$
begin
  update trade_documents set party_name = new.name where party_id = new.id;
  update payments        set party_name = new.name where party_id = new.id;
  return null;
end $$;
create trigger parties_rename after update of name on parties
  for each row when (old.name is distinct from new.name) execute function propagate_party_name();

create or replace function propagate_category_name() returns trigger language plpgsql as $$
begin
  update trade_lines set category = new.name where category_id = new.id;
  update payments    set category = new.name where category_id = new.id;
  return null;
end $$;
create trigger categories_rename after update of name on categories
  for each row when (old.name is distinct from new.name) execute function propagate_category_name();

-- =====================================================================================
-- 10. Audit log: every deleted row is kept as JSON (CLAUDE.md rule 6)
-- =====================================================================================
create table audit_log (
  id         bigint generated always as identity primary key,
  company_id uuid not null,                      -- no FK: the log outlives what it records
  table_name text not null,
  row_id     text,
  action     text not null,
  row_data   jsonb not null,
  user_id    uuid default auth.uid(),
  at         timestamptz not null default now()
);
create index audit_log_company_at on audit_log (company_id, at desc);
alter table audit_log enable row level security;
create policy audit_log_read on audit_log for select using (has_role(company_id, array['owner', 'accountant']::member_role[]));
-- no insert/update/delete policies: rows are written only by the trigger below

create or replace function log_delete() returns trigger
language plpgsql security definer set search_path = round_island, public as $$
begin
  insert into audit_log (company_id, table_name, row_id, action, row_data)
  values (old.company_id, tg_table_name, to_jsonb(old) ->> 'id', 'delete', to_jsonb(old));
  return old;
end $$;
do $$ declare t text; begin
  foreach t in array array['trade_documents','trade_lines','payments','payment_allocations','parties','categories','products','deposit_slips'] loop
    execute format('create trigger %I_audit after delete on %I for each row execute function log_delete()', t, t);
  end loop;
end $$;

-- =====================================================================================
-- 11. Views behind party balances (security_invoker: the caller's RLS applies)
-- =====================================================================================
-- Customers / Suppliers screen: billed – returns – paid, all dates (partyTotals in the reference)
create view party_totals with (security_invoker = true) as
select p.id as party_id, p.company_id, p.kind, p.name,
       coalesce(d.billed, 0)  as billed,
       coalesce(d.returns, 0) as returns,
       coalesce(y.paid, 0)    as paid,
       coalesce(d.billed, 0) - coalesce(d.returns, 0) - coalesce(y.paid, 0) as outstanding
from parties p
left join (select party_id,
                  sum(total) filter (where kind in ('sale', 'purchase'))                as billed,
                  sum(total) filter (where kind in ('sales_return', 'purchase_return')) as returns
           from document_totals group by party_id) d on d.party_id = p.id
left join (select party_id, sum(amount) as paid from payments
           where kind in ('customer_receipt', 'supplier_payment') group by party_id) y on y.party_id = p.id;

-- Credits waiting to be applied (creditsOf in the reference): unallocated receipts/payments + unlinked credit notes
create view party_credits with (security_invoker = true) as
select party_id, company_id, sum(on_account) as on_account, sum(unlinked_notes) as unlinked_notes,
       sum(on_account) + sum(unlinked_notes) as credit
from (
  select p.party_id, p.company_id, p.amount - coalesce(sum(a.amount), 0) as on_account, 0::numeric as unlinked_notes
  from payments p left join payment_allocations a on a.payment_id = p.id
  where p.kind in ('customer_receipt', 'supplier_payment')
  group by p.id
  having p.amount - coalesce(sum(a.amount), 0) > 0.005
  union all
  select d.party_id, d.company_id, 0, d.total
  from document_totals d join trade_documents n on n.id = d.document_id
  where d.kind in ('sales_return', 'purchase_return') and n.against_id is null
) c
group by party_id, company_id;

-- new functions above: authenticated may call them (anon has no access to the schema)
grant execute on all functions in schema round_island to authenticated, service_role;
revoke execute on function create_company(text, date, date, text) from authenticated;
