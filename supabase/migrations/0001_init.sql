-- Round Island ERP – initial schema (Supabase / Postgres)
-- Paste into the Supabase SQL editor (migrations 0001, 0002, 0003 in that order).
-- Money columns are numeric(14,2). Every business table carries company_id and is protected by RLS.
-- The Supabase project is shared with other apps, so everything lives in its own schema "round_island".
-- Add round_island to Project Settings -> API -> Exposed schemas after running this.

create schema if not exists round_island;
set search_path = round_island, public;

-- ---------- enums ----------
create type member_role   as enum ('owner', 'accountant', 'sales');
create type party_kind    as enum ('customer', 'supplier');
create type doc_kind      as enum ('sale', 'sales_return', 'purchase', 'purchase_return');
create type invoice_type  as enum ('cash', 'credit', 'card', 'sample', 'foc');
create type payment_kind  as enum ('expense', 'other_income', 'asset_purchase', 'income_tax', 'turnover_tax', 'customer_receipt', 'supplier_payment');
create type cat_group     as enum ('sales', 'purchase', 'admin', 'selling', 'finance', 'other_income', 'assets');

-- ---------- companies & access ----------
create table companies (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  currency         text not null default 'LKR',
  period_start     date not null,
  period_end       date not null,
  opening_stock    numeric(14,2) not null default 0,
  closing_stock    numeric(14,2) not null default 0,
  income_tax_rate  numeric(6,4) not null default 0.30,      -- 0.30 = 30 %
  turnover_tax_rate numeric(6,4) not null default 0,
  invoice_address  text not null default E'NO 532/4F SIRIKOTHA LANE,\nCOLOMBO - 03',
  invoice_bank     text not null default E'Company Name: Round Island (Pvt) Ltd\nBank Name: Amana Bank\nBranch: Main Branch, Colombo 03\nAccount Number: 0010259175001\nSWIFT/BIC Code: AMNALKLX',
  invoice_terms    text not null default E'Cheque should be drawn in favour to "Round Island Pvt Ltd"\nNo Credit',
  logo_path        text,                                     -- Storage object path (bucket "company-assets")
  created_at       timestamptz not null default now(),
  check (period_start <= period_end)
);

