-- Round Island ERP – link to the Cloud Kitchen app (schema cloud_kitchen, same database). Run after 0007.
-- Round Island and Cloud Kitchen are one business (owner, 2026-11-10):
--   Cloud Kitchen owns orders, invoices, items, customers, ingredients, recipes, stock and production;
--   the ERP owns the books. This migration makes the ERP follow Cloud Kitchen automatically:
--   * staff      -> company_members (ERP access follows CK Staff; see ck_member_role)
--   * customers  -> parties (customer)
--   * items      -> products + a sales category "code – name"
--   * invoices   -> one sale document + lines, and for invoices paid at once a customer receipt set off in full
--                   (same rules as CK's post_order_invoice)
-- Triggers never block Cloud Kitchen: if a copy fails, the error goes to ck_sync_errors and the CK action
-- still succeeds. Run ck_backfill() once to copy what already exists.
-- During the parallel run CK keeps its own books as well; nothing in cloud_kitchen is changed here.
set search_path = round_island, public;

-- =====================================================================================
-- 1. Structure
-- =====================================================================================
-- CK orders can have any number of items, so an invoice is no longer limited to 6 lines
alter table trade_lines drop constraint trade_lines_line_no_check;
alter table trade_lines add constraint trade_lines_line_no_check check (line_no >= 1);

alter table parties add column ck_customer_id uuid unique;
-- CK identifies customers by phone, so names can repeat; unique names only for customers created in the ERP
drop index parties_unique_name;
create unique index parties_unique_name on parties (company_id, kind, lower(btrim(name))) where ck_customer_id is null;

alter table products add column ck_item_id uuid unique;

alter table trade_documents
  add column ck_invoice_id uuid unique,
  add column source text not null default 'manual' check (source in ('manual', 'ck_invoice', 'migrated'));

alter table payments add column ck_invoice_id uuid unique;            -- receipt created with a CK invoice

alter table company_members add column managed_by_ck boolean not null default false;

-- Ingredients and recipes live in Cloud Kitchen: purchase lines point at cloud_kitchen.ingredients
alter table trade_lines drop constraint trade_lines_ingredient_fk;
drop table product_recipes;
drop table ingredients;
alter table trade_lines add constraint trade_lines_ingredient_fk foreign key (ingredient_id) references cloud_kitchen.ingredients (id);

-- =====================================================================================
-- 2. Helpers
-- =====================================================================================
-- The single Round Island company
create or replace function ri_company_id() returns uuid
language sql stable security definer set search_path = round_island, public as $$
  select id from companies order by created_at limit 1;
$$;

create or replace function ck_category(cid uuid, g cat_group, n text) returns uuid
language plpgsql security definer set search_path = round_island, public as $$
declare cat uuid;
begin
  insert into categories (company_id, grp, name) values (cid, g, n) on conflict (company_id, grp, lower(btrim(name))) do nothing;
  select id into cat from categories where company_id = cid and grp = g and lower(btrim(name)) = lower(btrim(n));
  return cat;
end $$;

create table ck_sync_errors (
  id        bigint generated always as identity primary key,
  at        timestamptz not null default now(),
  source    text not null,           -- staff / customer / item / invoice
  source_id uuid,
  message   text not null
);
alter table ck_sync_errors enable row level security;
create policy ck_sync_errors_read on ck_sync_errors for select
  using (has_role(ri_company_id(), array['owner', 'accountant']::member_role[]));

-- =====================================================================================
-- 3. Staff -> ERP access
-- =====================================================================================
-- approved CK staff with the Cloud Kitchen workspace; kitchen and dispatch get no ERP access
create or replace function ck_member_role(ck_role text) returns member_role
language sql immutable as $$
  select case ck_role
    when 'admin'        then 'owner'::member_role
    when 'accountant'   then 'accountant'::member_role
    when 'supply_chain' then 'purchasing'::member_role
    when 'sales'        then 'cashier'::member_role
    when 'manager'      then 'viewer'::member_role
    when 'executive'    then 'viewer'::member_role
  end;
$$;

create or replace function ck_sync_staff(p_user uuid) returns void
language plpgsql security definer set search_path = round_island, public as $$
declare cid uuid := ri_company_id(); s jsonb; r member_role;
begin
  if cid is null then return; end if;
  select to_jsonb(x) into s from cloud_kitchen.staff x where x.user_id = p_user;
  if s is not null and s ->> 'status' = 'approved' and coalesce(s -> 'workspaces' ? 'cloud_kitchen', true) then
    r := ck_member_role(s ->> 'role');
  end if;
  if r is null then
    delete from company_members where company_id = cid and user_id = p_user and managed_by_ck;
  else
    insert into company_members (company_id, user_id, role, managed_by_ck) values (cid, p_user, r, true)
      on conflict (company_id, user_id) do update set role = excluded.role, managed_by_ck = true;
  end if;
end $$;

-- =====================================================================================
-- 4. Customers and items
-- =====================================================================================
create or replace function ck_sync_customer(p_id uuid) returns uuid
language plpgsql security definer set search_path = round_island, public as $$
declare cid uuid := ri_company_id(); c jsonb; pid uuid;
begin
  if cid is null then raise exception 'No company in round_island.companies'; end if;
  select to_jsonb(x) into c from cloud_kitchen.customers x where x.id = p_id;
  if c is null then raise exception 'Cloud Kitchen customer % not found', p_id; end if;
  update parties set name = c ->> 'name', phone = coalesce(c ->> 'contact_1', ''), address = coalesce(c ->> 'default_address', ''),
                     email = coalesce(c ->> 'email', ''), notes = coalesce(c ->> 'notes', '')
   where ck_customer_id = p_id
  returning id into pid;
  if pid is null then
    insert into parties (company_id, kind, name, phone, address, email, notes, ck_customer_id)
    values (cid, 'customer', c ->> 'name', coalesce(c ->> 'contact_1', ''), coalesce(c ->> 'default_address', ''),
            coalesce(c ->> 'email', ''), coalesce(c ->> 'notes', ''), p_id)
    returning id into pid;
  end if;
  return pid;
end $$;

create or replace function ck_sync_item(p_id uuid) returns uuid
language plpgsql security definer set search_path = round_island, public as $$
declare cid uuid := ri_company_id(); i cloud_kitchen.items; label text; pid uuid; old_cat uuid;
begin
  if cid is null then raise exception 'No company in round_island.companies'; end if;
  select * into i from cloud_kitchen.items where id = p_id;
  if not found then raise exception 'Cloud Kitchen item % not found', p_id; end if;
  label := i.code || ' – ' || i.name;                                -- like prodLabel in the reference app
  select id, category_id into pid, old_cat from products where ck_item_id = p_id;
  if pid is null then                                                -- adopt an ERP item with the same code, if any
    select id, category_id into pid, old_cat from products where company_id = cid and code = i.code and ck_item_id is null;
  end if;
  if old_cat is not null then                                        -- renamed in CK: rename its category (and past lines)
    update categories set name = label where id = old_cat and name <> label;
  end if;
  if pid is null then
    insert into products (company_id, code, name, group_name, rate, pack_weight_g, active, category_id, ck_item_id)
    values (cid, i.code, i.name, coalesce(i.category, ''), i.price, i.pack_weight_g, i.is_available, ck_category(cid, 'sales', label), p_id)
    returning id into pid;
  else
    update products set code = i.code, name = i.name, group_name = coalesce(i.category, ''), rate = i.price,
                        pack_weight_g = i.pack_weight_g, active = i.is_available, ck_item_id = p_id,
                        category_id = coalesce(old_cat, ck_category(cid, 'sales', label))
     where id = pid;
  end if;
  return pid;
end $$;

-- =====================================================================================
-- 5. Invoices (mirrors cloud_kitchen.post_order_invoice)
-- =====================================================================================
create or replace function ck_post_invoice(p_invoice_id uuid) returns uuid
language plpgsql security definer set search_path = round_island, public as $$
declare
  cid uuid := ri_company_id();
  v cloud_kitchen.invoices; o cloud_kitchen.orders; r record;
  d_id uuid; p_id uuid; party uuid; party_name text; prod uuid; cat uuid; cat_name text; del uuid;
  n int := 0; n_items int; net numeric; sum_amt numeric := 0; amt numeric; total numeric;
  method text; itype invoice_type; mode text;
begin
  if cid is null then raise exception 'No company in round_island.companies'; end if;
  select id into d_id from trade_documents where ck_invoice_id = p_invoice_id;
  if found then return d_id; end if;                                 -- already copied
  select * into v from cloud_kitchen.invoices where id = p_invoice_id;
  if not found then raise exception 'Cloud Kitchen invoice % not found', p_invoice_id; end if;
  select * into o from cloud_kitchen.orders where id = v.order_id;
  party := ck_sync_customer(o.customer_id);
  select name into party_name from parties where id = party;
  method := v.payment_method::text;
  itype := case method when 'card' then 'card' when 'online_transfer' then 'online' when 'credit' then 'credit' else 'cash' end;
  mode  := case method when 'card' then 'Card' when 'online_transfer' then 'Online' else 'Cash' end;

  insert into trade_documents (company_id, kind, doc_date, ref, party_id, party_name, invoice_type, discount_pct, tax_pct,
                               customer_details, order_source, notes, ck_invoice_id, source, created_by)
  values (cid, 'sale', v.invoice_date, v.invoice_no, party, coalesce(party_name, v.customer_name), itype, v.discount_pct, 0,
          concat_ws(E'\n', nullif(btrim(coalesce(v.delivery_address, '')), ''), nullif(btrim(coalesce(v.contact_1, '')), '')),
          case when o.source::text in ('walk_in', 'call', 'whatsapp', 'website') then o.source::text::order_source end,
          'Order ' || o.order_no, v.id, 'ck_invoice', v.created_by)
  returning id into d_id;

  -- items: the discount is spread over the lines; the last line takes the rounding so the lines add up exactly
  net := v.subtotal - v.discount_amount;
  select count(*) into n_items from cloud_kitchen.order_items where order_id = o.id;
  for r in select oi.*, row_number() over (order by oi.item_name, oi.id) as rn
             from cloud_kitchen.order_items oi where oi.order_id = o.id order by oi.item_name, oi.id loop
    n := n + 1;
    amt := case when r.rn = n_items then round(net - sum_amt, 2) else round(r.line_total * (1 - v.discount_pct / 100), 2) end;
    sum_amt := sum_amt + amt;
    prod := ck_sync_item(r.item_id);
    select c.id, c.name into cat, cat_name from products p join categories c on c.id = p.category_id where p.id = prod;
    insert into trade_lines (document_id, company_id, line_no, category_id, category, description, qty, unit, price_mode, unit_price, amount, tax)
    values (d_id, cid, n, cat, coalesce(cat_name, 'Product Sales'), r.item_name, r.qty,
            case when r.sold_by = 'kg' then 'kg'::line_unit else 'pack'::line_unit end,
            case when r.sold_by = 'kg' then 'free'::price_mode else 'fixed'::price_mode end,
            r.unit_price, amt, 0);
  end loop;
  if v.delivery_fee > 0 then                                         -- the discount never applies to delivery
    n := n + 1;
    del := ck_category(cid, 'sales', 'Delivery Charges');
    insert into trade_lines (document_id, company_id, line_no, category_id, category, description, qty, unit_price, amount, tax)
    values (d_id, cid, n, del, 'Delivery Charges', 'Delivery', 1, v.delivery_fee, v.delivery_fee, 0);
  end if;

  -- paid with the order (cash, transfer, card): receipt set off in full; credit: stays open in receivables
  total := doc_total(d_id);
  if total > 0 and method <> 'credit' then
    insert into payments (company_id, kind, pay_date, ref, party_id, party_name, description, mode, reference, amount, ck_invoice_id, created_by)
    values (cid, 'customer_receipt', v.invoice_date, v.invoice_no, party, coalesce(party_name, v.customer_name),
            'Paid with order ' || o.order_no, mode, coalesce(v.payment_ref, ''), total, v.id, v.created_by)
    returning id into p_id;
    insert into payment_allocations (payment_id, document_id, company_id, amount) values (p_id, d_id, cid, total);
  end if;
  return d_id;
end $$;

-- =====================================================================================
-- 6. Triggers on Cloud Kitchen tables (errors are logged, never passed back to CK)
-- =====================================================================================
create or replace function ck_log(p_source text, p_id uuid, p_msg text) returns void
language sql security definer set search_path = round_island, public as $$
  insert into ck_sync_errors (source, source_id, message) values (p_source, p_id, p_msg);
$$;

create or replace function ck_on_staff() returns trigger
language plpgsql security definer set search_path = round_island, public as $$
declare u uuid := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
begin
  begin perform ck_sync_staff(u);
  exception when others then perform ck_log('staff', u, sqlerrm); end;
  return null;
end $$;

create or replace function ck_on_customer() returns trigger
language plpgsql security definer set search_path = round_island, public as $$
begin
  begin perform ck_sync_customer(new.id);
  exception when others then perform ck_log('customer', new.id, sqlerrm); end;
  return null;
end $$;

create or replace function ck_on_item() returns trigger
language plpgsql security definer set search_path = round_island, public as $$
begin
  begin perform ck_sync_item(new.id);
  exception when others then perform ck_log('item', new.id, sqlerrm); end;
  return null;
end $$;

create or replace function ck_on_invoice() returns trigger
language plpgsql security definer set search_path = round_island, public as $$
begin
  begin perform ck_post_invoice(new.id);
  exception when others then perform ck_log('invoice', new.id, sqlerrm); end;
  return null;
end $$;

create trigger ri_sync_staff     after insert or update or delete on cloud_kitchen.staff     for each row execute function ck_on_staff();
create trigger ri_sync_customers after insert or update on cloud_kitchen.customers           for each row execute function ck_on_customer();
create trigger ri_sync_items     after insert or update on cloud_kitchen.items               for each row execute function ck_on_item();
create trigger ri_sync_invoices  after insert on cloud_kitchen.invoices                      for each row execute function ck_on_invoice();

-- =====================================================================================
-- 7. One-off backfill and the parallel-run check (SQL editor only)
-- =====================================================================================
create or replace function ck_backfill() returns table (what text, copied int, failed int)
language plpgsql security definer set search_path = round_island, public as $$
declare r record; ok int; bad int;
begin
  ok := 0; bad := 0;
  for r in select user_id from cloud_kitchen.staff loop
    begin perform ck_sync_staff(r.user_id); ok := ok + 1;
    exception when others then perform ck_log('staff', r.user_id, sqlerrm); bad := bad + 1; end;
  end loop;
  what := 'staff'; copied := ok; failed := bad; return next;

  ok := 0; bad := 0;
  for r in select id from cloud_kitchen.customers loop
    begin perform ck_sync_customer(r.id); ok := ok + 1;
    exception when others then perform ck_log('customer', r.id, sqlerrm); bad := bad + 1; end;
  end loop;
  what := 'customers'; copied := ok; failed := bad; return next;

  ok := 0; bad := 0;
  for r in select id from cloud_kitchen.items loop
    begin perform ck_sync_item(r.id); ok := ok + 1;
    exception when others then perform ck_log('item', r.id, sqlerrm); bad := bad + 1; end;
  end loop;
  what := 'items'; copied := ok; failed := bad; return next;

  ok := 0; bad := 0;
  for r in select id from cloud_kitchen.invoices order by invoice_date, invoice_no loop
    begin perform ck_post_invoice(r.id); ok := ok + 1;
    exception when others then perform ck_log('invoice', r.id, sqlerrm); bad := bad + 1; end;
  end loop;
  what := 'invoices'; copied := ok; failed := bad; return next;
end $$;

-- every CK invoice must have its ERP copy with the same total
create view ck_sync_check as
select 'CK invoices' as item, count(*)::numeric as value from cloud_kitchen.invoices
union all select 'ERP copies', count(*) from trade_documents where source = 'ck_invoice'
union all select 'missing in ERP', count(*) from cloud_kitchen.invoices i where not exists (select 1 from trade_documents d where d.ck_invoice_id = i.id)
union all select 'total differs', count(*) from cloud_kitchen.invoices i join trade_documents d on d.ck_invoice_id = i.id where abs(doc_total(d.id) - i.total) > 0.005
union all select 'CK invoiced total', coalesce(sum(total), 0) from cloud_kitchen.invoices
union all select 'ERP copied total', coalesce(sum(doc_total(id)), 0) from trade_documents where source = 'ck_invoice'
union all select 'sync errors', count(*) from ck_sync_errors;

-- These run as admin only (SQL editor) or from triggers – not callable through the API
-- (ri_company_id stays callable: the ck_sync_errors read policy uses it)
revoke execute on function ck_category(uuid, cat_group, text), ck_member_role(text), ck_sync_staff(uuid),
  ck_sync_customer(uuid), ck_sync_item(uuid), ck_post_invoice(uuid), ck_log(text, uuid, text), ck_on_staff(), ck_on_customer(),
  ck_on_item(), ck_on_invoice(), ck_backfill() from public, anon, authenticated;
revoke all on ck_sync_check from anon, authenticated;
