-- Recreate the Round Island company with you as owner (run once, in the Supabase SQL editor).
-- Step 1: on the line marked EDIT, put the e-mail you sign in to the app with (Authentication -> Users).
-- It does nothing if a company already exists. Afterwards run items_ingredients_2026-11.sql.
-- Creates: the company (financial year 2026-04-01 to 2027-03-31, income tax 30 %, turnover tax 0 %, invoice
-- address / bank / terms defaults), your owner membership and the standard category list (incl. "Ingridients").
set search_path = round_island, public;

do $$
declare
  owner_email text := 'YOUR_LOGIN_EMAIL';   -- EDIT
  cid uuid;
begin
  if exists (select 1 from companies) then
    raise notice 'A company already exists – nothing to do.';
    return;
  end if;
  cid := create_company('Round Island (Pvt) Ltd', '2026-04-01', '2027-03-31', owner_email);
  raise notice 'Company created: %', cid;
end $$;

-- check: 1 company, 1 owner, the default categories
select c.name, c.period_start, c.period_end, u.email as owner,
       (select count(*) from round_island.categories k where k.company_id = c.id) as categories
from round_island.companies c
join round_island.company_members m on m.company_id = c.id and m.role = 'owner'
join auth.users u on u.id = m.user_id;