create table company_members (
  company_id uuid not null references companies(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       member_role not null default 'sales',
  created_at timestamptz not null default now(),
  primary key (company_id, user_id)
);

-- helper functions used by every policy (security definer so they bypass RLS on company_members)
create or replace function is_member(cid uuid) returns boolean
language sql stable security definer set search_path = round_island, public as $$
  select exists (select 1 from company_members where company_id = cid and user_id = auth.uid());
$$;
create or replace function has_role(cid uuid, roles member_role[]) returns boolean
language sql stable security definer set search_path = round_island, public as $$
  select exists (select 1 from company_members where company_id = cid and user_id = auth.uid() and role = any(roles));
$$;

-- ---------- master data ----------
create table parties (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  kind       party_kind not null,
  name       text not null,
  phone      text not null default '',
  email      text not null default '',
  address    text not null default '',
  notes      text not null default '',
  created_at timestamptz not null default now()
);
create unique index parties_unique_name on parties (company_id, kind, lower(btrim(name)));

create table categories (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  grp        cat_group not null,           -- decides which P&L note the category appears under
  name       text not null,
  sort_order int not null default 0
);
create unique index categories_unique on categories (company_id, grp, lower(btrim(name)));

create table products (                    -- each product is also a "sales" category (category_id)
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  code        text not null default '',
  name        text not null,
  group_name  text not null default '',    -- e.g. Convenience Range / Marinated Fillets
  rate        numeric(14,2) not null default 0,   -- default unit price per kg
  category_id uuid references categories(id) on delete set null,
  active      boolean not null default true
);
create unique index products_unique on products (company_id, lower(btrim(code)), lower(btrim(name)));

-- ---------- sales & purchase documents (one header, 1..6 lines) ----------
create table trade_documents (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  kind             doc_kind not null,
  doc_date         date not null,
  ref              text not null,                      -- invoice / bill no, e.g. INV01611
  party_id         uuid references parties(id),
  party_name       text not null,                      -- snapshot, so history survives a rename
  invoice_type     invoice_type,                       -- sales only
  discount_pct     numeric(6,3) not null default 0 check (discount_pct >= 0 and discount_pct < 100),
  tax_pct          numeric(6,3) not null default 0 check (tax_pct >= 0),   -- VAT & SSCL
  customer_details text not null default '',           -- contact lines printed under the customer name
  against_id       uuid references trade_documents(id) on delete set null, -- credit / return note -> original document
  notes            text not null default '',
  created_by       uuid references auth.users(id) default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
-- numbers must be unique per kind; blank refs (old data only) are allowed to repeat
create unique index trade_documents_ref_unique on trade_documents (company_id, kind, lower(btrim(ref))) where btrim(ref) <> '';
create index trade_documents_date on trade_documents (company_id, doc_date);

create table trade_lines (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null references trade_documents(id) on delete cascade,
  company_id  uuid not null references companies(id) on delete cascade,
  line_no     int not null,
  category_id uuid references categories(id),
  category    text not null,                           -- snapshot of the category name
  description text not null default '',
  qty         numeric(14,3),                           -- kg
  unit_price  numeric(14,2),
  amount      numeric(14,2) not null check (amount >= 0),   -- net of discount, excluding tax
  tax         numeric(14,2) not null default 0 check (tax >= 0),
  unique (document_id, line_no),
  check (line_no between 1 and 6)
);

-- ---------- payments, receipts and set-offs ----------
create table payments (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  kind         payment_kind not null,
  pay_date     date not null,
  ref          text not null default '',
  party_id     uuid references parties(id),
  party_name   text not null default '',
  description  text not null default '',
  category_id  uuid references categories(id),
  category     text not null default '',
  mode         text not null default 'Bank',           -- Cash / Bank / Cheque ...
  reference    text not null default '',               -- cheque / transaction reference
  amount       numeric(14,2) not null check (amount > 0),
  created_by   uuid references auth.users(id) default auth.uid(),
  created_at   timestamptz not null default now()
);
create index payments_date on payments (company_id, pay_date);

-- set-off of a receipt / supplier payment against invoices or bills
create table payment_allocations (
  payment_id  uuid not null references payments(id) on delete cascade,
  document_id uuid not null references trade_documents(id) on delete cascade,
  company_id  uuid not null references companies(id) on delete cascade,
  amount      numeric(14,2) not null check (amount > 0),
  primary key (payment_id, document_id)
);

-- cash-sales deposit slips (PDF or photo) – file lives in Storage bucket "deposit-slips"
create table deposit_slips (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  slip_date    date not null,
  storage_path text not null,
  file_name    text not null,
  uploaded_by  uuid references auth.users(id) default auth.uid(),
  created_at   timestamptz not null default now(),
  unique (company_id, slip_date)
);

-- ---------- views used by reports ----------
-- document totals (security_invoker so RLS of the caller applies)
create view document_totals with (security_invoker = true) as
select d.id as document_id, d.company_id, d.kind, d.doc_date, d.ref, d.party_id, d.party_name, d.invoice_type,
       coalesce(sum(l.amount), 0)              as amount,
       coalesce(sum(l.tax), 0)                 as tax,
       coalesce(sum(l.amount + l.tax), 0)      as total,
       coalesce((select sum(a.amount) from payment_allocations a where a.document_id = d.id), 0)
         + coalesce((select sum(x.amt) from (select sum(l2.amount + l2.tax) amt from trade_documents n join trade_lines l2 on l2.document_id = n.id
                      where n.against_id = d.id group by n.id) x), 0) as settled
from trade_documents d left join trade_lines l on l.document_id = d.id
group by d.id;

create view open_documents with (security_invoker = true) as
select *, total - settled as balance from document_totals
where kind in ('sale', 'purchase') and total - settled > 0.005;

-- ---------- row level security ----------
alter table companies           enable row level security;
alter table company_members     enable row level security;
alter table parties             enable row level security;
alter table categories          enable row level security;
alter table products            enable row level security;
alter table trade_documents     enable row level security;
alter table trade_lines         enable row level security;
alter table payments            enable row level security;
alter table payment_allocations enable row level security;
alter table deposit_slips       enable row level security;

create policy companies_read   on companies for select using (is_member(id));
create policy companies_update on companies for update using (has_role(id, array['owner']::member_role[]));
create policy members_read     on company_members for select using (user_id = auth.uid() or has_role(company_id, array['owner']::member_role[]));
create policy members_manage   on company_members for all    using (has_role(company_id, array['owner']::member_role[])) with check (has_role(company_id, array['owner']::member_role[]));

-- everyone in the company can read master data; owners / accountants edit it
do $$ declare t text; begin
  foreach t in array array['parties','categories','products'] loop
    execute format('create policy %I_read  on %I for select using (is_member(company_id))', t, t);
    execute format('create policy %I_write on %I for all using (has_role(company_id, array[''owner'',''accountant'']::member_role[])) with check (has_role(company_id, array[''owner'',''accountant'']::member_role[]))', t, t);
  end loop;
end $$;
-- sales staff may add customers while invoicing
create policy parties_sales_insert on parties for insert with check (kind = 'customer' and has_role(company_id, array['sales']::member_role[]));

-- accounts staff: full access. Sales staff: read, and create / edit only SALE documents they created.
create policy docs_read   on trade_documents for select using (is_member(company_id));
create policy docs_acct   on trade_documents for all    using (has_role(company_id, array['owner','accountant']::member_role[])) with check (has_role(company_id, array['owner','accountant']::member_role[]));
create policy docs_sales_ins on trade_documents for insert with check (kind = 'sale' and has_role(company_id, array['sales']::member_role[]));
create policy docs_sales_upd on trade_documents for update using (kind = 'sale' and created_by = auth.uid() and has_role(company_id, array['sales']::member_role[]));

create policy lines_read  on trade_lines for select using (is_member(company_id));
create policy lines_acct  on trade_lines for all    using (has_role(company_id, array['owner','accountant']::member_role[])) with check (has_role(company_id, array['owner','accountant']::member_role[]));
create policy lines_sales on trade_lines for all    using (has_role(company_id, array['sales']::member_role[]) and exists (select 1 from trade_documents d where d.id = document_id and d.kind = 'sale' and d.created_by = auth.uid()))
                                                    with check (has_role(company_id, array['sales']::member_role[]) and exists (select 1 from trade_documents d where d.id = document_id and d.kind = 'sale' and d.created_by = auth.uid()));

-- payments, set-offs, deposit slips: accounts staff only
do $$ declare t text; begin
  foreach t in array array['payments','payment_allocations','deposit_slips'] loop
    execute format('create policy %I_all on %I for all using (has_role(company_id, array[''owner'',''accountant'']::member_role[])) with check (has_role(company_id, array[''owner'',''accountant'']::member_role[]))', t, t);
  end loop;
end $$;

-- ---------- keep updated_at fresh ----------
create or replace function touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
create trigger trade_documents_touch before update on trade_documents for each row execute function touch_updated_at();

-- ---------- storage buckets (private) ----------
-- Buckets and storage policies are project-wide (shared with other apps), hence the "ri-" / "ri_" prefixes.
insert into storage.buckets (id, name, public) values ('ri-deposit-slips', 'ri-deposit-slips', false), ('ri-company-assets', 'ri-company-assets', false)
on conflict (id) do nothing;
-- object paths are "<company_id>/<file>"; only accounts staff may touch deposit slips, all members may read the logo
create policy ri_slips_all on storage.objects for all
  using (bucket_id = 'ri-deposit-slips' and round_island.has_role(((storage.foldername(name))[1])::uuid, array['owner','accountant']::round_island.member_role[]))
  with check (bucket_id = 'ri-deposit-slips' and round_island.has_role(((storage.foldername(name))[1])::uuid, array['owner','accountant']::round_island.member_role[]));
create policy ri_assets_read on storage.objects for select using (bucket_id = 'ri-company-assets' and round_island.is_member(((storage.foldername(name))[1])::uuid));
create policy ri_assets_write on storage.objects for all
  using (bucket_id = 'ri-company-assets' and round_island.has_role(((storage.foldername(name))[1])::uuid, array['owner']::round_island.member_role[]))
  with check (bucket_id = 'ri-company-assets' and round_island.has_role(((storage.foldername(name))[1])::uuid, array['owner']::round_island.member_role[]));

-- ---------- bootstrap: create a company and make the caller its owner ----------
create or replace function create_company(p_name text, p_start date, p_end date) returns uuid
language plpgsql security definer set search_path = round_island, public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into companies (name, period_start, period_end) values (p_name, p_start, p_end) returning id into cid;
  insert into company_members (company_id, user_id, role) values (cid, auth.uid(), 'owner');
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

-- ---------- API access (the schema is new, so nothing is granted by default) ----------
-- Only signed-in users get in; RLS decides which rows they see. anon gets nothing.
grant usage on schema round_island to authenticated, service_role;
grant select, insert, update, delete on all tables in schema round_island to authenticated, service_role;
grant usage, select on all sequences in schema round_island to authenticated, service_role;
grant execute on all functions in schema round_island to authenticated, service_role;
alter default privileges in schema round_island grant select, insert, update, delete on tables to authenticated, service_role;
alter default privileges in schema round_island grant usage, select on sequences to authenticated, service_role;
alter default privileges in schema round_island grant execute on functions to authenticated, service_role;
-- Functions are executable by PUBLIC by default. anon has no USAGE on the schema, so it can't reach them anyway;
-- the revoke is belt and braces for the functions that exist now.
revoke execute on all functions in schema round_island from public, anon;
