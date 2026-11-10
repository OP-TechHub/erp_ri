-- Call once per company:  select round_island.seed_products('<company uuid>');
-- Loads the 12-item product list with default rates; each product becomes a "sales" category.
-- Not needed for Round Island itself: supabase/data/import_data.sql already loads its products.
set search_path = round_island, public;

create or replace function seed_products(cid uuid) returns void
language plpgsql security definer set search_path = round_island, public as $$
declare r record; c uuid;
begin
  if not has_role(cid, array['owner','accountant']::member_role[]) then raise exception 'not allowed'; end if;
  for r in select * from (values
    ('Barra Spring Rolls 500g box','Convenience Range',1175),
    ('Asian Tropical Marinated Fillet 300g','Marinated Fillets',1890),
    ('Barra Battered Fillets 300g box 1kg','Convenience Range',4300),
    ('Barra Burger Patties (05 pcs) box 400g','Convenience Range',760),
    ('Exotic Delight Marinated Fillet 300g','Marinated Fillets',1890),
    ('Japanese Classic Marinated Fillet 300g','Marinated Fillets',1890),
    ('Barra Bits 250g box','Convenience Range',862),
    ('Barra Slidder 400g','Convenience Range',760),
    ('Barra BBQ-Marinated Butterfly Cuts (01 ptn) 375g box','Convenience Range',1200),
    ('Barra Battered Belly Strips 300g box','Convenience Range',1950),
    ('Salt and Pepper 300g','Marinated Fillets',1890),
    ('Barra Kofta (08 pcs) 320g box','Convenience Range',880)) v(n, g, rate)
  loop
    insert into categories (company_id, grp, name) values (cid, 'sales', r.n)
      on conflict (company_id, grp, lower(btrim(name))) do nothing;
    select id into c from categories where company_id = cid and grp = 'sales' and lower(btrim(name)) = lower(btrim(r.n));
    insert into products (company_id, name, group_name, rate, category_id) values (cid, r.n, r.g, r.rate, c)
      on conflict (company_id, lower(btrim(code)), lower(btrim(name))) do nothing;
  end loop;
end $$;
