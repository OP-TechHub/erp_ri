-- Round Island ERP – order source on sale invoices (how the order came in).
-- New invoices must pick one (checked by the invoice form); invoices imported from the old app stay null = "Not set".
set search_path = round_island, public;

create type order_source as enum ('walk_in', 'call', 'whatsapp', 'website', 'other');

alter table trade_documents
  add column order_source order_source,
  add constraint trade_documents_source_kind check (order_source is null or kind = 'sale');

create index trade_documents_order_source on trade_documents (company_id, order_source) where kind = 'sale';

-- expose it to the reports (new columns may only be appended to a view)
create or replace view document_totals with (security_invoker = true) as
select d.id as document_id, d.company_id, d.kind, d.doc_date, d.ref, d.party_id, d.party_name, d.invoice_type,
       coalesce(sum(l.amount), 0)              as amount,
       coalesce(sum(l.tax), 0)                 as tax,
       coalesce(sum(l.amount + l.tax), 0)      as total,
       coalesce((select sum(a.amount) from payment_allocations a where a.document_id = d.id), 0)
         + coalesce((select sum(x.amt) from (select sum(l2.amount + l2.tax) amt from trade_documents n join trade_lines l2 on l2.document_id = n.id
                      where n.against_id = d.id group by n.id) x), 0) as settled,
       d.order_source
from trade_documents d left join trade_lines l on l.document_id = d.id
group by d.id;
