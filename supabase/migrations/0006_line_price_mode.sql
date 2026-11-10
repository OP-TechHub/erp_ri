-- Round Island ERP – fixed or free price on sale lines.
--  fixed: packs at the item master's pack price and pack size; the price can't be changed on the line
--  free : quantity and price typed in (e.g. a bulk order in kg at a negotiated price), unit packs or kg
-- The invoice save fills the fixed price from the item master on the server (Phase 4); this only keeps the data consistent.
-- Lines imported from the old app and purchase lines have no mode.
set search_path = round_island, public;

create type price_mode as enum ('fixed', 'free');

alter table trade_lines
  add column price_mode price_mode,
  add constraint trade_lines_mode_unit check (
    price_mode is null
    or (price_mode = 'fixed' and unit = 'pack')
    or (price_mode = 'free'  and unit in ('pack', 'kg'))
  );
