-- Round Island ERP – new values used by the Cloud Kitchen link (0008). Run on its own, before 0008:
-- Postgres can't use an enum value in the same transaction that adds it.
--  purchasing – CK supply_chain staff: purchasing after PO approved
--  cashier    – CK sales / front office: customer receipts and the daily cash-up
--  viewer     – CK manager / executive: reports only
--  online     – invoice type for CK invoices paid by bank transfer (online_transfer)
set search_path = round_island, public;

alter type member_role  add value if not exists 'purchasing';
alter type member_role  add value if not exists 'cashier';
alter type member_role  add value if not exists 'viewer';
alter type invoice_type add value if not exists 'online';
