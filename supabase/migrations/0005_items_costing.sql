-- Round Island ERP – item master (packs / kg), ingredients and recipes (BOM) for recipe costing.
--  * an item is sold either by the pack (fixed pack price) or by the kg (bulk orders, price typed on the invoice);
--    the unit is stored per invoice line
--  * ingredients have NO price list: their cost is the monthly weighted average of actual purchase lines
--    (src/lib/accounting/costing.ts), because the price changes with every purchase
--  * recipe = quantity of each ingredient in ONE pack of an item
set search_path = round_island, public;

-- ---------- items ----------
comment on column products.rate is 'default price per pack';
alter table products
  add column pack_size     text not null default '',                              -- as printed, e.g. "320g (8pc)", "500ml"
  add column pack_weight_g numeric(8,1) check (pack_weight_g > 0),                -- grams per pack; converts kg sold to packs
  add column kg_rate       numeric(14,2) check (kg_rate >= 0),                    -- optional default bulk price per kg
  add constraint products_id_company unique (id, company_id);

-- ---------- unit on every invoice / bill line ----------
create type line_unit as enum ('pack', 'kg', 'unit', 'l');
alter table trade_lines add column unit line_unit;    -- null on lines imported from the old app

-- ---------- ingredients (raw materials and packaging) ----------
create table ingredients (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name       text not null,
  unit       line_unit not null default 'kg' check (unit in ('kg', 'unit', 'l')),
  notes      text not null default '',
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  constraint ingredients_id_company unique (id, company_id)
);
create unique index ingredients_unique_name on ingredients (company_id, lower(btrim(name)));

-- recipe: how much of each ingredient goes into ONE pack of an item
create table product_recipes (
  product_id    uuid not null,
  ingredient_id uuid not null,
  company_id    uuid not null references companies(id) on delete cascade,
  qty_per_unit  numeric(12,4) not null check (qty_per_unit > 0),
  primary key (product_id, ingredient_id),
  constraint product_recipes_product_fk    foreign key (product_id, company_id)    references products (id, company_id) on delete cascade,
  constraint product_recipes_ingredient_fk foreign key (ingredient_id, company_id) references ingredients (id, company_id)
);
create index product_recipes_ingredient on product_recipes (ingredient_id);

-- a purchase line can name the ingredient bought; qty is in the ingredient's unit, amount (excl. tax) is what was paid
alter table trade_lines
  add column ingredient_id uuid,
  add constraint trade_lines_ingredient_fk foreign key (ingredient_id, company_id) references ingredients (id, company_id);
create index trade_lines_ingredient on trade_lines (ingredient_id) where ingredient_id is not null;

-- ---------- security: accounts staff only (sales staff never see costs) ----------
alter table ingredients     enable row level security;
alter table product_recipes enable row level security;
create policy ingredients_acct on ingredients for all
  using (has_role(company_id, array['owner', 'accountant']::member_role[]))
  with check (has_role(company_id, array['owner', 'accountant']::member_role[]));
create policy product_recipes_acct on product_recipes for all
  using (has_role(company_id, array['owner', 'accountant']::member_role[]))
  with check (has_role(company_id, array['owner', 'accountant']::member_role[]));

create trigger ingredients_audit     after delete on ingredients     for each row execute function log_delete();
create trigger product_recipes_audit after delete on product_recipes for each row execute function log_delete();
