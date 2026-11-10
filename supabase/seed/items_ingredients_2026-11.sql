-- Round Island item master, ingredients and recipes – from Round_Island_Monthly_Tracker (2026-11).
-- Run in the Supabase SQL editor AFTER migration 0005. Safe to run again: items are matched on their code,
-- ingredients on their name, recipes on (item, ingredient).
--  * Pack price and pack size: from the tracker's Product Master (owner will correct them in the app).
--    Exception: the two soups are served in a cup – weighed and priced as 150g for Rs 450 (owner, 2026-11-10);
--    their recipe is still the tracker's 500ml one until the owner corrects it.
--    LO_RI-00015 Barra Slidder and LO_RI-00016 Salt and Pepper are not in the Product Master and keep the old rates.
--    Per-kg prices are left blank. Running this again resets prices to these values.
--  * Recipe quantities are the tracker's starting values (marked there as placeholders) – correct them in the app.
--  * Ingredients get NO price: their cost comes from actual purchases (monthly weighted average).
--  * Items that are not in this list are hidden from new invoices (active = false), never deleted.
set search_path = round_island, public;

do $$
declare
  cid uuid;
  n   int;
  r   record;
  cat uuid;
  pid uuid;
begin
  select count(*) into n from companies;
  if n <> 1 then
    raise exception 'Expected exactly one company in round_island.companies, found %', n
      using hint = 'If the company was deleted, tell Claude – it needs to be recreated first.';
  end if;
  select id into cid from companies;

  -- ---------- items ----------
  for r in select * from (values
    ('LO_RI-00001', 'Asian Tropical Marinated Fillet',    'Marinated Fillets', '300g',        300::numeric, 950::numeric),
    ('LO_RI-00002', 'Japanese Classic Marinated Fillet',  'Marinated Fillets', '300g',        300, 950),
    ('LO_RI-00003', 'Exotic Delight Marinated Fillet',    'Marinated Fillets', '300g',        300, 980),
    ('LO_RI-00004', 'Black Bean Glow Marinated Fillet',   'Marinated Fillets', '300g',        300,  980),
    ('LO_RI-00005', 'Barra Battered Fillets',             'Convenience Range', '300g',        300, 850),
    ('LO_RI-00006', 'Barra Spring Rolls',                 'Convenience Range', '300g',        300, 720),
    ('LO_RI-00007', 'Barra Kofta',                        'Convenience Range', '320g (8pc)',  320,  780),
    ('LO_RI-00008', 'Barra Battered Goujons',             'Convenience Range', '300g',        300,  820),
    ('LO_RI-00009', 'Barra Burger Patties',               'Convenience Range', '300g (5pc)',  300,  790),
    ('LO_RI-00010', 'Barra BBQ-Marinated Butterfly Cuts', 'Convenience Range', '375g',        375, 1150),
    ('LO_RI-00011', 'Barra Bits',                         'Convenience Range', '320g',        320,  700),
    ('LO_RI-00012', 'Barra Battered Belly Strips',        'Convenience Range', '300g',        300, 760),
    ('LO_RI-00013', 'Barra Collagen Soup – Frozen',       'Convenience Range', '150g cup',    150,  450),
    ('LO_RI-00014', 'Barra Collagen Soup – Chilled',      'Convenience Range', '150g cup',    150,  450),
    ('LO_RI-00015', 'Barra Slidder',                      'Convenience Range', '400g',        400,  760),
    ('LO_RI-00016', 'Salt and Pepper',                    'Marinated Fillets', '300g',        300, 1890)
  ) v(code, name, grp, pack, weight, rate)
  loop
    -- every item is also a sales category, named like the reference app: "code – name"
    insert into categories (company_id, grp, name) values (cid, 'sales', r.code || ' – ' || r.name)
      on conflict (company_id, grp, lower(btrim(name))) do nothing;
    select id into cat from categories where company_id = cid and grp = 'sales' and lower(btrim(name)) = lower(r.code || ' – ' || r.name);

    update products set name = r.name, group_name = r.grp, pack_size = r.pack, pack_weight_g = r.weight,
                        rate = r.rate, category_id = cat, active = true
    where company_id = cid and code = r.code
    returning id into pid;
    if pid is null then
      insert into products (company_id, code, name, group_name, pack_size, pack_weight_g, rate, category_id)
      values (cid, r.code, r.name, r.grp, r.pack, r.weight, r.rate, cat);
    end if;
    pid := null;
  end loop;

  update products set active = false where company_id = cid and code not like 'LO\_RI-%';

  -- ---------- ingredients (no prices) ----------
  insert into ingredients (company_id, name, unit, notes) values
    (cid, 'Barramundi Fillet',     'kg',   'Grade A fillet, ex-factory transfer price'),
    (cid, 'Barramundi Offcut',     'kg',   'Trim/offcut from filleting line'),
    (cid, 'Barramundi Belly Flap', 'kg',   'Belly flap trim'),
    (cid, 'Mixed Vegetables',      'kg',   'Onion, carrot, spring onion mix'),
    (cid, 'Spice Mix',             'kg',   'House spice blend'),
    (cid, 'Marinate Mix',          'kg',   'Marination base for fillet range'),
    (cid, 'Pre-Dust Flour',        'kg',   'Seasoned flour, pre-batter coat'),
    (cid, 'Batter Mix',            'kg',   'Batter powder, water-mixed on site'),
    (cid, 'Breadcrumbs',           'kg',   'Panko/crumb coat for goujons'),
    (cid, 'Frozen Pouch',          'unit', 'Primary pack, frozen SKUs'),
    (cid, 'Chilled Pouch',         'unit', 'Primary pack, chilled SKUs'),
    (cid, 'Label',                 'unit', 'Printed product label')
  on conflict (company_id, lower(btrim(name))) do update set unit = excluded.unit, notes = excluded.notes, active = true;

  -- ---------- recipes: qty of each ingredient in ONE pack ----------
  insert into product_recipes (company_id, product_id, ingredient_id, qty_per_unit)
  select cid, p.id, i.id, v.qty
  from (values
    ('LO_RI-00001', 'Barramundi Fillet', 0.27), ('LO_RI-00001', 'Marinate Mix', 0.02), ('LO_RI-00001', 'Spice Mix', 0.01), ('LO_RI-00001', 'Frozen Pouch', 1), ('LO_RI-00001', 'Label', 1),
    ('LO_RI-00002', 'Barramundi Fillet', 0.27), ('LO_RI-00002', 'Marinate Mix', 0.02), ('LO_RI-00002', 'Spice Mix', 0.01), ('LO_RI-00002', 'Frozen Pouch', 1), ('LO_RI-00002', 'Label', 1),
    ('LO_RI-00003', 'Barramundi Fillet', 0.27), ('LO_RI-00003', 'Marinate Mix', 0.02), ('LO_RI-00003', 'Spice Mix', 0.01), ('LO_RI-00003', 'Frozen Pouch', 1), ('LO_RI-00003', 'Label', 1),
    ('LO_RI-00004', 'Barramundi Fillet', 0.27), ('LO_RI-00004', 'Marinate Mix', 0.02), ('LO_RI-00004', 'Spice Mix', 0.01), ('LO_RI-00004', 'Frozen Pouch', 1), ('LO_RI-00004', 'Label', 1),
    ('LO_RI-00005', 'Barramundi Fillet', 0.20), ('LO_RI-00005', 'Pre-Dust Flour', 0.02), ('LO_RI-00005', 'Batter Mix', 0.05), ('LO_RI-00005', 'Frozen Pouch', 1), ('LO_RI-00005', 'Label', 1),
    ('LO_RI-00006', 'Barramundi Offcut', 0.15), ('LO_RI-00006', 'Mixed Vegetables', 0.10), ('LO_RI-00006', 'Spice Mix', 0.01), ('LO_RI-00006', 'Pre-Dust Flour', 0.02), ('LO_RI-00006', 'Frozen Pouch', 1), ('LO_RI-00006', 'Label', 1),
    ('LO_RI-00007', 'Barramundi Offcut', 0.22), ('LO_RI-00007', 'Mixed Vegetables', 0.05), ('LO_RI-00007', 'Spice Mix', 0.02), ('LO_RI-00007', 'Batter Mix', 0.02), ('LO_RI-00007', 'Frozen Pouch', 1), ('LO_RI-00007', 'Label', 1),
    ('LO_RI-00008', 'Barramundi Fillet', 0.18), ('LO_RI-00008', 'Pre-Dust Flour', 0.02), ('LO_RI-00008', 'Batter Mix', 0.04), ('LO_RI-00008', 'Breadcrumbs', 0.05), ('LO_RI-00008', 'Frozen Pouch', 1), ('LO_RI-00008', 'Label', 1),
    ('LO_RI-00009', 'Barramundi Offcut', 0.20), ('LO_RI-00009', 'Barramundi Belly Flap', 0.05), ('LO_RI-00009', 'Spice Mix', 0.02), ('LO_RI-00009', 'Batter Mix', 0.03), ('LO_RI-00009', 'Frozen Pouch', 1), ('LO_RI-00009', 'Label', 1),
    ('LO_RI-00010', 'Barramundi Fillet', 0.32), ('LO_RI-00010', 'Marinate Mix', 0.03), ('LO_RI-00010', 'Spice Mix', 0.01), ('LO_RI-00010', 'Frozen Pouch', 1), ('LO_RI-00010', 'Label', 1),
    ('LO_RI-00011', 'Barramundi Offcut', 0.24), ('LO_RI-00011', 'Pre-Dust Flour', 0.02), ('LO_RI-00011', 'Batter Mix', 0.04), ('LO_RI-00011', 'Frozen Pouch', 1), ('LO_RI-00011', 'Label', 1),
    ('LO_RI-00012', 'Barramundi Belly Flap', 0.22), ('LO_RI-00012', 'Pre-Dust Flour', 0.02), ('LO_RI-00012', 'Batter Mix', 0.04), ('LO_RI-00012', 'Frozen Pouch', 1), ('LO_RI-00012', 'Label', 1),
    ('LO_RI-00013', 'Barramundi Belly Flap', 0.15), ('LO_RI-00013', 'Barramundi Offcut', 0.05), ('LO_RI-00013', 'Mixed Vegetables', 0.08), ('LO_RI-00013', 'Spice Mix', 0.01), ('LO_RI-00013', 'Frozen Pouch', 1), ('LO_RI-00013', 'Label', 1),
    ('LO_RI-00014', 'Barramundi Belly Flap', 0.15), ('LO_RI-00014', 'Barramundi Offcut', 0.05), ('LO_RI-00014', 'Mixed Vegetables', 0.08), ('LO_RI-00014', 'Spice Mix', 0.01), ('LO_RI-00014', 'Chilled Pouch', 1), ('LO_RI-00014', 'Label', 1)
  ) v(code, ingredient, qty)
  join products p on p.company_id = cid and p.code = v.code
  join ingredients i on i.company_id = cid and lower(i.name) = lower(v.ingredient)
  on conflict (product_id, ingredient_id) do update set qty_per_unit = excluded.qty_per_unit;
end $$;

-- check: 16 items, 12 ingredients, 76 recipe lines (no recipe yet for LO_RI-00015 Barra Slidder and LO_RI-00016 Salt and Pepper)
select 'items' as what, count(*) from round_island.products where code like 'LO\_RI-%' and active
union all select 'ingredients', count(*) from round_island.ingredients where active
union all select 'recipe lines', count(*) from round_island.product_recipes;
